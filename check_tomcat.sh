#!/bin/bash

SERVICE="tomcat"

# Change if your service name is different (tomcat9, tomcat10, etc.)

LOGFILE="/var/log/tomcat_monitor.log"

if ! systemctl is-active --quiet "$SERVICE"; then
    echo "$(date '+%F %T') - $SERVICE is DOWN. Restarting..." >> "$LOGFILE"

    systemctl restart "$SERVICE"

    sleep 5

    if systemctl is-active --quiet "$SERVICE"; then
        echo "$(date '+%F %T') - $SERVICE restarted successfully." >> "$LOGFILE"
    else
        echo "$(date '+%F %T') - ERROR: Failed to restart $SERVICE." >> "$LOGFILE"
    fi
fi
