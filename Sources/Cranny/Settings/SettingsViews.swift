import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    enum Pane: Int, CaseIterable {
        case general, nook, liveActivities, calendar, shortcuts, about

        init?(name: String) {
            switch name.lowercased() {
            case "general": self = .general
            case "nook", "widgets": self = .nook
            case "live", "liveactivities", "activities": self = .liveActivities
            case "calendar": self = .calendar
            case "shortcuts": self = .shortcuts
            case "about": self = .about
            default: return nil
            }
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .nook: return "Nook"
            case .liveActivities: return "Live Activities"
            case .calendar: return "Calendar"
            case .shortcuts: return "Shortcuts"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .nook: return "square.grid.2x2"
            case .liveActivities: return "waveform"
            case .calendar: return "calendar"
            case .shortcuts: return "bolt.horizontal"
            case .about: return "info.circle"
            }
        }

        /// nil lets the pane size itself to its content.
        var height: CGFloat? {
            switch self {
            case .general: return 620
            case .nook: return 520
            case .liveActivities: return 620
            case .calendar: return 460
            case .shortcuts: return 480
            case .about: return nil
            }
        }

        @MainActor var view: AnyView {
            let content: AnyView
            switch self {
            case .general: content = AnyView(GeneralSettingsView())
            case .nook: content = AnyView(NookSettingsView())
            case .liveActivities: content = AnyView(LiveActivitiesSettingsView())
            case .calendar: content = AnyView(CalendarSettingsView())
            case .shortcuts: content = AnyView(ShortcutsSettingsView())
            case .about: content = AnyView(AboutView())
            }
            return AnyView(
                content
                    .environmentObject(AppSettings.shared)
                    .environmentObject(CalendarService.shared)
                    .environmentObject(ShortcutsService.shared)
                    .environmentObject(UpdateChecker.shared)
                    .frame(width: 540, height: height)
                    .fixedSize(horizontal: false, vertical: height == nil)
            )
        }
    }

    private var window: NSWindow?
    private var tabs: NSTabViewController?

    func show(pane: Pane? = nil) {
        if window == nil { build() }
        if let pane { tabs?.selectedTabViewItemIndex = pane.rawValue }
        if let tabs { window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: pane.view)
            host.sizingOptions = [.preferredContentSize]
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.tabs = tabs
        self.window = window
    }
}

/// Keeps the window title in sync with the selected pane, like System Settings-style windows.
final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }

    /// The About pane grows when an update shows up, so resize the window with it,
    /// keeping the top edge in place.
    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard let window = view.window, selectedTabViewItemIndex >= 0,
              tabViewItems[selectedTabViewItemIndex].viewController === viewController
        else { return }
        let delta = viewController.preferredContentSize.height - view.frame.height
        guard abs(delta) >= 1 else { return }
        var frame = window.frame
        frame.origin.y -= delta
        frame.size.height += delta
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

// MARK: - Rows

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .frame(width: 170)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text("\(Int(value.rounded()))\(unit)"))
                Text("\(Int(value.rounded()))\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// A toggle whose switch carries its own accessibility label. In grouped forms SwiftUI
/// draws the title as a separate row label that isn't linked to the switch, which leaves
/// VoiceOver announcing an unnamed checkbox.
struct LabeledToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .accessibilityLabel(Text(title))
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var s: AppSettings
    @ViewState private var launchAtLogin = LoginItem.isEnabled
    @ViewState private var confirmReset = false

    private var detectedWidth: Int {
        Int(NSScreen.screens.lazy.map(\.notchGeometry).first(where: \.hasNotch)?.size.width ?? 0)
    }

    var body: some View {
        Form {
            Section {
                LabeledToggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LoginItem.set(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                LabeledToggle("Always open on hover", isOn: $s.alwaysOpenOnHover)
                Caption("When off, hovering wakes the notch up and a click opens it.")
                LabeledToggle("Disable haptics", isOn: $s.disableHaptics)
            }

            Section("Notch") {
                SliderRow(title: "Content padding", value: $s.contentPadding, range: 4...24, unit: "pt")
                SliderRow(title: "Notch width fine tune", value: $s.notchWidthFineTune, range: -40...40, unit: "pt")
                Caption(detectedWidth > 0
                    ? "Cranny measures your notch automatically (detected: \(detectedWidth)pt). If the black shape looks a bit off, fine-tune it until it matches your notch exactly."
                    : "No notch detected on the connected screens.")
                LabeledToggle("Translucent notch background (experimental)", isOn: $s.translucent)
                LabeledToggle("Demo mode", isOn: $s.demoMode)
                Caption("Keeps the notch drawn while idle. Useful for screen recordings (no effect on screens without a notch).")
            }

            Section("Fullscreen") {
                Picker("In fullscreen apps", selection: $s.fullscreenBehavior) {
                    ForEach(FullscreenBehavior.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityLabel(Text("In fullscreen apps"))
                Caption("\"While watching video\" means the fullscreen app is the one playing media, like YouTube in your browser, IINA or Netflix. Music from another app still shows. \"Hide Cranny entirely\" also stops the notch from opening while an app is fullscreen.")
            }

            Section("Screens without a notch") {
                LabeledToggle("Show on screens without a notch", isOn: $s.enableOnNonNotchScreens)
                Caption("On a Mac without a notch, Cranny always shows the handle on the main screen.")
                SliderRow(title: "Handle width", value: $s.handleWidth, range: 80...320, step: 2, unit: "pt")
                    .disabled(!s.enableOnNonNotchScreens)
                SliderRow(title: "Handle height", value: $s.handleHeight, range: 4...24, unit: "pt")
                    .disabled(!s.enableOnNonNotchScreens)
                LabeledToggle("Transparent handle", isOn: $s.transparentHandle)
                    .disabled(!s.enableOnNonNotchScreens)
            }

            Section("Gestures") {
                LabeledToggle("Allow gestures when hovering the notch", isOn: $s.allowGestures)
                LabeledToggle("Open/close the notch with vertical swipes", isOn: $s.gestureControlOpenState)
                    .disabled(!s.allowGestures)
                LabeledToggle("Control media with horizontal swipes", isOn: $s.gestureControlMedia)
                    .disabled(!s.allowGestures)
                LabeledToggle("Invert media gesture actions", isOn: $s.invertMediaGestures)
                    .disabled(!s.allowGestures || !s.gestureControlMedia)
                Caption("When on, a left swipe plays the next song; when off, it goes back to the previous one.")
            }

            Section {
                HStack {
                    Button("Reset all settings…") { confirmReset = true }
                    Spacer()
                    Button("Quit Cranny") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { s.resetAll() }
        } message: {
            Text("Every option goes back to its default. Files in the tray are kept.")
        }
    }
}

// MARK: - Nook

struct NookSettingsView: View {
    @EnvironmentObject var s: AppSettings

    private var available: [WidgetKind] { WidgetKind.allCases.filter { !s.enabledWidgets.contains($0) } }

    var body: some View {
        Form {
            Section {
                LabeledToggle("Enable nook", isOn: $s.nookEnabled)
                Caption("If disabled, clicking the notch won't do anything. Dragging files onto it still opens the tray.")
            }

            Section("Size") {
                Stepper("Width: \(s.nookWidthCells) cells", value: $s.nookWidthCells, in: 9...16)
                    .accessibilityLabel(Text("Nook width"))
                    .accessibilityValue(Text("\(s.nookWidthCells) cells"))
                Stepper("Height: \(s.nookHeightCells) cells", value: $s.nookHeightCells, in: 2...3)
                    .accessibilityLabel(Text("Nook height"))
                    .accessibilityValue(Text("\(s.nookHeightCells) cells"))
                Caption("Widget sizes are measured in grid cells. 1 cell is \(Int(AppSettings.cellSize))pt.")
                LabeledToggle("Show dividers between widgets", isOn: $s.showDividers)
                SliderRow(title: "Padding around widgets", value: $s.widgetsPadding, range: 4...24, unit: "pt")
            }

            Section {
                ForEach(Array(s.enabledWidgets.enumerated()), id: \.element) { index, kind in
                    WidgetSettingsRow(kind: kind, index: index)
                }
                if !available.isEmpty {
                    Menu("Add Widget") {
                        ForEach(available) { kind in
                            Button {
                                s.enabledWidgets.append(kind)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                HStack {
                    Text("Widgets")
                    Spacer()
                    Text("TOTAL CELLS: \(s.nookWidthCells)    REMAINING CELLS: \(s.nookWidthCells - s.usedCells)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct WidgetSettingsRow: View {
    @EnvironmentObject var s: AppSettings
    let kind: WidgetKind
    let index: Int

    var body: some View {
        let visible = s.visibleWidgets.contains(kind)
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                Text(visible ? "\(s.widthCells(for: kind)) cells wide" : "Hidden, it doesn't fit.")
                    .font(.caption)
                    .foregroundStyle(visible ? Color.secondary : Color.orange)
            }
            Spacer()
            if kind != .mirror {
                Stepper(
                    "\(kind.title) width",
                    value: Binding(get: { s.widthCells(for: kind) }, set: { s.setWidthCells($0, for: kind) }),
                    in: s.widthRange(for: kind)
                )
                .labelsHidden()
                .accessibilityValue(Text("\(s.widthCells(for: kind)) cells"))
            }
            Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
            Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == s.enabledWidgets.count - 1)
            Button {
                s.enabledWidgets.removeAll { $0 == kind }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
        }
        .buttonStyle(.borderless)
    }

    private func move(by delta: Int) {
        var list = s.enabledWidgets
        let target = index + delta
        guard list.indices.contains(index), list.indices.contains(target) else { return }
        list.swapAt(index, target)
        s.enabledWidgets = list
    }
}

// MARK: - Live activities

struct LiveActivitiesSettingsView: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledToggle("Enable live activities", isOn: $s.liveActivitiesEnabled)
                Group {
                    LabeledToggle("Enable Quick Peek", isOn: $s.enableQuickPeek)
                    Caption("Hover a live activity to take a quick peek at its details.")
                    LabeledToggle("Enable interactive activities", isOn: $s.interactiveActivities)
                    Caption("Clicking an activity acts on it (play/pause, join a meeting) instead of opening the nook.")
                    SliderRow(title: "Inactivity timeout", value: $s.inactivityTimeout, range: 0...60, unit: "s")
                    Caption("How long an activity sticks around after it becomes inactive, like when music pauses.")
                }
                .disabled(!s.liveActivitiesEnabled)
            }

            Section("Activities") {
                ForEach(LiveActivityKind.allCases) { kind in
                    Toggle(isOn: Binding(
                        get: { s.enabledLiveActivities.contains(kind) },
                        set: { s.setLiveActivity(kind, enabled: $0) }
                    )) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                    .accessibilityLabel(Text(kind.title))
                }
            }
            .disabled(!s.liveActivitiesEnabled)

            Section("Media") {
                LabeledToggle("Only show music", isOn: $s.onlyShowMusic)
                Caption("Shows Spotify, Apple Music, TIDAL, Amazon Music and other music apps, plus songs playing in your browser, but not videos. Applies to live activities and the nook's media player.")
                Picker("Effect", selection: $s.mediaEffect) {
                    ForEach(MediaEffect.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityLabel(Text("Effect"))
                if s.mediaEffect == .audioSpectrograph {
                    LabeledToggle("Colored spectrograph", isOn: $s.coloredSpectrograph)
                    Caption("Tints the spectrograph with the colour of the current album art; otherwise it's white.")
                }
                if s.mediaEffect == .gif {
                    LabeledContent("GIF") {
                        HStack {
                            Text(s.gifPath.isEmpty ? "None chosen" : (s.gifPath as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Button("Choose…", action: chooseGIF)
                        }
                    }
                }
                SliderRow(title: "Album corner radius", value: $s.albumCornerRadius, range: 0...12, unit: "pt")
            }

            Section("Calendar") {
                Stepper("Show up \(s.calendarMinutesBefore) minutes before an event", value: $s.calendarMinutesBefore, in: 1...120)
                    .accessibilityLabel(Text("Minutes before an event"))
                    .accessibilityValue(Text("\(s.calendarMinutesBefore) minutes"))
                LabeledToggle("Show while in events", isOn: $s.calendarShowWhileInEvent)
                LabeledToggle("Show time lapsed while in events", isOn: $s.calendarShowTimeLapsed)
                    .disabled(!s.calendarShowWhileInEvent)
                LabeledToggle("Only events with a meeting link", isOn: $s.calendarOnlyMeetings)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let destination = TrayStore.supportDirectory.appendingPathComponent("live-activity.gif")
        try? FileManager.default.createDirectory(at: TrayStore.supportDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            s.gifPath = ""
            s.gifPath = destination.path
        } catch {
            s.gifPath = url.path
        }
    }
}

// MARK: - Calendar

struct CalendarSettingsView: View {
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var calendar: CalendarService

    private var groups: [(String, [EKCalendar])] {
        Dictionary(grouping: calendar.calendars, by: { $0.source.title })
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var statusText: String {
        switch calendar.status {
        case .fullAccess: return "Allowed"
        case .notDetermined: return "Not requested yet"
        case .writeOnly: return "Write-only (full access needed)"
        default: return "Denied"
        }
    }

    var body: some View {
        Form {
            Section("Access") {
                LabeledContent("Calendar access") { Text(statusText).foregroundStyle(.secondary) }
                if calendar.status == .notDetermined {
                    Button("Allow Calendar Access") { calendar.requestAccess() }
                } else if !calendar.hasAccess {
                    Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                }
            }
            if calendar.hasAccess {
                ForEach(groups, id: \.0) { source, calendars in
                    Section(source) {
                        ForEach(calendars, id: \.calendarIdentifier) { item in
                            Toggle(isOn: binding(for: item)) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(cgColor: item.cgColor))
                                        .frame(width: 10, height: 10)
                                    Text(item.title)
                                }
                            }
                            .accessibilityLabel(Text(item.title))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { calendar.refreshStatus() }
    }

    private func binding(for item: EKCalendar) -> Binding<Bool> {
        let id = item.calendarIdentifier
        return Binding(
            get: { !s.hiddenCalendarIDs.contains(id) },
            set: { show in
                if show {
                    s.hiddenCalendarIDs.removeAll { $0 == id }
                } else if !s.hiddenCalendarIDs.contains(id) {
                    s.hiddenCalendarIDs.append(id)
                }
                calendar.invalidate()
            }
        )
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var shortcuts: ShortcutsService

    var body: some View {
        Form {
            Section("Widget") {
                Stepper("Width: \(s.shortcutsWidthCells) cells", value: $s.shortcutsWidthCells, in: 2...8)
                    .accessibilityLabel(Text("Shortcuts widget width"))
                    .accessibilityValue(Text("\(s.shortcutsWidthCells) cells"))
                Stepper("Columns: \(s.shortcutColumns)", value: $s.shortcutColumns, in: 1...4)
                    .accessibilityLabel(Text("Shortcut columns"))
                    .accessibilityValue(Text("\(s.shortcutColumns)"))
                Caption("Each column holds \(s.nookHeightCells) shortcuts. Add the Shortcuts widget in the Nook tab.")
            }
            Section {
                if shortcuts.all.isEmpty {
                    if shortcuts.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("No shortcuts found. Create some in the Shortcuts app.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(shortcuts.all, id: \.self) { name in
                    LabeledToggle(name, isOn: binding(for: name))
                }
            } header: {
                HStack {
                    Text("Choose Shortcuts")
                    Spacer()
                    Button("Refresh") { shortcuts.refresh() }
                        .buttonStyle(.link)
                    Button("Open Shortcuts") { shortcuts.openShortcutsApp() }
                        .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts.refresh() }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { s.shortcutsToDisplay.contains(name) },
            set: { on in
                if on {
                    if !s.shortcutsToDisplay.contains(name) { s.shortcutsToDisplay.append(name) }
                } else {
                    s.shortcutsToDisplay.removeAll { $0 == name }
                }
            }
        )
    }
}

// MARK: - About

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Cranny")
                .font(.title.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Turns your MacBook's notch into a home for media controls, your calendar, a camera mirror, Shortcuts and a files tray.")
                .multilineTextAlignment(.center)
                .frame(width: 400)
            UpdateSection()
                .padding(.top, 6)
            Divider().frame(width: 320).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Automation").font(.headline)
                Text("cranny://open    cranny://open?tab=tray\ncranny://toggle  cranny://close\ncranny://settings?pane=nook")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UpdateSection: View {
    @EnvironmentObject var updates: UpdateChecker
    @EnvironmentObject var s: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            if let release = updates.available {
                Text("Cranny \(release.version) is available")
                    .font(.headline)
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(Self.markdown(release.notes))
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(width: 400, height: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                }
                HStack {
                    Button(updates.canInstallInPlace ? "Install and Relaunch" : "Download") { updates.install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(updates.status == .downloading || updates.status == .installing)
                    Button("Release Notes") { NSWorkspace.shared.open(release.page) }
                }
            } else {
                HStack(spacing: 10) {
                    Text(statusText).foregroundStyle(.secondary)
                    Button("Check for Updates") { updates.check(showingDetails: true) }
                        .disabled(updates.status == .checking)
                }
            }
            if updates.status == .downloading {
                ProgressView("Downloading the update…").controlSize(.small)
            }
            if case .failed(let message) = updates.status {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            LabeledToggle("Check for updates automatically", isOn: $s.checkForUpdates)
                .toggleStyle(.checkbox)
        }
        .onAppear { updates.markSeen() }
    }

    private var statusText: String {
        switch updates.status {
        case .checking: return "Checking for updates…"
        case .upToDate: return "Cranny is up to date."
        case .failed: return "Couldn't check for updates."
        default:
            if let date = updates.lastChecked { return "Last checked \(date.formatted(.relative(presentation: .named)))." }
            return "Not checked yet."
        }
    }

    /// Release notes use headings and lists, which inline Markdown doesn't render,
    /// so turn those into bold lines and bullets first.
    static func markdown(_ text: String) -> AttributedString {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    return "**" + trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**"
                }
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return "• " + trimmed.dropFirst(2) }
                return String(line)
            }
        let source = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
    }
}

// MARK: - Welcome

@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = WelcomeView { launchAtLogin in
                LoginItem.set(launchAtLogin)
                AppSettings.shared.hasCompletedOnboarding = true
                WelcomeWindowController.shared.window?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    let onStart: (Bool) -> Void
    @ViewState private var launchAtLogin = true

    private var importedFromNotchNook: Bool {
        UserDefaults(suiteName: "lo.cafe.NotchNook")?.string(forKey: "generalSettings") != nil
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 4) {
                Text("Welcome to Cranny")
                    .font(.system(size: 24, weight: .bold))
                Text("A new way to interact with your Mac's notch")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                feature("cursorarrow.motionlines", "Hover and click the notch", "Hover to wake it up, then click or swipe down to open the nook and its widgets.")
                feature("tray.and.arrow.down.fill", "Drop files on it", "Drag files onto the notch to keep them in the tray, or drop them on AirDrop.")
                feature("music.note", "Live activities", "See what's playing beside the notch. Swipe left or right over it to change songs.")
                feature("gearshape.fill", "Make it yours", "Use the gear in the open notch to pick widgets, sizes and gestures.")
            }
            .frame(width: 380, alignment: .leading)
            if importedFromNotchNook {
                Text("Your NotchNook settings were imported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledToggle("Launch Cranny at login", isOn: $launchAtLogin)
            Button {
                onStart(launchAtLogin)
            } label: {
                Text("Start").frame(width: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 460)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
