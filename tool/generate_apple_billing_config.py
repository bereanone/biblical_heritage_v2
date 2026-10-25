#!/usr/bin/env python3
"""Give native Watch startup the same billing switch as Dart, without other defines."""
import base64
import os
from pathlib import Path
import plistlib
import sys


def billing_enabled(encoded_defines):
    values = {}
    for encoded in filter(None, encoded_defines.split(',')):
        decoded = base64.b64decode(encoded, validate=True).decode('utf-8')
        key, separator, value = decoded.partition('=')
        if separator:
            values[key] = value
    # bool.fromEnvironment accepts only the exact true literal here.
    return values.get('STUDYBIBLE_APPLE_BILLING') == 'true'


def generate(destination, encoded_defines):
    data = plistlib.dumps({'enabled': billing_enabled(encoded_defines)})
    path = Path(destination)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


if __name__ == '__main__':
    generate(sys.argv[1], os.environ.get('DART_DEFINES', ''))
