#!/bin/bash
#==============================================================================
# Foreman/Katello Memory Tuning for 8 GB RAM
# Production-ready, idempotent
#==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'

ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
skip(){ echo -e "${YELLOW}[SKIP]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; }
header(){
echo
echo -e "${BLUE}============================================================${NC}"
echo -e "${WHITE}$1${NC}"
echo -e "${BLUE}============================================================${NC}"
}

BACKUP_TIME=$(date +%F-%H%M%S)
ROLLBACK=/root/foreman-memory-rollback-${BACKUP_TIME}.sh
echo "#!/bin/bash" > "$ROLLBACK"

backup_file() {
    local FILE="$1"
    [ -f "$FILE" ] || { skip "$FILE not found"; return; }
    local BK="${FILE}.${BACKUP_TIME}.bak"
    cp -a "$FILE" "$BK"
    chmod 600 "$BK"
    ok "Backup: $BK"
    printf 'cp -af "%s" "%s"\n' "$BK" "$FILE" >> "$ROLLBACK"
}

header "Initial Memory Usage"
free -h

header "Tomcat JVM"
if [ -f /etc/tomcat/tomcat.conf ]; then
    backup_file /etc/tomcat/tomcat.conf
    sed -ri 's/-Xms[0-9]+[mMgG]/-Xms512m/g;s/-Xmx[0-9]+[mMgG]/-Xmx2048m/g' /etc/tomcat/tomcat.conf
    systemctl restart tomcat || warn "Unable to restart tomcat"
    ok "Tomcat tuned"
fi

header "Puppet Server"
if [ -f /etc/sysconfig/puppetserver ]; then
    backup_file /etc/sysconfig/puppetserver
    cat >/etc/sysconfig/puppetserver <<'EOF'
JAVA_ARGS="-Xms512m -Xmx1024m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger"
EOF
    systemctl stop puppetserver 2>/dev/null || true
    systemctl disable puppetserver 2>/dev/null || true
    ok "Puppet disabled"
fi

header "Foreman Puma"
PUMA=/etc/systemd/system/foreman.service.d/installer.conf
if [ -f "$PUMA" ]; then
    backup_file "$PUMA"
    sed -ri \
      -e 's/FOREMAN_PUMA_THREADS_MIN=.*/FOREMAN_PUMA_THREADS_MIN=3/' \
      -e 's/FOREMAN_PUMA_THREADS_MAX=.*/FOREMAN_PUMA_THREADS_MAX=3/' \
      -e 's/FOREMAN_PUMA_WORKERS=.*/FOREMAN_PUMA_WORKERS=2/' "$PUMA"
    systemctl daemon-reload
    ok "Puma tuned"
fi

header "Dynflow Workers"
for f in /etc/foreman/dynflow/worker-1.yml /etc/foreman/dynflow/worker-hosts-queue-1.yml; do
    if [ -f "$f" ]; then
        backup_file "$f"
        sed -ri 's/^:concurrency:.*/:concurrency: 2/' "$f"
        ok "Updated $(basename "$f")"
    fi
done

header "Kernel Memory"
backup_file /etc/sysctl.d/99-memory.conf
cat >/etc/sysctl.d/99-memory.conf <<EOF
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
sysctl --system >/dev/null
ok "Kernel tuned"

header "Restart Services"
for svc in foreman tomcat; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
        systemctl restart "$svc" || warn "Failed to restart $svc"
    fi
done

header "Verification"
echo "Memory:"
free -h
echo
echo "Tomcat: $(systemctl is-active tomcat 2>/dev/null || true)"
echo "Foreman: $(systemctl is-active foreman 2>/dev/null || true)"
echo "Puppet: $(systemctl is-active puppetserver 2>/dev/null || true)"
echo
echo "Dynflow:"
grep -H concurrency /etc/foreman/dynflow/*.yml 2>/dev/null || true
echo
echo "Puma:"
systemctl cat foreman 2>/dev/null | grep FOREMAN_PUMA || true
echo
echo "Kernel:"
sysctl vm.swappiness vm.vfs_cache_pressure

chmod +x "$ROLLBACK"

header "Completed"
ok "Memory tuning completed."
ok "Rollback script: $ROLLBACK"
