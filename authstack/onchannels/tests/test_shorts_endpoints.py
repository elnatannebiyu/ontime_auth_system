from django.test import TestCase
from django.utils import timezone
from datetime import timedelta
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from onchannels.models import Channel, Playlist, Video
from tenants.models import Tenant

User = get_user_model()


class TestShortsEndpoints(TestCase):
    def setUp(self):
        # Base tenant and user
        self.tenant = Tenant.objects.create(slug="ontime", name="Ontime", active=True)
        self.user = User.objects.create_user(username="tester", password="Passw0rd!")
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        self.headers = {"HTTP_X_TENANT_ID": "ontime"}
        # Base channel
        self.channel = Channel.objects.create(
            tenant="ontime",
            id_slug="ebs",
            name_en="EBS",
            is_active=True,
        )

    def _make_playlist(self, title: str, days_ago: int, item_count: int = 10):
        pl = Playlist.objects.create(
            id=f"PL_{title}_{days_ago}",
            channel=self.channel,
            title=title,
            thumbnails={},
            item_count=item_count,
            is_active=True,
            is_shorts=True,
        )
        # Attach a video with published_at to drive recency
        Video.objects.create(
            channel=self.channel,
            playlist=pl,
            video_id=f"vid_{title}_{days_ago}",
            title=f"{title} item",
            thumbnails={},
            position=0,
            published_at=timezone.now() - timedelta(days=days_ago),
            is_active=True,
        )
        return pl

    def test_playlists_filters_30day_window(self):
        # Recent within 30 days
        recent = self._make_playlist("Short Recent", days_ago=5)
        # Old outside 30 days (won't appear)
        old = self._make_playlist("Short Old", days_ago=45)

        resp = self.client.get(
            "/api/channels/shorts/playlists/?days=30&limit=50",
            **self.headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        ids = [it["id"] for it in data.get("results", [])]
        assert recent.id in ids
        assert old.id not in ids

    def test_per_channel_limit_enforced(self):
        # Create 6 playlists all for same channel
        for i in range(6):
            self._make_playlist(f"Short P{i}", days_ago=i)

        resp = self.client.get(
            "/api/channels/shorts/playlists/?days=30&limit=100&per_channel_limit=5",
            **self.headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        # All from same channel, so limited to 5
        assert data["count"] <= 5
        assert len(data["results"]) <= 5

    def test_feed_deterministic_shuffle_by_seed(self):
        # Make multiple items to observe ordering differences, within window
        titles = ["Short A", "Short B", "Short C", "Short D"]
        for i, t in enumerate(titles):
            self._make_playlist(t, days_ago=i)

        # Force shuffle of all by setting recent_bias_count=0
        url = "/api/channels/shorts/feed/?days=30&limit=50&per_channel_limit=5&recent_bias_count=0"
        resp1 = self.client.get(url + "&seed=alpha", **self.headers)
        resp2 = self.client.get(url + "&seed=beta", **self.headers)
        assert resp1.status_code == 200 and resp2.status_code == 200
        order1 = [it["playlist_id"] for it in resp1.json()["results"]]
        order2 = [it["playlist_id"] for it in resp2.json()["results"]]
        # Same elements
        assert set(order1) == set(order2)
        # Different order if seeds differ (very high likelihood with >2 items)
        assert order1 != order2

    def test_auth_required(self):
        anon = APIClient()
        # Include tenant header so auth check is evaluated (not tenant 400)
        resp = anon.get("/api/channels/shorts/playlists/?days=30", HTTP_X_TENANT_ID="ontime")
        assert resp.status_code in (401, 403)

    def test_tenant_header_required(self):
        # Missing X-Tenant-Id should be 400 from middleware for /api/*
        resp = self.client.get("/api/channels/shorts/playlists/?days=30")
        assert resp.status_code == 400
        assert resp.json().get("detail") in {"Unknown tenant"}
