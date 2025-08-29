#!/usr/bin/env python3
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parents[1]  # authstack/
CHANNELS_DIR = ROOT / "youtube_channels"
SCHEMA_PATH = ROOT / "schemas" / "channel.v1.json"
TENANT = "ontime"
CDN_BASE = os.environ.get("CHANNEL_CDN_BASE", "https://cdn.ontime.example/channels")
IMAGE_MODE = os.environ.get("CHANNEL_IMAGE_MODE", "url")  # "url" or "path"

slug_re = re.compile(r"[^a-z0-9]+")

def slugify(value: str) -> str:
    value = (value or "").strip().lower()
    value = slug_re.sub("-", value)
    value = value.strip("-")
    return value or str(uuid.uuid4())

def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def load_json(path: Path):
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None

def find_logo_filename(dir_path: Path, meta: dict) -> Optional[str]:
    # Prefer explicit metadata image_path
    image_path = meta.get("image_path") or meta.get("original_source", {}).get("image_path")
    if image_path:
        candidate = dir_path / image_path
        if candidate.exists() and candidate.is_file():
            return image_path

    # Common logo filenames
    candidates = [
        "logo.png", "logo.jpg", "logo.jpeg",
        "icon.png", "icon.jpg", "icon.jpeg",
        "Logo.png", "Logo.jpg", "Icon.png", "Icon.jpg"
    ]
    for name in candidates:
        p = dir_path / name
        if p.exists() and p.is_file():
            return name

    # Also check icon/ subfolder
    icon_dir = dir_path / "icon"
    if icon_dir.exists() and icon_dir.is_dir():
        for p in sorted(icon_dir.iterdir()):
            if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".svg"}:
                return f"icon/{p.name}"

    # Fallback: first image in folder
    for p in sorted(dir_path.iterdir()):
        if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".svg"}:
            return p.name
    return None

def build_sources(meta: dict) -> list:
    sources = []
    # Try to derive satellite info if numeric fields exist
    freq = meta.get("frequency_mhz") or meta.get("original_source", {}).get("frequency_mhz")
    srate = meta.get("symbol_rate_ksps") or meta.get("original_source", {}).get("symbol_rate_ksps")
    pol = meta.get("polarization") or meta.get("original_source", {}).get("polarization")
    discovered = meta.get("created_at") or meta.get("original_source", {}).get("created_at")

    if isinstance(freq, (int, float)) and isinstance(srate, (int, float)) and isinstance(pol, str):
        sources.append({
            "id": f"src_sat_{datetime.fromisoformat(discovered.replace('Z','+00:00')).strftime('%Y%m%d') if isinstance(discovered, str) else 'auto'}",
            "type": "satellite",
            "name": "NileSat",
            "frequency_mhz": float(freq),
            "symbol_rate_ksps": float(srate),
            "polarization": pol,
            "status": "observed",
            "confidence": 0.9,
            "discovered_at": discovered if isinstance(discovered, str) else None
        })

    # Always add a manual record to indicate export provenance
    sources.append({
        "id": f"src_manual_{datetime.now(timezone.utc).strftime('%Y%m%d')}",
        "type": "manual",
        "note": "Exported from v2 metadata by export_channels_v1.py",
        "status": "current",
        "confidence": 0.7,
        "discovered_at": now_iso()
    })
    return sources


def export_one(dir_path: Path) -> Optional[Path]:
    meta_path = dir_path / "metadata.json"
    meta = load_json(meta_path)
    if not meta:
        return None

    name_am = meta.get("name_am") or meta.get("name") or dir_path.name
    name_en = meta.get("name_en") or dir_path.name

    # id: slug of English name
    chan_id = slugify(name_en)

    images = []
    logo_name = find_logo_filename(dir_path, meta)
    if logo_name:
        img_obj = {"kind": "logo", "source": "folder"}
        if IMAGE_MODE == "path":
            img_obj["path"] = logo_name
        else:
            img_obj["url"] = f"{CDN_BASE}/{chan_id}/{logo_name}"
        images.append(img_obj)

    doc = {
        "schema": "channel.v1",
        "uid": str(uuid.uuid4()),
        "id": chan_id,
        "tenant": TENANT,
        "display": {
            "default_locale": "am",
            "name": {
                **({"am": name_am} if name_am else {}),
                **({"en": name_en} if name_en else {}),
            },
            "aliases": []
        },
        "images": images,
        "categorization": {
            "genres": ["general"],
            "language": "am",
            "country": "ET",
            "tags": []
        },
        "availability": {
            "is_active": True,
            "regions_allow": ["ET"],
            "regions_deny": [],
            "platforms": ["mobile", "web"],
            "drm_required": False
        },
        "lineup": {
            "sort_order": 100,
            "featured": False
        },
        "sources": build_sources(meta),
        "rights": {
            "start_at": None,
            "end_at": None,
            "notes": None
        },
        "audit": {
            "created_at": now_iso(),
            "updated_at": now_iso(),
            "last_verified_at": None
        }
    }

    out_path = dir_path / "channel.v1.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
    return out_path


def main():
    count = 0
    for child in sorted(CHANNELS_DIR.iterdir()):
        if child.is_dir():
            out = export_one(child)
            if out:
                count += 1
                print(f"Wrote {out.relative_to(CHANNELS_DIR)}")
    print(f"Done. Exported {count} channel.v1 files.")


if __name__ == "__main__":
    main()
