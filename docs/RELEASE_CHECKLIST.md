# Release Checklist

Before tagging a release:

1. Confirm GitHub Actions is green on `main`.
2. Run `./script/test_all.sh --full`.
3. Run `./script/test_all.sh --boot --rom /path/to/test.z64` with a lawful local ROM.
4. Run `./script/build_and_run.sh --prepare --print-bundle-path`.
5. Verify `dist/Cinder64.app` contains:
   - `Contents/MacOS/Cinder64`
   - `Contents/Frameworks/libcinder64_gopher64.dylib`
   - `Contents/Frameworks/libMoltenVK.dylib`
   - `Contents/Frameworks/libfreetype.6.dylib`
   - `Contents/Frameworks/libpng16.16.dylib`
6. Run `codesign --verify --deep --strict dist/Cinder64.app`.
7. Review `docs/LEGAL.md` and confirm license status is intentional.
8. Publish release notes with user-visible changes, known limitations, and the required runtime dependencies.
