# Generated manually for Version Gate API
from django.db import migrations, models
import django.utils.timezone
import uuid


class Migration(migrations.Migration):

    dependencies = [
        ('channels', '0003_video'),
    ]

    operations = [
        migrations.CreateModel(
            name='AppVersion',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, primary_key=True, serialize=False)),
                ('platform', models.CharField(choices=[('ios', 'iOS'), ('android', 'Android'), ('web', 'Web')], max_length=10)),
                ('version', models.CharField(max_length=20)),
                ('build_number', models.IntegerField(default=0)),
                ('version_code', models.IntegerField(default=0)),
                ('status', models.CharField(choices=[('active', 'active'), ('deprecated', 'deprecated'), ('unsupported', 'unsupported'), ('blocked', 'blocked')], default='active', max_length=20)),
                ('update_type', models.CharField(choices=[('optional', 'optional'), ('required', 'required'), ('forced', 'forced')], default='optional', max_length=20)),
                ('min_supported_version', models.CharField(blank=True, max_length=20)),
                ('update_title', models.CharField(default='Update Available', max_length=100)),
                ('update_message', models.TextField(default='A new version is available. Please update for the best experience.')),
                ('force_update_message', models.TextField(default='This version is no longer supported. Please update to continue.')),
                ('ios_store_url', models.URLField(blank=True)),
                ('android_store_url', models.URLField(blank=True)),
                ('features', models.JSONField(default=list)),
                ('changelog', models.TextField(blank=True)),
                ('released_at', models.DateTimeField(default=django.utils.timezone.now)),
                ('deprecated_at', models.DateTimeField(blank=True, null=True)),
                ('end_of_support_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'db_table': 'channels_appversion',
                'ordering': ['platform', '-released_at'],
                'unique_together': {('platform', 'version')},
            },
        ),
        migrations.CreateModel(
            name='FeatureFlag',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, primary_key=True, serialize=False)),
                ('name', models.CharField(max_length=100, unique=True)),
                ('description', models.TextField(blank=True)),
                ('enabled', models.BooleanField(default=False)),
                ('enabled_for_staff', models.BooleanField(default=False)),
                ('rollout_percentage', models.IntegerField(default=0)),
                ('min_ios_version', models.CharField(blank=True, max_length=20, null=True)),
                ('min_android_version', models.CharField(blank=True, max_length=20, null=True)),
                ('enabled_users', models.JSONField(default=list)),
                ('disabled_users', models.JSONField(default=list)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'db_table': 'channels_featureflag',
                'ordering': ['name'],
            },
        ),
    ]
