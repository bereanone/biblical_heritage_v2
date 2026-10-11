# Storage cleanup ledger — 2026-09-17

Scope: authorized low-risk cleanup of the Mac startup disk, with protected active StudyBible2 work, protected Ollama model download/store, and no use of OldMusic.

## Baseline

- Startup filesystem available: 57,831,728 KiB at initial check.
- Sandisk1 available: 87,855,104 KiB at initial check.
- Google Drive local mount observed at `Library/CloudStorage/GoogleDrive-bereanone@gmail.com/My Drive`; no archive upload or source retirement has yet been performed.
- Active processes observed: Ollama service and `ollama pull qwen3-coder-next`; StudyBible2 Flutter/Dart debug session. These areas are excluded.

## Classification

Excluded from deletion:

- StudyBible2 `build/` and `.dart_tool/`: active Flutter session and concurrent audit.
- TCAIS `build/`: not a Flutter project root; contains named smoke/crop/PDF/EPUB outputs that may be unique.
- All live app data, source EPUBs, artwork/restoration assets, history recovery, databases, and unknown backups.
- Ollama store/download and all model processes.

Approved low-risk generated-output cohort (allocated size before deletion):

| Project | Generated directory | KiB | Evidence |
|---|---|---:|---|
| BRHC | `build/` | 3,428,272 | Flutter pubspec; Git ignored `build/`; no active process |
| CaptureBookViewer | `build/` | 576,784 | Flutter pubspec; standard macOS build/cache tree; no active process |
| GeoMuteLab | `build/` | 4,206,968 | Flutter pubspec; standard Android/plugin build tree; no active process |
| Promises | `build/` | 2,569,232 | Flutter pubspec; standard macOS/Android build tree; no active process |
| bible_app_mac | `build/` | 893,976 | Flutter pubspec; Git ignored `build/`; no active process; authored source untouched |
| capture_clipper | `build/` | 1,679,028 | Flutter pubspec; Git ignored `build/`; no active process |
| memorize_app | `build/` | 1,622,288 | Flutter pubspec; standard macOS/iOS build tree; no active process |
| **Total** |  | **14,976,548** | reproducible generated output only |

## Actions

### 1. Inactive Flutter generated output

- Deleted only the seven exact `build/` paths listed above.
- All seven paths were absent on readback.
- Startup free space immediately before: 56,485,696 KiB.
- Startup free space immediately after: 70,351,424 KiB.
- **Measured gain: 13,865,728 KiB** (about 14.2 GB decimal). This measured delta, not the larger `du` estimate, is the claimed recovery.

### 2. Legacy app archive assessment

- Identified `bible_app_mac` as the legacy candidate with bundle name “Biblical Heritage.”
- Working tree is materially dirty and contains many untracked authored documents/assets; it must not be retired without a verified archive.
- `.git` is a symlink to a separate local Git directory. The resolved Git store passed `git lfs fsck` and contains 181 LFS objects totaling 11,995,137,244 logical bytes.
- Provisioning-profile files are present. For privacy, no cloud upload was attempted.
- A self-contained Sandisk archive plan was prepared to embed the resolved Git directory as a real `.git/` and verify every regular member by SHA-256.
- The external archive write was blocked by the safety reviewer because the exact sensitive payload/destination requires explicit approval. No archive was written and no legacy-app source was removed.

### 3. Exact duplicate downloads identified

SHA-256 checks proved these duplicate cohorts byte-identical; originals are retained and only numbered copies are candidates:

- App Store asset ZIP: three identical 279,200,773-byte files; retain unnumbered original.
- VS Code Windows ARM installer: three identical 124,947,080-byte files; retain unnumbered original.
- APLib EPUB archive: two identical 57,973,177-byte files; retain unnumbered original.
- Daniel and the Revelation EPUB: two identical 13,486,777-byte files; retain unnumbered original.

Pending exact duplicate deletion and measurement.
