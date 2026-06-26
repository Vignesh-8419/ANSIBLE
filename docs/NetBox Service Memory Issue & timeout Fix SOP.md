# Fix NetBox Memory Usage by Reducing Gunicorn Workers

## Problem

After modifying the NetBox `systemd` service to reduce memory usage, NetBox failed to start with the following error:

```text
ModuleNotFoundError: No module named 'netbox.wsgi'
```

The issue occurred because the `ExecStart` command was modified and the required options:

* `--pythonpath /opt/netbox/netbox`
* `--config /opt/netbox/gunicorn.py`

were removed.

---

# Resolution

## 1. Backup the Existing Service

```bash
cp -p /etc/systemd/system/netbox.service \
      /etc/systemd/system/netbox.service.bak
```

---

## 2. Replace the Service File

```bash
cat >/etc/systemd/system/netbox.service <<'EOF'
[Unit]
Description=NetBox WSGI Service
Documentation=https://docs.netbox.dev/
After=network.target postgresql-15.service redis.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netbox

ExecStart=/opt/netbox/venv/bin/gunicorn \
    --pythonpath /opt/netbox/netbox \
    --config /opt/netbox/gunicorn.py \
    --workers 2 \
    --worker-class gthread \
    --threads 4 \
    netbox.wsgi

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

---

## 3. Reload Systemd

```bash
systemctl daemon-reload
```

---

## 4. Restart NetBox

```bash
systemctl restart netbox
```

---

## 5. Verify Service Status

```bash
systemctl status netbox
```

Expected output:

```text
Active: active (running)
```

---

## 6. If NetBox Still Fails

Collect the following logs for troubleshooting:

```bash
journalctl -u netbox -n 100 --no-pager
```

Verify the WSGI file exists:

```bash
ls -l /opt/netbox/netbox/netbox/wsgi.py
```

Verify the Gunicorn configuration:

```bash
cat /opt/netbox/gunicorn.py
```

Test Gunicorn manually:

```bash
/opt/netbox/venv/bin/gunicorn \
    --pythonpath /opt/netbox/netbox \
    --config /opt/netbox/gunicorn.py \
    netbox.wsgi
```

---

# Summary

The original service file supplied with NetBox is correct. To reduce memory consumption, only the Gunicorn worker configuration should be modified. The required options:

* `--pythonpath /opt/netbox/netbox`
* `--config /opt/netbox/gunicorn.py`

must always remain in the `ExecStart` command. Removing either option prevents Gunicorn from locating the `netbox.wsgi` module and causes NetBox to fail during startup.
