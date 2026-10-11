#!/usr/bin/env python3
"""Prepare an isolated Android tester; never rewrite the source pubspec/assets.
Build from completed HEAD plus the explicitly reviewed Android repair files.
Usage: python3 tool/prepare_android_tester.py /absolute/new/staging-directory
Then in that directory:
ORG_GRADLE_PROJECT_testBedDebugSigning=true flutter build apk --release --split-per-abi --target-platform android-arm64 --build-number 87
All recorded Bible chapters remain bundled for complete offline functionality.
"""
import io
import re
import subprocess
import sys
import tarfile
from pathlib import Path
import shutil

REPAIRS = (
    'lib/features/library/data/library_source_type.dart',
    'lib/features/library/data/library_document_canonicalizer.dart',
    'lib/features/library/data/user_epub_import_service.dart',
    'lib/features/library/presentation/canonical_library_reader.dart',
    'lib/features/library/presentation/library_book_reader_screen.dart',
    'lib/features/library/presentation/library_speech_controls.dart',
    'lib/features/library/presentation/speech_tilt_binding.dart',
    'lib/core/theme/app_settings_service.dart',
    'test/features/library/presentation/speech_tilt_binding_test.dart',
    'test/features/reader/presentation/bible_loop_announcement_settings_test.dart',
    'lib/features/reader/presentation/bundled_bible_audio_narrator.dart',
    'lib/features/utilities/data/elibrary_download_service.dart',
    'android/app/src/main/kotlin/com/deanbowen/bibleappmac/MainActivity.kt',
    'android/app/build.gradle.kts',
    'test/features/library/data/library_source_type_test.dart',
    'test/features/library/data/android_device_epub_rehearsal_test.dart',
)

def main():
    source = Path(__file__).resolve().parents[1]
    destination = Path(sys.argv[1]).resolve()
    if destination.exists():
        raise SystemExit('Choose a new, nonexistent staging directory.')
    if destination == source or source in destination.parents:
        raise SystemExit('Staging must be outside the source checkout.')
    destination.mkdir(parents=True)
    snapshot = subprocess.check_output(['git', 'archive', 'HEAD'], cwd=source)
    with tarfile.open(fileobj=io.BytesIO(snapshot)) as archive:
        archive.extractall(destination, filter='data')
    for name in REPAIRS:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
    subprocess.run(['rsync', '-a', str(source / 'assets') + '/',
                    str(destination / 'assets') + '/'], check=True)
    shutil.copy2(source / 'pubspec.lock', destination / 'pubspec.lock')
    local = source / 'android/local.properties'
    if local.exists():
        # SDK paths only; no signing keys or credentials are copied.
        sdk_lines = [line for line in local.read_text().splitlines()
                     if line.startswith(('sdk.dir=', 'flutter.sdk='))]
        (destination / 'android/local.properties').write_text('\n'.join(sdk_lines) + '\n')
    bible = destination / 'lib/features/reader/presentation/bible_explorer_screen.dart'
    bible_text = bible.read_text().replace(
        'if (_macAutoScroll != null)\n              MacReaderAutoscrollStatusOverlay(',
        'if (_macAutoScroll != null && !Platform.isAndroid)\n              MacReaderAutoscrollStatusOverlay(')
    bible_text = bible_text.replace('                  ReaderTiltAutoScrollActiveIndicator(',
        '                  if (!Platform.isAndroid)\n                    ReaderTiltAutoScrollActiveIndicator(', 1)
    bible_text = re.sub(r'  void _toggleTiltAutoScroll\(\) \{.*?\n  \}\n',
        '  void _toggleTiltAutoScroll() {\n'
        '    unawaited(toggleSilentReaderTilt(tilt: _tiltAutoScroll, speech: _macAutoScroll));\n'
        '  }\n', bible_text, count=1, flags=re.S)
    bible.write_text(bible_text)
    manifest = destination / 'pubspec.yaml'
    text = manifest.read_text()
    for line in ('    - assets/audio/qwen_loop_cues/\n',
                 '    - assets/audio/kokoro/models/kokoro-v1.0.onnx\n',
                 '    - assets/audio/kokoro/models/voices-v1.0.bin\n'):
        text = text.replace(line, '')
    manifest.write_text(text)
    (destination / 'ANDROID_TESTER_SOURCE.txt').write_text(
        subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source).decode()
        + 'Reviewed overlays:\n' + '\n'.join(REPAIRS) + '\n')
    print(destination)

if __name__ == '__main__':
    main()
