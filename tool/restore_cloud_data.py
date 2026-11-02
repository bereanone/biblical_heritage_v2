#!/usr/bin/env python3
"""Restore ignored StudyBible build data from verified private Drive archives."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import zipfile


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def target_path(root: Path, relative: str) -> Path:
    path = Path(relative)
    if path.is_absolute() or not path.parts or '..' in path.parts:
        raise ValueError(f'Unsafe data path: {relative}')
    destination = root / path
    if not destination.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Data path leaves the checkout: {relative}')
    for parent in [destination, *destination.parents]:
        if parent == root.parent:
            break
        if parent.is_symlink():
            raise ValueError(f'Restore requires a regular local path: {relative}')
    return destination


def restore(manifest: dict, root: Path, archives: Path | None, verify_only: bool = False) -> dict:
    root = root.resolve()
    if manifest.get('schema') != 1:
        raise ValueError('Unsupported data manifest schema')
    files = manifest['files']
    if len({entry['path'] for entry in files}) != len(files):
        raise ValueError('Duplicate destination paths in data manifest')
    missing = []
    modified = []
    matched = 0
    for entry in files:
        destination = target_path(root, entry['path'])
        if not destination.exists():
            missing.append(entry)
        elif not destination.is_file() or destination.stat().st_size != entry['bytes'] or digest(destination) != entry['sha256']:
            modified.append(entry['path'])
        else:
            matched += 1
    if modified:
        raise ValueError('Existing files differ; preserve or relocate them before restoring: ' + ', '.join(modified[:10]))
    if verify_only:
        if missing:
            raise ValueError(f'{len(missing)} required data files are missing')
        return {'verified': matched, 'restored': 0}
    if not missing:
        return {'verified': matched, 'restored': 0}
    if archives is None:
        raise ValueError('Download the numbered archives from the manifest Drive folder and pass --archives')
    needed = {entry['archive'] for entry in missing}
    archive_specs = {entry['name']: entry for entry in manifest['archives']}
    # Verify every required archive before creating any destination files.
    for name in sorted(needed):
        spec = archive_specs[name]
        archive = archives / name
        if archive.stat().st_size != spec['bytes'] or digest(archive) != spec['sha256']:
            raise ValueError(f'Archive checksum mismatch: {name}')
    restored = 0
    for name in sorted(needed):
        with zipfile.ZipFile(archives / name) as zipped:
            for entry in (item for item in missing if item['archive'] == name):
                destination = target_path(root, entry['path'])
                member = 'objects/' + entry['sha256']
                if zipped.getinfo(member).file_size != entry['bytes']:
                    raise ValueError(f'Wrong object size: {entry["path"]}')
                destination.parent.mkdir(parents=True, exist_ok=True)
                temporary = None
                try:
                    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix='.restore-', delete=False) as output:
                        temporary = Path(output.name)
                        checksum = hashlib.sha256()
                        with zipped.open(member) as source:
                            for chunk in iter(lambda: source.read(1024 * 1024), b''):
                                checksum.update(chunk)
                                output.write(chunk)
                    if checksum.hexdigest() != entry['sha256']:
                        raise ValueError(f'Object checksum mismatch: {entry["path"]}')
                    temporary.chmod(entry.get('mode', 0o644))
                    # Create without overwriting a file another process made meanwhile.
                    os.link(temporary, destination)
                    restored += 1
                finally:
                    if temporary is not None:
                        temporary.unlink(missing_ok=True)
    return {'verified': matched, 'restored': restored}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    checkout = Path(__file__).resolve().parents[1]
    parser.add_argument('--manifest', type=Path, default=checkout / 'data/cloud-data-20261102.json')
    parser.add_argument('--root', type=Path, default=checkout)
    parser.add_argument('--archives', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(restore(json.loads(args.manifest.read_text()), args.root, args.archives, args.verify_only)))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
