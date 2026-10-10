import AppKit
import SwiftUI

/// The Clipboard tab: recent copies as tiles, newest on the left.
struct ClipboardView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var clipboard: ClipboardStore

    private let spacing: CGFloat = 10

    var body: some View {
        // The same size as the tray's AirDrop square.
        let side = max(model.contentHeight, 96)
        Group {
            switch clipboard.access {
            case .needsPermission, .blocked:
                ClipboardPermissionCard(blocked: clipboard.access == .blocked)
            case .allowed:
                if clipboard.items.isEmpty {
                    EmptyClipboardView()
                } else {
                    tiles(side: side)
                }
            }
        }
        .frame(width: model.contentWidth, height: model.contentHeight)
    }

    private func tiles(side: CGFloat) -> some View {
        let rowWidth = CGFloat(clipboard.items.count) * (side + spacing) - spacing
        let overflows = rowWidth > model.contentWidth + 0.5
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(clipboard.items) { item in
                    ClipTile(
                        item: item, side: side,
                        isCurrent: item.id == clipboard.currentID,
                        justCopied: item.id == clipboard.justCopiedID
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(height: side)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: clipboard.items.map(\.id))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.regions[.clipboard] = $0 }
        .onDisappear { model.regions[.clipboard] = nil }
        // When there's more than fits, fade the right edge so it's clear the row scrolls.
        .mask {
            if overflows {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            } else {
                Color.black
            }
        }
    }
}

struct ClipTile: View {
    let item: ClipboardStore.Item
    let side: CGFloat
    /// What's on the clipboard right now.
    let isCurrent: Bool
    let justCopied: Bool
    @EnvironmentObject var clipboard: ClipboardStore
    @ViewState private var hovering = false
    @ViewState private var fileImage: NSImage?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(.white.opacity(hovering ? 0.13 : 0.07))
            content
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            if justCopied {
                ZStack {
                    Color.black.opacity(0.6)
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22))
                        Text("Copied").font(.system(size: 11, weight: .semibold))
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(isCurrent ? 0.55 : 0), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if hovering && !justCopied {
                Button {
                    clipboard.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.25))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Remove")
            }
        }
        .animation(.easeOut(duration: 0.15), value: justCopied)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { ClipboardDragOut.shared.itemFrames[item.id] = $0 }
        .onDisappear { ClipboardDragOut.shared.itemFrames[item.id] = nil }
        .onTapGesture { clipboard.copy(item) }
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button("Remove") { clipboard.remove(item.id) }
            Divider()
            Button("Clear All") { clipboard.removeAll() }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text("Copies it again"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { clipboard.copy(item) }
        .accessibilityAction(named: Text("Remove")) { clipboard.remove(item.id) }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text(let text):
            Text(Self.preview(text))
                .font(.system(size: side > 120 ? 12 : 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(side > 120 ? 8 : 5)
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                ))
        case .link(let url):
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.7, blue: 1))
                Spacer(minLength: 0)
                Text(Self.host(of: url))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                Text(Self.path(of: url))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(10)
            .padding(.bottom, item.appIcon == nil ? 0 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipped()
        case .files(let files):
            VStack(spacing: 6) {
                ZStack {
                    if files.count > 1 {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: files[1].path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(8))
                            .offset(x: 6, y: -2)
                            .opacity(0.8)
                    }
                    Image(nsImage: fileImage ?? NSWorkspace.shared.icon(forFile: files[0].path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .frame(width: side * 0.46, height: side * 0.46)
                Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files")
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    // Keeps the name clear of the app badge in the corner.
                    .frame(maxWidth: item.appIcon == nil ? .infinity : side - 44)
            }
            .padding(8)
            .task(id: files.first) {
                if let first = files.first, files.count == 1 {
                    fileImage = await Thumbnails.image(for: first, side: side)
                }
            }
        }
    }

    private var helpText: String {
        switch item.kind {
        case .text(let text): return String(text.prefix(300))
        case .link(let url): return url.absoluteString
        case .image: return item.appName.map { "Picture from \($0)" } ?? "Picture"
        case .files(let files): return files.map(\.path).joined(separator: "\n")
        }
    }

    private var accessibilityText: String {
        switch item.kind {
        case .text(let text): return "Text: " + String(text.prefix(120))
        case .link(let url): return "Link: " + url.absoluteString
        case .image: return "Picture"
        case .files(let files): return files.count == 1 ? "File: \(files[0].lastPathComponent)" : "\(files.count) files"
        }
    }

    /// The start of the text, trimmed, with tabs as spaces.
    static func preview(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
            .replacingOccurrences(of: "\t", with: "  ")
    }

    static func host(of url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func path(of url: URL) -> String {
        var rest = url.path
        if let query = url.query { rest += "?" + query }
        return rest == "/" ? "" : rest
    }
}

struct EmptyClipboardView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(0.25))
            VStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 20))
                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold))
                Text("Things you copy show up here")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// Shown when macOS asks before every clipboard read, or blocks it.
struct ClipboardPermissionCard: View {
    let blocked: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 4) {
                Text(blocked ? "macOS is blocking the clipboard" : "Let Cranny keep your clipboard history")
                    .font(.system(size: 12, weight: .semibold))
                Text("In System Settings → Privacy & Security → Paste from Other Apps, set Cranny to Allow.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { ClipboardStore.openPrivacySettings() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }
}
