#!/usr/bin/env python3
"""Resumable, hash-deduplicated copy of locally available SDA archive files."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import shutil
import sqlite3
import stat
import sys
from datetime import datetime, timezone
from pathlib import Path


SOURCE_DB = Path("/Users/deanbowen/Documents/SDAArchiveTransfer/manifest.sqlite3")
DEST_ROOT = Path("/Volumes/Sandisk1/SDA-Archive-Staging/SDA-Archive")
CONTROL_ROOT = Path("/Volumes/Sandisk1/SDA-Archive-Staging/_transfer_control")
COPY_DB = CONTROL_ROOT / "sandisk_copy.sqlite3"
COPY_CSV = CONTROL_ROOT / "sandisk_copy_manifest.csv"
MIN_FREE = 50_000_000_000
SF_DATALESS = getattr(stat, "SF_DATALESS", 0x40000000)


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def digest(path: Path, chunk: int = 4 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb", buffering=0) as handle:
        while block := handle.read(chunk):
            h.update(block)
    return h.hexdigest()


def is_local(path: Path) -> bool:
    try:
        current = path.stat()
        return not (current.st_flags & SF_DATALESS) and current.st_blocks > 0
    except OSError:
        return False


def streamed_copy(source: Path, target: Path, chunk: int = 4 * 1024 * 1024) -> None:
    """Avoid copyfile(3), which can stall writing File Provider data to ExFAT."""
    with source.open("rb", buffering=0) as src, target.open("wb", buffering=0) as dst:
        shutil.copyfileobj(src, dst, length=chunk)


def connect_copy_db() -> sqlite3.Connection:
    CONTROL_ROOT.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(COPY_DB)
    db.row_factory = sqlite3.Row
    # The ledger lives on ExFAT. Commit in bounded checkpoints below; per-row
    # FULL/WAL fsyncs make thousands of small verified copies needlessly slow.
    db.execute("PRAGMA journal_mode=DELETE")
    db.execute("PRAGMA synchronous=NORMAL")
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS copies (
          source_id INTEGER PRIMARY KEY,
          source_path TEXT NOT NULL,
          source_rel_path TEXT NOT NULL,
          original_filename TEXT NOT NULL,
          sha256 TEXT NOT NULL,
          size INTEGER NOT NULL,
          canonical_source_id INTEGER NOT NULL,
          destination_rel_path TEXT NOT NULL,
          status TEXT NOT NULL,
          error TEXT,
          verified_at TEXT,
          updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS copies_hash_idx ON copies(sha256);
        CREATE INDEX IF NOT EXISTS copies_status_idx ON copies(status);
        """
    )
    return db


def source_rows() -> list[sqlite3.Row]:
    src = sqlite3.connect(f"file:{SOURCE_DB}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    rows = src.execute(
        """
        SELECT * FROM files
        WHERE classification='definite_sda'
          AND local_state='local'
          AND sha256 IS NOT NULL
        ORDER BY sha256,
          CASE status WHEN 'confirmed_uploaded' THEN 0 WHEN 'copied_to_sync' THEN 1 ELSE 2 END,
          id
        """
    ).fetchall()
    src.close()
    return rows


def safe_rel(row: sqlite3.Row) -> Path:
    rel = Path(row["destination_rel_path"] or row["source_rel_path"])
    if rel.is_absolute() or ".." in rel.parts:
        raise ValueError(f"unsafe destination path: {rel}")
    return rel


def export(db: sqlite3.Connection) -> None:
    fields = [r[1] for r in db.execute("PRAGMA table_info(copies)")]
    tmp = COPY_CSV.with_name(COPY_CSV.name + f".part-{os.getpid()}")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(fields)
        writer.writerows(tuple(r) for r in db.execute("SELECT * FROM copies ORDER BY source_path"))
    os.replace(tmp, COPY_CSV)


def choose_target(rel: Path, expected_hash: str) -> Path:
    target = DEST_ROOT / rel
    if not target.exists():
        return target
    try:
        if digest(target) == expected_hash:
            return target
    except OSError:
        pass
    return target.with_name(f"{target.stem}__{expected_hash[:12]}{target.suffix}")


def run() -> int:
    rows = source_rows()
    db = connect_copy_db()
    canonical: dict[str, sqlite3.Row] = {}
    for row in rows:
        if row["sha256"] not in canonical or (not is_local(Path(canonical[row["sha256"]]["source_path"])) and is_local(Path(row["source_path"]))):
            canonical[row["sha256"]] = row

    verified_files = verified_bytes = mapped_rows = errors = 0
    for index, row in enumerate(rows, 1):
        winner = canonical[row["sha256"]]
        existing = db.execute("SELECT * FROM copies WHERE source_id=?", (row["id"],)).fetchone()
        if existing:
            rel = Path(existing["destination_rel_path"])
        else:
            rel = safe_rel(winner)
            db.execute(
                """
                INSERT INTO copies(source_id,source_path,source_rel_path,original_filename,sha256,size,
                  canonical_source_id,destination_rel_path,status,updated_at)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                """,
                (row["id"], row["source_path"], row["source_rel_path"], Path(row["source_path"]).name,
                 row["sha256"], row["size"], winner["id"], str(rel), "pending", now()),
            )

        target = DEST_ROOT / rel
        if row["id"] != winner["id"]:
            primary = db.execute("SELECT status,destination_rel_path FROM copies WHERE source_id=?", (winner["id"],)).fetchone()
            if primary and primary["status"] in ("verified", "deduplicated"):
                db.execute(
                    "UPDATE copies SET destination_rel_path=?,status='deduplicated',error=NULL,verified_at=?,updated_at=? WHERE source_id=?",
                    (primary["destination_rel_path"], now(), now(), row["id"]),
                )
                mapped_rows += 1
            continue

        try:
            prior = db.execute("SELECT status FROM copies WHERE source_id=?", (row["id"],)).fetchone()
            if prior and prior["status"] == "verified" and target.is_file() and target.stat().st_size == row["size"] and digest(target) == row["sha256"]:
                verified_files += 1
                verified_bytes += row["size"]
                mapped_rows += 1
                continue

            if shutil.disk_usage(DEST_ROOT.parent).free - row["size"] < MIN_FREE:
                db.execute("UPDATE copies SET status='blocked_low_space',error=?,updated_at=? WHERE source_id=?", (f"50 GB reserve would be breached; free={shutil.disk_usage(DEST_ROOT.parent).free}", now(), row["id"]))
                db.commit()
                export(db)
                print("Stopped before breaching the 50 GB Sandisk reserve.", flush=True)
                return 2

            source = Path(row["source_path"])
            if not is_local(source):
                db.execute(
                    "UPDATE copies SET status='source_not_local',error='Skipped without hydration',updated_at=? WHERE source_id=?",
                    (now(), row["id"]),
                )
                continue

            target = choose_target(rel, row["sha256"])
            rel = target.relative_to(DEST_ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                temp = target.with_name(f".{target.name}.part-{os.getpid()}")
                if temp.exists():
                    temp.unlink()
                streamed_copy(source, temp)
                if temp.stat().st_size != row["size"]:
                    raise OSError(f"temporary size mismatch: {temp.stat().st_size} != {row['size']}")
                os.replace(temp, target)
            if target.stat().st_size != row["size"]:
                raise OSError(f"final size mismatch: {target.stat().st_size} != {row['size']}")
            actual = digest(target)
            if actual != row["sha256"]:
                raise OSError(f"final SHA-256 mismatch: {actual} != {row['sha256']}")
            db.execute(
                "UPDATE copies SET destination_rel_path=?,status='verified',error=NULL,verified_at=?,updated_at=? WHERE source_id=?",
                (str(rel), now(), now(), row["id"]),
            )
            verified_files += 1
            verified_bytes += row["size"]
            mapped_rows += 1
        except Exception as exc:
            errors += 1
            db.execute("UPDATE copies SET status='error',error=?,updated_at=? WHERE source_id=?", (repr(exc), now(), row["id"]))

        if index % 100 == 0:
            db.commit()
            export(db)
            print(f"processed={index}/{len(rows)} verified_unique={verified_files} mapped={mapped_rows} errors={errors}", flush=True)

    # A second pass resolves duplicate mappings whose canonical row appeared earlier.
    for row in rows:
        winner = canonical[row["sha256"]]
        if row["id"] == winner["id"]:
            continue
        primary = db.execute("SELECT status,destination_rel_path FROM copies WHERE source_id=?", (winner["id"],)).fetchone()
        if primary and primary["status"] == "verified":
            db.execute(
                "UPDATE copies SET destination_rel_path=?,status='deduplicated',error=NULL,verified_at=?,updated_at=? WHERE source_id=?",
                (primary["destination_rel_path"], now(), now(), row["id"]),
            )
        elif primary and primary["status"] == "source_not_local":
            db.execute(
                "UPDATE copies SET destination_rel_path=?,status='source_not_local',error='Canonical content is cloud-only; skipped without hydration',updated_at=? WHERE source_id=?",
                (primary["destination_rel_path"], now(), row["id"]),
            )
    db.commit()
    export(db)
    stats = db.execute(
        "SELECT status,count(*) n,coalesce(sum(size),0) bytes FROM copies GROUP BY status ORDER BY status"
    ).fetchall()
    print({r["status"]: {"files": r["n"], "bytes": r["bytes"]} for r in stats}, flush=True)
    return 1 if errors else 0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("copy-local",))
    args = parser.parse_args()
    if args.command == "copy-local":
        raise SystemExit(run())


if __name__ == "__main__":
    main()
