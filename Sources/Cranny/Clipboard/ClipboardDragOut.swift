import AppKit
import UniformTypeIdentifiers

/// Lets clipboard tiles be dragged into other apps. Dragging always copies: the item stays
/// in the history, and dragged files are copied, never moved.
@MainActor
final class ClipboardDragOut: NSObject, NSDraggingSource {
    static let shared = ClipboardDragOut()

    /// Frames of the visible tiles, in the hosting view's top-left-origin coordinates.
    var itemFrames: [UUID: CGRect] = [:]
    private var pending: (id: UUID, location: NSPoint)?

    /// Returns true when the event started a drag and should not be delivered.
    func handle(_ event: NSEvent) -> Bool {
        guard event.window is NotchPanel else { return false }
        switch event.type {
        case .leftMouseDown:
            pending = nil
            guard let controller = NotchRegistry.controller(for: event.window),
                  controller.model.state == .open, controller.model.tab == .clipboard else { break }
            let point = controller.viewPoint(for: event)
            guard controller.model.region(.clipboard, contains: point),
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
        guard let item = ClipboardStore.shared.items.first(where: { $0.id == id }),
              let view = event.window?.contentView else { return false }
        let writers: [NSPasteboardWriting]
        let icon: NSImage
        switch item.kind {
        case .files(let urls):
            writers = urls.map { $0 as NSURL }
            icon = NSWorkspace.shared.icon(forFile: urls[0].path)
        case .image(let preview):
            writers = Self.pasteboardItems(item)
            icon = preview
        case .link:
            writers = Self.pasteboardItems(item)
            icon = NSWorkspace.shared.icon(for: .internetLocation)
        case .text:
            writers = Self.pasteboardItems(item)
            icon = NSWorkspace.shared.icon(for: .plainText)
        }
        let point = view.convert(event.locationInWindow, from: nil)
        let draggingItems = writers.enumerated().map { index, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let offset = CGFloat(min(index, 3)) * 4
            draggingItem.setDraggingFrame(NSRect(x: point.x - 24 + offset, y: point.y - 24 - offset, width: 48, height: 48), contents: icon)
            return draggingItem
        }
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        Log.app.info("Dragging a clipboard item")
        return true
    }

    /// The item's formats, ready to hand to another app.
    private static func pasteboardItems(_ item: ClipboardStore.Item) -> [NSPasteboardItem] {
        item.contents.map { representations in
            let pasteboardItem = NSPasteboardItem()
            for representation in representations {
                pasteboardItem.setData(representation.data, forType: representation.type)
            }
            return pasteboardItem
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
