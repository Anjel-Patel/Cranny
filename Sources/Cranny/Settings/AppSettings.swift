import AppKit
import Combine

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case media, calendar, shortcuts, mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media Player"
        case .calendar: return "Calendar"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        }
    }

    var symbol: String {
        switch self {
        case .media: return "play.square.stack"
        case .calendar: return "calendar"
        case .shortcuts: return "square.grid.2x2"
        case .mirror: return "person.crop.square"
        }
    }
}

enum LiveActivityKind: String, CaseIterable, Identifiable, Codable {
    case media, calendar, tray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .tray: return "Files Tray"
        }
    }

    var symbol: String {
        switch self {
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .tray: return "tray.full"
        }
    }
}

enum MediaEffect: String, CaseIterable, Identifiable {
    case audioSpectrograph, gif, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audioSpectrograph: return "Audio spectrograph"
        case .gif: return "Custom GIF"
        case .none: return "None"
        }
    }
}

enum FullscreenBehavior: String, CaseIterable, Identifiable {
    case showEverything, hideWhileWatching, hideLiveActivities, hideEverything

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showEverything: return "Show everything"
        case .hideWhileWatching: return "Hide live activities while watching video"
        case .hideLiveActivities: return "Hide live activities"
        case .hideEverything: return "Hide Cranny entirely"
        }
    }
}

/// Every user-facing option. Values persist to UserDefaults as soon as they change.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(loadFromStore: true)

    /// Size of one widget grid cell, in points.
    static let cellSize: CGFloat = 50

    private let store = UserDefaults.standard
    private var persists = false

    // MARK: General
    @Published var alwaysOpenOnHover = false { didSet { put("alwaysOpenOnHover", alwaysOpenOnHover) } }
    @Published var disableHaptics = false { didSet { put("disableHaptics", disableHaptics) } }
    @Published var contentPadding: Double = 12 { didSet { put("contentPadding", contentPadding) } }
    @Published var notchWidthFineTune: Double = 0 { didSet { put("notchWidthFineTune", notchWidthFineTune) } }
    @Published var translucent = false { didSet { put("translucent", translucent) } }
    @Published var enableOnNonNotchScreens = false { didSet { put("enableOnNonNotchScreens", enableOnNonNotchScreens) } }
    @Published var handleWidth: Double = 184 { didSet { put("handleWidth", handleWidth) } }
    @Published var handleHeight: Double = 8 { didSet { put("handleHeight", handleHeight) } }
    @Published var transparentHandle = false { didSet { put("transparentHandle", transparentHandle) } }
    @Published var demoMode = false { didSet { put("demoMode", demoMode) } }
    @Published var fullscreenBehavior: FullscreenBehavior = .hideWhileWatching {
        didSet { put("fullscreenBehavior", fullscreenBehavior.rawValue) }
    }

    // MARK: Gestures
    @Published var allowGestures = true { didSet { put("allowGestures", allowGestures) } }
    @Published var gestureControlOpenState = true { didSet { put("gestureControlOpenState", gestureControlOpenState) } }
    @Published var gestureControlMedia = true { didSet { put("gestureControlMedia", gestureControlMedia) } }
    @Published var invertMediaGestures = false { didSet { put("invertMediaGestures", invertMediaGestures) } }

    // MARK: Nook
    @Published var nookEnabled = true { didSet { put("nookEnabled", nookEnabled) } }
    @Published var nookWidthCells = 11 { didSet { put("nookWidthCells", nookWidthCells) } }
    @Published var nookHeightCells = 2 { didSet { put("nookHeightCells", nookHeightCells) } }
    @Published var enabledWidgets: [WidgetKind] = [.media, .shortcuts, .mirror] {
        didSet { put("enabledWidgets", enabledWidgets.map(\.rawValue)) }
    }
    @Published var showDividers = true { didSet { put("showDividers", showDividers) } }
    @Published var widgetsPadding: Double = 12 { didSet { put("widgetsPadding", widgetsPadding) } }
    @Published var mediaWidthCells = 5 { didSet { put("mediaWidthCells", mediaWidthCells) } }
    @Published var calendarWidthCells = 4 { didSet { put("calendarWidthCells", calendarWidthCells) } }
    @Published var shortcutsWidthCells = 3 { didSet { put("shortcutsWidthCells", shortcutsWidthCells) } }
    @Published var shortcutColumns = 1 { didSet { put("shortcutColumns", shortcutColumns) } }
    @Published var shortcutsToDisplay: [String] = [] { didSet { put("shortcutsToDisplay", shortcutsToDisplay) } }

    // MARK: Live activities
    @Published var liveActivitiesEnabled = true { didSet { put("liveActivitiesEnabled", liveActivitiesEnabled) } }
    @Published var enabledLiveActivities: [LiveActivityKind] = [.media, .tray] {
        didSet { put("enabledLiveActivities", enabledLiveActivities.map(\.rawValue)) }
    }
    @Published var enableQuickPeek = true { didSet { put("enableQuickPeek", enableQuickPeek) } }
    @Published var interactiveActivities = true { didSet { put("interactiveActivities", interactiveActivities) } }
    @Published var inactivityTimeout: Double = 10 { didSet { put("inactivityTimeout", inactivityTimeout) } }
    @Published var mediaEffect: MediaEffect = .audioSpectrograph { didSet { put("mediaEffect", mediaEffect.rawValue) } }
    @Published var coloredSpectrograph = true { didSet { put("coloredSpectrograph", coloredSpectrograph) } }
    @Published var albumCornerRadius: Double = 5 { didSet { put("albumCornerRadius", albumCornerRadius) } }
    @Published var gifPath = "" { didSet { put("gifPath", gifPath) } }

    // MARK: Calendar
    @Published var calendarMinutesBefore = 15 { didSet { put("calendarMinutesBefore", calendarMinutesBefore) } }
    @Published var calendarShowWhileInEvent = false { didSet { put("calendarShowWhileInEvent", calendarShowWhileInEvent) } }
    @Published var calendarShowTimeLapsed = true { didSet { put("calendarShowTimeLapsed", calendarShowTimeLapsed) } }
    @Published var calendarOnlyMeetings = false { didSet { put("calendarOnlyMeetings", calendarOnlyMeetings) } }
    @Published var hiddenCalendarIDs: [String] = [] { didSet { put("hiddenCalendarIDs", hiddenCalendarIDs) } }

    // MARK: Onboarding
    @Published var hasCompletedOnboarding = false { didSet { put("hasCompletedOnboarding", hasCompletedOnboarding) } }

    private init(loadFromStore: Bool) {
        guard loadFromStore else { return }
        load()
        persists = true
    }

    private func put(_ key: String, _ value: Any) {
        guard persists else { return }
        store.set(value, forKey: key)
    }

    private func read<T>(_ key: String, _ fallback: T) -> T {
        guard let raw = store.object(forKey: key) else { return fallback }
        if let value = raw as? T { return value }
        if let number = raw as? NSNumber {
            if T.self == Int.self { return number.intValue as! T }
            if T.self == Double.self { return number.doubleValue as! T }
            if T.self == Bool.self { return number.boolValue as! T }
        }
        return fallback
    }

    private func load() {
        alwaysOpenOnHover = read("alwaysOpenOnHover", alwaysOpenOnHover)
        disableHaptics = read("disableHaptics", disableHaptics)
        contentPadding = read("contentPadding", contentPadding)
        notchWidthFineTune = read("notchWidthFineTune", notchWidthFineTune)
        translucent = read("translucent", translucent)
        enableOnNonNotchScreens = read("enableOnNonNotchScreens", enableOnNonNotchScreens)
        handleWidth = read("handleWidth", handleWidth)
        handleHeight = read("handleHeight", handleHeight)
        transparentHandle = read("transparentHandle", transparentHandle)
        demoMode = read("demoMode", demoMode)
        fullscreenBehavior = FullscreenBehavior(rawValue: read("fullscreenBehavior", fullscreenBehavior.rawValue)) ?? .hideWhileWatching

        allowGestures = read("allowGestures", allowGestures)
        gestureControlOpenState = read("gestureControlOpenState", gestureControlOpenState)
        gestureControlMedia = read("gestureControlMedia", gestureControlMedia)
        invertMediaGestures = read("invertMediaGestures", invertMediaGestures)

        nookEnabled = read("nookEnabled", nookEnabled)
        nookWidthCells = read("nookWidthCells", nookWidthCells)
        nookHeightCells = read("nookHeightCells", nookHeightCells)
        if let raw = store.stringArray(forKey: "enabledWidgets") {
            enabledWidgets = raw.compactMap(WidgetKind.init(rawValue:))
        }
        showDividers = read("showDividers", showDividers)
        widgetsPadding = read("widgetsPadding", widgetsPadding)
        mediaWidthCells = read("mediaWidthCells", mediaWidthCells)
        calendarWidthCells = read("calendarWidthCells", calendarWidthCells)
        shortcutsWidthCells = read("shortcutsWidthCells", shortcutsWidthCells)
        shortcutColumns = read("shortcutColumns", shortcutColumns)
        shortcutsToDisplay = store.stringArray(forKey: "shortcutsToDisplay") ?? shortcutsToDisplay

        liveActivitiesEnabled = read("liveActivitiesEnabled", liveActivitiesEnabled)
        if let raw = store.stringArray(forKey: "enabledLiveActivities") {
            enabledLiveActivities = raw.compactMap(LiveActivityKind.init(rawValue:))
        }
        enableQuickPeek = read("enableQuickPeek", enableQuickPeek)
        interactiveActivities = read("interactiveActivities", interactiveActivities)
        inactivityTimeout = read("inactivityTimeout", inactivityTimeout)
        mediaEffect = MediaEffect(rawValue: read("mediaEffect", mediaEffect.rawValue)) ?? .audioSpectrograph
        coloredSpectrograph = read("coloredSpectrograph", coloredSpectrograph)
        albumCornerRadius = read("albumCornerRadius", albumCornerRadius)
        gifPath = read("gifPath", gifPath)

        calendarMinutesBefore = read("calendarMinutesBefore", calendarMinutesBefore)
        calendarShowWhileInEvent = read("calendarShowWhileInEvent", calendarShowWhileInEvent)
        calendarShowTimeLapsed = read("calendarShowTimeLapsed", calendarShowTimeLapsed)
        calendarOnlyMeetings = read("calendarOnlyMeetings", calendarOnlyMeetings)
        hiddenCalendarIDs = store.stringArray(forKey: "hiddenCalendarIDs") ?? hiddenCalendarIDs

        hasCompletedOnboarding = read("hasCompletedOnboarding", hasCompletedOnboarding)
    }

    /// Restores every option (except onboarding state) to its default.
    func resetAll() {
        let d = AppSettings(loadFromStore: false)
        alwaysOpenOnHover = d.alwaysOpenOnHover
        disableHaptics = d.disableHaptics
        contentPadding = d.contentPadding
        notchWidthFineTune = d.notchWidthFineTune
        translucent = d.translucent
        enableOnNonNotchScreens = d.enableOnNonNotchScreens
        handleWidth = d.handleWidth
        handleHeight = d.handleHeight
        transparentHandle = d.transparentHandle
        demoMode = d.demoMode
        fullscreenBehavior = d.fullscreenBehavior
        allowGestures = d.allowGestures
        gestureControlOpenState = d.gestureControlOpenState
        gestureControlMedia = d.gestureControlMedia
        invertMediaGestures = d.invertMediaGestures
        nookEnabled = d.nookEnabled
        nookWidthCells = d.nookWidthCells
        nookHeightCells = d.nookHeightCells
        enabledWidgets = d.enabledWidgets
        showDividers = d.showDividers
        widgetsPadding = d.widgetsPadding
        mediaWidthCells = d.mediaWidthCells
        calendarWidthCells = d.calendarWidthCells
        shortcutsWidthCells = d.shortcutsWidthCells
        shortcutColumns = d.shortcutColumns
        shortcutsToDisplay = d.shortcutsToDisplay
        liveActivitiesEnabled = d.liveActivitiesEnabled
        enabledLiveActivities = d.enabledLiveActivities
        enableQuickPeek = d.enableQuickPeek
        interactiveActivities = d.interactiveActivities
        inactivityTimeout = d.inactivityTimeout
        mediaEffect = d.mediaEffect
        coloredSpectrograph = d.coloredSpectrograph
        albumCornerRadius = d.albumCornerRadius
        gifPath = d.gifPath
        calendarMinutesBefore = d.calendarMinutesBefore
        calendarShowWhileInEvent = d.calendarShowWhileInEvent
        calendarShowTimeLapsed = d.calendarShowTimeLapsed
        calendarOnlyMeetings = d.calendarOnlyMeetings
        hiddenCalendarIDs = d.hiddenCalendarIDs
    }

    // MARK: Derived values

    func widthCells(for kind: WidgetKind) -> Int {
        switch kind {
        case .media: return mediaWidthCells
        case .calendar: return calendarWidthCells
        case .shortcuts: return shortcutsWidthCells
        case .mirror: return nookHeightCells
        }
    }

    func setWidthCells(_ value: Int, for kind: WidgetKind) {
        switch kind {
        case .media: mediaWidthCells = value
        case .calendar: calendarWidthCells = value
        case .shortcuts: shortcutsWidthCells = value
        case .mirror: break
        }
    }

    func widthRange(for kind: WidgetKind) -> ClosedRange<Int> {
        switch kind {
        case .media: return 4...8
        case .calendar: return 3...6
        case .shortcuts: return 2...8
        case .mirror: return nookHeightCells...nookHeightCells
        }
    }

    /// Widgets that fit in the nook, in order. Widgets that overflow are hidden.
    var visibleWidgets: [WidgetKind] {
        var used = 0
        var result: [WidgetKind] = []
        for kind in enabledWidgets {
            let w = widthCells(for: kind)
            if used + w <= nookWidthCells {
                result.append(kind)
                used += w
            }
        }
        return result
    }

    var usedCells: Int { visibleWidgets.reduce(0) { $0 + widthCells(for: $1) } }

    func isLiveActivityEnabled(_ kind: LiveActivityKind) -> Bool {
        liveActivitiesEnabled && enabledLiveActivities.contains(kind)
    }

    func setLiveActivity(_ kind: LiveActivityKind, enabled: Bool) {
        if enabled {
            if !enabledLiveActivities.contains(kind) { enabledLiveActivities.append(kind) }
        } else {
            enabledLiveActivities.removeAll { $0 == kind }
        }
    }
}
