import SwiftUI
import AudioRouterCore

/// One app: icon, where its sound is going, and an inline device chooser.
struct AppCard: View {
    @EnvironmentObject private var engine: RouterEngine
    let app: AudioApp
    @Binding var expandedAppID: String?

    private var isExpanded: Bool { expandedAppID == app.id }
    private var status: RouteStatus { engine.status(for: app.id) }
    private var chosenUID: String? { engine.assignments[app.id]?.deviceUID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                DeviceChooser(app: app, chosenUID: chosenUID) { device in
                    engine.assign(device, to: app.id)
                    withAnimation(.snappy(duration: 0.22)) { expandedAppID = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card(highlighted: isExpanded)
        .opacity(app.isPlaying || chosenUID != nil ? 1 : 0.8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppIconView(app: app)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                StatusLine(status: status, isPlaying: app.isPlaying)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if case .failed = status, let device = engine.devices.first(where: { $0.uid == chosenUID }) {
                Button("Retry") { engine.assign(device, to: app.id) }
                    .buttonStyle(GhostButtonStyle())
            }
            DeviceChip(device: chosenDevice, waitingName: waitingName, expanded: isExpanded) {
                withAnimation(.snappy(duration: 0.22)) { expandedAppID = isExpanded ? nil : app.id }
            }
        }
        .padding(10)
        .contentShape(Rectangle())
    }

    private var chosenDevice: OutputDevice? {
        engine.devices.first { $0.uid == chosenUID }
    }

    private var waitingName: String? {
        guard chosenDevice == nil else { return nil }
        return engine.assignments[app.id]?.deviceName
    }
}

/// The compact pill showing the current choice. Click to open the chooser.
struct DeviceChip: View {
    let device: OutputDevice?
    let waitingName: String?
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(Self.shorten(title)).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(device != nil ? Color.white : Color.primary)
            .background(Capsule().fill(device != nil ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.08))))
        }
        .buttonStyle(.plain)
        .help("Choose where this app plays")
        .accessibilityLabel("Output: \(title)")
    }

    private var title: String { device?.name ?? waitingName ?? "System" }

    /// Keeps the chip compact so the app name always has room.
    static func shorten(_ name: String, limit: Int = 16) -> String {
        name.count <= limit ? name : name.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
    private var symbol: String {
        if let device { return device.kind.symbolName }
        return waitingName != nil ? "bolt.horizontal.circle" : "macwindow.and.cursorarrow"
    }
}

/// Inline list of outputs for one app.
struct DeviceChooser: View {
    @EnvironmentObject private var engine: RouterEngine
    let app: AudioApp
    let chosenUID: String?
    let choose: (OutputDevice?) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Divider().padding(.bottom, 4)
            OptionRow(glyph: nil, title: "System output",
                      subtitle: engine.defaultDevice.map { "Follows your Mac · now \($0.name)" } ?? "Follows your Mac",
                      selected: chosenUID == nil) { choose(nil) }
            ForEach(engine.devices) { device in
                OptionRow(glyph: device.kind, title: device.name, subtitle: device.kind.label,
                          selected: chosenUID == device.uid) { choose(device) }
            }
        }
        .padding([.horizontal, .bottom], 6)
    }
}

private struct OptionRow: View {
    let glyph: DeviceKind?
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DeviceGlyph(kind: glyph, selected: selected)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
