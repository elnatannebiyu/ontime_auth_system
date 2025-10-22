# Celery Worker/Beat systemd setup (Production)

This guide provides unit templates and steps to run Celery worker and Celery Beat for the Django project `authstack/`.

## Assumptions
- Project path on server: `/srv/ontime/authstack`
- Python venv: `/srv/ontime/.venv`
- Django settings module: `authstack.settings_prod` (adjust if different)
- Broker/Backend: Redis at `redis://127.0.0.1:6379/0`
- Firebase Admin JSON: `/etc/ontime/secrets/firebase-admin.json`

## Environment file
Create `/etc/ontime/env` with:
```
DJANGO_SETTINGS_MODULE=authstack.settings_prod
DJANGO_SECRET_KEY=change-me
DATABASE_URL=postgres://ontime:password@127.0.0.1:5432/ontime
REDIS_URL=redis://127.0.0.1:6379/0
FIREBASE_CREDENTIALS_JSON=/etc/ontime/secrets/firebase-admin.json
# Optional: add any other env vars consumed by Django
```

Ensure the Firebase service account JSON exists and is readable by the service user:
```
sudo mkdir -p /etc/ontime/secrets
sudo chown root:root /etc/ontime/secrets
sudo chmod 750 /etc/ontime/secrets
# copy your JSON to /etc/ontime/secrets/firebase-admin.json
sudo chmod 640 /etc/ontime/secrets/firebase-admin.json
```

## Unit: Celery Worker
Create `/etc/systemd/system/ontime-celery.service`:
```
[Unit]
Description=Ontime Celery Worker
After=network.target redis.service
Requires=redis.service

[Service]
Type=simple
WorkingDirectory=/srv/ontime/authstack
EnvironmentFile=/etc/ontime/env
ExecStart=/srv/ontime/.venv/bin/celery -A authstack worker -l info --pidfile=/run/ontime/celery.pid --logfile=/var/log/ontime/celery-worker.log
Restart=always
User=ontime
Group=ontime
RuntimeDirectory=ontime
RuntimeDirectoryMode=0755
StandardOutput=append:/var/log/ontime/celery-worker.log
StandardError=append:/var/log/ontime/celery-worker.err.log

[Install]
WantedBy=multi-user.target
```

## Unit: Celery Beat
Create `/etc/systemd/system/ontime-celery-beat.service`:
```
[Unit]
Description=Ontime Celery Beat Scheduler
After=network.target redis.service ontime-celery.service
Requires=redis.service ontime-celery.service

[Service]
Type=simple
WorkingDirectory=/srv/ontime/authstack
EnvironmentFile=/etc/ontime/env
ExecStart=/srv/ontime/.venv/bin/celery -A authstack beat -l info --pidfile=/run/ontime/celery-beat.pid --logfile=/var/log/ontime/celery-beat.log
Restart=always
User=ontime
Group=ontime
RuntimeDirectory=ontime
RuntimeDirectoryMode=0755
StandardOutput=append:/var/log/ontime/celery-beat.log
StandardError=append:/var/log/ontime/celery-beat.err.log

[Install]
WantedBy=multi-user.target
```

## Setup steps
```
sudo useradd -r -s /usr/sbin/nologin ontime || true
sudo mkdir -p /var/log/ontime /run/ontime
sudo chown -R ontime:ontime /var/log/ontime /run/ontime

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable ontime-celery.service ontime-celery-beat.service
sudo systemctl start ontime-celery.service ontime-celery-beat.service

# Check status
systemctl status ontime-celery.service
systemctl status ontime-celery-beat.service
```

## Notes
- Ensure your Django app uses the same env (`DJANGO_SETTINGS_MODULE`) under which Celery should run.
- If your broker is not Redis, update `CELERY_BROKER_URL` in settings and ensure the service can reach it.
- Log rotation: configure `logrotate` for files in `/var/log/ontime/` as needed.
