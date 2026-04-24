# Cinder64

Cinder64 is a native macOS front end for Nintendo 64 emulation. It is built with SwiftUI and AppKit, and embeds the vendored `gopher64` runtime through a small Rust dynamic library exposed through a versioned C ABI.

The Swift app loads `libcinder64_gopher64.dylib` at runtime and packages it inside `Cinder64.app/Contents/Frameworks` alongside MoltenVK, freetype, and libpng.

## Requirements

- macOS 15 or newer.
- Xcode with Swift tools 6.3 support.
- Rust and Cargo for the bundled bridge crate.
- Homebrew libraries: `molten-vk`, `freetype`, and `libpng`.

## Build And Test

Use the scripts in `script/`; they assemble the app bundle and runtime libraries correctly.

```bash
./script/test_all.sh
./script/test_all.sh --full
./script/build_and_run.sh
```

ROM boot verification is opt-in because ROM files are not committed:

```bash
./script/test_all.sh --boot --rom /path/to/your/game.z64
```

## Documentation

- [Build guide](docs/BUILD.md)
- [Runtime bridge](docs/RUNTIME_BRIDGE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Legal and ROM note](docs/LEGAL.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

No reuse license is currently declared for this repository. Do not redistribute, fork for reuse, or incorporate Cinder64 source into another project until the project owner adds an explicit license.
