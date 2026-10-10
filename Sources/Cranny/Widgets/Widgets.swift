import AppKit
import SwiftUI

struct NookView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let widgets = settings.visibleWidgets
        if widgets.isEmpty {
            VStack(spacing: 8) {
                Text("Nothing selected").font(.system(size: 13, weight: .semibold))
                Button("Customize widgets") {
                    model.close()
                    SettingsWindowController.shared.show(pane: .nook)
                }
                .buttonStyle(PillButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: settings.widgetsPadding) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                    widget(kind)
                        .frame(width: CGFloat(settings.widthCells(for: kind)) * model.cell, height: model.contentHeight)
                        .overlay(alignment: .leading) {
                            if index > 0 && settings.showDividers {
                                Capsule()
                                    .fill(.white.opacity(0.12))
                                    .frame(width: 1, height: model.contentHeight * 0.7)
                                    .offset(x: -settings.widgetsPadding / 2 - 0.5)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func widget(_ kind: WidgetKind) -> some View {
        switch kind {
        case .media: MediaWidget()
        case .calendar: CalendarWidget(model: model)
        case .shortcuts: ShortcutsWidget(model: model)
        case .mirror: MirrorWidget(model: model)
        }
    }
}

// MARK: - Media

struct MediaWidget: View {
    @EnvironmentObject var player: NowPlaying

    var body: some View {
        if player.isShown {
            GeometryReader { geo in
                let art = min(geo.size.height, geo.size.width * 0.4)
                HStack(spacing: 12) {
                    artwork(size: art)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(player.title.isEmpty ? "Unknown Title" : player.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(player.artist.isEmpty ? (player.appName.isEmpty ? "Unknown Artist" : player.appName) : player.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        MediaProgress()
                        Spacer(minLength: 2)
                        MediaControls()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        } else {
            EmptyPlayerView(hidingOtherMedia: player.hasPlayer)
        }
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = player.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.35))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let icon = player.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: 6, y: 6)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(player.isPlaying ? 1 : 0.92)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: player.isPlaying)
        .contentShape(Rectangle())
        .onTapGesture { player.openSourceApp() }
        .help(player.appName.isEmpty ? "" : "Open \(player.appName)")
    }
}

struct MediaProgress: View {
    @EnvironmentObject var player: NowPlaying
    @ViewState private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = player.duration
            let position = player.position(at: context.date)
            let shown = dragFraction.map { $0 * duration } ?? position
            let fraction = duration > 0 ? min(1, max(0, shown / duration)) : 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white.opacity(dragFraction == nil ? 0.85 : 1))
                            .frame(width: max(4, geo.size.width * fraction))
                    }
                    .frame(height: dragFraction == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragFraction = min(1, max(0, value.location.x / max(1, geo.size.width)))
                            }
                            .onEnded { value in
                                guard duration > 0 else { return }
                                let f = min(1, max(0, value.location.x / max(1, geo.size.width)))
                                player.seek(to: f * duration)
                                dragFraction = nil
                            }
                    )
                    .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(Self.format(shown))
                    Spacer()
                    Text(duration > 0 ? "-" + Self.format(max(0, duration - shown)) : "LIVE")
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct MediaControls: View {
    @EnvironmentObject var player: NowPlaying

    var body: some View {
        HStack(spacing: 14) {
            ControlButton(symbol: "backward.fill", size: 13) { player.previous() }
            ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 19) { player.togglePlayPause() }
            ControlButton(symbol: "forward.fill", size: 13) { player.next() }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyPlayerView: View {
    /// Something is playing, but "Only show music" hides it.
    var hidingOtherMedia = false

    var body: some View {
        VStack(spacing: 6) {
            Text(hidingOtherMedia ? "No music is playing" : "No app seems to be running")
                .font(.system(size: 12, weight: .semibold))
            Text(hidingOtherMedia ? "Wanna open a music app?" : "Wanna open one?")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 12) {
                ForEach(installedPlayers, id: \.self) { url in
                    Button {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(FileManager.default.displayName(atPath: url.path))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installedPlayers: [URL] { Self.players }

    private static let players: [URL] = NowPlaying.suggestedPlayers.compactMap {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }
}

// MARK: - Calendar

struct CalendarWidget: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var calendar: CalendarService

    private var day: Date {
        Calendar.current.date(byAdding: .day, value: model.calendarDayOffset, to: Date()) ?? Date()
    }

    var body: some View {
        Group {
            if calendar.hasAccess {
                content
            } else {
                accessPrompt
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.regions[.calendar] = $0 }
        .onDisappear { model.regions[.calendar] = nil }
    }

    private var content: some View {
        let events = calendar.events(on: day)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.red)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(model.calendarDayOffset)))
                Text(day.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                if model.calendarDayOffset != 0 {
                    Button("Today") { model.calendarDayOffset = 0 }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 46, alignment: .leading)
            .animation(.snappy, value: model.calendarDayOffset)

            if events.isEmpty {
                Text(model.calendarDayOffset == 0 ? "Nothing for today" : "Nothing scheduled")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events) { EventRow(event: $0) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var accessPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 20))
            Text(calendar.status == .notDetermined ? "See your upcoming events here" : "Calendar access is off")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
            Button(calendar.status == .notDetermined ? "Allow Access" : "Open Settings") {
                if calendar.status == .notDetermined {
                    calendar.requestAccess()
                } else {
                    calendar.openPrivacySettings()
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EventRow: View {
    let event: CalendarEventInfo
    @EnvironmentObject var calendar: CalendarService
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(5)
                        .background(Circle().fill(Color.green.opacity(0.85)))
                }
                .buttonStyle(PressScaleStyle())
                .help("Join meeting")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.08 : 0)))
        .opacity(event.end < Date() ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { calendar.open(event) }
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }
}

// MARK: - Mirror

struct MirrorWidget: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var camera: CameraService
    @EnvironmentObject var settings: AppSettings
    @ViewState private var hovering = false

    var body: some View {
        ZStack {
            if camera.isRunning {
                CameraPreview(layer: camera.previewLayer)
            } else {
                Color.white.opacity(hovering ? 0.12 : 0.07)
                VStack(spacing: 6) {
                    Image(systemName: camera.isDenied ? "video.slash.fill" : "person.crop.square.fill")
                        .font(.system(size: 22))
                    Text(camera.isDenied ? "No access" : (camera.noCamera ? "No camera" : "Mirror"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: activate)
        .help(settings.largerMirror && !camera.isDenied ? "Click for a bigger mirror" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mirror"))
        .accessibilityValue(Text(camera.isRunning ? "On" : "Off"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
        // Growing into the larger Mirror replaces this widget, but the camera should keep going.
        .onDisappear { if !model.mirrorExpanded { camera.stop() } }
    }

    private func activate() {
        if camera.isDenied {
            camera.openPrivacySettings()
        } else if settings.largerMirror {
            camera.start()
            model.mirrorExpanded = true
        } else {
            camera.toggle()
        }
    }
}

/// The experimental larger Mirror. Clicking it puts it away again.
struct LargeMirrorView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var camera: CameraService

    var body: some View {
        let size = model.largeMirrorSize
        ZStack {
            Color.white.opacity(0.07)
            if camera.isRunning {
                CameraPreview(layer: camera.previewLayer)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: camera.isDenied ? "video.slash.fill" : "person.crop.square.fill")
                        .font(.system(size: 30))
                    Text(camera.isDenied ? "No access to the camera" : (camera.noCamera ? "No camera" : "Starting the camera…"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.mirrorExpanded = false }
        .help("Click to put the mirror away")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Larger Mirror"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.mirrorExpanded = false }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shortcuts

struct ShortcutsWidget: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let names = settings.shortcutsToDisplay
        if names.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18))
                Text("Choose your shortcuts in settings.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                Button("Select some shortcuts") {
                    model.close()
                    SettingsWindowController.shared.show(pane: .shortcuts)
                }
                .buttonStyle(PillButtonStyle())
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rows = max(1, settings.nookHeightCells)
            let columns = max(1, settings.shortcutColumns)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = column * rows + row
                            if index < names.count {
                                ShortcutButton(name: names[index])
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ShortcutButton: View {
    let name: String
    @EnvironmentObject var shortcuts: ShortcutsService
    @ViewState private var hovering = false

    var body: some View {
        Button {
            shortcuts.run(name)
        } label: {
            HStack(spacing: 5) {
                Group {
                    if shortcuts.running.contains(name) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: shortcuts.failed.contains(name) ? "exclamationmark.triangle.fill" : "bolt.fill")
                            .font(.system(size: 11))
                    }
                }
                .frame(width: 12)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.16 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
        .help(name)
    }
}
