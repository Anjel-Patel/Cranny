import AppKit
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var live: LiveActivityCenter
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var player: NowPlaying

    var body: some View {
        let activity = model.visibleActivity(live.current)
        VStack(spacing: 0) {
            NotchContainer(model: model, layout: model.layout(activity: activity), activity: activity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

struct NotchContainer: View {
    @ObservedObject var model: NotchModel
    let layout: NotchLayout
    let activity: LiveActivityKind?
    @EnvironmentObject var settings: AppSettings

    private var shape: NotchShape { NotchShape(top: layout.top, bottom: layout.bottom) }

    var body: some View {
        ZStack(alignment: .top) {
            background
            content
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(layout.appearance == .open ? 0.45 : 0), radius: 12, y: 6)
        .onTapGesture(perform: tapped)
        .contextMenu {
            Button("Open Settings") { SettingsWindowController.shared.show() }
            Divider()
            Button("Quit Cranny") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: layout)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.tab)
        // Deliberately outside the animations above: the shape appears at full opacity at the
        // physical notch's exact size and grows from there, and only disappears after it has
        // shrunk back onto the notch, so it never shows as a translucent ghost.
        .opacity(layout.appearance == .hidden ? 0 : 1)
    }

    @ViewBuilder private var background: some View {
        if layout.appearance == .open && settings.translucent {
            ZStack {
                VisualEffectBlur()
                Color.black.opacity(0.4)
            }
        } else if !model.hasPhysicalNotch && settings.transparentHandle && layout.appearance == .idle {
            Color.black.opacity(0.001)
        } else {
            Color.black
        }
    }

    @ViewBuilder private var content: some View {
        if layout.appearance == .activity || layout.appearance == .peek {
            VStack(spacing: 0) {
                LiveActivityRow(model: model, layout: layout)
                if layout.appearance == .peek {
                    PeekInfo()
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .transition(.opacity)
        }
        if layout.appearance == .open {
            OpenNotchView(model: model, layout: layout)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        }
    }

    private func tapped() {
        guard model.state == .closed else { return }
        if activity == .tray {
            model.open(tab: .tray)
        } else if settings.nookEnabled {
            model.open(tab: .nook)
        }
    }
}

// MARK: - Live activities

struct LiveActivityRow: View {
    @ObservedObject var model: NotchModel
    let layout: NotchLayout
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var live: LiveActivityCenter
    @EnvironmentObject var player: NowPlaying
    @EnvironmentObject var tray: TrayStore

    var body: some View {
        let slot = model.barHeight - 9
        HStack(spacing: 0) {
            leading(slot)
                .frame(width: model.sideWidth, height: model.barHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: activate)
            Spacer(minLength: 0)
            trailing(slot)
                .frame(width: model.sideWidth, height: model.barHeight)
                .contentShape(Rectangle())
                .onTapGesture(perform: activate)
        }
        .padding(.horizontal, layout.top + max(0, (layout.bodyWidth - model.activityBodyWidth) / 2))
        .frame(height: model.barHeight)
    }

    @ViewBuilder private func leading(_ slot: CGFloat) -> some View {
        switch live.current {
        case .media:
            Group {
                if let art = player.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else if let icon = player.appIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "music.note").font(.system(size: slot * 0.55)).foregroundStyle(.white)
                }
            }
            .frame(width: slot, height: slot)
            .clipShape(RoundedRectangle(cornerRadius: settings.albumCornerRadius, style: .continuous))
            .opacity(player.isPlaying ? 1 : 0.6)
        case .calendar:
            Image(systemName: "calendar")
                .font(.system(size: slot * 0.62, weight: .semibold))
                .foregroundStyle(Color(nsColor: live.calendarEvent?.color ?? .systemRed))
        case .tray:
            Image(systemName: "tray.full.fill")
                .font(.system(size: slot * 0.58, weight: .semibold))
                .foregroundStyle(.white)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private func trailing(_ slot: CGFloat) -> some View {
        switch live.current {
        case .media:
            switch settings.mediaEffect {
            case .audioSpectrograph:
                Spectrograph(
                    color: settings.coloredSpectrograph ? Color(nsColor: player.accentColor) : .white,
                    playing: player.isPlaying,
                    maxHeight: slot * 0.8
                )
            case .gif:
                if !settings.gifPath.isEmpty {
                    AnimatedGIF(path: settings.gifPath, playing: player.isPlaying)
                        .frame(width: slot, height: slot)
                }
            case .none:
                EmptyView()
            }
        case .calendar:
            if let event = live.calendarEvent {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(Self.countdown(to: event, now: context.date, inProgress: live.calendarInProgress, showLapsed: settings.calendarShowTimeLapsed))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(live.calendarInProgress ? Color(nsColor: event.color) : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        case .tray:
            Text("\(tray.items.count)")
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        case nil:
            EmptyView()
        }
    }

    private func activate() {
        guard settings.interactiveActivities else {
            if settings.nookEnabled || live.current == .tray { model.open(tab: live.current == .tray ? .tray : .nook) }
            return
        }
        switch live.current {
        case .media:
            player.togglePlayPause()
        case .calendar:
            if let url = live.calendarEvent?.meetingURL {
                NSWorkspace.shared.open(url)
            } else if let event = live.calendarEvent {
                CalendarService.shared.open(event)
            }
        case .tray:
            model.open(tab: .tray)
        case nil:
            break
        }
    }

    static func countdown(to event: CalendarEventInfo, now: Date, inProgress: Bool, showLapsed: Bool) -> String {
        if inProgress {
            guard showLapsed else { return "now" }
            return "+" + compact(now.timeIntervalSince(event.start))
        }
        return "in " + compact(event.start.timeIntervalSince(now))
    }

    static func compact(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h\(minutes % 60 > 0 ? "\(minutes % 60)" : "")"
    }
}

/// The short line of info shown when hovering a live activity.
struct PeekInfo: View {
    @EnvironmentObject var live: LiveActivityCenter
    @EnvironmentObject var player: NowPlaying
    @EnvironmentObject var tray: TrayStore

    var body: some View {
        Group {
            switch live.current {
            case .media:
                Text(player.title.isEmpty ? "Unknown Title" : player.title).fontWeight(.semibold)
                    + Text("  " + (player.artist.isEmpty ? "Unknown Artist" : player.artist)).foregroundStyle(.white.opacity(0.6))
            case .calendar:
                if let event = live.calendarEvent {
                    Text(event.title).fontWeight(.semibold)
                        + Text("  " + event.start.formatted(date: .omitted, time: .shortened)).foregroundStyle(.white.opacity(0.6))
                }
            case .tray:
                Text(tray.items.count == 1 ? "1 file in the tray" : "\(tray.items.count) files in the tray")
            case nil:
                EmptyView()
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 26)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}

struct Spectrograph: View {
    let color: Color
    let playing: Bool
    var maxHeight: CGFloat = 16
    private let bars = 4
    private let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]
    private let offsets: [Double] = [0.0, 1.7, 3.1, 4.6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: playing ? height(i, t) : 3)
                }
            }
            .frame(height: maxHeight)
            .animation(.easeInOut(duration: 0.18), value: t)
        }
    }

    private func height(_ i: Int, _ t: Double) -> CGFloat {
        let a = sin(t * speeds[i] + offsets[i])
        let b = sin(t * speeds[(i + 2) % bars] * 0.53 + offsets[i] * 2)
        let v = (a * 0.6 + b * 0.4 + 1) / 2
        return 4 + CGFloat(v) * (maxHeight - 4)
    }
}

struct AnimatedGIF: NSViewRepresentable {
    let path: String
    let playing: Bool

    final class Coordinator { var path = "" }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.path != path {
            context.coordinator.path = path
            view.image = NSImage(contentsOfFile: path)
        }
        view.animates = playing
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Open notch

struct OpenNotchView: View {
    @ObservedObject var model: NotchModel
    let layout: NotchLayout
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 6) {
            NotchHeader(model: model)
                .frame(height: model.barHeight)
            Group {
                switch model.tab {
                case .nook:
                    NookView(model: model)
                case .tray:
                    TrayView(model: model)
                }
            }
            .frame(width: model.contentWidth, height: model.contentHeight)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.top + settings.contentPadding)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .foregroundStyle(.white)
    }
}

struct NotchHeader: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var tray: TrayStore

    var body: some View {
        HStack(spacing: 6) {
            if settings.nookEnabled {
                tab(.nook, title: "Nook", symbol: "square.grid.2x2.fill")
            }
            tab(.tray, title: "Tray", symbol: tray.items.isEmpty ? "tray.fill" : "tray.full.fill")
            Spacer(minLength: model.closedSize.width + 12)
            HeaderIconButton(symbol: "gearshape.fill") {
                model.close()
                SettingsWindowController.shared.show()
            }
        }
    }

    private func tab(_ tab: NotchTab, title: String, symbol: String) -> some View {
        let selected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
                if tab == .tray && !tray.items.isEmpty {
                    Text("\(tray.items.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.2)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(selected ? 0.16 : 0)))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct HeaderIconButton: View {
    let symbol: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Capsule().fill(.white.opacity(hovering ? 0.14 : 0)))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared styles

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 14
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 16, height: size + 10)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .foregroundStyle(.white)
        .onHover { hovering = $0 }
    }
}
