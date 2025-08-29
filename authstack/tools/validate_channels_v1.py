#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
from typing import List, Tuple

ROOT = Path(__file__).resolve().parents[1]
CHANNELS_DIR = ROOT / "youtube_channels"
SCHEMA_FILE = ROOT / "schemas" / "channel.v1.json"

REQUIRED_TOP = ["schema", "uid", "id", "tenant", "display", "availability"]


def load_json(p: Path):
    with p.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_images(images) -> List[str]:
    errs: List[str] = []
    if not isinstance(images, list):
        return ["images must be an array"]
    for i, img in enumerate(images):
        if not isinstance(img, dict):
            errs.append(f"images[{i}] must be an object")
            continue
        if img.get("kind") not in {"logo", "poster", "banner"}:
            errs.append(f"images[{i}].kind missing or invalid")
        has_url = "url" in img and isinstance(img.get("url"), str)
        has_path = "path" in img and isinstance(img.get("path"), str)
        if not (has_url or has_path):
            errs.append(f"images[{i}] must include either url or path")
    return errs


def validate_one(p: Path) -> Tuple[bool, List[str]]:
    try:
        data = load_json(p)
    except Exception as e:
        return False, [f"invalid json: {e}"]

    errs: List[str] = []
    # top-level required
    for k in REQUIRED_TOP:
        if k not in data:
            errs.append(f"missing required field: {k}")
    if data.get("schema") != "channel.v1":
        errs.append("schema must be 'channel.v1'")

    # display
    disp = data.get("display", {})
    if not isinstance(disp, dict):
        errs.append("display must be object")
    else:
        if disp.get("default_locale") not in {"am", "en"}:
            errs.append("display.default_locale must be 'am' or 'en'")
        name = disp.get("name", {})
        if not isinstance(name, dict) or not name:
            errs.append("display.name must be a non-empty object")

    # images
    images = data.get("images", [])
    errs.extend(validate_images(images))

    # availability
    avail = data.get("availability", {})
    if not isinstance(avail, dict) or "is_active" not in avail:
        errs.append("availability.is_active is required")

    return (len(errs) == 0), errs


def main():
    total = 0
    bad = 0
    for d in sorted(CHANNELS_DIR.iterdir()):
        if not d.is_dir():
            continue
        f = d / "channel.v1.json"
        if not f.exists():
            continue
        total += 1
        ok, errs = validate_one(f)
        if not ok:
            bad += 1
            print(f"INVALID {f.relative_to(CHANNELS_DIR)}")
            for e in errs:
                print(f"  - {e}")
    if bad == 0:
        print(f"All {total} channel.v1 files valid.")
    else:
        print(f"{bad}/{total} files invalid.")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
