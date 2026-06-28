#!/bin/bash
# ============================================================
# Foreman Apache Configuration Auto Restore
# Restores custom 05-foreman*.conf after reboot
# ============================================================

set -e

echo "==========================================="
echo " Creating backup of working configuration"
echo "==========================================="

mkdir -p /opt/vgs/apache

cp -f /etc/httpd/conf.d/05-foreman.conf \
      /opt/vgs/apache/05-foreman.conf

cp -f /etc/httpd/conf.d/05-foreman-ssl.conf \
      /opt/vgs/apache/05-foreman-ssl.conf

echo "==========================================="
echo " Creating restore script"
echo "==========================================="

cat >/opt/vgs/apache/restore_foreman_apache.sh <<'EOF'
#!/bin/bash

echo "Restoring custom Apache configuration..."

cp -f /opt/vgs/apache/05-foreman.conf \
      /etc/httpd/conf.d/05-foreman.conf

cp -f /opt/vgs/apache/05-foreman-ssl.conf \
      /etc/httpd/conf.d/05-foreman-ssl.conf

restorecon -Rv /etc/httpd/conf.d >/dev/null 2>&1 || true

httpd -t || exit 1

systemctl restart httpd

echo "Apache configuration restored successfully."
EOF

chmod +x /opt/vgs/apache/restore_foreman_apache.sh

echo "==========================================="
echo " Creating systemd service"
echo "==========================================="

cat >/etc/systemd/system/restore-foreman-apache.service <<'EOF'
[Unit]
Description=Restore Foreman Apache Configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 60
ExecStart=/opt/vgs/apache/restore_foreman_apache.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "==========================================="
echo " Enabling service"
echo "==========================================="

systemctl daemon-reload
systemctl enable restore-foreman-apache.service

echo
echo "==========================================="
echo " Installation Complete"
echo "==========================================="
echo
echo "Backups stored in:"
echo "  /opt/vgs/apache/"
echo
echo "Restore script:"
echo "  /opt/vgs/apache/restore_foreman_apache.sh"
echo
echo "Service:"
echo "  restore-foreman-apache.service"
echo
echo "Test now using:"
echo
echo "systemctl start restore-foreman-apache.service"
echo
echo "Check status:"
echo
echo "systemctl status restore-foreman-apache.service"
