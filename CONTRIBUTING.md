# Contributing to Audio Router 🎧

Thanks for helping! This project is small on purpose: one Swift package, no dependencies, no Xcode project.

## Setup (2 minutes)

```bash
xcode-select --install        # if you don't have the Command Line Tools
git clone https://github.com/<you>/AudioRouter.git && cd AudioRouter
swift test                    # should print "48 tests passed" (or more!)
./build.sh                    # build, install, launch
```

Requirements: macOS 14.2+, Swift 6 (Command Line Tools 16+ or Xcode 16+).

## The workflow: red → green → refactor

1. **Red.** Write a failing test in `Tests/AudioRouterCoreTests/`. Use the fakes in `Fakes.swift` (`FakeAudioSystem`, `FakeRouteFactory`, `InMemoryAssignmentStore`) to describe the situation: devices, apps, failures, time.
2. **Green.** Make it pass with the smallest change in `Sources/AudioRouterCore/`.
3. **Refactor.** Tidy up with the tests still green.
4. Only then wire it into the adapters (`AudioRouterCoreAudio`) or the UI (`AudioRouter`).

If a behaviour can't be tested without real hardware, that's a sign the logic belongs in the core behind a port.

## Where things go

| You're changing… | Put it in… | Tested by |
|---|---|---|
| *When* routes start/stop | `RoutePlanner.swift` | `RoutePlannerTests` |
| What the UI says about an app | `RouteStatus.resolve` | `RouteStatusTests` |
| Commands (assign, reset, …) | `RouterEngine.swift` | `RouterEngineTests` |
| How settings are saved | `FileAssignmentStore.swift` | `FileAssignmentStoreTests` |
| Sample processing (gain, mixing) | `ChannelMixer.swift` | `ChannelMixerTests` |
| Core Audio calls | `AudioRouterCoreAudio/` | manual (see below) |
| Look and feel | `AudioRouter/` + `Theme.swift` | `--render-preview` screenshots |

## Rules of the road

- **Swift 6 strict concurrency stays on.** State lives on the `@MainActor`. Code that runs on the audio thread (`ChannelMixer`, the IOProc block) must not allocate, lock, or touch actors. Build the IOProc block in a `nonisolated` function (see `ProcessTapRoute.makeIOBlock`).
- **Keep the engine on protocols.** Only `AppEnvironment` creates concrete Core Audio types.
- **Keep ACID guarantees.** Save before applying; roll back on failure; never leave a half-built route.
- **UI controls are drawn in SwiftUI** (not AppKit-backed), so `--render-preview` screenshots match the real thing.
- **No new dependencies** without opening an issue first.

## Testing on real hardware

```bash
./build.sh
/usr/bin/log stream --predicate 'process == "coreaudiod" AND eventMessage CONTAINS "Muter"'
```

Route an app and you should see `muted by AudioRouter <bundle id>`; un-route or quit and you should see `unmuted`. Please test at least: route, switch device, System output, Bluetooth off/on, quit.

## UI changes

Regenerate the screenshots and include them in your PR:

```bash
B=$(swift build -c release --show-bin-path)/AudioRouter
$B --render-preview docs/panel-dark.png --dark
$B --render-preview docs/panel-light.png
$B --render-preview docs/panel-chooser.png --dark --expanded
```

## Pull requests

- One focused change per PR, with tests.
- `swift test` and `./build.sh --no-install` must pass (CI checks both).
- Describe how you tested on real hardware if you touched `AudioRouterCoreAudio/`.
