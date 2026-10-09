import AppKit
import Combine
import SwiftUI

/// Owns one screen's notch window and turns pointer, drag and scroll input into notch state.
@MainActor
final class NotchController {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let model: NotchModel
    let panel: NotchPanel

    private var bag = Set<AnyCancellable>()
    private var openTask: DispatchWorkItem?
    private var peekTask: DispatchWorkItem?
    private var closeTask: DispatchWorkItem?
    private let swipe = SwipeTracker()

    init(screen: NSScreen) {
        self.screen = screen
        displayID = screen.displayID
        model = NotchModel(screen: screen)
        panel = NotchPanel(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        model.controller = self

        let root = NotchRootView(model: model)
            .environmentObject(AppSettings.shared)
            .environmentObject(LiveActivityCenter.shared)
            .environmentObject(NowPlaying.shared)
            .environmentObject(TrayStore.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(CameraService.shared)
            .environmentObject(ShortcutsService.shared)
        let host = NotchHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host
        layoutPanel()
        panel.orderFrontRegardless()

        AppSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.layoutPanel() }
            .store(in: &bag)
        LiveActivityCenter.shared.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshPointer() }
            .store(in: &bag)
    }

    func tearDown() {
        openTask?.cancel(); peekTask?.cancel(); closeTask?.cancel()
        bag.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    func layoutPanel() {
        let maximum = model.maximumSize
        let width = min(screen.frame.width, maximum.width + 80)
        let height = min(screen.frame.height, maximum.height + 60)
        let frame = NSRect(x: model.notchMidX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Current notch body (excluding the decorative ears) in screen coordinates.
    func notchRect() -> NSRect {
        let layout = model.layout(activity: LiveActivityCenter.shared.current)
        return NSRect(x: model.notchMidX - layout.bodyWidth / 2, y: screen.frame.maxY - layout.height,
                      width: layout.bodyWidth, height: layout.height)
    }

    var needsPolling: Bool { model.state == .open || model.hovering || model.peeking }

    // MARK: Pointer

    func pointerMoved(_ point: NSPoint, draggingContent: Bool) {
        let rect = notchRect()
        let zone: NSRect
        if model.state == .open {
            zone = NSRect(x: rect.minX - 4, y: rect.minY - 6, width: rect.width + 8, height: rect.height + 12)
        } else if draggingContent {
            zone = NSRect(x: rect.minX - 50, y: rect.minY - 30, width: rect.width + 100, height: rect.height + 40)
        } else if LiveActivityCenter.shared.current == nil {
            // Only the camera housing (or handle) itself, so menu bar items beside it stay clickable.
            let closed = model.closedSize
            zone = NSRect(x: model.notchMidX - closed.width / 2, y: screen.frame.maxY - closed.height - 4,
                          width: closed.width, height: closed.height + 10)
        } else {
            zone = NSRect(x: rect.minX, y: rect.minY - 4, width: rect.width, height: rect.height + 10)
        }
        let inside = zone.contains(point)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        switch model.state {
        case .closed:
            if draggingContent {
                if inside { open(tab: .tray, viaDrag: true) }
                return
            }
            setHovering(inside)
        case .open:
            if inside {
                cancelClose()
                if model.pinned { model.pinned = false }
            } else if !model.pinned {
                scheduleClose(after: model.dragActive ? 0.3 : 0.1)
            }
        }
    }

    func refreshPointer() {
        pointerMoved(MouseTracker.shared.pointerLocation, draggingContent: MouseTracker.shared.isDraggingContent)
    }

    func fileDragEnded() {
        guard model.state == .open, model.dragActive else { return }
        model.dragActive = false
        refreshPointer()
    }

    private func setHovering(_ inside: Bool) {
        guard inside != model.hovering else { return }
        model.hovering = inside
        openTask?.cancel(); openTask = nil
        peekTask?.cancel(); peekTask = nil
        if inside {
            Haptics.tap()
            let settings = AppSettings.shared
            if settings.alwaysOpenOnHover && (settings.nookEnabled || LiveActivityCenter.shared.current == .tray) {
                openTask = after(0.12) { [weak self] in self?.open(tab: nil) }
            } else if LiveActivityCenter.shared.current != nil, settings.enableQuickPeek {
                peekTask = after(0.3) { [weak self] in self?.model.peeking = true }
            }
        } else if model.peeking {
            model.peeking = false
        }
    }

    // MARK: Open / close

    func open(tab: NotchTab?, viaDrag: Bool = false, pinned: Bool = false) {
        openTask?.cancel(); openTask = nil
        peekTask?.cancel(); peekTask = nil
        cancelClose()
        let settings = AppSettings.shared
        if let tab {
            model.tab = tab
        } else {
            model.tab = LiveActivityCenter.shared.current == .tray ? .tray : .nook
        }
        if model.tab == .nook && !settings.nookEnabled { model.tab = .tray }
        model.dragActive = viaDrag
        model.pinned = pinned
        model.peeking = false
        guard model.state != .open else { return }
        model.state = .open
        panel.ignoresMouseEvents = false
        Haptics.tap(.levelChange)
        for other in NotchRegistry.controllers where other !== self { other.close() }
        MouseTracker.shared.refreshSoon()
    }

    func close() {
        openTask?.cancel(); openTask = nil
        peekTask?.cancel(); peekTask = nil
        cancelClose()
        guard model.state == .open else { return }
        model.state = .closed
        model.dragActive = false
        model.pinned = false
        model.peeking = false
        model.calendarDayOffset = 0
        CameraService.shared.stop()
        refreshPointer()
        MouseTracker.shared.refreshSoon()
    }

    func toggle() {
        model.state == .open ? close() : open(tab: nil, pinned: true)
    }

    private func scheduleClose(after delay: Double) {
        guard closeTask == nil else { return }
        closeTask = after(delay) { [weak self] in
            guard let self else { return }
            self.closeTask = nil
            self.close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }

    // MARK: Gestures

    /// Returns true when the scroll event was used as a gesture.
    func handleScroll(_ event: NSEvent) -> Bool {
        let settings = AppSettings.shared
        guard settings.allowGestures, let direction = swipe.feed(event) else { return false }
        let point = viewPoint(for: event)
        let overCalendar = model.state == .open && model.region(.calendar, contains: point)
        let overTray = model.state == .open && model.region(.tray, contains: point)
        switch direction {
        case .down:
            guard model.state == .closed, settings.gestureControlOpenState, settings.nookEnabled else { return false }
            open(tab: nil)
            return true
        case .up:
            guard model.state == .open, settings.gestureControlOpenState, !overCalendar else { return false }
            close()
            return true
        case .left, .right:
            if overCalendar {
                model.calendarDayOffset += direction == .left ? 1 : -1
                Haptics.tap()
                return true
            }
            if overTray { return false }
            guard settings.gestureControlMedia, NowPlaying.shared.hasPlayer else { return false }
            let next = (direction == .left) == settings.invertMediaGestures
            next ? NowPlaying.shared.next() : NowPlaying.shared.previous()
            Haptics.tap()
            return true
        }
    }
}

extension NotchController {
    /// Converts an event location into the hosting view's top-left-origin coordinates.
    func viewPoint(for event: NSEvent) -> CGPoint {
        let height = panel.contentView?.bounds.height ?? panel.frame.height
        return CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
    }
}

/// Turns trackpad scroll phases into a single swipe per gesture.
final class SwipeTracker {
    enum Direction { case up, down, left, right }

    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false
    private let threshold: CGFloat = 24

    func feed(_ event: NSEvent) -> Direction? {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return nil }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            dx = 0; dy = 0; fired = false
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            dx = 0; dy = 0; fired = false
            return nil
        }
        guard !fired else { return nil }
        // Normalise to physical finger movement: positive = fingers moving down / right.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        dx += event.scrollingDeltaX * sign
        dy += event.scrollingDeltaY * sign
        if abs(dy) > threshold && abs(dy) > abs(dx) * 1.3 {
            fired = true
            return dy > 0 ? .down : .up
        }
        if abs(dx) > threshold && abs(dx) > abs(dy) * 1.3 {
            fired = true
            return dx > 0 ? .right : .left
        }
        return nil
    }
}

@MainActor
enum NotchRegistry {
    static var controllers: [NotchController] = []

    static func controller(for window: NSWindow?) -> NotchController? {
        guard let window else { return nil }
        return controllers.first { $0.panel === window }
    }

    /// The notch on the built-in display when there is one.
    static var primary: NotchController? {
        controllers.first { $0.model.hasPhysicalNotch } ?? controllers.first
    }

    static func isPointInsideOpenNotch(_ point: NSPoint) -> Bool {
        controllers.contains { $0.model.state == .open && $0.notchRect().insetBy(dx: -4, dy: -4).contains(point) }
    }
}

/// Global and local mouse monitoring shared by all notch controllers.
@MainActor
final class MouseTracker {
    static let shared = MouseTracker()

    private(set) var isDraggingContent = false
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var dragChangeCount = 0
    private var simulated: (point: NSPoint, until: Date)?

    private init() {}

    var pointerLocation: NSPoint {
        if let simulated, simulated.until > Date() { return simulated.point }
        return NSEvent.mouseLocation
    }

    func start() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        let globalMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { event in
            MainActor.assumeIsolated { MouseTracker.shared.handle(event, local: false) }
        }) {
            monitors.append(global)
        }
        let localMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .scrollWheel]
        if let local = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { event in
            let swallow = MainActor.assumeIsolated { MouseTracker.shared.handleLocal(event) }
            return swallow ? nil : event
        }) {
            monitors.append(local)
        }
        broadcast()
    }

    /// Re-evaluates every notch against the pointer on the next run loop turn and makes
    /// sure polling runs while a notch is open, even if no mouse events arrive.
    func refreshSoon() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { MouseTracker.shared.broadcast() }
        }
    }

    /// Pretends the pointer is at `point` for a while (used by automation commands).
    func simulate(_ point: NSPoint, for seconds: Double) {
        simulated = (point, Date().addingTimeInterval(seconds))
        broadcast()
    }

    /// Returns true when the event was consumed.
    private func handleLocal(_ event: NSEvent) -> Bool {
        switch event.type {
        case .scrollWheel:
            guard let controller = NotchRegistry.controller(for: event.window) else { return false }
            return controller.handleScroll(event)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            let consumed = TrayDragOut.shared.handle(event)
            handle(event, local: true)
            return consumed
        default:
            handle(event, local: true)
            return false
        }
    }

    private func handle(_ event: NSEvent, local: Bool) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if isDraggingContent { endDrag() }
        case .leftMouseDragged:
            if !local && !isDraggingContent {
                let pasteboard = NSPasteboard(name: .drag)
                if pasteboard.changeCount != dragChangeCount && Self.hasDroppableContent(pasteboard) {
                    isDraggingContent = true
                }
            }
        case .leftMouseUp:
            if isDraggingContent { endDrag() }
        default:
            break
        }
        broadcast()
    }

    private func endDrag() {
        isDraggingContent = false
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        for controller in NotchRegistry.controllers { controller.fileDragEnded() }
    }

    private func broadcast() {
        let point = pointerLocation
        for controller in NotchRegistry.controllers {
            controller.pointerMoved(point, draggingContent: isDraggingContent)
        }
        updatePolling()
    }

    /// Polls while something is open or hovered, so leaving is noticed even when
    /// no events reach the monitors (menus, our own drag sessions, other apps' drags).
    private func updatePolling() {
        let needed = isDraggingContent || simulated != nil || NotchRegistry.controllers.contains { $0.needsPolling }
        if needed && pollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in
                MainActor.assumeIsolated { MouseTracker.shared.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !needed, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    private func poll() {
        if let simulated, simulated.until <= Date() { self.simulated = nil }
        if isDraggingContent && (NSEvent.pressedMouseButtons & 1) == 0 { endDrag() }
        broadcast()
    }

    static func hasDroppableContent(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let accepted: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .URL, .png, .tiff,
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]
        return types.contains { accepted.contains($0) }
    }
}
