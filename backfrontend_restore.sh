#!/bin/bash
# ============================================================
# Install Foreman Apache Restore Service
# ============================================================

set -e

echo "==========================================="
echo " Checking backup files"
echo "==========================================="

if [ ! -f /opt/vgs/apache/05-foreman.conf ]; then
    echo "ERROR: /opt/vgs/apache/05-foreman.conf not found"
    exit 1
fi

if [ ! -f /opt/vgs/apache/05-foreman-ssl.conf ]; then
    echo "ERROR: /opt/vgs/apache/05-foreman-ssl.conf not found"
    exit 1
fi

echo "==========================================="
echo " Creating restore script"
echo "==========================================="

cat >/opt/vgs/apache/restore_foreman_apache.sh <<'EOF'
#!/bin/bash

LOG=/var/log/restore_foreman_apache.log

echo "===================================" >> $LOG
echo "$(date) Starting restore" >> $LOG

# Wait until Foreman/Puppet finishes startup
sleep 180

cp -f /opt/vgs/apache/05-foreman.conf \
      /etc/httpd/conf.d/05-foreman.conf

cp -f /opt/vgs/apache/05-foreman-ssl.conf \
      /etc/httpd/conf.d/05-foreman-ssl.conf

restorecon -Rv /etc/httpd/conf.d >/dev/null 2>&1 || true

if httpd -t; then
    systemctl restart httpd
    echo "$(date) Apache restarted successfully" >> $LOG
else
    echo "$(date) Apache configuration invalid" >> $LOG
    exit 1
fi

echo "$(date) Restore completed" >> $LOG
EOF

chmod +x /opt/vgs/apache/restore_foreman_apache.sh

echo "==========================================="
echo " Creating systemd service"
echo "==========================================="

cat >/etc/systemd/system/restore-foreman-apache.service <<'EOF'
[Unit]
Description=Restore Foreman Apache Configuration
After=multi-user.target
Wants=network-online.target

[Service]
Type=oneshot
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
echo "Test with:"
echo
echo "systemctl start restore-foreman-apache.service"
echo
echo "View log:"
echo
echo "cat /var/log/restore_foreman_apache.log"
