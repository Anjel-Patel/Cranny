import AppKit
import CryptoKit

/// Checks GitHub for a newer release once a day and can install it in place.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    nonisolated static let repository = "Anjel-Patel/Cranny"

    struct Release: Equatable, Sendable {
        let version: String
        let notes: String
        let page: URL
        let zip: URL?
        let checksum: URL?
    }

    enum Status: Equatable {
        case idle, checking, upToDate, downloading, installing
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?
    /// The update version whose live activity the user has already seen.
    @Published private(set) var dismissedVersion: String?

    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private init() {
        lastChecked = defaults.object(forKey: "lastUpdateCheck") as? Date
        dismissedVersion = defaults.string(forKey: "dismissedUpdateVersion")
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Whether the "Update available" live activity should show.
    var showsActivity: Bool {
        guard let available else { return false }
        return available.version != dismissedVersion
    }

    /// Updating in place needs a writable install location (not a read-only, translocated copy).
    var canInstallInPlace: Bool {
        let app = Bundle.main.bundleURL
        guard !app.path.contains("/AppTranslocation/") else { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// Checks shortly after every launch, so restarting picks up a new release, then about
    /// once a day while Cranny runs.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            MainActor.assumeIsolated { UpdateChecker.shared.checkIfDue(interval: 0) }
        }
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.checkIfDue(interval: 23 * 3600) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Checks when automatic checks are on and the last successful check is at least
    /// `interval` seconds old.
    private func checkIfDue(interval: TimeInterval) {
        guard AppSettings.shared.checkForUpdates else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < interval { return }
        check()
    }

    /// Pass `showingDetails` when Settings → About is about to show the result, so the
    /// live activity doesn't repeat it.
    func check(showingDetails: Bool = false) {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        Task.detached(priority: .utility) {
            let result: Result<Release, Error>
            do { result = .success(try await Self.fetchLatest()) } catch { result = .failure(error) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { UpdateChecker.shared.finishCheck(result, seen: showingDetails) }
            }
        }
    }

    /// Hides the live activity for the current update once the user has seen it.
    func markSeen() {
        guard let version = available?.version, dismissedVersion != version else { return }
        dismissedVersion = version
        defaults.set(version, forKey: "dismissedUpdateVersion")
    }

    private func finishCheck(_ result: Result<Release, Error>, seen: Bool) {
        switch result {
        case .success(let release):
            let now = Date()
            lastChecked = now
            defaults.set(now, forKey: "lastUpdateCheck")
            if Self.isNewer(release.version, than: currentVersion) {
                available = release
                status = .idle
                if seen { markSeen() }
                Log.app.notice("Update available: \(release.version, privacy: .public)")
            } else {
                available = nil
                status = .upToDate
            }
        case .failure(let error):
            // Not counted as a check, so the hourly timer tries again.
            status = .failed(error.localizedDescription)
        }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            enum CodingKeys: String, CodingKey { case name, browserDownloadURL = "browser_download_url" }
        }
        let tagName: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", body, htmlURL = "html_url", assets }
    }

    nonisolated private static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub didn't respond as expected.") }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        func asset(_ name: String) -> URL? { release.assets.first { $0.name == name }?.browserDownloadURL }
        return Release(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            notes: release.body ?? "",
            page: release.htmlURL,
            zip: asset("Cranny.zip"),
            checksum: asset("Cranny.zip.sha256")
        )
    }

    // MARK: Installing

    func install() {
        guard let release = available else { return }
        guard canInstallInPlace, let zip = release.zip, let checksum = release.checksum,
              let bundleID = Bundle.main.bundleIdentifier
        else {
            NSWorkspace.shared.open(release.page)
            return
        }
        status = .downloading
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CrannyUpdate-\(UUID().uuidString)")
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                result = .success(try await Self.prepare(zip: zip, checksum: checksum, bundleID: bundleID, in: work))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { UpdateChecker.shared.finishInstall(result, work: work) }
            }
        }
    }

    /// Downloads the release, checks it against its published SHA-256 and unpacks it.
    nonisolated private static func prepare(zip: URL, checksum: URL, bundleID: String, in work: URL) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let (zipData, zipResponse) = try await URLSession.shared.data(from: zip)
        let (sumData, sumResponse) = try await URLSession.shared.data(from: checksum)
        guard (zipResponse as? HTTPURLResponse)?.statusCode == 200, (sumResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("The download failed.")
        }
        let expected = String(decoding: sumData, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, expected == actual else { throw UpdateError("The download didn't match its checksum.") }

        let zipFile = work.appendingPathComponent("Cranny.zip")
        try zipData.write(to: zipFile)
        let unpacked = work.appendingPathComponent("new")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zipFile.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = unpacked.appendingPathComponent("Cranny.app")
        guard ditto.terminationStatus == 0, Bundle(url: app)?.bundleIdentifier == bundleID else {
            throw UpdateError("The download didn't contain Cranny.")
        }
        return app
    }

    /// Hands over to a small script that waits for Cranny to quit, swaps in the new
    /// version (restoring the old one if anything fails) and opens it again.
    private func finishInstall(_ result: Result<URL, Error>, work: URL) {
        switch result {
        case .failure(let error):
            status = .failed(error.localizedDescription)
            try? FileManager.default.removeItem(at: work)
        case .success(let newApp):
            status = .installing
            let script = work.appendingPathComponent("swap.sh")
            let body = """
            #!/bin/sh
            pid="$1"; target="$2"; new="$3"; work="$4"
            while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
            rm -rf "$target.previous"
            if mv "$target" "$target.previous" && /usr/bin/ditto "$new" "$target"; then
              rm -rf "$target.previous"
            else
              rm -rf "$target"; mv "$target.previous" "$target"
            fi
            /usr/bin/open "$target"
            rm -rf "$work"
            """
            do {
                try body.write(to: script, atomically: true, encoding: .utf8)
                let swap = Process()
                swap.executableURL = URL(fileURLWithPath: "/bin/sh")
                swap.arguments = [script.path, String(getpid()), Bundle.main.bundleURL.path, newApp.path, work.path]
                try swap.run()
                Log.app.notice("Installing update and relaunching")
                NSApp.terminate(nil)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
