# Build Guide

## Toolchain

Cinder64 is a Swift Package Manager project with no Xcode project file. `Package.swift` requires Swift tools 6.3, Swift language mode 6, and macOS 15 or newer.

Install runtime dependencies with Homebrew:

```bash
brew install molten-vk freetype libpng
```

Rust and Cargo are required for `ThirdParty/gopher64/cinder64_bridge`.

## Commands

Run the default test lane:

```bash
./script/test_all.sh
```

Run the full stack lane:

```bash
./script/test_all.sh --full
```

Prepare and launch the app bundle:

```bash
./script/build_and_run.sh
```

Prepare a bundle without launching:

```bash
./script/build_and_run.sh --prepare --print-bundle-path
```

Avoid `swift run` for app launches. The raw SwiftPM executable does not include the bundled runtime libraries and is not equivalent to the assembled `.app`.

## Artifacts

Test logs, Swift Testing XML, coverage JSON, boot logs, metrics, and summaries are written under `test-artifacts/<timestamp>/` by default. That directory is intentionally ignored by git.
