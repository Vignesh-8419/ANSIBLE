#!/bin/bash

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
REPO_URL="http://http-server-01.vgs.com/repo"

SSH_USER="root"
SSH_PASS='Root@123'


DEFAULT_GW="192.168.253.2"

# -----------------------------------------------------------------------------
# COLOR DEFINITIONS
# -----------------------------------------------------------------------------
COLOR_INFO=$'\e[1;33m'
COLOR_OK=$'\e[1;32m'
COLOR_FAIL=$'\e[1;31m'
COLOR_BLUE=$'\e[1;34m'
COLOR_RESET=$'\e[0m'

export TERM=xterm-256color

log_info() { echo -e "${COLOR_INFO}[INFO] $1${COLOR_RESET}"; }
log_ok()   { echo -e "${COLOR_OK}[OK] $1${COLOR_RESET}"; }
log_fail() { echo -e "${COLOR_FAIL}[FAIL] $1${COLOR_RESET}"; }
log_blue() { echo -e "${COLOR_BLUE}$1${COLOR_RESET}"; }

display_usage() {

    echo "Usage: $0 --node=node1,node2,node3"
    echo
    echo "Example:"
    echo "  $0 --node=192.168.253.10,192.168.253.11,localhost"
    exit 1
}

# =============================================================================
# TASK 1 - AWX STYLE DASHBOARD MODULE
# =============================================================================

PROGRESS_DIR="/tmp/offline_patch_progress_$$"

mkdir -p "$PROGRESS_DIR"

update_progress() {

    local NODE="$1"
    local STAGE="$2"
    local PERCENT="$3"
    local STATUS="$4"

TMP_FILE="${PROGRESS_DIR}/${NODE}.tmp"

cat > "$TMP_FILE" << EOF
NODE="${NODE}"
STAGE="${STAGE}"
PERCENT="${PERCENT}"
STATUS="${STATUS}"
EOF

mv "$TMP_FILE" "${PROGRESS_DIR}/${NODE}.status"
}

draw_bar() {

    local PERCENT="$1"

    local FILLED=$((PERCENT / 5))
    [ "$FILLED" -gt 20 ] && FILLED=20

    local EMPTY=$((20 - FILLED))

    printf "["

    for ((i=0;i<FILLED;i++))
    do
        printf "█"
    done

    for ((i=0;i<EMPTY;i++))
    do
        printf "░"
    done

    printf "]"
}

show_dashboard() {

    printf "\033[H\033[2J"

    echo "===================================================================="
    echo "OFFLINE PATCH ORCHESTRATOR"
    echo "===================================================================="
    echo
    echo -e "${COLOR_INFO}● Running${COLOR_RESET}   ${COLOR_OK}● Success${COLOR_RESET}   ${COLOR_FAIL}● Failed${COLOR_RESET}"
    echo

    local COMPLETED=0
    local RUNNING=0
    local FAILED=0
    local TOTAL=0

    for FILE in "${PROGRESS_DIR}"/*.status
    do

        [ -f "$FILE" ] || continue

		unset NODE STAGE PERCENT STATUS
		source "$FILE"

        TOTAL=$((TOTAL + 1))

        BAR=$(draw_bar "$PERCENT")

        case "$STATUS" in
            COMPLETED)
                COLOR="$COLOR_OK"
                ICON="✓"
                ;;
            FAILED)
                COLOR="$COLOR_FAIL"
                ICON="✗"
                ;;
            *)
                COLOR="$COLOR_INFO"
                ICON="➜"
                ;;
        esac
        
        printf "%b%-20s %-25s %3s%% %-35s %s%b\n" \
            "$COLOR" \
            "$NODE" \
            "$BAR" \
            "$PERCENT" \
            "$STAGE" \
            "$ICON" \
            "$COLOR_RESET"

        case "$STATUS" in
            COMPLETED)
                COMPLETED=$((COMPLETED + 1))
                ;;
            FAILED)
                FAILED=$((FAILED + 1))
                ;;
            *)
                RUNNING=$((RUNNING + 1))
                ;;
        esac

    done

    echo
    echo -e "${COLOR_OK}Completed : ${COMPLETED}/${TOTAL}${COLOR_RESET}"
    echo -e "${COLOR_INFO}Running   : ${RUNNING}/${TOTAL}${COLOR_RESET}"
    echo -e "${COLOR_FAIL}Failed    : ${FAILED}/${TOTAL}${COLOR_RESET}"
    echo
    echo "===================================================================="
}

cleanup() {

    stop_dashboard

    rm -rf "$PROGRESS_DIR"
}

trap cleanup EXIT
trap 'exit 1' INT TERM

start_dashboard() {

    (
        while true
        do
            show_dashboard
            sleep 1
        done
    ) &

    DASHBOARD_PID=$!
}

stop_dashboard() {

    if [ -n "${DASHBOARD_PID:-}" ]
    then
        kill "$DASHBOARD_PID" 2>/dev/null || true
        wait "$DASHBOARD_PID" 2>/dev/null || true
    fi
}

init_dashboard_nodes() {

    for NODE in "${TARGET_NODES[@]}"
    do
        NODE=$(echo "$NODE" | xargs)

        update_progress \
            "$NODE" \
            "Waiting" \
            "0" \
            "RUNNING"
    done
}
# =============================================================================
# TASK 2 - LIVE STAGE INTEGRATION
# =============================================================================

# -----------------------------------------------------------------------------
# STAGE REPORTER
# -----------------------------------------------------------------------------

progress_stage() {

    local NODE="$1"
    local STAGE="$2"
    local PERCENT="$3"

    update_progress \
        "$NODE" \
        "$STAGE" \
        "$PERCENT" \
        "RUNNING"
}

remote_exec() {

    local NODE="$1"
    shift

    sshpass -p "${SSH_PASS}" \
ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "${SSH_USER}@${NODE}" "$@"
}

restore_remote_environment() {

    local NODE="$1"
    local BACKUP_DIR="$2"

    remote_exec "$NODE" "
        rm -f /etc/yum.repos.d/centos7-offline.repo
        rm -f /etc/yum.repos.d/rhel7-installed.repo
    
        if [ -d /etc/yum.repos.d/${BACKUP_DIR} ]
        then
            find /etc/yum.repos.d/${BACKUP_DIR} \
                -type f \
                -name '*.repo' \
                -exec mv {} /etc/yum.repos.d/ \;
    
            rm -rf /etc/yum.repos.d/${BACKUP_DIR}
        fi
    "
    
    return $?
}

# =============================================================================
# TASK 3 - DASHBOARD STARTUP AND NODE INITIALIZATION
# =============================================================================

patch_remote_node() {

    local NODE="$1"

    local LOCAL_BACKUP_DIR
    LOCAL_BACKUP_DIR="backup_repos_${NODE}_$(date +%Y%m%d_%H%M%S)"
    progress_stage "$NODE" "SSH Connectivity" "5"
    
    remote_exec "$NODE" "
		hostname >/dev/null &&
		[ \$(id -u) -eq 0 ]
    "
    
    if [ $? -ne 0 ]
    then
        update_progress "$NODE" "SSH Connection Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Repo Server Check" "10"
    
    remote_exec "$NODE" "
    curl -sf ${REPO_URL}/centos/repodata/repomd.xml >/dev/null
    "
    
    if [ $? -ne 0 ]
    then
        update_progress "$NODE" "Repo Server Unreachable" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Repository Backup" "15"

    remote_exec "$NODE" "
        mkdir -p /etc/yum.repos.d/${LOCAL_BACKUP_DIR}

        find /etc/yum.repos.d -maxdepth 1 -name '*.repo' \
            ! -name 'centos7-offline.repo' \
            ! -name 'rhel7-installed.repo' \
            -exec mv {} /etc/yum.repos.d/${LOCAL_BACKUP_DIR}/ \;
    "

    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Repo Backup Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Repository Validation" "20"
        
    remote_exec "$NODE" "
        curl -sf ${REPO_URL}/centos/repodata/repomd.xml >/dev/null &&
        curl -sf ${REPO_URL}/installed_rhel7/repodata/repomd.xml >/dev/null
    "
    
    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Repository Content Missing" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Creating Offline Repositories" "25"

remote_exec "$NODE" "

cat > /etc/yum.repos.d/centos7-offline.repo << EOF
[centos7-offline]
name=CentOS 7 Offline Repository
baseurl=${REPO_URL}/centos
enabled=1
gpgcheck=0
sslverify=0
EOF

cat > /etc/yum.repos.d/rhel7-installed.repo << EOF
[rhel7-installed]
name=Installed RHEL7 Packages
baseurl=${REPO_URL}/installed_rhel7
enabled=1
gpgcheck=0
sslverify=0
EOF

"

    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Repo Creation Failed" "100" "FAILED"
        return 1
    fi

remote_exec "$NODE" "
        test -f /etc/yum.repos.d/centos7-offline.repo &&
        test -f /etc/yum.repos.d/rhel7-installed.repo
"

    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Repo Creation Failed" "100" "FAILED"
        return 1
    fi
    progress_stage "$NODE" "Cleaning Metadata" "30"

    remote_exec "$NODE" "
		yum clean all
		rm -rf /var/cache/yum/*
    "
	
    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Metadata Cleanup Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Building Repository Cache" "35"

    remote_exec "$NODE" "
    yum makecache fast \
        --disablerepo='*' \
        --enablerepo=centos7-offline,rhel7-installed
	"

    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Makecache Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Repository Verification" "40"
    
    remote_exec "$NODE" "
        yum repolist enabled >/dev/null 2>&1 || exit 1
    
        RC=0
        yum check-update >/dev/null 2>&1 || RC=\$?
    
        [ \$RC -eq 0 ] || [ \$RC -eq 100 ]
    "
    
    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Repository Verification Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Installing Updates" "60"

    remote_exec "$NODE" "
    yum update - --skip-broken --allowerasing --nobest \
        --disablerepo='*' \
        --enablerepo=centos7-offline,rhel7-installed
    "

    if [ $? -ne 0 ]
    then
        restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
        update_progress "$NODE" "Install Failed" "100" "FAILED"
        return 1
    fi

    progress_stage "$NODE" "Restoring Configuration" "90"
    
    restore_remote_environment "$NODE" "$LOCAL_BACKUP_DIR"
    
    if [ $? -ne 0 ]
    then
        update_progress "$NODE" "Repository Restore Failed" "100" "FAILED"
        return 1
    fi
    
    remote_exec "$NODE" "
        test ! -f /etc/yum.repos.d/centos7-offline.repo &&
        test ! -f /etc/yum.repos.d/rhel7-installed.repo &&
        test ! -d /etc/yum.repos.d/${LOCAL_BACKUP_DIR} &&
        ls /etc/yum.repos.d/*.repo >/dev/null 2>&1
    "
    
    if [ $? -ne 0 ]
    then
        update_progress "$NODE" "Repository Restore Validation Failed" "100" "FAILED"
        return 1
    fi
progress_stage "$NODE" "Rebooting Server" "95"

remote_exec "$NODE" "
    nohup bash -c 'sleep 2; reboot' >/dev/null 2>&1 &
" >/dev/null 2>&1 || true

progress_stage "$NODE" "Waiting For Shutdown" "96"

SERVER_DOWN=0

for i in {1..30}
do
    if ! sshpass -p "${SSH_PASS}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        "${SSH_USER}@${NODE}" \
        "echo online" >/dev/null 2>&1
    then
        SERVER_DOWN=1
        break
    fi

    sleep 2
done

if [ "$SERVER_DOWN" -ne 1 ]
then
    update_progress "$NODE" "Shutdown Validation Failed" "100" "FAILED"
    return 1
fi

progress_stage "$NODE" "Waiting For Startup" "97"

SERVER_UP=0

for i in {1..60}
do
    if sshpass -p "${SSH_PASS}" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${NODE}" \
        "echo online" >/dev/null 2>&1
    then
        SERVER_UP=1
        break
    fi

    sleep 10
done

if [ "$SERVER_UP" -eq 1 ]
then

    progress_stage "$NODE" "Post-Reboot Validation" "99"

    if remote_exec "$NODE" "
        uptime >/dev/null 2>&1 &&
        rpm -qa >/dev/null 2>&1 &&
        test -d /etc/yum.repos.d
    " >/dev/null 2>&1
    then
        update_progress \
            "$NODE" \
            "Completed Successfully" \
            "100" \
            "COMPLETED"
    else
        update_progress \
            "$NODE" \
            "Post-Reboot Validation Failed" \
            "100" \
            "FAILED"
        return 1
    fi

else

    update_progress \
        "$NODE" \
        "Reboot Validation Failed" \
        "100" \
        "FAILED"

    return 1
fi


return 0
}

# -----------------------------------------------------------------------------
# ARGUMENT PARSING
# -----------------------------------------------------------------------------

NODES_INPUT=""

for arg in "$@"
do
    case "$arg" in
        --node=*)
            NODES_INPUT="${arg#*=}"
            ;;
        *)
            display_usage
            ;;
    esac
done

if [ -z "$NODES_INPUT" ]
then
    echo "ERROR: Missing --node argument"
    display_usage
fi

IFS=',' read -r -a TARGET_NODES <<< "$NODES_INPUT"

# -----------------------------------------------------------------------------
# PRECHECKS
# -----------------------------------------------------------------------------

install_sshpass() {

    if command -v sshpass >/dev/null 2>&1
    then
        return 0
    fi

    echo
    echo "[INFO] sshpass not found. Creating temporary local repository..."
    echo

cat >/etc/yum.repos.d/patch.repo <<EOF
[patch]
name=patch-repo
baseurl=http://http-server-01/repo/installed_rhel7
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/base.repo <<EOF
[base]
name=base-repo
baseurl=http://http-server-01/repo/centos/
enabled=1
gpgcheck=0
EOF

yum clean all >/dev/null 2>&1

yum makecache \
    --disablerepo='*' \
    --enablerepo=base,patch >/dev/null 2>&1

yum install -y \
    --disablerepo='*' \
    --enablerepo=base,patch \
    sshpass

    RC=$?

    rm -f /etc/yum.repos.d/base.repo
	rm -f /etc/yum.repos.d/patch.repo

    yum clean all >/dev/null 2>&1

    if [ $RC -ne 0 ] || ! command -v sshpass >/dev/null 2>&1
    then
        echo
        echo "[ERROR] Failed to install sshpass"
        exit 1
    fi

    echo
    echo "[OK] sshpass installed successfully"
    echo
}

install_sshpass
# -----------------------------------------------------------------------------
# DASHBOARD STARTUP
# -----------------------------------------------------------------------------

init_dashboard_nodes
start_dashboard

# -----------------------------------------------------------------------------
# TEST EXECUTION LOOP
# -----------------------------------------------------------------------------
# TEMPORARY
# This simulates patch progress until real worker integration is added
# Remove this section in Task 4

declare -a WORKER_PIDS=()

for NODE in "${TARGET_NODES[@]}"
do

(
    patch_remote_node "$NODE"
) &

WORKER_PIDS+=($!)

done

OVERALL_RC=0

for PID in "${WORKER_PIDS[@]}"
do
    wait "$PID" || OVERALL_RC=1
done

sleep 2

stop_dashboard
rm -rf "$PROGRESS_DIR"

exit $OVERALL_RC
