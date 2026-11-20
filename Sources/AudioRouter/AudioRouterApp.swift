import SwiftUI
import AppKit
import AudioRouterCore
import AudioRouterCoreAudio

/// Composition root: the only place that knows about concrete implementations.
@MainActor
enum AppEnvironment {
    static let engine = RouterEngine(system: CoreAudioSystem(),
                                     factory: ProcessTapRouteFactory(),
                                     store: FileAssignmentStore.standard())
}

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            MainActor.assumeIsolated {
                PreviewRenderer.render(to: URL(fileURLWithPath: args[i + 1]),
                                       dark: args.contains("--dark"),
                                       expandFirst: args.contains("--expanded"))
            }
            return
        }
        AudioRouterApp.main()
    }
}

struct AudioRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var engine = AppEnvironment.engine

    var body: some Scene {
        MenuBarExtra {
            RouterPanel().environmentObject(engine)
        } label: {
            Image(systemName: engine.hasActiveRoutes ? "hifispeaker.2.fill" : "hifispeaker.2")
                .accessibilityLabel("Audio Router")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppEnvironment.engine.startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.engine.stopAll()
    }
}

/// Renders the panel with demo data to a PNG: `AudioRouter --render-preview out.png [--dark] [--expanded]`.
@MainActor
enum PreviewRenderer {
    static func render(to url: URL, dark: Bool, expandFirst: Bool) {
        _ = NSApplication.shared
        let engine = Demo.engine()
        let view = PreviewFrame(dark: dark, expandedAppID: expandFirst ? "demo.vlc" : nil)
            .environmentObject(engine)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}

private struct PreviewFrame: View {
    let dark: Bool
    let expandedAppID: String?

    var body: some View {
        RouterPanel(initiallyExpanded: expandedAppID, scrollable: false)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(dark ? Color(white: 0.13) : Color(white: 0.97))
            )
            .padding(24)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

