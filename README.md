# Cinder64

Cinder64 is a macOS-focused fork of [gopher64](https://github.com/gopher64/gopher64). It keeps gopher64's Rust emulator core, SDL3 runtime, parallel-rdp renderer, and Slint/winit/Skia launcher stack, while branding the macOS app as Cinder64 and refining the launcher experience.

The Cargo package and binary stay named `gopher64` for upstream compatibility. The macOS app bundle is named `Cinder64` and uses bundle identifier `com.patricedery.Cinder64`.

## Status

- Base: upstream gopher64 `v1.1.19`
- Rust: `1.95.0` from `rust-toolchain.toml`
- macOS minimum: `15.0`
- UI: Slint launcher with SDL3 game window
- License: GPLv3, inherited from gopher64

## Features

- Native macOS app bundle named `Cinder64`
- Upstream-compatible CLI behavior for ROM launch, fullscreen, save states, netplay, input profiles, RetroAchievements, and config flags
- Library launcher with Open ROM, Recent ROMs, and saves-folder access
- Existing gopher64 pages for Controllers, Netplay, Cheats, RetroAchievements, Settings, and About

## Legal

Cinder64 does not include games, BIOS files, or game assets. Use ROMs only when you have the legal right to do so.

This project is based on gopher64 and remains under the GPLv3. Portions of gopher64 were adapted from mupen64plus and/or ares; see the upstream project and included license files for attribution details.

## Build

Clone with submodules:

```bash
git clone --recursive https://github.com/PowerBeef/Cinder64.git
cd Cinder64
git submodule update --init --recursive
```

Run the standard checks:

```bash
cargo fmt --check
cargo test
cargo build --release
```

Run a ROM directly from the CLI:

```bash
./target/release/gopher64 /path/to/rom.z64
```

## macOS Bundle

Install local bundle tools and libraries:

```bash
cargo install cargo-bundle
brew install molten-vk freetype libpng
```

Build and assemble the unsigned app bundle:

```bash
cargo build --release --no-default-features --target aarch64-apple-darwin
mv target/aarch64-apple-darwin/release/gopher64 target/aarch64-apple-darwin/release/gopher64-cli
cargo bundle --release --target aarch64-apple-darwin --format osx
cp target/aarch64-apple-darwin/release/gopher64-cli target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/MacOS/gopher64-cli
install_name_tool -change /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib \
  @executable_path/../Frameworks/libfreetype.6.dylib target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/MacOS/gopher64
install_name_tool -change /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib \
  @executable_path/../Frameworks/libfreetype.6.dylib target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/MacOS/gopher64-cli
install_name_tool -change /opt/homebrew/opt/libpng/lib/libpng16.16.dylib \
  @executable_path/../Frameworks/libpng16.16.dylib target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/Frameworks/libfreetype.6.dylib
```

Verify and ad-hoc sign the bundle:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleName" target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app/Contents/Info.plist
codesign -f --entitlements data/macos/entitlements_dev.plist --deep --timestamp --options runtime -s - target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app
codesign --verify --deep --strict --verbose=2 target/aarch64-apple-darwin/release/bundle/osx/Cinder64.app
```

Signing and notarization with Apple Developer credentials are not configured yet. CI verifies an unsigned/ad-hoc-signable macOS bundle.

## Upstream

Cinder64 tracks gopher64 closely. Keep emulator-core behavior upstream-compatible unless a Cinder64 milestone explicitly changes it.

When refreshing upstream:

- update the root source tree from the target gopher64 release,
- keep Cinder64 bundle metadata and launcher wording,
- preserve local Recent ROMs behavior,
- update this README and `AGENTS.md` if commands, toolchains, or repo layout change.
