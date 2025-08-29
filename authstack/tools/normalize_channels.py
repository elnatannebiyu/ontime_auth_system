#!/usr/bin/env python3
"""
Normalize channel metadata files to v2 format.
- Reads: authstack/youtube_channels/*/metadata.json
- Writes: authstack/youtube_channels/*/metadata.v2.json (non-destructive)

v2 schema is defined in authstack/youtube_channels/schema.json
"""
import json
import copy
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

ROOT = Path(__file__).resolve().parents[1]
CHANNELS_DIR = ROOT / "youtube_channels"
SCHEMA_PATH = CHANNELS_DIR / "schema.json"
OVERRIDES_PATH = CHANNELS_DIR / "name_overrides.json"

# Heuristics for source and satellite parsing
SATELLITE_HINTS = [
    "ethiosat", "nss12", "nss 12", "lyngsat", "dvbs", "dvb-s", "dvb-s2",
    "symbol rate", "polarization", "horizontal", "vertical", "hz", "mhz",
    "al yah", "yah", "orbital", "ku band", "c band", "ka band", "57.0",
]

POL_MAP = {
    "horizontal": "H",
    "vertical": "V",
    "h": "H",
    "v": "V",
}

BAND_HINTS = {
    "ku": "Ku",
    "c band": "C",
    "ka": "Ka",
    "s/ka": "S",
}


def read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"WARN: Failed to read {path}: {e}")
        return None


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def has_ethiopic(text: Optional[str]) -> bool:
    if not text:
        return False
    return any(0x1200 <= ord(ch) <= 0x137F for ch in text)


def has_latin(text: Optional[str]) -> bool:
    if not text:
        return False
    return any('A' <= ch <= 'Z' or 'a' <= ch <= 'z' for ch in text)


def iso(dt: Optional[str]) -> Optional[str]:
    if not dt:
        return None
    try:
        # Pass-through if already iso
        if re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.*Z$", dt):
            return dt
        # Attempt parse common forms
        return datetime.fromisoformat(dt.replace("Z", "+00:00")).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return None


def parse_numeric(text: str) -> Optional[float]:
    if not text:
        return None
    nums = re.findall(r"\d+(?:\.\d+)?", text)
    if not nums:
        return None
    try:
        return float(nums[0])
    except Exception:
        return None


def infer_source(freq_value: Optional[str]) -> str:
    if not freq_value:
        return "other"
    val = freq_value.strip().lower()
    if val in {"youtube", "yt"}:
        return "youtube"
    if val in {"dstv", "dStv".lower()}:
        return "dstv"
    if any(h in val for h in SATELLITE_HINTS):
        return "satellite"
    # Pure number likely satellite frequency
    if re.fullmatch(r"\d+", val):
        return "satellite"
    return "other"


def parse_satellite_fields(text: Optional[str]) -> Dict[str, Any]:
    if not text:
        return {}
    lower = text.lower()
    fields: Dict[str, Any] = {}
    # Frequency MHz
    mhz = None
    # Try MHz mentioned explicitly
    m = re.search(r"(\d{4,6})\s*mhz", lower)
    if m:
        mhz = float(m.group(1))
    else:
        # Fall back: first 4-6 digit number
        n = re.search(r"\b(\d{4,6})\b", lower)
        if n:
            mhz = float(n.group(1))
    if mhz:
        fields["frequency_mhz"] = mhz
    # Symbol rate ksps
    m = re.search(r"symbol\s*rate\s*[:\-]?\s*(\d{4,6})", lower)
    if m:
        fields["symbol_rate_ksps"] = float(m.group(1))
    else:
        # Sometimes given as 45000 without label
        nums = re.findall(r"\b(\d{5})\b", lower)
        if nums:
            try:
                val = float(nums[0])
                if 1000 <= val <= 60000:
                    fields["symbol_rate_ksps"] = val
            except Exception:
                pass
    # Polarization
    for key, mapped in POL_MAP.items():
        if key in lower:
            fields["polarization"] = mapped
            break
    # Band
    for key, mapped in BAND_HINTS.items():
        if key in lower:
            fields["band"] = mapped
            break
    # Satellite / orbital position
    sat_match = re.search(r"(nss\s*12|ethiosat|al\s*yah\s*1)", lower)
    if sat_match:
        fields["satellite"] = sat_match.group(1).upper().replace(" ", " ")
    orb_match = re.search(r"(\d{1,3}\.\d+°[e|w])", text, re.IGNORECASE)
    if orb_match:
        fields["orbital_position"] = orb_match.group(1)
    # Standard
    std_match = re.search(r"(dvb\-s2|dvb\-s)", lower)
    if std_match:
        fields["standard"] = std_match.group(1).upper()
    return fields


def normalize_one(dir_path: Path, overrides: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
    meta_path = dir_path / "metadata.json"
    icon_path = dir_path / "icon.jpg"
    data = read_json(meta_path)
    if not data:
        return None

    raw = data.get("raw", {}) or {}
    channel_name = data.get("channel_name") or raw.get("channel_name", {}).get("stringValue") or dir_path.name
    # Optional Amharic name (Ethiopic block)
    name_am: Optional[str] = None
    # Prefer Ethiopic from raw, otherwise from directory name
    raw_name = raw.get("channel_name", {}).get("stringValue")
    if has_ethiopic(raw_name):
        name_am = raw_name
    elif has_ethiopic(dir_path.name):
        name_am = dir_path.name
    # Optional English/Latin name
    name_en: Optional[str] = None
    if has_latin(channel_name):
        name_en = channel_name
    elif has_latin(dir_path.name):
        name_en = dir_path.name
    image_url_raw = raw.get("image", {}).get("stringValue")
    created = raw.get("createdAt", {}).get("timestampValue")
    updated = raw.get("updatedAt", {}).get("timestampValue")
    fid = raw.get("id", {}).get("integerValue") or dir_path.name
    freq = raw.get("frequency", {}).get("stringValue")

    v2: Dict[str, Any] = {
        "id": str(fid),
        "name": str(channel_name),
        "source": infer_source(freq),
        "created_at": iso(created) or created or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "updated_at": iso(updated) or created or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }

    if name_am:
        v2["name_am"] = name_am
    if name_en:
        v2["name_en"] = name_en

    # Apply name overrides if present for this folder
    key = dir_path.name
    if overrides and key in overrides and isinstance(overrides[key], dict):
        o = overrides[key]
        if o.get("name"):
            v2["name"] = str(o["name"])
        if o.get("name_en"):
            v2["name_en"] = str(o["name_en"])
        if o.get("name_am"):
            v2["name_am"] = str(o["name_am"])

    # Prefer local icon if exists
    if icon_path.exists():
        v2["image_path"] = "icon.jpg"
        v2["image_url"] = None
    else:
        v2["image_url"] = image_url_raw if image_url_raw and image_url_raw.startswith("http") else None

    # Satellite details if applicable
    if v2["source"] in ("satellite", "dstv"):
        sat_fields = parse_satellite_fields(freq or "")
        v2.update(sat_fields)
    
    # Preserve original but sanitize misleading Firebase image fields
    san = copy.deepcopy(data)

    def scrub_images(obj):
        # Remove any key named 'image' if it's a string URL, and remove raw.image objects
        if isinstance(obj, dict):
            # Remove 'image' string URLs
            if "image" in obj:
                val = obj.get("image")
                if isinstance(val, str) and val.startswith("http"):
                    obj.pop("image", None)
                elif isinstance(val, dict):
                    # raw.image like { stringValue: "..." }
                    obj.pop("image", None)
            # Recurse into remaining keys
            for k in list(obj.keys()):
                scrub_images(obj[k])
        elif isinstance(obj, list):
            for it in obj:
                scrub_images(it)

    scrub_images(san)
    v2["original_source"] = san

    return v2


def main() -> int:
    if not CHANNELS_DIR.exists():
        print(f"ERROR: Channels dir not found: {CHANNELS_DIR}")
        return 1

    # Load overrides if present
    overrides: Optional[Dict[str, Any]] = None
    if OVERRIDES_PATH.exists():
        try:
            with OVERRIDES_PATH.open("r", encoding="utf-8") as f:
                overrides = json.load(f)
            print(f"Loaded overrides from {OVERRIDES_PATH.relative_to(ROOT)}")
        except Exception as e:
            print(f"WARN: Failed to load overrides: {e}")

    count = 0
    for sub in sorted(CHANNELS_DIR.iterdir()):
        if not sub.is_dir():
            continue
        src = sub / "metadata.json"
        if not src.exists():
            continue
        v2 = normalize_one(sub, overrides)
        if not v2:
            continue
        out = sub / "metadata.v2.json"
        write_json(out, v2)
        count += 1
        print(f"Wrote {out.relative_to(ROOT)}")

    print(f"Done. Generated {count} v2 files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
