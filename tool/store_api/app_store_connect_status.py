#!/usr/bin/env python3
"""Read-only App Store Connect API status check for com.deanbowen.bibleAppMac.

Credentials: expects three values saved at
  ~/.config/studybible2-release-api/asc_key_id.txt      (the Key ID)
  ~/.config/studybible2-release-api/asc_issuer_id.txt    (the Issuer ID)
  ~/.config/studybible2-release-api/asc_private_key.p8   (the downloaded .p8 file)
(never stored in this repo).

Usage:
  ~/.config/studybible2-release-api/venv/bin/python3 tool/store_api/app_store_connect_status.py
"""

from __future__ import annotations

import json
import os
import sys
import time

import jwt
import requests

CONFIG_DIR = os.path.expanduser("~/.config/studybible2-release-api")
KEY_ID_PATH = os.path.join(CONFIG_DIR, "asc_key_id.txt")
ISSUER_ID_PATH = os.path.join(CONFIG_DIR, "asc_issuer_id.txt")
PRIVATE_KEY_PATH = os.path.join(CONFIG_DIR, "asc_private_key.p8")

API_BASE = "https://api.appstoreconnect.apple.com/v1"
APPLE_ID = "6760154157"  # Biblical Heritage #StudyBible


def _read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().strip()


def make_token() -> str:
    key_id = _read(KEY_ID_PATH)
    issuer_id = _read(ISSUER_ID_PATH)
    private_key = _read(PRIVATE_KEY_PATH)

    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }
    headers = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def main() -> int:
    missing = [p for p in (KEY_ID_PATH, ISSUER_ID_PATH, PRIVATE_KEY_PATH) if not os.path.exists(p)]
    if missing:
        print("Missing credential file(s):", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1

    token = make_token()
    headers = {"Authorization": f"Bearer {token}"}

    app_resp = requests.get(f"{API_BASE}/apps/{APPLE_ID}", headers=headers, timeout=30)
    app_resp.raise_for_status()
    print("App info:")
    print(json.dumps(app_resp.json(), indent=2))

    builds_resp = requests.get(
        f"{API_BASE}/builds",
        headers=headers,
        params={"filter[app]": APPLE_ID, "sort": "-uploadedDate", "limit": 10},
        timeout=30,
    )
    builds_resp.raise_for_status()
    print("\nRecent builds:")
    print(json.dumps(builds_resp.json(), indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
