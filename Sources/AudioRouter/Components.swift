import SwiftUI
import AppKit
import AudioRouterCore

/// Three bouncing bars: "this app is making sound right now".
struct EqualizerBars: View {
    var color: Color = Theme.live
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: barHeight(t: t, index: i))
                }
            }
            .frame(width: 11, height: 10, alignment: .bottom)
        }
        .accessibilityLabel("Playing")
    }

    private func barHeight(t: Double, index: Int) -> CGFloat {
        guard animated else { return [6, 9, 4][index] }
        let phase = Double(index) * 1.7
        return 3 + 7 * CGFloat(abs(sin(t * 5 + phase)))
    }
}

/// The app's icon, or a friendly monogram tile when there isn't one.
struct AppIconView: View {
    let app: AudioApp
    var size: CGFloat = 30

    var body: some View {
        if let url = app.bundleURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            monogram
        }
    }

    private var monogram: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.65)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Text(String(app.name.prefix(1))).font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white))
            .frame(width: size, height: size)
    }

    private var color: Color {
        let palette: [Color] = [.orange, .blue, .pink, .teal, .purple, .indigo, .green]
        let hash = app.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

/// A round glyph for a device kind.
struct DeviceGlyph: View {
    let kind: DeviceKind?
    var selected = false

    var body: some View {
        Image(systemName: kind?.symbolName ?? "macwindow.and.cursorarrow")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? .white : .secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.08))))
    }
}

/// A one-line explanation of where an app's sound is going.
struct StatusLine: View {
    let status: RouteStatus
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 5) {
            leading
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color)
    }

    @ViewBuilder private var leading: some View {
        switch status {
        case .routed, .systemDefault:
            if isPlaying { EqualizerBars(color: color) } else { Image(systemName: "pause.fill").font(.system(size: 8)) }
        case .connecting:
            Spinner(color: color).frame(width: 11, height: 10)
        case .waitingForDevice:
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 10))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
        }
    }

    private var text: String {
        switch status {
        case .systemDefault: isPlaying ? "Playing" : "Quiet"
        case .routed: isPlaying ? "Playing · routed" : "Routed · quiet"
        case .connecting: "Connecting…"
        case .waitingForDevice: "Speaker off"
        case .failed(let message): message
        }
    }

    private var color: Color {
        switch status {
        case .systemDefault: isPlaying ? Theme.live : .secondary
        case .routed: isPlaying ? Theme.accent : .secondary
        case .connecting, .waitingForDevice: Theme.warning
        case .failed: Theme.danger
        }
    }
}

/// Card background that lights up on hover.
struct CardBackground: ViewModifier {
    var highlighted: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(hovering || highlighted ? Theme.cardHover : Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}

/// A small rounded switch drawn in SwiftUI (renders identically in screenshots).
struct PillSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: 26, height: 15)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(radius: 0.5)
                    }
                    .animation(.snappy(duration: 0.18), value: configuration.isOn)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

/// Quiet text+icon button used in the header and footer.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration)
    }

    private struct GhostButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(hovering || configuration.isPressed ? 0.08 : 0)))
                .onHover { hovering = $0 }
        }
    }
}

/// Spinning arc (SwiftUI-only stand-in for ProgressView).
struct Spinner: View {
    var color: Color = Theme.warning
    var body: some View {
        TimelineView(.animation) { context in
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
        }
        .frame(width: 9, height: 9)
    }
}
