# Cinder64

Cinder64 is a macOS-focused fork of [gopher64](https://github.com/gopher64/gopher64). This restart keeps gopher64's Rust emulator core, SDL3 runtime, parallel-rdp renderer, and Slint/winit/Skia launcher stack, while branding the app as Cinder64 and refining the first-run launcher experience.

The first milestone intentionally avoids a SwiftUI frontend and avoids changing the emulation core. The Cargo package and executable remain close to upstream gopher64 so future rebases stay practical.

## Status

- Base: upstream gopher64 `v1.1.19`
- Rust: `1.95.0` via `rust-toolchain.toml`
- macOS minimum: `15.0`
- UI: Slint launcher with SDL3 game window
- License: GPLv3, inherited from gopher64

## Features

- Native macOS app bundle named `Cinder64`
- Existing gopher64 CLI behavior for ROM launch, fullscreen, save states, netplay, input profiles, RetroAchievements, and config flags
- Cleaner Library screen with Open ROM, Recent ROMs, and saves-folder access
- Existing gopher64 pages for Controllers, Netplay, Cheats, RetroAchievements, Settings, and About

## Legal

Cinder64 does not include games or game assets. Use ROMs only when you have the legal right to do so.

This project is based on gopher64 and remains under the GPLv3. Many portions of gopher64 were adapted from mupen64plus and/or ares; see the upstream project and included license files for attribution details.

## Build

Clone with submodules:

```bash
git clone --recursive https://github.com/PowerBeef/Cinder64.git
cd Cinder64
git submodule update --init --recursive
```

Run the core checks:

```bash
cargo fmt --check
cargo test
cargo build --release
```

Run a ROM directly:

```bash
./target/release/gopher64 /path/to/rom.z64
```

## macOS Bundle

Install local bundle tools and libraries:

```bash
cargo install cargo-bundle
brew install molten-vk freetype libpng
```

Build the unsigned app bundle:

```bash
cargo build --release --no-default-features --target aarch64-apple-darwin
mv target/aarch64-apple-darwin/release/gopher64 target/aarch64-apple-darwin/release/gopher64-cli
cargo bundle --release --target aarch64-apple-darwin --format osx
cp target/aarch64-apple-darwin/release/gopher64-cli target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/MacOS/gopher64-cli
```

Signing and notarization are intentionally optional until Cinder64 has Apple Developer credentials configured. CI verifies an unsigned/ad-hoc-signable bundle.

## Upstream

Cinder64 currently tracks gopher64 closely. The user-facing app name, macOS bundle identifier, launcher wording, and recent-ROM metadata differ from upstream; emulator-core behavior should remain upstream-compatible unless a later Cinder64 milestone deliberately changes it.
