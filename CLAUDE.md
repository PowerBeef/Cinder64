# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Cinder64 is a native macOS (SwiftUI / AppKit) front-end that embeds [gopher64](ThirdParty/gopher64), a Rust N64 emulator, via a thin Rust cdylib exposing a versioned C ABI. The Swift app dynamically loads the bridge `dylib` at runtime (`dlopen`) rather than linking against it, and the bridge is bundled inside `Cinder64.app/Contents/Frameworks/libcinder64_gopher64.dylib` alongside MoltenVK/freetype/libpng.

Targets macOS 15+, Swift 6 language mode, Swift Package Manager (`Package.swift`). There is no Xcode project — the SwiftPM executable is wrapped into an `.app` bundle by `script/build_and_run.sh`.

## Build / run / test commands

Use the shell scripts in `script/` — they codify the bundle-assembly, library rewriting, ad-hoc codesigning, and Info.plist generation that the app needs to launch correctly. Invoking `swift build` / `swift run` directly produces a binary that cannot find its bundled runtime.

- `./script/build_and_run.sh` — build Rust bridge (release) + `swift build`, assemble `dist/runs/<timestamp>/Cinder64.app`, update `dist/Cinder64.app` symlink, launch via `open -n`.
  - `run` (default), `--prepare`, `--verify`, `--debug` (lldb), `--logs`, `--telemetry` modes.
  - `--prepare --print-bundle-path` prints the bundle path without launching; used by verify scripts.
- `./script/build_rust_bridge.sh [release|debug]` — cargo-builds the bridge crate at `ThirdParty/gopher64/cinder64_bridge/` and prints the resulting `libcinder64_gopher64.dylib` path.
- `swift test` — runs `Cinder64Tests`. For a single test: `swift test --filter Cinder64Tests.EmulationSessionTests/test_openROM_updatesSnapshot` (filter is `Target.ClassName/methodName`).
- `./script/test_app_bundle_helpers.sh` — bash unit tests for `script/app_bundle_helpers.sh`.

### End-to-end boot verifications

These launch the prepared `.app` and assert against runtime logs + metrics. They look for a ROM at `Roms/` or `Super Mario 64 (USA)/Super Mario 64 (USA).z64`; pass an explicit path as `$1` otherwise.

- `./script/verify_launch_services_boot.sh` — boot via Launch Services, assert `recent-games.json` + readiness log, single on-screen window, no new crash reports.
- `./script/verify_full_boot.sh` — same plus scripted keyboard injection (see `boot_key_profiles.sh` — the `smoke` profile) and metrics thresholds (`renderFrameCount ≥ 250`, `presentCount ≥ 250`, `viCount ≥ 700`).
- `./script/verify_visual_boot.sh` — longer `visual` key profile, leaves the app running for manual inspection.

Don't take screenshots of the running app during a boot run: `screencapture -l` causes parallel-rdp's `check_callback()` to observe `emu_running == false`, flipping the bridge's `status.active` and dropping subsequent scripted keystrokes (see comment in `verify_full_boot.sh`).

## Environment variables

- `CINDER64_APP_SUPPORT_ROOT` — override the app's Application Support root (used by every verify script to isolate state under a tempdir). Also settable via `--app-support-root` CLI flag.
- `CINDER64_GOPHER64_BRIDGE` — override the path to `libcinder64_gopher64.dylib`; bypasses the `Bundle.privateFrameworksURL` / `ThirdParty/.../target/release` / executable-dir search chain in `BundledGopher64RuntimeLocator`.
- `CINDER64_MOLTENVK_LIBRARY`, `CINDER64_FREETYPE_LIBRARY`, `CINDER64_LIBPNG_LIBRARY` — point the bundler at specific dylibs; otherwise it resolves them from Homebrew (`brew --prefix molten-vk` etc.).
- `CINDER64_SCRIPTED_KEYS` — `timeMs:scancode:down|up;...` schedule consumed by `ScriptedKeyPlayer` after a ROM launches; used by the boot verifiers for deterministic input.
- `CINDER64_BOOT_KEY_PROFILE` — `smoke` or `visual`, resolved to a `CINDER64_SCRIPTED_KEYS` string by `boot_key_profiles.sh`.

## Architecture

### Process layering

1. **SwiftUI scene (`Sources/Cinder64/App/Cinder64App.swift`)** — single `Window` scene, registers `AppDelegate` for Launch Services `open urls:` / reopen / terminate interception, wires `CommandGroup` + `CommandMenu` menu items to `EmulationSession` async operations.
2. **`LaunchRequestBroker` (singleton)** — marshals ROM launch requests from multiple sources (CLI args, `open`/drag-drop URLs, Recents, Open ROM panel) through one async handler so the App can `await` session work without blocking AppKit delegate callbacks.
3. **`CloseGameCoordinator`** — intercepts window-close / app-quit / return-to-home while a ROM is running, prompts for protected save behavior, and only then lets the close/quit proceed. `MainWindowController` + `AppDelegate` call into it before honoring user-initiated exits.
4. **`EmulationSession` (`@MainActor @Observable`)** — the top-level state machine. Owns `snapshot: SessionSnapshot`, `activeSettings`, `recentGames`, and the current `RenderSurfaceDescriptor`. All commands (`openROM`, `pause/resume/reset`, `updateRenderSurface`, `saveState/loadState`, `setKeyboardKey`, `dispose`) go through it.
5. **`Gopher64CoreHost : CoreHosting`** — adapts `EmulationSession` calls to `Gopher64CoreExecutor`, emits `os_signpost` intervals, records frame/metrics artifacts via `RuntimeMetricsArtifactStore`, and produces `CoreRuntimeEvent`s consumed by the pump.
6. **`Gopher64Bridge` (`Services/Gopher64Bridge.swift`)** — loads the cdylib with `dlopen`, calls `cinder64_bridge_get_api`, validates ABI version + struct sizes against `Cinder64BridgeABI/include/cinder64_bridge.h`, and wraps the function pointers. Any struct change to the C header must be mirrored in both the Rust bridge crate and this file; the ABI version constant gates compatibility.
7. **`RuntimePumpCoordinator` (under `Views/`)** — ticks `coreHost.pumpEvents()` on a timer from the SwiftUI side, translating bridge events into `SessionSnapshot` mutations. State transitions it can produce are enumerated by `RuntimeLifecycleStateMachine`.

`CoreHosting` (`Models/CoreContracts.swift`) is the protocol seam between `EmulationSession` and `Gopher64CoreHost`; tests substitute fakes here rather than touching the dylib. Test doubles live in `Tests/Cinder64Tests/TestSupport.swift`.

### Render surface handoff

AppKit's `MTKView` / `NSWindow` are captured into a `RenderSurfaceDescriptor` (window handle, view handle, logical + pixel sizes, backing scale) and attached to the bridge session. Publication is policied by `RenderSurfacePublicationPolicy` (when to re-attach vs. update) and `RenderSurfaceKeyboardFocusPolicy`. If a ROM is requested before the surface is ready, `EmulationSession` parks via `waitForValidRenderSurface()` continuations and replays a deferred surface update after boot.

### Persistence

`PersistenceStore.live()` roots everything under `~/Library/Application Support/Cinder64` (or the override). All stores are file-backed JSON keyed off `ROMIdentity` (hash/header-derived identity, not a path):

- `RecentGamesStore` — `recent-games.json`
- `SaveStateMetadataStore` — `savestate-metadata.json`
- `PerGameSettingsStore` — `per-game-settings.json`
- `LogStore` — `logs/runtime.log` (what boot verifiers grep)
- `RuntimeMetricsArtifactStore` — `metrics.json` snapshot the verifiers read

### Rust bridge crate

`ThirdParty/gopher64/cinder64_bridge/` is a `cdylib` (`cinder64_gopher64`) that depends on the sibling `gopher64` crate. It exports the C ABI declared in `Sources/Cinder64BridgeABI/include/cinder64_bridge.h`. `UPSTREAM_COMMIT.txt` records the vendored gopher64 commit; it's embedded in the build manifest the bundler writes to `Contents/Resources/build-manifest.json`.

When rebasing/refreshing the vendored emulator: update `ThirdParty/gopher64/`, bump `UPSTREAM_COMMIT.txt`, and verify no struct-layout changes leak past the ABI header.

## Conventions worth knowing

- Keep `@MainActor` discipline — `EmulationSession` and everything it owns are main-actor-isolated; `Gopher64Bridge.Session` is `@unchecked Sendable` only because the Rust handle is thread-neutral. Don't pass it off the main actor casually.
- Tests that verify main-window / surface-lifecycle behavior drive `MainWindowDisplayModeTests`, `RenderSurfaceKeyboardFocusPolicyTests`, `RenderSurfacePublicationPolicyTests`; prefer adding cases there rather than rewriting the policies inline.
- Run bundles accumulate under `dist/runs/<timestamp>-<pid>/`. `build_and_run.sh` prunes to the newest 5 (keeping whatever `dist/Cinder64.app` symlinks to). Don't hand-edit under `dist/`.
