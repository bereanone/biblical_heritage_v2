# Restoring the local narration assets

The source repository intentionally excludes generated Bible audio, downloaded
Kokoro models, and locally built native speech libraries. Keep a separate,
verified backup before cloning, cleaning, or replacing the working Mac.

The September 26, 2026 Purple Drive backup is in
`StudyBible2 Audio Backup 2026-09-26`. Its `BACKUP_VERIFICATION.json` lists the
SHA-256 and size of every backed-up file. The phone-ready set contains 1,189
Qwen chapter recordings. The backup also retains the original Qwen masters,
including segment WAVs and manifests, plus the local Qwen models, runtime,
voice recipe, and timing work. The phone-ready versions of eleven chapters
differ from their original master recordings; restore the phone set separately.

From the repository root, restore these folders from the backup before building:

| Backup folder | Repository destination |
| --- | --- |
| `Phone Qwen chapters` | `assets/audio/qwen_bible` |
| `Kokoro models` | `assets/audio/kokoro` |
| `Pronunciation data` | `assets/audio/pronunciation` (merge with tracked files) |
| `Native speech libraries/iOS/SherpaOnnxC.xcframework` | `packages/sherpa_onnx_ios_lexicon/ios/sherpa_onnx_ios/SherpaOnnxC.xcframework` |
| `Native speech libraries/macOS/sherpa-onnx.xcframework` | `packages/sherpa_onnx_macos_lexicon/macos/sherpa_onnx_macos/sherpa-onnx.xcframework` |

The `Bible base` copy is an additional safety copy of the tracked database.
Restore it only when the repository's expected database version is known;
do not overwrite newer user or library data. `Qwen KJV masters`,
`Qwen timing and integration`, `Classic narrator recipe`, `Qwen local models`,
and `Qwen local runtime` are recovery and regeneration material, not app assets.

For Kokoro's upstream origins and model digests, also see
[`narration_model_restore.md`](narration_model_restore.md). The GitHub source
repository alone cannot reconstruct the exact phone audio without this backup.
