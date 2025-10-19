#!/usr/bin/env python3
"""
Discover the master HLS playlist (.m3u8) + minimal headers/cookies from a page
(e.g., https://www.fanamc.com/english/live/). Works even if the player is inside
an iframe. Prints a ready-to-run curl, and (optionally) JSON with variants.

Usage:
  pip install playwright
  playwright install
  python tools/snoop_hls.py --url https://www.fanamc.com/english/live/ --wait 20 --json out.json
"""
import argparse, asyncio, html, json
from typing import Optional, Dict, Tuple, List
from urllib.parse import urlparse, urljoin
from playwright.async_api import async_playwright

MASTER_TAG = "#EXT-X-STREAM-INF"
IS_M3U8 = lambda ct: "mpegurl" in (ct or "").lower()

def parse_variants(master_body: str, master_url: str) -> List[Dict[str, str]]:
    out = []
    base = master_url.rsplit("/", 1)[0] + "/"
    lines = [l.strip() for l in master_body.splitlines() if l.strip()]
    for i, line in enumerate(lines):
        if line.startswith(MASTER_TAG):
            attrs = line[len(MASTER_TAG)+1:].strip()
            # next non-tag line should be the URI (often relative)
            j = i + 1
            while j < len(lines) and lines[j].startswith("#"):
                j += 1
            if j < len(lines):
                uri = lines[j]
                out.append({
                    "attrs": attrs,
                    "uri": urljoin(base, uri)
                })
    return out

def minimal_headers(req_headers: Dict[str, str], fallback_referer: str) -> Dict[str, str]:
    # Normalize keys
    get = lambda k: req_headers.get(k) or req_headers.get(k.lower()) or req_headers.get(k.title())
    return {
        "Origin": get("origin"),
        "Referer": get("referer") or fallback_referer,
        "User-Agent": get("user-agent"),
        "Accept-Language": get("accept-language") or "en-US,en;q=0.9",
    }

def build_curl(url: str, headers: Dict[str, str], cookie: Optional[str]) -> str:
    parts = [f"curl -vL '{url}' \\"]
    for k, v in headers.items():
        if v:
            parts.append(f"  -H '{k}: {v}' \\")
    if cookie:
        parts.append(f"  -H 'Cookie: {cookie}' \\")
    return "\n".join(parts).rstrip(" \\")

async def find_master(context, fallback_referer: str, wait_seconds: int) -> Tuple[Optional[str], Optional[Dict[str, str]], Optional[str]]:
    master_body = None
    master_req_headers = None
    master_url = None

    async def on_response(response):
        nonlocal master_body, master_req_headers, master_url
        try:
            url = response.url
            if ".m3u8" not in url:
                return
            ct = (response.headers.get("content-type") or "").lower()
            if not (IS_M3U8(ct) or url.lower().endswith(".m3u8")):
                return
            body = await response.text()  # playlists are small text
            if MASTER_TAG in body:
                master_body = body
                master_url = url
                master_req_headers = dict(response.request.headers)
        except Exception:
            pass

    context.on("response", on_response)
    # Playwright Python does not support removing listeners via context.off; keep it for the wait
    await asyncio.sleep(wait_seconds)

    if not master_url:
        return None, None, None

    # Collect cookies for that domain (may be empty)
    cookie_hdr = master_req_headers.get("cookie") or master_req_headers.get("Cookie")
    domain = urlparse(master_url).hostname or ""
    ctx_cookies = await context.cookies()
    domain_cookies = [f"{c['name']}={c['value']}" for c in ctx_cookies if domain.endswith(c.get('domain','').lstrip('.'))]
    cookie_combined = "; ".join(sorted(set([c for c in [cookie_hdr] if c] + domain_cookies))) or None

    # Minimal, reproducible headers
    headers = minimal_headers(master_req_headers, fallback_referer)
    return (master_url, headers, cookie_combined), master_body, None

async def run(url: str, headed: bool, wait_seconds: int, json_path: Optional[str]):
    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=not headed)
        context = await browser.new_context()  # real browser context
        page = await context.new_page()
        print(f"Navigating to: {url}")
        await page.goto(url, wait_until="domcontentloaded")
        # Let the page load network activity (players often lazy-load)
        try:
            await page.wait_for_load_state("networkidle", timeout=15000)
        except Exception:
            pass

        # Best effort: try clicking a big play button if present
        for sel in ['.vjs-big-play-button', 'button[aria-label*="play" i]', '[class*="play"]', 'button[title*="play" i]']:
            try:
                if await page.locator(sel).first.is_visible():
                    await page.locator(sel).first.click()
                    break
            except Exception:
                pass

        result, master_body, _ = await find_master(context, fallback_referer=url, wait_seconds=wait_seconds)
        if not result:
            print("\n[!] No master .m3u8 detected. Try --headed and interact with the page (click play), or increase --wait.")
            await browser.close()
            return

        (m3u8_url, headers, cookie) = result

        print("\n[+] Master URL:\n" + m3u8_url)
        print("\n[+] Minimal headers to replay:")
        for k, v in headers.items():
            print(f"  {k}: {v or '(none)'}")
        if cookie:
            print("  Cookie:", cookie)

        # List variants
        variants = parse_variants(master_body, m3u8_url)
        if variants:
            print("\n[+] Variants discovered:")
            for v in variants:
                print(f"  - {v['attrs']} -> {v['uri']}")

        print("\n[+] Ready-to-run curl:\n")
        print(build_curl(m3u8_url, headers, cookie))

        if json_path:
            payload = {
                "page": url,
                "master": {"url": m3u8_url, "headers": headers, "cookie": cookie},
                "variants": variants,
            }
            with open(json_path, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
            print(f"\n[✓] Wrote JSON to {json_path}")

        await browser.close()

def main():
    ap = argparse.ArgumentParser(description="Discover master HLS URL + headers/cookies from a live page")
    ap.add_argument("--url", required=True, help="Page URL (e.g., https://www.fanamc.com/english/live/)")
    ap.add_argument("--headed", action="store_true", help="Show browser window")
    ap.add_argument("--wait", type=int, default=20, help="Seconds to observe network (default: 20)")
    ap.add_argument("--json", dest="json_path", help="Write machine-readable JSON to this path")
    args = ap.parse_args()
    asyncio.run(run(args.url, args.headed, args.wait, args.json_path))

if __name__ == "__main__":
    main()
