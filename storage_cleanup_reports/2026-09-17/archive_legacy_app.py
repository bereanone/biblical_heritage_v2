#!/usr/bin/env python3
import hashlib
import json
import os
import shutil
import tarfile
import time
import uuid
from pathlib import Path

SOURCE = Path("/Users/deanbowen/Development/bible_app_mac")
RESOLVED_GIT = Path("/Users/deanbowen/Sandisks/512/bible_app_mac/.git")
REPORT_DIR = Path("/Users/deanbowen/Development/StudyBible2/storage_cleanup_reports/2026-09-17")
DEST_DIR = Path("/Volumes/Sandisk1/Archives")
ARCHIVE_NAME = "bible_app_mac_legacy_2026-09-17.tar"
MANIFEST_NAME = "bible_app_mac_legacy_2026-09-17.manifest.jsonl"
SUMMARY_NAME = "bible_app_mac_legacy_2026-09-17.summary.json"
EXCLUDED_DIR_NAMES = {"build", ".dart_tool", ".swift-tmp", "__pycache__", "ephemeral", ".symlinks"}
EXCLUDED_FILE_NAMES = {".DS_Store"}
MIN_INTERNAL_FREE = 10_000_000_000
BUFFER_SIZE = 8 * 1024 * 1024


def hash_stream(handle) -> str:
    digest = hashlib.sha256()
    while True:
        block = handle.read(BUFFER_SIZE)
        if not block:
            break
        digest.update(block)
    return digest.hexdigest()


def hash_file(path: Path) -> str:
    with path.open("rb") as handle:
        return hash_stream(handle)


def check_internal_space() -> int:
    free = shutil.disk_usage("/").free
    if free < MIN_INTERNAL_FREE:
        raise RuntimeError(f"internal free space below 10 GB: {free}")
    return free


def collect_tree(root: Path, archive_prefix: Path, source_kind: str, skip_root_git: bool):
    records = []

    def visit(path: Path, relative: Path):
        if relative.parts:
            if any(part in EXCLUDED_DIR_NAMES for part in relative.parts):
                return
            if path.name in EXCLUDED_FILE_NAMES:
                return
            if skip_root_git and relative == Path(".git"):
                return
        archive_path = archive_prefix / relative
        metadata = path.lstat()
        if path.is_symlink():
            records.append({
                "archive_path": archive_path.as_posix(),
                "source_path": str(path),
                "source_kind": source_kind,
                "type": "symlink",
                "link_target": os.readlink(path),
                "size": 0,
            })
            return
        if path.is_dir():
            records.append({
                "archive_path": archive_path.as_posix(),
                "source_path": str(path),
                "source_kind": source_kind,
                "type": "directory",
                "size": 0,
            })
            for child in sorted(path.iterdir(), key=lambda p: p.name):
                visit(child, relative / child.name)
            return
        if path.is_file():
            check_internal_space()
            records.append({
                "archive_path": archive_path.as_posix(),
                "source_path": str(path),
                "source_kind": source_kind,
                "type": "file",
                "size": metadata.st_size,
                "sha256": hash_file(path),
            })

    visit(root, Path(""))
    return records


def write_json_atomic(path: Path, data) -> None:
    temp = path.with_name(path.name + f".tmp-{uuid.uuid4().hex}")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temp, path)


def copy_verified(source: Path, destination: Path) -> str:
    if destination.exists():
        raise RuntimeError(f"destination conflict: {destination}")
    temp = destination.with_name(destination.name + f".tmp-{uuid.uuid4().hex}")
    try:
        with source.open("rb") as src, temp.open("xb") as dst:
            shutil.copyfileobj(src, dst, BUFFER_SIZE)
            dst.flush()
            os.fsync(dst.fileno())
        source_hash = hash_file(source)
        temp_hash = hash_file(temp)
        if source_hash != temp_hash:
            raise RuntimeError(f"copy verification failed for {destination}")
        os.rename(temp, destination)
        return source_hash
    finally:
        if temp.exists():
            temp.unlink()


def main():
    started = time.time()
    if not SOURCE.is_dir() or not RESOLVED_GIT.is_dir():
        raise RuntimeError("source or resolved Git directory unavailable")
    if SOURCE.joinpath(".git").resolve() != RESOLVED_GIT.resolve():
        raise RuntimeError("resolved Git directory no longer matches source symlink")
    check_internal_space()
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    archive_final = DEST_DIR / ARCHIVE_NAME
    manifest_external = DEST_DIR / MANIFEST_NAME
    summary_external = DEST_DIR / SUMMARY_NAME
    for destination in (archive_final, manifest_external, summary_external):
        if destination.exists():
            raise RuntimeError(f"destination conflict; refusing overwrite: {destination}")

    working_records = collect_tree(SOURCE, Path("bible_app_mac"), "working_tree", True)
    git_records = collect_tree(RESOLVED_GIT, Path("bible_app_mac/.git"), "resolved_git", False)
    records = working_records + git_records
    records.sort(key=lambda item: item["archive_path"])
    regular_records = [item for item in records if item["type"] == "file"]
    expected = {item["archive_path"]: item for item in records}
    logical_bytes = sum(item["size"] for item in regular_records)
    external_free = shutil.disk_usage(DEST_DIR).free
    if external_free < logical_bytes + 2_000_000_000:
        raise RuntimeError(
            f"insufficient Sandisk free space: need reserve over {logical_bytes}, have {external_free}"
        )

    manifest_local = REPORT_DIR / MANIFEST_NAME
    manifest_temp = manifest_local.with_name(manifest_local.name + f".tmp-{uuid.uuid4().hex}")
    with manifest_temp.open("w", encoding="utf-8") as handle:
        for record in records:
            public_record = {k: v for k, v in record.items() if k != "source_path"}
            handle.write(json.dumps(public_record, sort_keys=True) + "\n")
    os.replace(manifest_temp, manifest_local)

    archive_temp = archive_final.with_name(archive_final.name + f".tmp-{uuid.uuid4().hex}")
    try:
        with tarfile.open(archive_temp, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for index, record in enumerate(records, start=1):
                check_internal_space()
                source_path = Path(record["source_path"])
                info = archive.gettarinfo(str(source_path), arcname=record["archive_path"])
                if record["type"] == "file":
                    with source_path.open("rb") as handle:
                        archive.addfile(info, handle)
                else:
                    archive.addfile(info)
                if index % 500 == 0:
                    print(json.dumps({"event": "archive_progress", "processed": index, "total": len(records)}), flush=True)
        seen = set()
        with tarfile.open(archive_temp, mode="r") as archive:
            members = archive.getmembers()
            for index, member in enumerate(members, start=1):
                record = expected.get(member.name)
                if record is None:
                    raise RuntimeError(f"unexpected archive member: {member.name}")
                seen.add(member.name)
                if record["type"] == "file":
                    if member.size != record["size"]:
                        raise RuntimeError(f"size mismatch in archive: {member.name}")
                    extracted = archive.extractfile(member)
                    if extracted is None or hash_stream(extracted) != record["sha256"]:
                        raise RuntimeError(f"hash mismatch in archive: {member.name}")
                elif record["type"] == "symlink":
                    if not member.issym() or member.linkname != record["link_target"]:
                        raise RuntimeError(f"symlink mismatch in archive: {member.name}")
                elif not member.isdir():
                    raise RuntimeError(f"type mismatch in archive: {member.name}")
                if index % 500 == 0:
                    print(json.dumps({"event": "verify_progress", "processed": index, "total": len(members)}), flush=True)
        missing = sorted(set(expected) - seen)
        if missing:
            raise RuntimeError(f"archive missing {len(missing)} expected members")

        archive_hash = hash_file(archive_temp)
        os.rename(archive_temp, archive_final)
        manifest_hash = copy_verified(manifest_local, manifest_external)
        summary = {
            "archive": str(archive_final),
            "archive_bytes": archive_final.stat().st_size,
            "archive_sha256": archive_hash,
            "manifest": str(manifest_external),
            "manifest_sha256": manifest_hash,
            "source_working_tree": str(SOURCE),
            "resolved_git_source": str(RESOLVED_GIT),
            "regular_files": len(regular_records),
            "directories_and_links": len(records) - len(regular_records),
            "logical_source_bytes": logical_bytes,
            "excluded_directory_names": sorted(EXCLUDED_DIR_NAMES),
            "excluded_file_names": sorted(EXCLUDED_FILE_NAMES),
            "verification": "every regular archive member matched manifest size and SHA-256; paths and symlinks matched",
            "elapsed_seconds": round(time.time() - started, 1),
            "internal_free_final": shutil.disk_usage("/").free,
            "sandisk_free_final": shutil.disk_usage(DEST_DIR).free,
        }
        summary_local = REPORT_DIR / SUMMARY_NAME
        write_json_atomic(summary_local, summary)
        summary_hash = copy_verified(summary_local, summary_external)
        summary["summary_sha256"] = summary_hash
        print(json.dumps({"event": "result", **summary}, sort_keys=True), flush=True)
    finally:
        if archive_temp.exists():
            archive_temp.unlink()


if __name__ == "__main__":
    main()
