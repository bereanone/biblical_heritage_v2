#!/usr/bin/env python3
"""Read-only guard against a release Flutter engine with debug Dart assets."""
import argparse
from pathlib import Path
import zipfile


def check(apk: Path) -> None:
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        if 'assets/flutter_assets/kernel_blob.bin' in names:
            raise RuntimeError('Release package contains a debug kernel')
        engines = [n for n in names if n.startswith('lib/') and n.endswith('/libflutter.so')]
        if not engines:
            raise RuntimeError('Flutter engine library missing')
        for engine in engines:
            application = engine.removesuffix('libflutter.so') + 'libapp.so'
            if application not in names:
                raise RuntimeError(f'Precompiled app library missing beside {engine}')
            with archive.open(application) as binary:
                if binary.read(4) != b'\x7fELF':
                    raise RuntimeError(f'Invalid precompiled app library: {application}')
    print('Android release snapshot/engine packaging verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    check(parser.parse_args().apk)
