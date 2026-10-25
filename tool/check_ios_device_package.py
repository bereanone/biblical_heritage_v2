#!/usr/bin/env python3
"""Fail before device install if native assets target a simulator or aren't signed.

Read-only check. Run after a physical iOS build and before installation/upload.
"""
from pathlib import Path
import argparse
import plistlib
import subprocess


def check(app: Path, expected_build: str | None = None, expected_billing: bool | None = None) -> None:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    build = str(info['CFBundleVersion'])
    if expected_build is not None and build != expected_build:
        raise RuntimeError(f'Expected build {expected_build}, found {build}')
    config = plistlib.loads((app / 'StudyBibleBilling.plist').read_bytes())
    enabled = config.get('enabled')
    if type(enabled) is not bool:
        raise RuntimeError('Native Watch billing configuration is missing or invalid')
    if expected_billing is not None and enabled != expected_billing:
        raise RuntimeError(f'Native Watch billing flag mismatch: {enabled}')
    for framework in sorted((app / 'Frameworks').glob('*.framework')):
        binary = framework / framework.stem
        if not binary.is_file():
            raise RuntimeError(f'Missing framework executable: {framework.name}')
        platform = subprocess.check_output(
            ['xcrun', 'vtool', '-show-build', str(binary)], text=True)
        if 'platform IOS\n' not in platform or 'IOSSIMULATOR' in platform:
            raise RuntimeError(f'{framework.name} does not target physical iOS')
        signature = subprocess.run(
            ['codesign', '-dv', '--verbose=4', str(framework)],
            check=True, capture_output=True, text=True).stderr
        if 'Signature=adhoc' in signature or 'TeamIdentifier=not set' in signature:
            raise RuntimeError(f'{framework.name} lacks a device-install signing identity')
    for child in [*app.glob('Watch/*.app/Info.plist'), *app.glob('Watch/*.app/PlugIns/*.appex/Info.plist')]:
        companion = plistlib.loads(child.read_bytes())
        if str(companion['CFBundleVersion']) != build or companion['CFBundleShortVersionString'] != info['CFBundleShortVersionString']:
            raise RuntimeError(f'Companion version mismatch: {child.parent.name}')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(f'Physical iOS package and companion signatures verified: {info["CFBundleShortVersionString"]}+{build}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--build')
    parser.add_argument('--apple-billing', choices=['on', 'off'])
    args = parser.parse_args()
    expected_billing = None if args.apple_billing is None else args.apple_billing == 'on'
    check(args.app, args.build, expected_billing)
