import AppKit
import Combine

/// System-wide "Now Playing" state and controls, fed by the perl-hosted helper.
@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()

    @Published private(set) var hasPlayer = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: NSColor = .white
    @Published private(set) var bundleID = ""
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appName = ""
    /// When playback last stopped; nil while playing or when nothing has played since launch.
    @Published private(set) var pausedAt: Date?

    private var elapsed: Double = 0
    private var elapsedTimestamp = Date()
    private var rate: Double = 0
    private var pid: pid_t = 0
    private var artworkHash = 0

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restartDelay: Double = 1
    private var stopping = false

    private init() {}

    // MARK: Helper process

    func start() {
        stopping = false
        launchHelper()
    }

    func stop() {
        stopping = true
        try? input?.close()
        process?.terminate()
        process = nil
    }

    private func launchHelper() {
        guard process == nil,
              let script = Bundle.main.url(forResource: "media-helper", withExtension: "pl"),
              let library = Self.helperLibrary()
        else {
            Log.media.error("Media helper resources are missing")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, library.path]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NowPlaying.shared.ingest(data) }
            }
        }
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NowPlaying.shared.helperExited() }
            }
        }

        do {
            try p.run()
            process = p
            input = stdin.fileHandleForWriting
            buffer.removeAll()
            Log.media.info("Media helper started (pid \(p.processIdentifier))")
        } catch {
            Log.media.error("Could not start media helper: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    /// Downloaded copies of the app carry a quarantine flag on every file, and perl refuses
    /// to load a quarantined library. Clear it on the bundled helper, or use a private copy
    /// when the bundle is read-only (for example when macOS runs the app from a translocated path).
    private static func helperLibrary() -> URL? {
        guard let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaHelper.dylib"),
              FileManager.default.fileExists(atPath: bundled.path)
        else { return nil }
        if clearQuarantine(bundled) { return bundled }
        let directory = TrayStore.supportDirectory.appendingPathComponent("Helper", isDirectory: true)
        let copy = directory.appendingPathComponent("MediaHelper.dylib")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: bundled, to: copy)
            _ = clearQuarantine(copy)
            return copy
        } catch {
            return bundled
        }
    }

    private static func clearQuarantine(_ url: URL) -> Bool {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return removexattr(path, "com.apple.quarantine", 0)
        }
        return result == 0 || errno == ENOATTR
    }

    private func helperExited() {
        process = nil
        input = nil
        guard !stopping else { return }
        Log.media.error("Media helper exited; restarting")
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let player = NowPlaying.shared
                if !player.stopping { player.launchHelper() }
            }
        }
    }

    private func send(_ command: String) {
        guard let input else { return }
        do {
            try input.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            Log.media.error("Media helper write failed: \(error.localizedDescription)")
        }
    }

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            restartDelay = 1
            apply(object)
        }
    }

    private func apply(_ d: [String: Any]) {
        let empty = (d["empty"] as? NSNumber)?.boolValue ?? true
        if empty {
            hasPlayer = false
            isPlaying = false
            title = ""; artist = ""; album = ""
            duration = 0; elapsed = 0; rate = 0
            artwork = nil; artworkHash = 0
            bundleID = ""; appIcon = nil; appName = ""
            pausedAt = nil
            return
        }

        let wasPlaying = isPlaying
        hasPlayer = true
        title = d["title"] as? String ?? ""
        artist = d["artist"] as? String ?? ""
        album = d["album"] as? String ?? ""
        duration = (d["duration"] as? NSNumber)?.doubleValue ?? 0
        elapsed = (d["elapsed"] as? NSNumber)?.doubleValue ?? 0
        rate = (d["rate"] as? NSNumber)?.doubleValue ?? 0
        if let ts = (d["timestamp"] as? NSNumber)?.doubleValue, ts > 0 {
            elapsedTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            elapsedTimestamp = Date()
        }
        let playing = (d["playing"] as? NSNumber)?.boolValue ?? false
        if wasPlaying && !playing { pausedAt = Date() }
        if playing { pausedAt = nil }
        isPlaying = playing
        pid = (d["pid"] as? NSNumber)?.int32Value ?? 0

        let parent = d["parentBundleID"] as? String ?? ""
        let own = d["bundleID"] as? String ?? ""
        let resolved = !parent.isEmpty ? parent : (!own.isEmpty ? own : runningBundleID(for: pid))
        if resolved != bundleID {
            bundleID = resolved
            refreshAppInfo()
        }

        let hash = (d["artworkHash"] as? NSNumber)?.intValue ?? 0
        if hash == 0 {
            if artworkHash != 0 { artwork = nil; accentColor = .white }
        } else if let base64 = d["artwork"] as? String,
                  let data = Data(base64Encoded: base64),
                  let image = NSImage(data: data) {
            artwork = image
            accentColor = ImageTools.accentColor(of: image) ?? .white
        }
        artworkHash = hash
    }

    private func runningBundleID(for pid: pid_t) -> String {
        guard pid > 0 else { return "" }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
    }

    private func refreshAppInfo() {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            appIcon = nil
            appName = ""
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Playback

    /// Current position, extrapolated from the last report while playing.
    func position(at date: Date = Date()) -> Double {
        var value = elapsed
        if isPlaying {
            value += date.timeIntervalSince(elapsedTimestamp) * (rate > 0 ? rate : 1)
        }
        return duration > 0 ? min(max(0, value), duration) : max(0, value)
    }

    /// True while playing, or for `timeout` seconds after playback stopped.
    func isActive(timeout: Double, now: Date = Date()) -> Bool {
        guard hasPlayer else { return false }
        if isPlaying { return true }
        guard let pausedAt else { return false }
        return now.timeIntervalSince(pausedAt) < timeout
    }

    func togglePlayPause() {
        send("toggle")
        if hasPlayer {
            elapsed = position()
            elapsedTimestamp = Date()
            if isPlaying { pausedAt = Date() } else { pausedAt = nil }
            isPlaying.toggle()
        }
    }

    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to seconds: Double) {
        send(String(format: "seek %.3f", seconds))
        elapsed = seconds
        elapsedTimestamp = Date()
    }

    func openSourceApp() {
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static let suggestedPlayers = ["com.spotify.client", "com.apple.Music"]
}
