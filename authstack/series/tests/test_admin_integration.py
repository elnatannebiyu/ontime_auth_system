from django.test import TestCase, RequestFactory
from django.contrib import admin
from django.contrib.auth import get_user_model

from onchannels.models import Channel, Playlist
from onchannels.admin import ChannelAdmin
from series.models import Show
from series.admin import ShowAdmin, ShowAdminForm


User = get_user_model()


class SeriesAdminIntegrationTests(TestCase):
    def setUp(self):
        self.rf = RequestFactory()
        # Minimal admin user
        self.admin_user = User.objects.create_superuser(
            username="elu1",
            email="elu@gmail.com",
            password="12345678",
        )

        # Two channels, different tenants and activity
        self.ch_active_same_tenant = Channel.objects.create(
            tenant="ontime",
            id_slug="ebs",
            default_locale="am",
            name_en="EBS",
            is_active=True,
        )
        self.ch_inactive_same_tenant = Channel.objects.create(
            tenant="ontime",
            id_slug="inactive-ch",
            default_locale="am",
            name_en="Inactive CH",
            is_active=False,
        )
        self.ch_active_other_tenant = Channel.objects.create(
            tenant="other",
            id_slug="other-ebs",
            default_locale="am",
            name_en="Other EBS",
            is_active=True,
        )

        # Example playlist from EBS (YouTube playlist ID and title)
        self.ebs_playlist = Playlist.objects.create(
            id="PL_EBS_FETAGNE_KUSHENA",
            channel=self.ch_active_same_tenant,
            title="Fetagne Kushena / ፈታኝ ኩሽና",
            item_count=10,
            is_active=True,
        )

    def test_showadmin_channel_queryset_filters_active_and_tenant(self):
        # When creating a Show with tenant=ontime, the channel choices should include only active channels from 'ontime'
        form = ShowAdminForm(data={
            "tenant": "ontime",
            "title": "Sample Show",
            "is_active": True,
        })
        self.assertIn(self.ch_active_same_tenant, form.fields["channel"].queryset)
        self.assertNotIn(self.ch_inactive_same_tenant, form.fields["channel"].queryset)
        # Active but different tenant should be filtered out when tenant provided
        self.assertNotIn(self.ch_active_other_tenant, form.fields["channel"].queryset)

    def test_show_slug_auto_suggests_from_channel_id_slug_if_blank(self):
        # Prepare admin context
        model_admin = ShowAdmin(Show, admin.site)
        request = self.rf.post("/admin/series/show/add/")
        request.user = self.admin_user

        # 1) Create an existing Show that occupies the base slug (channel.id_slug)
        existing = Show.objects.create(
            tenant="ontime",
            slug=self.ch_active_same_tenant.id_slug,
            title="Existing",
            channel=self.ch_active_same_tenant,
            is_active=True,
        )

        # 2) Now save a new Show with a blank slug; it should auto-suffix to avoid collision
        show2 = Show(
            tenant="ontime",
            title="Another",
            slug="",
            channel=self.ch_active_same_tenant,
            is_active=True,
        )
        model_admin.save_model(request, show2, form=None, change=False)
        show2.refresh_from_db()
        self.assertNotEqual(show2.slug, self.ch_active_same_tenant.id_slug)
        self.assertTrue(show2.slug.startswith(f"{self.ch_active_same_tenant.id_slug}-show"))

    def test_channel_admin_action_creates_show_from_channel(self):
        # Ensure no Show exists initially
        self.assertFalse(Show.objects.filter(channel=self.ch_active_same_tenant).exists())
        # Run the admin action to create a Show from channel
        model_admin = ChannelAdmin(Channel, admin.site)
        request = self.rf.post("/admin/onchannels/channel/")
        request.user = self.admin_user
        queryset = Channel.objects.filter(pk=self.ch_active_same_tenant.pk)
        model_admin.create_show_from_channel(request, queryset)
        # A Show should now be created and linked to the channel
        show = Show.objects.filter(channel=self.ch_active_same_tenant).first()
        self.assertIsNotNone(show)
        self.assertEqual(show.tenant, self.ch_active_same_tenant.tenant)
        self.assertTrue(show.slug.startswith(self.ch_active_same_tenant.id_slug))
        self.assertEqual(show.title, self.ch_active_same_tenant.name_en or self.ch_active_same_tenant.name_am or self.ch_active_same_tenant.id_slug)

        # Running the action again should skip creating a duplicate
        model_admin.create_show_from_channel(request, queryset)
        self.assertEqual(Show.objects.filter(channel=self.ch_active_same_tenant).count(), 1)
