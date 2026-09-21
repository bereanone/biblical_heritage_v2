# StudyBible2 dictionary mode

Local fork of sherpa_onnx_macos 1.13.8. Upstream source: https://github.com/k2-fsa/sherpa-onnx/tree/11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf

The explicit `kokoro.lang = lexicon` option clears only the frontend language argument, allowing dictionary lookup while retaining `en-us` in the original model metadata for unknown-word fallback. Model weights, speakers, and Scripture are unchanged. Other language modes preserve upstream behavior.

`dictionary-mode.patch` contains the complete native source change and shared C API build setting. The library includes arm64 and x86_64 slices, built from the pinned source with static dependencies. Deployment target preserved: macOS 10.15 on Intel; Apple Silicon requires macOS 11.

Rebuild with CMake Release, BUILD_SHARED_LIBS=OFF, SHERPA_ONNX_ENABLE_PORTAUDIO=OFF, SHERPA_ONNX_ENABLE_WEBSOCKET=OFF, SHERPA_ONNX_ENABLE_BINARY=OFF, SHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF, SHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF, CMAKE_OSX_ARCHITECTURES="arm64;x86_64", CMAKE_OSX_DEPLOYMENT_TARGET=10.15, CMAKE_POLICY_VERSION_MINIMUM=3.5. Build the sherpa-onnx-c-api target.

Runtime tests verified dictionary tokens for God, hast, Sodom, Gomorrah, Methuselah and contrasting live/lived contexts; these do not constitute listening approval of the whole Bible.

Library SHA-256: f5361451c83cfd05a697e0036bf2843afdc5747ae865bcce827dd8d66695d52e
