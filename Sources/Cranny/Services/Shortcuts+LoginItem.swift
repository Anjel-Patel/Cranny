import AppKit
import ServiceManagement

/// Lists and runs the user's macOS Shortcuts through the `shortcuts` command-line tool.
@MainActor
final class ShortcutsService: ObservableObject {
    static let shared = ShortcutsService()

    @Published private(set) var all: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var running: Set<String> = []
    @Published private(set) var failed: Set<String> = []

    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Self.shell(["list"]) ?? ""
            let names = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let service = ShortcutsService.shared
                    service.all = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    service.isLoading = false
                }
            }
        }
    }

    func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        failed.remove(name)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Self.shell(["run", name]) != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let service = ShortcutsService.shared
                    service.running.remove(name)
                    if !ok { service.failed.insert(name) }
                }
            }
        }
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Runs `/usr/bin/shortcuts` and returns stdout, or nil when it failed.
    nonisolated private static func shell(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription)")
        }
    }
}
