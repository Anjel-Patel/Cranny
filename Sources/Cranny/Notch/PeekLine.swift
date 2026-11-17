import AppKit
import SwiftUI

/// One line of Quick Peek text: a bold part, then an optional dimmer part. If the line doesn't
/// fit, it scrolls sideways and loops, pausing at the start of every pass. The bold part can
/// carry a soft highlight that drifts across it every few seconds.
///
/// The text is laid out once; the scrolling and the highlight only move it and a gradient band
/// masked by it, so SwiftUI animates positions instead of redrawing text every frame.
struct PeekLine: View {
    let primary: String
    var secondary: String?
    /// Colour of the drifting highlight. With a highlight, the bold part sits slightly dimmer so
    /// the highlight has something to brighten.
    var highlight: Color?
    /// Whether the highlight moves; it rests while music is paused.
    var animatesHighlight = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ViewState private var textWidth: CGFloat = 0

    private let spacing: CGFloat = 6
    private let gap: CGFloat = 36
    private let fade: CGFloat = 12
    private let speed = 30.0         // points per second
    private let restAtStart = 1.4    // seconds still at the start of every pass
    private let sweep = 2.4          // seconds the highlight takes to cross
    private let sweepRest = 1.6      // seconds between highlights

    /// Reduce Motion stops both the scrolling and the highlight. To check that without changing
    /// the system setting: `defaults write io.github.rdbms234.Cranny debugReduceMotion -bool true`.
    private var reduceMotion: Bool {
        systemReduceMotion || UserDefaults.standard.bool(forKey: "debugReduceMotion")
    }

    private var shimmers: Bool { highlight != nil && animatesHighlight && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            if textWidth > width + 0.5 {
                if reduceMotion {
                    truncatedLine
                        .frame(width: width, height: geo.size.height)
                } else {
                    scrollingLine
                        .frame(width: width, height: geo.size.height, alignment: .leading)
                        .mask(edgeFade(width: width))
                }
            } else {
                line
                    .frame(width: width, height: geo.size.height)
            }
        }
        .clipped()
        .background(measuringLine)
        // A new song starts its scrolling and highlight from the beginning.
        .id(primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([primary, secondary ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")))
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            title
            if let secondary, !secondary.isEmpty {
                Text(secondary)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    /// Two copies side by side. One pass moves the first copy out and the second into its place,
    /// then it jumps back without animating, so the loop is seamless. It starts a little in from
    /// the left edge so the first letters stay clear of the fade while it rests.
    private var scrollingLine: some View {
        let distance = textWidth + gap
        return HStack(spacing: gap) {
            line
            line
        }
        .fixedSize()
        .padding(.leading, fade)
        .phaseAnimator([false, true]) { content, scrolled in
            content.offset(x: scrolled ? -distance : 0)
        } animation: { scrolled in
            scrolled ? .linear(duration: distance / speed).delay(restAtStart) : nil
        }
    }

    @ViewBuilder private var title: some View {
        let text = Text(primary).fontWeight(.semibold)
        if let highlight {
            text
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .overlay {
                    if shimmers {
                        band(highlight).mask(text.lineLimit(1))
                    }
                }
                .layoutPriority(1)
        } else {
            text
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// A soft band of the highlight colour that slides across the title, then rests.
    private func band(_ color: Color) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let bandWidth = max(36, width * 0.6)
            LinearGradient(colors: [color.opacity(0), color, color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: bandWidth, height: geo.size.height)
                .phaseAnimator([false, true]) { content, crossed in
                    content.offset(x: crossed ? width : -bandWidth)
                } animation: { crossed in
                    crossed ? .linear(duration: sweep).delay(sweepRest) : nil
                }
        }
    }

    /// The same line as a single text, so cutting it short ends cleanly in "…".
    private var truncatedLine: some View {
        let first = Text(primary)
            .fontWeight(.semibold)
            .foregroundStyle(highlight == nil ? Color.white : Color.white.opacity(0.85))
        var text = first
        if let secondary, !secondary.isEmpty {
            let second = Text(secondary).foregroundStyle(.white.opacity(0.6))
            text = Text("\(first)  \(second)")
        }
        return text.lineLimit(1).truncationMode(.tail)
    }

    /// Measures the line's natural width, without any animation running.
    private var measuringLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(primary).fontWeight(.semibold)
            if let secondary, !secondary.isEmpty {
                Text(secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .hidden()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
    }

    /// Soft edges while scrolling.
    private func edgeFade(width: CGFloat) -> some View {
        let f = min(fade, width / 5) / max(width, 1)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: f),
                .init(color: .black, location: 1 - f),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
