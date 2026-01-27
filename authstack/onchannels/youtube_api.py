import os
import re
from typing import Dict, Any, Optional
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from django.conf import settings

YOUTUBE_API_BASE = "https://www.googleapis.com/youtube/v3"

_SESSION = requests.Session()
_RETRY = Retry(
    total=3,
    connect=3,
    read=3,
    status=3,
    backoff_factor=0.5,
    status_forcelist=(429, 500, 502, 503, 504),
    allowed_methods=("GET",),
    raise_on_status=False,
)
_SESSION.mount("https://", HTTPAdapter(max_retries=_RETRY))


def _get(url: str, *, params: dict) -> requests.Response:
    return _SESSION.get(url, params=params, timeout=(5, 20))


class YouTubeAPIError(Exception):
    pass


def _api_key() -> str:
    key = getattr(settings, "YOUTUBE_API_KEY", None) or os.getenv("YOUTUBE_API_KEY")
    if not key:
        raise YouTubeAPIError("YOUTUBE_API_KEY is not configured.")
    return key


def resolve_channel_id(handle_or_url: str) -> Optional[str]:
    """
    Resolve a channel ID (UC...) from a handle like '@ebstvWorldwide' or a channel URL.
    Falls back to search API if needed.
    """
    # If it's already a channel id
    if handle_or_url.startswith("UC") and len(handle_or_url) >= 20:
        return handle_or_url

    # Extract handle from common URL patterns
    m = re.search(r"/@([A-Za-z0-9_\.\-]+)", handle_or_url)
    handle = m.group(1) if m else None
    if not handle and handle_or_url.startswith("@"):
        handle = handle_or_url[1:]

    if handle:
        # Use search to find channel by handle
        params = {
            "part": "snippet",
            "q": handle,
            "type": "channel",
            "maxResults": 1,
            "key": _api_key(),
        }
        r = _get(f"{YOUTUBE_API_BASE}/search", params=params)
        if r.status_code != 200:
            raise YouTubeAPIError(f"YouTube search error: {r.status_code} {r.text}")
        data = r.json()
        items = data.get("items", [])
        if items:
            return items[0]["snippet"]["channelId"]
        return None

    # Try to extract channel ID from a direct channel URL
    m = re.search(r"/channel/(UC[\w-]+)", handle_or_url)
    if m:
        return m.group(1)

    return None

def playlist_id_from_url(url: str) -> Optional[str]:
    try:
        import urllib.parse as _up
        parsed = _up.urlparse(url)
        qs = _up.parse_qs(parsed.query)
        vals = qs.get("list")
        return vals[0] if vals else None
    except Exception:
        return None


def get_playlist(playlist_id: str) -> Dict[str, Any]:
    params = {
        "part": "snippet,contentDetails",
        "id": playlist_id,
        "key": _api_key(),
    }
    r = _get(f"{YOUTUBE_API_BASE}/playlists", params=params)
    if r.status_code != 200:
        raise YouTubeAPIError(f"YouTube playlist fetch error: {r.status_code} {r.text}")
    data = r.json()
    items = data.get("items", [])
    if not items:
        raise YouTubeAPIError("Playlist not found")
    it = items[0]
    return {
        "id": it.get("id"),
        "title": it.get("snippet", {}).get("title"),
        "thumbnails": it.get("snippet", {}).get("thumbnails", {}),
        "itemCount": it.get("contentDetails", {}).get("itemCount"),
        "publishedAt": it.get("snippet", {}).get("publishedAt"),
    }
    


def list_playlists(channel_id: str, page_token: Optional[str] = None, max_results: int = 25) -> Dict[str, Any]:
    params = {
        "part": "snippet,contentDetails",
        "channelId": channel_id,
        "maxResults": max(1, min(max_results, 50)),
        "key": _api_key(),
    }
    if page_token:
        params["pageToken"] = page_token
    r = _get(f"{YOUTUBE_API_BASE}/playlists", params=params)
    if r.status_code != 200:
        raise YouTubeAPIError(f"YouTube playlists error: {r.status_code} {r.text}")
    data = r.json()
    # Normalize
    return {
        "items": [
            {
                "id": it.get("id"),
                "title": it.get("snippet", {}).get("title"),
                "publishedAt": it.get("snippet", {}).get("publishedAt"),
                "thumbnails": it.get("snippet", {}).get("thumbnails", {}),
                "itemCount": it.get("contentDetails", {}).get("itemCount"),
            }
            for it in data.get("items", [])
        ],
        "nextPageToken": data.get("nextPageToken"),
        "prevPageToken": data.get("prevPageToken"),
    }


def list_playlist_items(playlist_id: str, page_token: Optional[str] = None, max_results: int = 25) -> Dict[str, Any]:
    params = {
        "part": "snippet,contentDetails",
        "playlistId": playlist_id,
        "maxResults": max(1, min(max_results, 50)),
        "key": _api_key(),
    }
    if page_token:
        params["pageToken"] = page_token
    r = _get(f"{YOUTUBE_API_BASE}/playlistItems", params=params)
    if r.status_code != 200:
        raise YouTubeAPIError(f"YouTube playlistItems error: {r.status_code} {r.text}")
    data = r.json()
    return {
        "items": [
            {
                "videoId": it.get("contentDetails", {}).get("videoId"),
                "title": it.get("snippet", {}).get("title"),
                "position": it.get("snippet", {}).get("position"),
                "publishedAt": it.get("contentDetails", {}).get("videoPublishedAt"),
                "thumbnails": it.get("snippet", {}).get("thumbnails", {}),
            }
            for it in data.get("items", [])
        ],
        "nextPageToken": data.get("nextPageToken"),
        "prevPageToken": data.get("prevPageToken"),
    }


def get_video_privacy_status(video_id: str) -> Optional[str]:
    """Return the privacyStatus for a single video id.

    Possible values include "public", "unlisted", "private". Returns None if
    the video is not found or the status cannot be determined.
    """
    params = {
        "part": "status",
        "id": video_id,
        "key": _api_key(),
    }
    r = _get(f"{YOUTUBE_API_BASE}/videos", params=params)
    if r.status_code != 200:
        raise YouTubeAPIError(f"YouTube videos status error: {r.status_code} {r.text}")
    data = r.json()
    items = data.get("items", [])
    if not items:
        return None
    return items[0].get("status", {}).get("privacyStatus")
