from django.db import migrations


def seed_first_login(apps, schema_editor):
    Announcement = apps.get_model('channels', 'Announcement')
    Announcement.objects.update_or_create(
        kind='first_login',
        tenant='ontime',
        defaults={
            'title': 'Welcome to Ontime',
            'body': 'Thanks for signing in! Enjoy curated channels and new episodes every week.',
            'is_active': True,
        },
    )


def unseed_first_login(apps, schema_editor):
    Announcement = apps.get_model('channels', 'Announcement')
    Announcement.objects.filter(kind='first_login', tenant='ontime').delete()


class Migration(migrations.Migration):

    dependencies = [
        ('channels', '0007_announcement'),
    ]

    operations = [
        migrations.RunPython(seed_first_login, unseed_first_login),
    ]
