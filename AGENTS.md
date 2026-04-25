# AGENTS.md

Guidance for Codex and other coding agents working in this repository.

## Project Overview

Cinder64 is now a Rust/Slint fork of upstream `gopher64`, pinned initially to upstream `v1.1.19`. It is not the old SwiftUI/AppKit front end. There is no Swift Package, Xcode project, Swift bridge ABI, `EmulationSession`, or bundled `ThirdParty/gopher64` runtime host on `main`.

The Cargo package and CLI binary remain named `gopher64` for easier upstream rebasing. The macOS bundle is branded as `Cinder64` with bundle identifier `com.patricedery.Cinder64`.

## Build And Test Commands

Use Cargo from the repository root:

```bash
git submodule update --init --recursive
cargo fmt --check
cargo test
cargo build --release
```

The pinned toolchain is in `rust-toolchain.toml` and should currently resolve to Rust `1.95.0`.

Run a ROM directly:

```bash
./target/release/gopher64 /path/to/rom.z64
```

Build the macOS app bundle:

```bash
cargo install cargo-bundle
brew install molten-vk freetype libpng
cargo build --release --no-default-features --target aarch64-apple-darwin
mv target/aarch64-apple-darwin/release/gopher64 target/aarch64-apple-darwin/release/gopher64-cli
cargo bundle --release --target aarch64-apple-darwin --format osx
cp target/aarch64-apple-darwin/release/gopher64-cli target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/MacOS/gopher64-cli
```

CI also rewrites Homebrew dylib install names and ad-hoc signs the bundle. Keep local bundle commands aligned with `.github/workflows/ci.yml`.

## Architecture Notes

- `src/main.rs` owns CLI parsing, launcher startup, and direct ROM boot paths.
- `src/ui/gui.rs` wires the Slint launcher callbacks, Recent ROMs behavior, settings persistence, and ROM process spawning.
- `src/ui/gui/*.slint` defines the launcher UI.
- `src/ui/video.rs` and the SDL3 paths own the game window/runtime presentation.
- `parallel-rdp/parallel-rdp-standalone`, `retroachievements/rcheevos`, and `src/compat/sse2neon` are git submodules.

## Conventions

- Prefer small, upstream-friendly changes. Avoid rewriting emulator core behavior unless explicitly requested.
- Do not edit submodule contents unless the task is specifically an upstream/vendor refresh or a focused vendored patch.
- Keep Cinder64 branding in bundle metadata, launcher copy, README, and About text.
- Keep CLI behavior upstream-compatible whenever possible.
- Do not reintroduce SwiftUI, AppKit bridge code, SwiftPM files, old `script/` bundle helpers, or the previous bridge/runtime-host architecture.
- For third-party warning noise, prefer build-wrapper suppression in `build.rs` over patching vendored headers.

## Verification Expectations

For normal code changes, run:

```bash
cargo fmt --check
cargo test
cargo build --release
```

For macOS packaging changes, also run the no-default-features aarch64 bundle build and verify:

```bash
cargo build --release --no-default-features --target aarch64-apple-darwin
cargo bundle --release --target aarch64-apple-darwin --format osx
codesign --verify --deep --strict --verbose=2 target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app
```

ROM-dependent smoke checks are local and opt-in. Do not add ROM assets to the repository.
