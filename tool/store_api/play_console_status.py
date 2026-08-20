#!/usr/bin/env python3
"""Read-only Google Play Developer API status check for com.deanbowen.bibleappmac.

Credentials: expects a service-account JSON key at
  ~/.config/studybible2-release-api/play-service-account.json
(never stored in this repo).

Usage:
  ~/.config/studybible2-release-api/venv/bin/python3 tool/store_api/play_console_status.py
"""

from __future__ import annotations

import json
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build

PACKAGE_NAME = "com.deanbowen.bibleappmac"
CREDENTIALS_PATH = os.path.expanduser(
    "~/.config/studybible2-release-api/play-service-account.json"
)
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main() -> int:
    if not os.path.exists(CREDENTIALS_PATH):
        print(f"Missing credentials file: {CREDENTIALS_PATH}", file=sys.stderr)
        print(
            "Download the service-account JSON key from Google Cloud Console "
            "and place it at that path.",
            file=sys.stderr,
        )
        return 1

    credentials = service_account.Credentials.from_service_account_file(
        CREDENTIALS_PATH, scopes=SCOPES
    )
    service = build("androidpublisher", "v3", credentials=credentials)

    edit_request = service.edits().insert(body={}, packageName=PACKAGE_NAME)
    edit = edit_request.execute()
    edit_id = edit["id"]

    try:
        tracks = (
            service.edits()
            .tracks()
            .list(packageName=PACKAGE_NAME, editId=edit_id)
            .execute()
        )
        print(json.dumps(tracks, indent=2))
    finally:
        service.edits().delete(packageName=PACKAGE_NAME, editId=edit_id).execute()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
