import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Files the user parked in the notch. The tray keeps references to the original
/// files (dragging one back out moves or copies it from its original location).
/// Things that are not files yet (images, links, text) are saved into the app's
/// own "Dropped Items" folder first.
@MainActor
final class TrayStore: ObservableObject {
    static let shared = TrayStore()

    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        var url: URL
        var bookmark: Data?
        var owned: Bool
        let added: Date
    }

    @Published private(set) var items: [Item] = []

    nonisolated static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cranny", isDirectory: true)
    }()
    nonisolated static let droppedDirectory = supportDirectory.appendingPathComponent("Dropped Items", isDirectory: true)
    nonisolated private static let indexFile = supportDirectory.appendingPathComponent("tray.json")

    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText, .data]

    private init() {
        load()
    }

    func add(_ urls: [URL], owned: Bool = false) {
        var changed = false
        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path),
                  !items.contains(where: { $0.url.standardizedFileURL == standardized })
            else { continue }
            let bookmark = try? standardized.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            items.append(Item(id: UUID(), url: standardized, bookmark: bookmark, owned: owned, added: Date()))
            changed = true
        }
        if changed { save() }
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        discardIfOwned(item)
        save()
    }

    /// Called after an item was dragged out of the tray.
    func didDragOut(_ id: UUID, moved: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        if !moved { discardIfOwned(item) }
        save()
    }

    func removeAll() {
        items.forEach(discardIfOwned)
        items.removeAll()
        save()
    }

    func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    private func discardIfOwned(_ item: Item) {
        guard item.owned, item.url.path.hasPrefix(Self.droppedDirectory.path) else { return }
        try? FileManager.default.removeItem(at: item.url)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexFile),
              let saved = try? JSONDecoder().decode([Item].self, from: data)
        else { return }
        items = saved.compactMap { item in
            var item = item
            if let bookmark = item.bookmark {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    item.url = resolved
                    if stale { item.bookmark = try? resolved.bookmarkData() }
                }
            }
            return FileManager.default.fileExists(atPath: item.url.path) ? item : nil
        }
        if items.count != saved.count { save() }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.indexFile, options: .atomic)
        } catch {
            Log.tray.error("Saving tray failed: \(error.localizedDescription)")
        }
    }

    // MARK: Dropping

    /// Accepts anything dragged onto the tray: files, images, links or text.
    func accept(_ providers: [NSItemProvider]) {
        for provider in providers {
            Self.resolveFile(from: provider) { url, owned in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { TrayStore.shared.add([url], owned: owned) }
                }
            }
        }
    }

    /// Resolves an item provider to a file on disk, saving non-file content first.
    nonisolated static func resolveFile(from provider: NSItemProvider, completion: @escaping @Sendable (URL, Bool) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { completion(url, false) }
            }
            return
        }
        let suggestedName = provider.suggestedName
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { temp, _ in
                guard let temp else { return }
                let name = suggestedName.map { $0 + "." + temp.pathExtension } ?? temp.lastPathComponent
                if let saved = copyIntoDropFolder(temp, name: name) { completion(saved, true) }
            }
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let plist: [String: String] = ["URL": url.absoluteString]
                guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
                let base = (url.host ?? "Link").replacingOccurrences(of: "/", with: "-")
                if let saved = writeIntoDropFolder(data, name: base + ".webloc") { completion(saved, true) }
            }
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                guard let text, !text.isEmpty else { return }
                let firstLine = text.split(separator: "\n").first.map(String.init) ?? "Text"
                let base = String(firstLine.prefix(40)).replacingOccurrences(of: "/", with: "-")
                if let saved = writeIntoDropFolder(Data(text.utf8), name: base + ".txt") { completion(saved, true) }
            }
            return
        }
        if let type = provider.registeredTypeIdentifiers.first {
            provider.loadFileRepresentation(forTypeIdentifier: type) { temp, _ in
                guard let temp else { return }
                if let saved = copyIntoDropFolder(temp, name: suggestedName ?? temp.lastPathComponent) {
                    completion(saved, true)
                }
            }
        }
    }

    nonisolated private static func uniqueDestination(named name: String) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: droppedDirectory, withIntermediateDirectories: true)
        let cleaned = name.isEmpty ? "Item" : name
        var candidate = droppedDirectory.appendingPathComponent(cleaned)
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = droppedDirectory.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    nonisolated private static func copyIntoDropFolder(_ source: URL, name: String) -> URL? {
        let destination = uniqueDestination(named: name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    nonisolated private static func writeIntoDropFolder(_ data: Data, name: String) -> URL? {
        let destination = uniqueDestination(named: name)
        return (try? data.write(to: destination)) != nil ? destination : nil
    }
}

@MainActor
enum AirDrop {
    static let icon: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image

    static func share(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }

    static func share(_ providers: [NSItemProvider]) {
        let collector = URLCollector(expected: providers.count)
        for provider in providers {
            TrayStore.resolveFile(from: provider) { url, _ in
                collector.add(url)
            }
        }
    }

    /// Gathers the asynchronously resolved URLs and shares them once all arrived (or after a short wait).
    private final class URLCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private let expected: Int
        private var fired = false

        init(expected: Int) {
            self.expected = expected
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in fire() }
        }

        func add(_ url: URL) {
            lock.lock()
            urls.append(url)
            let done = urls.count >= expected
            lock.unlock()
            if done { DispatchQueue.main.async { [self] in fire() } }
        }

        private func fire() {
            lock.lock()
            guard !fired, !urls.isEmpty else { lock.unlock(); return }
            fired = true
            let result = urls
            lock.unlock()
            MainActor.assumeIsolated { AirDrop.share(result) }
        }
    }
}

enum Thumbnails {
    static func image(for url: URL, side: CGFloat) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.nsImage
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Starts AppKit drag sessions for tray items so they can be dropped into Finder
/// or any other app, and removes them from the tray once dropped.
@MainActor
final class TrayDragOut: NSObject, NSDraggingSource {
    static let shared = TrayDragOut()

    /// Frames of the visible tray items, in the hosting view's top-left-origin coordinates.
    var itemFrames: [UUID: CGRect] = [:]
    private var pending: (id: UUID, location: NSPoint)?
    private var draggingItem: UUID?

    /// Returns true when the event started a drag and should not be delivered.
    func handle(_ event: NSEvent) -> Bool {
        guard event.window is NotchPanel else { return false }
        switch event.type {
        case .leftMouseDown:
            pending = nil
            guard let controller = NotchRegistry.controller(for: event.window),
                  controller.model.state == .open, controller.model.tab == .tray else { break }
            let point = controller.viewPoint(for: event)
            guard controller.model.region(.tray, contains: point),
                  let id = itemFrames.first(where: { $0.value.contains(point) })?.key else { break }
            pending = (id, event.locationInWindow)
        case .leftMouseDragged:
            guard let candidate = pending else { return false }
            let dx = event.locationInWindow.x - candidate.location.x
            let dy = event.locationInWindow.y - candidate.location.y
            guard dx * dx + dy * dy > 16 else { return false }
            pending = nil
            return beginDrag(candidate.id, event: event)
        case .leftMouseUp:
            pending = nil
        default:
            break
        }
        return false
    }

    private func beginDrag(_ id: UUID, event: NSEvent) -> Bool {
        guard let item = TrayStore.shared.items.first(where: { $0.id == id }),
              let view = event.window?.contentView else { return false }
        let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        let point = view.convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        self.draggingItem = id
        let session = view.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated {
            defer { draggingItem = nil }
            guard let id = draggingItem, operation != [] else { return }
            // Dropping back onto our own tray is not a drag out.
            if NotchRegistry.isPointInsideOpenNotch(screenPoint) { return }
            TrayStore.shared.didDragOut(id, moved: operation.contains(.move))
        }
    }
}
