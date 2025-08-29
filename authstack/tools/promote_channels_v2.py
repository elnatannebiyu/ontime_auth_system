#!/usr/bin/env python3
"""
Promote v2 channel metadata to replace originals, with backups.
- For each channel dir under authstack/youtube_channels:
  - If metadata.v2.json exists, back up metadata.json to metadata.backup.json (or with numeric suffix),
    then rename metadata.v2.json -> metadata.json
- Leaves originals preserved as backups.
"""
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
CHANNELS_DIR = ROOT / "youtube_channels"


def next_backup_path(p: Path) -> Path:
    base = p.with_name("metadata.backup.json")
    if not base.exists():
        return base
    i = 1
    while True:
        cand = p.with_name(f"metadata.backup.{i}.json")
        if not cand.exists():
            return cand
        i += 1


def promote(dir_path: Path) -> bool:
    v2 = dir_path / "metadata.v2.json"
    orig = dir_path / "metadata.json"
    if not v2.exists():
        return False
    # Backup original if present
    if orig.exists():
        backup = next_backup_path(orig)
        shutil.copy2(orig, backup)
        print(f"Backed up {orig.relative_to(ROOT)} -> {backup.relative_to(ROOT)}")
    # Replace
    shutil.move(str(v2), str(orig))
    print(f"Promoted {orig.relative_to(ROOT)} (from v2)")
    return True


def main() -> int:
    if not CHANNELS_DIR.exists():
        print(f"ERROR: not found {CHANNELS_DIR}")
        return 1
    count = 0
    for sub in sorted(CHANNELS_DIR.iterdir()):
        if not sub.is_dir():
            continue
        if promote(sub):
            count += 1
    print(f"Done. Promoted {count} channels.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
