# Restoring the Kokoro narration payloads on a fresh clone

The narration source, Swift bridge, tests, pronunciation assets and the sherpa
package patch/docs/build scripts are tracked. The large upstream payloads and
the locally built native binaries are **git-ignored** (see `.gitignore`) and
must be restored before `flutter build` / `flutter run` will succeed, because
`pubspec.yaml` lists them as assets and path dependencies.

Tests: `context_lexicon_test`, `tag_playback_pronunciation_test` and
`tag_playback_settings_test` read `lexicon-us-en.txt` and `tokens.txt` from the
restored `sherpa/kokoro-multi-lang-v1_0/` directory, so restore it before
`flutter test`.

## 1. Model files — `assets/audio/kokoro/`

The runtime reads only `assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0/`
(`kokoro_engine_host.dart`). `pubspec.yaml` also bundles the two `models/`
files, which no code in `lib/` currently reads.

```sh
mkdir -p assets/audio/kokoro/sherpa assets/audio/kokoro/models

# Runtime model (verified byte-identical to the tree the app was tested with)
curl -L -o /tmp/kokoro-multi-lang-v1_0.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2
shasum -a 256 /tmp/kokoro-multi-lang-v1_0.tar.bz2
#   c5f7e2d2caf082bc1d20fb70334a61d99d20b484500aad32e7cf84c128ea3298
tar -xjf /tmp/kokoro-multi-lang-v1_0.tar.bz2 -C assets/audio/kokoro/sherpa

# Bundled by pubspec.yaml, not read by lib/ (sizes match upstream; upstream
# publishes no digest, so compare with the checksums below)
curl -L -o assets/audio/kokoro/models/kokoro-v1.0.onnx \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -L -o assets/audio/kokoro/models/voices-v1.0.bin \
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
```

Reference SHA-256 (recorded 2026-09-21 from the tested tree):

| File | SHA-256 |
| --- | --- |
| `models/kokoro-v1.0.onnx` (325,532,387 B) | `7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5` |
| `models/voices-v1.0.bin` (28,214,398 B) | `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d` |
| `sherpa/kokoro-multi-lang-v1_0/model.onnx` | `b40f62b166ac8164b0627ef48a0b358eda0985e272fb03ef5252e7206305da11` |
| `sherpa/kokoro-multi-lang-v1_0/voices.bin` | `1c5a5b983d3d50d8586d437a51f3faa2da7919ce76a013c081e65671a3447c29` |

## 2. Native sherpa binaries — inside `packages/`

These are hand-built from a patched sherpa-onnx (dictionary mode), so they
cannot be downloaded. **Keep an off-repo copy.** To rebuild, follow
`DICTIONARY_MODE.md`, `dictionary-mode.patch` and `build-device.sh` in each
package (pinned sherpa-onnx commit `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf`).

| Binary | SHA-256 |
| --- | --- |
| `packages/sherpa_onnx_ios_lexicon/ios/sherpa_onnx_ios/SherpaOnnxC.xcframework/ios-arm64/SherpaOnnxC.framework/SherpaOnnxC` | `8f8cd3d8ac885f1343bc6f9f07c1dfb6c1af17a0a63bf95358bf1fef195cadc6` |
| `packages/sherpa_onnx_macos_lexicon/macos/sherpa_onnx_macos/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx-c-api.dylib` | `f5361451c83cfd05a697e0036bf2843afdc5747ae865bcce827dd8d66695d52e` |
