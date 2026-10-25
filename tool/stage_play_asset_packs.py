#!/usr/bin/env python3
"""Stage install-time packs without changing Flutter asset paths or originals."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

PACKS = ('bible_audio_1', 'bible_audio_2', 'reader_voices')
LIMIT = 1400 * 1000 * 1000  # Margin below Play's individual pack limit.

def stage(source: Path, destination: Path):
    files = sorted((source / 'assets/audio/qwen_bible').rglob('*'))
    files = [p for p in files if p.is_file()]
    voices = [p for p in sorted((source / 'assets/audio/kokoro').rglob('*')) if p.is_file()]
    if not files or not voices:
        raise ValueError('Missing compiled Bible audio or narration assets')
    # Deterministic greedy balancing, keeping complete files and original paths.
    groups = {name: [] for name in PACKS}
    totals = {name: 0 for name in PACKS}
    for path in sorted(files, key=lambda p: (-p.stat().st_size, str(p))):
        name = min(PACKS[:2], key=lambda n: (totals[n], n))
        groups[name].append(path); totals[name] += path.stat().st_size
    groups['reader_voices'] = voices
    totals['reader_voices'] = sum(p.stat().st_size for p in voices)
    if max(totals.values()) > LIMIT:
        raise ValueError(f'Asset pack exceeds conservative size limit: {totals}')
    result = {'packs': {}, 'total_bytes': sum(totals.values())}
    for name, paths in groups.items():
        folder = destination / name / 'src/main/assets'
        # Only generated staging content; never touch compiled/source assets.
        if folder.exists(): shutil.rmtree(folder)
        entries = []
        for path in sorted(paths):
            relative = Path('flutter_assets') / path.relative_to(source)
            target = folder / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(path, target)
            entries.append({'path': relative.as_posix(), 'bytes': path.stat().st_size})
        result['packs'][name] = {'bytes': totals[name], 'files': entries}
    (destination / 'staging-manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({name: totals[name] for name in PACKS}))
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    stage(args.source.resolve(), args.destination.resolve())
