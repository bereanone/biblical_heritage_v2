"""Derive Android-playable AAC copies of the checked Qwen announcement cues.

The iPhone's lossless cue files and the original Qwen voice prompt are read only.
Existing Android outputs must match the generated manifest; this never silently
replaces a different clip.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/audio/qwen_loop_cues"
DEST = ROOT / "assets/audio/qwen_loop_cues_android"
FFMPEG = Path("/opt/homebrew/bin/ffmpeg")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    source_manifest = json.loads((SOURCE / "manifest.json").read_text())
    assert len(source_manifest["cues"]) == 392
    assert FFMPEG.is_file()
    DEST.mkdir(parents=True, exist_ok=True)
    records = []
    for index, source_row in enumerate(source_manifest["cues"], 1):
        name = source_row["name"]
        source = SOURCE / f"{name}.m4a"
        if sha(source) != source_row["audio_sha256"]:
            raise ValueError(f"Source checksum mismatch: {name}")
        output = DEST / f"{name}.m4a"
        if not output.exists():
            temporary = DEST / f"{name}.part.m4a"
            subprocess.run(
                [str(FFMPEG), "-nostdin", "-v", "error", "-y", "-i", str(source),
                 "-c:a", "aac", "-b:a", "80k", "-ac", "1", str(temporary)],
                check=True,
            )
            subprocess.run(
                [str(FFMPEG), "-nostdin", "-v", "error", "-i", str(temporary),
                 "-f", "null", "-"],
                check=True,
            )
            temporary.replace(output)
        row = dict(source_row)
        row["normalized_source_sha256"] = source_row["audio_sha256"]
        row["audio_sha256"] = sha(output)
        row["codec"] = "AAC"
        records.append(row)
        if index % 100 == 0:
            print(f"{index}/392 Android cues checked", flush=True)
    manifest = {
        "voice_prompt_sha256": source_manifest["voice_prompt_sha256"],
        "normalization": source_manifest["normalization"],
        "derived_from_manifest_sha256": sha(SOURCE / "manifest.json"),
        "cues": records,
    }
    manifest_path = DEST / "manifest.json"
    if manifest_path.exists() and json.loads(manifest_path.read_text()) != manifest:
        raise ValueError("Existing Android cue manifest differs")
    temporary = DEST / "manifest.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2) + "\n")
    temporary.replace(manifest_path)
    print("392/392 Android cues ready", flush=True)


if __name__ == "__main__":
    main()
