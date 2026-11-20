import SwiftUI
import ServiceManagement
import AudioRouterCore

/// The window that drops down from the menu bar.
struct RouterPanel: View {
    @EnvironmentObject private var engine: RouterEngine
    @State private var expandedAppID: String?

    /// Screenshots render without a scroll view (ImageRenderer can't draw AppKit-backed views).
    private let scrollable: Bool

    init(initiallyExpanded: String? = nil, scrollable: Bool = true) {
        _expandedAppID = State(initialValue: initiallyExpanded)
        self.scrollable = scrollable
    }

    private var playing: [AudioApp] { engine.apps.filter(\.isPlaying) }
    private var quiet: [AudioApp] { engine.apps.filter { !$0.isPlaying } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader()
            if let notice = engine.notice {
                NoticeBanner(text: notice) { engine.notice = nil }
            }
            if engine.apps.isEmpty {
                EmptyState()
            } else {
                if scrollable {
                    ScrollView { appList }
                        .scrollIndicators(.never)
                        .frame(maxHeight: 440)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    appList
                }
            }
            PanelFooter()
        }
        .padding(14)
        .frame(width: Theme.panelWidth)
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Playing now", apps: playing)
            section("Other apps", apps: quiet)
        }
    }

    @ViewBuilder
    private func section(_ title: String, apps: [AudioApp]) -> some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                ForEach(apps) { app in
                    AppCard(app: app, expandedAppID: $expandedAppID)
                }
            }
        }
    }
}

private struct PanelHeader: View {
    @EnvironmentObject private var engine: RouterEngine

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.brand)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "hifispeaker.2.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Audio Router").font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    Image(systemName: engine.defaultDevice?.kind.symbolName ?? "speaker.wave.2")
                    Text(engine.defaultDevice?.name ?? "No output").lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !engine.assignments.isEmpty {
                Button {
                    withAnimation { _ = engine.resetAll() }
                } label: {
                    Label("Reset all", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GhostButtonStyle())
                .help("Send every app back to the system output")
            }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.brand)
            Text("Nothing's playing yet").font(.system(size: 13, weight: .semibold))
            Text("Start music or a video in any app. It shows up here, and you can send it to any speaker.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }
}

private struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.warning)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.12)))
    }
}

private struct PanelFooter: View {
    var body: some View {
        HStack(spacing: 4) {
            LoginToggle()
            Spacer()
            Button {
                NSWorkspace.shared.open(Links.audioCapturePrivacy)
            } label: {
                Label("Permission", systemImage: "lock.shield")
            }
            .help("App silent after routing? Make sure Audio Router is allowed under System Audio Recording.")
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
            .help("Quit. Every app goes back to the system output.")
        }
        .buttonStyle(GhostButtonStyle())
        .padding(.top, 2)
    }
}

enum Links {
    static let audioCapturePrivacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
}

private struct LoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {}
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
        .toggleStyle(PillSwitchStyle())
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
    }
}
