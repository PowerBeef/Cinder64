# Troubleshooting

## App Launches Without The Runtime

Use `./script/build_and_run.sh`, not `swift run`. The script builds the Rust bridge, assembles `Cinder64.app`, rewrites dynamic-library paths, signs the bundle, and validates the copied frameworks.

## Missing MoltenVK, freetype, Or libpng

Install the dependencies:

```bash
brew install molten-vk freetype libpng
```

If Homebrew paths are unusual, set the explicit environment variables documented in [Runtime bridge](RUNTIME_BRIDGE.md).

## Tests Pass Locally But CI Fails

Run the same default lane that CI runs:

```bash
./script/test_all.sh --artifacts test-artifacts/local-default
```

The summary file and logs under the artifact directory are the first place to inspect.

## Boot Verification

Boot verification requires a local ROM path:

```bash
./script/test_all.sh --boot --rom /path/to/your/game.z64
```

The launch and full boot verifiers isolate app state under the artifact directory, collect runtime logs and metrics, and stop the app when the run completes.

Do not take screenshots of a running boot verifier. The current verifier scripts intentionally avoid screenshots because the running emulator can react badly to window-server capture during scripted input.
