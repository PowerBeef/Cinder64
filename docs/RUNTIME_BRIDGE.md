# Runtime Bridge

Cinder64 embeds the vendored `gopher64` runtime through `ThirdParty/gopher64/cinder64_bridge`, a Rust `cdylib` that exports the C ABI declared in `Sources/Cinder64BridgeABI/include/cinder64_bridge.h`.

The Swift side loads the bridge dynamically with `dlopen`, resolves `cinder64_bridge_get_api`, validates the ABI version and struct sizes, then calls through the returned function table.

## Build

```bash
./script/build_rust_bridge.sh release
```

The app bundler copies the resulting `libcinder64_gopher64.dylib` into:

```text
Cinder64.app/Contents/Frameworks/libcinder64_gopher64.dylib
```

## Runtime Lookup

`BundledGopher64RuntimeLocator` searches the app bundle first, then local development paths. Override lookup with:

```bash
export CINDER64_GOPHER64_BRIDGE=/absolute/path/to/libcinder64_gopher64.dylib
```

MoltenVK, freetype, and libpng can also be overridden with:

```bash
export CINDER64_MOLTENVK_LIBRARY=/absolute/path/to/libMoltenVK.dylib
export CINDER64_FREETYPE_LIBRARY=/absolute/path/to/libfreetype.6.dylib
export CINDER64_LIBPNG_LIBRARY=/absolute/path/to/libpng16.16.dylib
```

## ABI Changes

Any C struct or function-table change must be mirrored in three places:

- `Sources/Cinder64BridgeABI/include/cinder64_bridge.h`
- `ThirdParty/gopher64/cinder64_bridge`
- `Sources/Cinder64/Services/Gopher64Bridge.swift`

The ABI version and struct-size checks should reject incompatible bridge builds before a ROM is opened.
