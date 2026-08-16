```text
IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="ethernet"{print $1; exit}') && CONN=$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d="$IFACE" '$2==d{print $1; exit}') && nmcli -t -f NAME,DEVICE connection show | awk -F: -v c="$CONN" '$1!=c && $2==""{print $1}' | xargs -r -n1 nmcli connection delete && systemctl restart NetworkManager && nmcli device connect "$IFACE" && sleep 5 && curl -L -o /root/Server_Setup.sh "https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Server_Setup.sh?$(date +%s)" && chmod +x /root/Server_Setup.sh && nmcli device disconnect "$IFACE"
```

```text
curl -L -o Rocky_8_HTTP_Repository_Server_Setup.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Rocky_8_HTTP_Repository_Server_Setup.sh?$(date +%s)" && \
chmod +x Rocky_8_HTTP_Repository_Server_Setup.sh
```

```text
curl -L -o install_awx_k3s_new.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/install_awx_k3s_new.sh?$(date +%s)" && \
chmod +x install_awx_k3s_new.sh
```

```text
curl -L -o awx-bootstrap.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/awx-bootstrap.sh?$(date +%s)" && \
chmod +x awx-bootstrap.sh
```

```text
curl -L -o working_netbox.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/working_netbox.sh?$(date +%s)" && \
chmod +x working_netbox.sh
```

```text
curl -L -o netbox-initial-bootstrap.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/netbox-initial-bootstrap.sh?$(date +%s)" && \
chmod +x netbox-initial-bootstrap.sh
```

```text
curl -L -o netbox-bootstrap.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/netbox-bootstrap.sh?$(date +%s)" && \
chmod +x netbox-bootstrap.sh
```

```text
curl -L -o Device_Creation_Netbox.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Device_Creation_Netbox.sh?$(date +%s)" && \
chmod +x Device_Creation_Netbox.sh
```

```text
curl -L -o Create_Specific_NetBox_Devices.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Create_Specific_NetBox_Devices.sh?$(date +%s)" && \
chmod +x Create_Specific_NetBox_Devices.sh
```

```text
curl -L -o /root/netbox-kernel-compliance.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/netbox-kernel-compliance.sh?$(date +%s)" && \
chmod +x /root/netbox-kernel-compliance.sh && \
(crontab -l 2>/dev/null | grep -v netbox-kernel-compliance.sh; echo "*/30 * * * * /root/netbox-kernel-compliance.sh >> /var/log/netbox-kernel-compliance.log 2>&1") | crontab -
```

```text
curl -L -o Change_NetBox_Cluster_Group_IDs.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Change_NetBox_Cluster_Group_IDs.sh?$(date +%s)" && \
chmod +x Change_NetBox_Cluster_Group_IDs.sh
```

```text
curl -L -o Offline_Patching_el8_cifs.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Offline_Patching_el8_cifs.sh?$(date +%s)" && \
chmod +x Offline_Patching_el8_cifs.sh
```

```text
curl -L -o Offline_Patching_el8.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Offline_Patching_el8.sh?$(date +%s)" && \
chmod +x Offline_Patching_el8.sh
```

```text
curl -L -o Offline_Patching_el7_cifs.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Offline_Patching_el7_cifs.sh?$(date +%s)" && \
chmod +x Offline_Patching_el7_cifs.sh
```

```text
curl -L -o Foreman_Rocky.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Foreman_Rocky.sh?$(date +%s)" && \
chmod +x Foreman_Rocky.sh
```

```text
curl -L -o Foreman_Proxy_Rocky.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Foreman_Proxy_Rocky.sh?$(date +%s)" && \
chmod +x Foreman_Proxy_Rocky.sh
```

```text
curl -L -o frontbackend_Rocky.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/frontbackend_Rocky.sh?$(date +%s)" && \
chmod +x frontbackend_Rocky.sh
```

```text
curl -L -o foreman.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman.sh?$(date +%s)" && \
chmod +x foreman.sh
```

```text
curl -L -o foreman_proxy.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman_proxy.sh?$(date +%s)" && \
chmod +x foreman_proxy.sh
```

```text
curl -L -o /usr/local/sbin/fix_foreman_assets.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/fix_foreman_assets.sh?$(date +%s)" && \
chmod +x /usr/local/sbin/fix_foreman_assets.sh && cat >/etc/cron.d/foreman-assets <<EOF
*/5 * * * * root /usr/local/sbin/fix_foreman_assets.sh >/dev/null 2>&1
EOF
```

```text
curl -L -o /root/check_tomcat.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/check_tomcat.sh?$(date +%s)" && \
chmod +x /root/check_tomcat.sh && \
(crontab -l 2>/dev/null | grep -v check_tomcat.sh; \
echo "* * * * * /root/check_tomcat.sh >> /var/log/tomcat_monitor.log 2>&1"; \
echo "* * * * * sleep 30; /root/check_tomcat.sh >> /var/log/tomcat_monitor.log 2>&1") | crontab -
```

```text
curl -L -o foreman-memory-tuning-production.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-memory-tuning-production.sh?$(date +%s)" && \
chmod +x foreman-memory-tuning-production.sh
```

```text
curl -L -o frontbackend.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/frontbackend.sh?$(date +%s)" && \
chmod +x frontbackend.sh
```

```text
curl -L -o backfrontend_restore.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/backfrontend_restore.sh?$(date +%s)" && \
chmod +x backfrontend_restore.sh
```

```text
curl -L -o kernel_tuning_awx.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/kernel_tuning_awx.sh?$(date +%s)" && \
chmod +x kernel_tuning_awx.sh
```

```text
curl -L -o 01_foreman_pxe_bootstrap.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/01_foreman_pxe_bootstrap.sh?$(date +%s)" && \

curl -L -o 02_foreman_katello_bootstrap.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/02_foreman_katello_bootstrap.sh?$(date +%s)" && \

curl -L -o 02_foreman_pxe_bootstrap_single_disk.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/02_foreman_pxe_bootstrap_single_disk.sh?$(date +%s)" && \

curl -L -o 03_foreman_hostgroup_bootstrap_raid.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/03_foreman_hostgroup_bootstrap_raid.sh?$(date +%s)" && \

curl -L -o 03_foreman_hostgroup_bootstrap_single_disk.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/03_foreman_hostgroup_bootstrap_single_disk.sh?$(date +%s)" && \

curl -L -o 04-bootstrap-el7toel8.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/04-bootstrap-el7toel8.sh?$(date +%s)" && \

curl -L -o 05-bootstrap-el8toel9.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap/05-bootstrap-el8toel9.sh?$(date +%s)" && \

chmod +x \
01_foreman_pxe_bootstrap.sh \
02_foreman_katello_bootstrap.sh \
02_foreman_pxe_bootstrap_single_disk.sh \
03_foreman_hostgroup_bootstrap_raid.sh \
03_foreman_hostgroup_bootstrap_single_disk.sh \
04-bootstrap-el7toel8.sh \
05-bootstrap-el8toel9.sh
```

```text
curl -L -o get_foreman_ids.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/get_foreman_ids.sh?$(date +%s)" && \
chmod +x get_foreman_ids.sh
```

```text
curl -L -o bootstrap_subscription_manager.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/bootstrap_subscription_manager.sh?$(date +%s)" && \
chmod +x bootstrap_subscription_manager.sh
```

```text
curl -L -o Offline_Patching_el7.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/Offline_Patching_el7.sh?$(date +%s)" && \
chmod +x Offline_Patching_el7.sh
```

```text
curl -L -o enable-verbose-boot.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh?$(date +%s)" && \
chmod +x enable-verbose-boot.sh
```

```text
wget -r -np -nH --cut-dirs=4 \
  https://1407433742.rsc.cdn77.org/c7.2009.u.x86_64/cyrus-sasl/20220224132553/2.1.26-24.el7_9.x86_64/
```

```text
curl -L -o 01_foreman_pxe_bootstrap_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/01_foreman_pxe_bootstrap_api.sh?$(date +%s)" && \
curl -L -o 02_foreman_katello_bootstrap_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/02_foreman_katello_bootstrap_api.sh?$(date +%s)" && \
curl -L -o 02_foreman_pxe_bootstrap_single_disk_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/02_foreman_pxe_bootstrap_single_disk_api.sh?$(date +%s)" && \
curl -L -o 03_foreman_hostgroup_bootstrap_raid_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/03_foreman_hostgroup_bootstrap_raid_api.sh?$(date +%s)" && \
curl -L -o 03_foreman_hostgroup_bootstrap_single_disk_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/03_foreman_hostgroup_bootstrap_single_disk_api.sh?$(date +%s)" && \
curl -L -o 04-bootstrap-el7toel8_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/04-bootstrap-el7toel8_api.sh?$(date +%s)" && \
curl -L -o 05-bootstrap-el8toel9_api.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/foreman-bootstrap-API/05-bootstrap-el8toel9_api.sh?$(date +%s)" && \
chmod +x \
01_foreman_pxe_bootstrap_api.sh \
02_foreman_katello_bootstrap_api.sh \
02_foreman_pxe_bootstrap_single_disk_api.sh \
03_foreman_hostgroup_bootstrap_raid_api.sh \
03_foreman_hostgroup_bootstrap_single_disk_api.sh \
04-bootstrap-el7toel8_api.sh \
05-bootstrap-el8toel9_api.sh
```
