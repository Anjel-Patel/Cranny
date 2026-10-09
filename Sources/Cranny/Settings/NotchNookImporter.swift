import Foundation

/// One-time import of the user's existing NotchNook preferences, so the new app
/// starts with the same layout and behaviour they had configured.
@MainActor
enum NotchNookImporter {
    private static let doneKey = "didImportNotchNookSettings"

    static func importIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)
        guard let source = UserDefaults(suiteName: "lo.cafe.NotchNook") else { return }
        let s = AppSettings.shared
        var imported = false

        func json(_ key: String) -> [String: Any]? {
            guard let text = source.string(forKey: key), let data = text.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        func bool(_ d: [String: Any], _ key: String) -> Bool? { (d[key] as? NSNumber)?.boolValue }
        func double(_ d: [String: Any], _ key: String) -> Double? { (d[key] as? NSNumber)?.doubleValue }
        func cells(_ d: [String: Any], _ key: String) -> Int? {
            guard let size = d["size"] as? [String: Any], let dim = size[key] as? [String: Any] else { return nil }
            return (dim["value"] as? NSNumber)?.intValue
        }

        if let g = json("generalSettings") {
            imported = true
            if let v = bool(g, "alwaysOpenNotchOnHover") { s.alwaysOpenOnHover = v }
            if let v = double(g, "contentPadding") { s.contentPadding = v }
            if let v = bool(g, "disableHaptics") { s.disableHaptics = v }
            if let v = bool(g, "enableOnNonNotchScreens") { s.enableOnNonNotchScreens = v }
            if let v = double(g, "notchWidthFineTune") { s.notchWidthFineTune = v }
            if let v = bool(g, "transluscent") { s.translucent = v }
            if let v = bool(g, "transparentHandle") { s.transparentHandle = v }
            if let v = bool(g, "demoMode") { s.demoMode = v }
            if let size = g["handleSize"] as? [NSNumber], size.count == 2 {
                s.handleWidth = size[0].doubleValue
                s.handleHeight = size[1].doubleValue
            }
        }

        if let g = json("gestureControlSettings") {
            imported = true
            if let v = bool(g, "allowGestures") { s.allowGestures = v }
            if let v = bool(g, "controlMedia") { s.gestureControlMedia = v }
            if let v = bool(g, "controlOpenState") { s.gestureControlOpenState = v }
            if let v = bool(g, "invertMediaGestures") { s.invertMediaGestures = v }
        }

        if let l = json("liveActivitiesSettings") {
            imported = true
            if let v = bool(l, "enabled") { s.liveActivitiesEnabled = v }
            if let v = bool(l, "enableQuickPeek") { s.enableQuickPeek = v }
            if let v = bool(l, "interactive") { s.interactiveActivities = v }
            if let v = double(l, "inactivityTimeoutInSecs") { s.inactivityTimeout = v }
            if let list = l["enabledLiveActivities"] as? [String] {
                s.enabledLiveActivities = list.compactMap(LiveActivityKind.init(rawValue:))
            }
        }

        if let m = json("mediaLiveActivitySettings") {
            imported = true
            if let v = double(m, "albumCornerRadius") { s.albumCornerRadius = v }
            if let v = bool(m, "isAutomaticallyColored") { s.coloredSpectrograph = v }
            if let v = m["effect"] as? String, let effect = MediaEffect(rawValue: v) { s.mediaEffect = effect }
        }

        if let c = json("calendarLiveActivitySettings") {
            imported = true
            if let v = double(c, "minutesBeforeEvent") { s.calendarMinutesBefore = Int(v) }
            if let v = bool(c, "onlyEventsWithMeetings") { s.calendarOnlyMeetings = v }
            if let v = bool(c, "showEventTimeLapsed") { s.calendarShowTimeLapsed = v }
            if let v = bool(c, "showWhileInEvent") { s.calendarShowWhileInEvent = v }
        }

        if let n = json("nookSettings") {
            imported = true
            if let v = bool(n, "enabled") { s.nookEnabled = v }
            if let v = bool(n, "showDividers") { s.showDividers = v }
            if let v = double(n, "widgetsPadding") { s.widgetsPadding = v }
            if let v = cells(n, "width") { s.nookWidthCells = max(4, min(20, v)) }
            if let v = cells(n, "height") { s.nookHeightCells = max(2, min(4, v)) }
            if let list = n["enabledWidgets"] as? [String] {
                s.enabledWidgets = list.compactMap(WidgetKind.init(rawValue:))
            }
        }

        if let c = json("calendarWidgetSettings"), let w = cells(c, "width") {
            s.calendarWidthCells = max(3, min(6, w))
        }

        if let sc = json("shortcutsWidgetSettings") {
            if let w = cells(sc, "width") { s.shortcutsWidthCells = max(2, min(8, w)) }
            if let button = (sc["shortcutButtonWidth"] as? [String: Any])?["value"] as? NSNumber, button.intValue > 0 {
                s.shortcutColumns = max(1, min(4, s.shortcutsWidthCells / button.intValue))
            }
            if let list = sc["shortcutsToDisplay"] as? [String] { s.shortcutsToDisplay = list }
        }

        // Media gets whatever is left of the nook after the other enabled widgets.
        let others = s.enabledWidgets.filter { $0 != .media }.reduce(0) { $0 + s.widthCells(for: $1) }
        if s.enabledWidgets.contains(.media) {
            s.mediaWidthCells = max(4, min(8, s.nookWidthCells - others))
        }

        if imported { Log.app.info("Imported NotchNook preferences") }
    }
}
