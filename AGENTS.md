# AGENTS.md

This file gives coding agents the repo-specific context they need to work safely in this checkout.

## What this is

Cinder64 is a native macOS SwiftUI front-end for the [gopher64](https://github.com/gopher64/gopher64) Nintendo 64 emulator. The Swift app embeds gopher64 through a vendored Rust `cdylib` shim in `ThirdParty/gopher64/cinder64_bridge`, then hand-assembles `dist/Cinder64.app` with shell scripts.

Important repo shape:

- `Sources/Cinder64/App/` — app entry point, `AppDelegate`, `LaunchRequestBroker`
- `Sources/Cinder64/Models/` — pure value types like `CoreHostConfiguration`, `RenderSurfaceDescriptor`, `SessionSnapshot`, `ROMIdentity`
- `Sources/Cinder64/Services/` — `EmulationSession`, `Gopher64CoreHost`, runtime locator, bridge wrapper
- `Sources/Cinder64/Stores/` — JSON-backed persistence for recent games, save-state metadata, per-game settings, logs
- `Sources/Cinder64/Views/` — SwiftUI UI, including the embedded render host
- `ThirdParty/gopher64/` — vendored emulator, Rust bridge crate, parallel-rdp integration
- `script/` — the real build, bundle, and smoke-test entrypoints

There is no Xcode project workflow here. Use SwiftPM, Cargo, and the shell scripts.

## Build, run, and test

- Main dev loop: `./script/build_and_run.sh`
  What it does:
  Builds the Rust bridge in release, runs `swift build`, assembles `dist/Cinder64.app`, copies the bridge and optional Homebrew support dylibs into `Contents/Frameworks`, rewrites install names, ad-hoc signs the bundle, and launches it.
- Bundle-only verification: `./script/build_and_run.sh --prepare`
- Process/signature verification: `./script/build_and_run.sh --verify`
- Debug launch: `./script/build_and_run.sh --debug`
- Logs/telemetry: `./script/build_and_run.sh --logs` and `./script/build_and_run.sh --telemetry`
- Bridge only: `./script/build_rust_bridge.sh [release|debug]`
  Prints the resulting `libcinder64_gopher64.dylib` path on stdout.
- Swift tests: `swift test`
  Suites use Swift Testing `@Test`, not XCTest. `Gopher64CoreHostIntegrationTests` shells out to `cargo build --release`.
- LaunchServices smoke: `./script/verify_launch_services_boot.sh [ROM] [WORKDIR]`
  Cold-launches the bundle into an isolated app-support root, checks `runtime.log`, `recent-games.json`, and asserts exactly one visible `Cinder64` window.
- Full in-game boot smoke: `./script/verify_full_boot.sh [ROM] [WORKDIR]`
  Cold-launches the app, injects scripted Start/A keypresses, asserts the scripted steps in `runtime.log`, verifies `frame_count` progression, checks recent-games persistence, and fails on crash reports or rejected keyboard injections.

## Load-bearing overrides

- `CINDER64_APP_SUPPORT_ROOT` or `--app-support-root <path>`
  Redirects `~/Library/Application Support/Cinder64`. Tests and smoke scripts rely on this for isolation.
- `CINDER64_GOPHER64_BRIDGE`
  Absolute path to `libcinder64_gopher64.dylib`, bypassing bundle-relative lookup.
- `CINDER64_MOLTENVK_LIBRARY`, `CINDER64_FREETYPE_LIBRARY`, `CINDER64_LIBPNG_LIBRARY`
  Override Homebrew-resolved support libraries during bundle assembly.
- `--scripted-keys "<ms>:<scancode>:<down|up>;..."`
  Testing-only key injection hook used by `verify_full_boot.sh`.

## Launch and emulation flow

1. File-open events, menu opens, and CLI ROM args all flow into `LaunchRequestBroker.shared.enqueue(_:)`.
2. `Cinder64App` installs the broker handler and calls `EmulationSession.openROM(url:)`.
3. `EmulationSession` waits for a valid `RenderSurfaceDescriptor` from SwiftUI before constructing `CoreHostConfiguration`.
4. `Gopher64CoreHost` delegates to `Gopher64CoreExecutor`.
5. `Gopher64CoreExecutor` loads the Rust bridge through `Gopher64Bridge`, creates a bridge `Session`, attaches the render surface, opens the ROM, then resumes the core.
6. The vendored Rust bridge starts gopher64 on a background thread and routes hosted rendering through `ui::video` and `parallel-rdp`.

## Render surface contract

This is the easiest place to break the app.

- `RenderSurfaceView` hosts `RenderSurfaceHostingView`, an `NSViewRepresentable` wrapper around a custom `NSView`.
- The host view publishes raw `NSWindow` and `NSView` pointers as `UInt` bit-patterns in `RenderSurfaceDescriptor`.
  These are opaque handles for the bridge. Do not dereference them from Swift.
- `RenderSurfaceHostingView` must remain `CAMetalLayer`-backed.
  `makeBackingLayer()` returns `CAMetalLayer`, and `publishDescriptorIfPossible()` keeps the layer frame, `contentsScale`, and `drawableSize` synced to the current bounds and backing scale.
- The descriptor's `width` and `height` are logical view dimensions, not physical pixels.
  The Rust bridge multiplies them by `backingScaleFactor` before calling `ui::video::set_host_viewport(...)`.
- Identical surface descriptors are intentionally deduped on the Swift side.
  Re-sending the same descriptor repeatedly can churn `updateSurface()` and destabilize hosted presentation.
- The host view also owns a 60 Hz `Timer` that calls `pumpRuntimeEvents()` on the main thread so the embedded SDL/Vulkan loop can service its queue.

If you see audio plus advancing `frame_count` but a black or unstable image, suspect the host surface or point-to-pixel conversion before suspecting emulation correctness.

## Invariants worth preserving

- `openROM()` must suspend until a valid render surface exists.
  The `openingAROMWaitsForTheRenderSurfaceAndShowsBootingState` test covers this.
- Recent games and save-state metadata are persisted only after the runtime reports ready and `resume()` succeeds.
  Do not move `recordLaunch` earlier in `EmulationSession.openROM`.
- Keyboard input is forwarded only while a ROM is active and the session state is `.running` or `.paused`.
- Runtime failure must be surfaced explicitly.
  If the embedded runtime dies or rejects input, `SessionSnapshot.emulationState` must become `.failed` and the warning banner should explain why.
- The Swift host and Rust bridge must agree on hosted surface semantics.
  If you change `RenderSurfaceDescriptor`, `attachSurface`, `updateSurface`, or hosted viewport math on one side, update the other side in the same change.
- Bundle layout is hand-assembled.
  Anything copied into `Contents/Frameworks` must be ad-hoc signed and have install names rewritten to `@loader_path/...`.

## Current render/boot gotchas

- The hosted path is Retina-sensitive.
  The Swift host publishes logical size plus scale; the Rust bridge converts that to physical pixel viewport size.
- `verify_full_boot.sh` is log-based on purpose.
  Do not reintroduce screenshot assertions there: `screencapture -l <windowID>` can make the embedded runtime observe `emu_running == false` and exit on the next VI tick.
- If the app appears to "stall" at the SM64 title, verify whether input focus and render stability are intact before changing bindings.
  The default keyboard profile is already valid.

## Default keyboard to N64 map

These defaults are what users need for manual boot checks and what the scripted smoke uses:

- Start: `Return` (`SDL_SCANCODE_RETURN`, 40)
- A: `Left Shift` (225)
- B: `Left Control` (224)
- Z: `Z` (29)
- L / R: `K` / `L` (14 / 15)
- D-pad: `W A S D` (26 / 4 / 22 / 7)
- C-buttons: `I J K L` (12 / 13 / 14 / 15)
- Analog stick: arrow keys (82 / 80 / 81 / 79)

If `Return` appears to do nothing, first check focus on `RenderSurfaceHostingView` and the local `NSEvent` monitor path before editing bindings.

## Verification expectations

For changes in the bridge, input, launch flow, or render host, prefer this sequence:

- `swift build`
- `swift test`
- `./script/verify_launch_services_boot.sh`
- `./script/verify_full_boot.sh`

For render fixes specifically, a good manual acceptance path is:

1. Launch the repo ROM.
2. Confirm the SM64 title is visibly rendering, not just playing audio.
3. Press `Return` to leave the title.
4. Confirm the app advances into a live in-game scene without runtime failure banners.

## Not in this repo

- No CI config
- No linter config
- No `.cursorrules`
- No `.github/copilot-instructions.md`
- No top-level README

`.codex/environments/environment.toml` is auto-generated for the Run action. Do not hand-edit it.
