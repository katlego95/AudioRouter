// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioRouter",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "AudioRouter", targets: ["AudioRouter"]),
        .library(name: "AudioRouterCore", targets: ["AudioRouterCore"]),
    ],
    targets: [
        // Pure, deterministic logic: models, routing policy, persistence, sample mixing.
        // No Core Audio side effects, so every line here can be unit-tested.
        .target(name: "AudioRouterCore"),

        // Adapters that talk to the real Core Audio HAL (process taps, aggregate devices).
        .target(name: "AudioRouterCoreAudio", dependencies: ["AudioRouterCore"]),

        // The SwiftUI menu bar app. Wires the adapters into the core engine.
        .executableTarget(name: "AudioRouter", dependencies: ["AudioRouterCore", "AudioRouterCoreAudio"]),

        .testTarget(name: "AudioRouterCoreTests", dependencies: ["AudioRouterCore"]),
    ]
)
