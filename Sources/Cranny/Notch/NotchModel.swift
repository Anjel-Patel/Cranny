import AppKit
import Combine

enum NotchState: Equatable { case closed, open }
enum NotchRegion: Hashable { case calendar, tray }
enum NotchTab: String { case nook, tray }

enum NotchAppearance: Equatable {
    /// Nothing drawn; only the physical notch is visible.
    case hidden
    /// The plain notch / handle shape.
    case idle
    /// Pointer over the closed notch: slightly grown shape.
    case hover
    /// A live activity on both sides of the notch.
    case activity
    /// A live activity plus a short line of info underneath.
    case peek
    case open
}

struct NotchLayout: Equatable {
    var appearance: NotchAppearance
    var bodyWidth: CGFloat
    var height: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    var size: CGSize { CGSize(width: bodyWidth + 2 * top, height: height) }
}

/// Per-screen notch state and geometry.
@MainActor
final class NotchModel: ObservableObject {
    let hasPhysicalNotch: Bool
    let physicalNotch: CGSize
    /// Horizontal centre of the notch (or handle) in screen coordinates.
    let notchMidX: CGFloat
    private let menuBarHeight: CGFloat

    @Published var state: NotchState = .closed
    @Published var tab: NotchTab = .nook
    @Published var hovering = false
    @Published var peeking = false
    /// The notch was opened by something being dragged onto it.
    @Published var dragActive = false
    /// Opened by a command; stays open until the pointer has passed through it.
    @Published var pinned = false
    @Published var calendarDayOffset = 0
    /// True for a moment after the notch stops being shown, so the black shape shrinks back
    /// onto the physical notch at full opacity and only then disappears.
    @Published private(set) var settling = false
    /// Bundle identifier of the app showing fullscreen on this screen ("" if unknown), or nil.
    @Published var fullscreenApp: String?
    private var settleWork: DispatchWorkItem?
    /// Frames of interactive areas in the hosting view's (top-left origin) coordinates.
    var regions: [NotchRegion: CGRect] = [:]

    func region(_ region: NotchRegion, contains point: CGPoint) -> Bool {
        regions[region]?.contains(point) ?? false
    }

    weak var controller: NotchController?

    init(screen: NSScreen) {
        let geometry = screen.notchGeometry
        hasPhysicalNotch = geometry.hasNotch
        physicalNotch = geometry.size
        notchMidX = geometry.midX
        menuBarHeight = screen.menuBarHeight
    }

    private var settings: AppSettings { AppSettings.shared }

    /// Closed shape: the camera housing on notched screens, the handle elsewhere.
    var closedSize: CGSize {
        if hasPhysicalNotch {
            return CGSize(width: max(60, physicalNotch.width + settings.notchWidthFineTune), height: physicalNotch.height)
        }
        return CGSize(width: settings.handleWidth, height: settings.handleHeight)
    }

    /// Height of the band that holds live activities and the open header: the notch on
    /// notched screens, otherwise the menu bar (with a floor so artwork stays legible).
    var barHeight: CGFloat { hasPhysicalNotch ? physicalNotch.height : max(26, min(menuBarHeight, 40)) }
    var sideWidth: CGFloat { barHeight + 6 }
    var activityBodyWidth: CGFloat { closedSize.width + 2 * sideWidth }

    var cell: CGFloat { AppSettings.cellSize }
    var contentHeight: CGFloat { CGFloat(settings.nookHeightCells) * cell }
    var contentWidth: CGFloat {
        let count = max(1, settings.visibleWidgets.count)
        return CGFloat(settings.nookWidthCells) * cell + CGFloat(count - 1) * settings.widgetsPadding
    }
    var openBodyWidth: CGFloat { contentWidth + 2 * settings.contentPadding }
    var openHeight: CGFloat { barHeight + 6 + contentHeight + settings.contentPadding }

    func appearance(activity: LiveActivityKind?) -> NotchAppearance {
        if state == .open { return .open }
        if activity != nil {
            return peeking && settings.enableQuickPeek ? .peek : .activity
        }
        if hovering { return .hover }
        if !hasPhysicalNotch || settings.demoMode || settling { return .idle }
        return .hidden
    }

    /// Keeps the shape drawn while it shrinks back to the notch's size, then lets it hide.
    func settle() {
        settleWork?.cancel()
        settling = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settling = false }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: Fullscreen

    /// The live activity this screen should show, after applying the fullscreen setting.
    func visibleActivity(_ activity: LiveActivityKind?) -> LiveActivityKind? {
        guard let activity, let app = fullscreenApp else { return activity }
        switch settings.fullscreenBehavior {
        case .showEverything:
            return activity
        case .hideWhileWatching:
            return isPlayingMedia(app) ? nil : activity
        case .hideLiveActivities, .hideEverything:
            return nil
        }
    }

    /// In fullscreen with "Hide Cranny entirely", the notch ignores the pointer completely.
    var isDisabledForFullscreen: Bool {
        fullscreenApp != nil && settings.fullscreenBehavior == .hideEverything
    }

    /// Whether the fullscreen app is the one playing media (YouTube in a browser, IINA, …).
    private func isPlayingMedia(_ app: String) -> Bool {
        let player = NowPlaying.shared
        let source = player.bundleID
        guard player.hasPlayer, !app.isEmpty, !source.isEmpty else { return false }
        return app == source || app.hasPrefix(source + ".") || source.hasPrefix(app + ".")
    }

    func layout(activity: LiveActivityKind?) -> NotchLayout {
        let closed = closedSize
        let a = appearance(activity: activity)
        switch a {
        case .hidden, .idle:
            return hasPhysicalNotch
                ? NotchLayout(appearance: a, bodyWidth: closed.width, height: closed.height, top: 6, bottom: 10)
                : NotchLayout(appearance: a, bodyWidth: closed.width, height: closed.height, top: 3, bottom: closed.height / 2)
        case .hover:
            return hasPhysicalNotch
                ? NotchLayout(appearance: a, bodyWidth: closed.width + 14, height: closed.height + 5, top: 7, bottom: 12)
                : NotchLayout(appearance: a, bodyWidth: closed.width + 16, height: closed.height + 8, top: 4, bottom: (closed.height + 8) / 2)
        case .activity:
            let bump: CGFloat = hovering ? 8 : 0
            return NotchLayout(appearance: a, bodyWidth: activityBodyWidth + bump, height: barHeight + bump / 4, top: 6, bottom: 12)
        case .peek:
            return NotchLayout(appearance: a, bodyWidth: max(activityBodyWidth + 70, 330), height: barHeight + 30, top: 8, bottom: 16)
        case .open:
            return NotchLayout(appearance: a, bodyWidth: openBodyWidth, height: openHeight, top: 12, bottom: 24)
        }
    }

    /// Largest size the notch can take, used to size the window.
    var maximumSize: CGSize {
        CGSize(width: max(openBodyWidth + 24, 400), height: max(openHeight, barHeight + 40))
    }

    // MARK: Actions (forwarded to the controller, which owns timing and the window)

    func open(tab: NotchTab? = nil) { controller?.open(tab: tab) }
    func close() { controller?.close() }
}

/// Decides which live activity (if any) is shown around the closed notch.
@MainActor
final class LiveActivityCenter: ObservableObject {
    static let shared = LiveActivityCenter()

    @Published private(set) var current: LiveActivityKind?
    @Published private(set) var calendarEvent: CalendarEventInfo?
    @Published private(set) var calendarInProgress = false

    private var bag = Set<AnyCancellable>()
    private var timer: Timer?
    private var scheduled = false

    private init() {}

    func start() {
        NowPlaying.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRecompute() }.store(in: &bag)
        TrayStore.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRecompute() }.store(in: &bag)
        AppSettings.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRecompute() }.store(in: &bag)
        CalendarService.shared.objectWillChange.sink { [weak self] _ in self?.scheduleRecompute() }.store(in: &bag)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { LiveActivityCenter.shared.recompute() }
        }
        recompute()
    }

    private func scheduleRecompute() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let center = LiveActivityCenter.shared
                center.scheduled = false
                center.recompute()
            }
        }
    }

    func recompute() {
        let s = AppSettings.shared
        var next: LiveActivityKind?
        var event: CalendarEventInfo?
        var inProgress = false
        if s.liveActivitiesEnabled {
            if s.isLiveActivityEnabled(.calendar), let live = CalendarService.shared.liveEvent() {
                next = .calendar
                event = live.event
                inProgress = live.inProgress
            } else if s.isLiveActivityEnabled(.media), NowPlaying.shared.isActive(timeout: s.inactivityTimeout) {
                next = .media
            } else if s.isLiveActivityEnabled(.tray), !TrayStore.shared.items.isEmpty {
                next = .tray
            }
        }
        if current != next { current = next }
        if calendarEvent != event { calendarEvent = event }
        if calendarInProgress != inProgress { calendarInProgress = inProgress }
    }
}
