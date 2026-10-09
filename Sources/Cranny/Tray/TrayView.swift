import AppKit
import SwiftUI

struct TrayView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var tray: TrayStore
    @ViewState private var filesTargeted = false
    @ViewState private var airDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            files
            airDrop
                .frame(width: max(model.contentHeight, 96))
        }
    }

    private var files: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(filesTargeted ? 0.1 : 0.03))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(filesTargeted ? 0.75 : (tray.items.isEmpty || model.dragActive ? 0.25 : 0.08)))

            if tray.items.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 20))
                    Text("Files Tray")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Drop files here to keep them around")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(tray.items) { item in
                            TrayItemView(item: item)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.regions[.tray] = $0 }
        .onDisappear { model.regions[.tray] = nil }
        .onDrop(of: TrayStore.acceptedTypes, isTargeted: $filesTargeted) { providers in
            tray.accept(providers)
            return true
        }
        .contextMenu {
            if !tray.items.isEmpty {
                Button("AirDrop All") { AirDrop.share(tray.items.map(\.url)) }
                Button("Remove All from Tray") { tray.removeAll() }
            }
        }
    }

    private var airDrop: some View {
        VStack(spacing: 6) {
            if let icon = AirDrop.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 22))
            }
            Text("AirDrop")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(airDropTargeted ? Color.blue.opacity(0.35) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.blue.opacity(airDropTargeted ? 0.9 : 0), lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            AirDrop.share(tray.items.map(\.url))
        }
        .onDrop(of: TrayStore.acceptedTypes, isTargeted: $airDropTargeted) { providers in
            AirDrop.share(providers)
            return true
        }
        .help(tray.items.isEmpty ? "Drop files here to AirDrop them" : "Drop files here, or click to AirDrop everything in the tray")
    }
}

struct TrayItemView: View {
    static let placeholder = NSWorkspace.shared.icon(for: .data)

    let item: TrayStore.Item
    @EnvironmentObject var tray: TrayStore
    @ViewState private var hovering = false
    @ViewState private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: thumbnail ?? Self.placeholder)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button {
                            tray.remove(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(white: 0.25))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -6)
                        .help("Remove from tray")
                    }
                }
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 70, height: 26, alignment: .top)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { TrayDragOut.shared.itemFrames[item.id] = $0 }
        .onDisappear { TrayDragOut.shared.itemFrames[item.id] = nil }
        .onTapGesture(count: 2) { tray.open(item) }
        .contextMenu {
            Button("Open") { tray.open(item) }
            Button("Show in Finder") { tray.revealInFinder(item) }
            Button("AirDrop") { AirDrop.share([item.url]) }
            Divider()
            Button("Remove from Tray") { tray.remove(item.id) }
        }
        .task(id: item.url) {
            if thumbnail == nil { thumbnail = NSWorkspace.shared.icon(forFile: item.url.path) }
            thumbnail = await Thumbnails.image(for: item.url, side: 88)
        }
        .help(item.url.path)
    }
}
