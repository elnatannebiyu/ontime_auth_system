#!/usr/bin/env python3
import json
import os
import uuid
from pathlib import Path
from typing import List, Dict, Any

ROOT = Path(__file__).resolve().parents[1]
CHANNELS_DIR = ROOT / "youtube_channels"
SEED_DIR = ROOT / "seed"
SEED_DIR.mkdir(exist_ok=True)
SEED_FILE = SEED_DIR / "channels.v1.seed.json"

UID_MODE = os.environ.get("CHANNEL_UID_MODE", "stable")  # stable|random


def load(p: Path) -> Dict[str, Any]:
    with p.open("r", encoding="utf-8") as f:
        return json.load(f)


def stable_uuid(tenant: str, chan_id: str) -> str:
    ns = uuid.uuid5(uuid.NAMESPACE_URL, f"https://ontime/{tenant}")
    return str(uuid.uuid5(ns, chan_id))


def main():
    items: List[Dict[str, Any]] = []
    for d in sorted(CHANNELS_DIR.iterdir()):
        if not d.is_dir():
            continue
        f = d / "channel.v1.json"
        if not f.exists():
            continue
        data = load(f)
        # ensure required keys
        tenant = data.get("tenant", "ontime")
        chan_id = data.get("id")
        if not chan_id:
            continue
        if UID_MODE == "stable":
            data["uid"] = stable_uuid(tenant, chan_id)
        # normalize images to ensure path or url only
        imgs = data.get("images") or []
        data["images"] = [img for img in imgs if isinstance(img, dict) and ("path" in img or "url" in img)]
        items.append(data)

    with SEED_FILE.open("w", encoding="utf-8") as f:
        json.dump({"schema": "channels.seed.v1", "count": len(items), "items": items}, f, ensure_ascii=False, indent=2)
    print(f"Wrote seed: {SEED_FILE.relative_to(ROOT)} with {len(items)} items")


if __name__ == "__main__":
    main()
