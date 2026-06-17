#!/bin/bash

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
REPO_MOUNT="//192.168.31.87/ISO"
MOUNT_POINT="/var/www/html/repo"
CIFS_USER="vigne"
CIFS_PASS='Vigneshv12$'

# Target Server Credentials (SSH/SSHPASS)
SSH_USER="root"
SSH_PASS='Root@123'

# Backup directory name inside /etc/yum.repos.d/
BACKUP_DIR_NAME="backup_repos_original"

# NEW: Synced default gateway configuration from variables
DEFAULT_GW="192.168.253.2"

# -----------------------------------------------------------------------------
# COLOR DEFINITIONS
# -----------------------------------------------------------------------------
COLOR_INFO='\033[1;33m'   # Yellow
COLOR_OK='\033[0;32m'     # Green
COLOR_FAIL='\033[0;31m'    # Red
COLOR_BLUE='\033[0;34m'   # Blue
COLOR_RESET='\033[0m'     # Reset

log_info() { echo -e "${COLOR_INFO}[INFO] $1${COLOR_RESET}"; }
log_ok()   { echo -e "${COLOR_OK}[OK] $1${COLOR_RESET}"; }
log_fail() { echo -e "${COLOR_FAIL}[FAIL] $1${COLOR_RESET}"; }
log_blue() { echo -e "${COLOR_BLUE}$1${COLOR_RESET}"; }

print_header() {
    local title="$1"
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}  $title ${COLOR_RESET}"
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
}

display_usage() {
    echo "Usage: $0 --node=<node1,node2,localhost,...>"
    echo ""
    echo "Options:"
    echo "  --node=      Comma-separated list of IP addresses or hostnames to patch."
    echo "               Use 'localhost' to include the master server."
    echo ""
    echo "Example:"
    echo "  $0 --node=192.168.253.10,192.168.253.11,localhost"
    exit 1
}

# -----------------------------------------------------------------------------
# ARGUMENT PARSING
# -----------------------------------------------------------------------------
NODES_INPUT=""

for arg in "$@"; do
    case $arg in
        --node=*)
            NODES_INPUT="${arg#*=}"
            shift
            ;;
        *)
            display_usage
            ;;
    esac
done

if [ -z "$NODES_INPUT" ]; then
    log_fail "Missing required argument: --node"
    display_usage
fi

IFS=',' read -r -a TARGET_NODES <<< "$NODES_INPUT"

if ! command -v sshpass &> /dev/null; then
    log_fail "sshpass tool is not installed on the master server. Run 'dnf install sshpass' first."
    exit 1
fi

# -----------------------------------------------------------------------------
# THE TARGET CORE ENGINE (INJECTED WORKER)
# -----------------------------------------------------------------------------
node_lifecycle_worker() {
    cat << 'EOF'
        set -e

        log_node_info() { echo -e "${COLOR_INFO}  -> [INFO] $1${COLOR_RESET}"; }
        log_node_ok()   { echo -e "${COLOR_OK}  -> [OK] $1${COLOR_RESET}"; }
        log_node_fail() { echo -e "${COLOR_FAIL}  -> [FAIL] $1${COLOR_RESET}"; }

        # --- NEW PRE-TASK: GATEWAY CHECK ---
        log_node_info "Verifying Network Topology Routes..."
        if ! ip route show | grep -q '^default'; then
            log_node_info "Default gateway missing! Dynamically appending fallback via ${DEFAULT_GW}..."
            ip route add default via "${DEFAULT_GW}"
            log_node_ok "Fallback route appended successfully."
        else
            log_node_ok "Valid structural network gateway already present."
        fi

        log_node_info "Kernel Release: $(uname -r)"

        log_node_info "Backing up original repositories..."
        mkdir -p /etc/yum.repos.d/${BACKUP_DIR_NAME}
        
        if ls /etc/yum.repos.d/*.repo &>/dev/null; then
            find /etc/yum.repos.d/ -maxdepth 1 -type f -name "*.repo" -exec mv {} /etc/yum.repos.d/${BACKUP_DIR_NAME}/ \;
        fi
        log_node_ok "Repository backup saved to /etc/yum.repos.d/${BACKUP_DIR_NAME}/"

        log_node_info "Checking network ISO share mount status..."
        mkdir -p ${MOUNT_POINT}
        
        if ! findmnt -rn ${MOUNT_POINT} > /dev/null; then
            log_node_info "ISO share not detected. Mounting target volume..."
            
            # FIXED: Also add entry to /etc/fstab to replicate what ansible.posix.mount does
            echo "${REPO_MOUNT} ${MOUNT_POINT} cifs username=${CIFS_USER},password=${CIFS_PASS},rw,dir_mode=0777,file_mode=0777,vers=3.0 0 0" >> /etc/fstab
            
            mount "${MOUNT_POINT}" || {
                log_node_fail "Mount failed! Stripping invalid fstab config and restoring profiles..."
                sed -i "\#${MOUNT_POINT}#d" /etc/fstab
                if [ -d "/etc/yum.repos.d/${BACKUP_DIR_NAME}" ]; then
                    if ls /etc/yum.repos.d/${BACKUP_DIR_NAME}/*.repo &>/dev/null; then
                        mv /etc/yum.repos.d/${BACKUP_DIR_NAME}/*.repo /etc/yum.repos.d/
                    fi
                    rmdir /etc/yum.repos.d/${BACKUP_DIR_NAME}
                fi
                exit 1
            }
            log_node_ok "Mount successful."
        else
            log_node_ok "ISO share is already actively mounted."
        fi

        log_node_info "Generating localized offline repository files..."

        cat <<REPO_EOF > /etc/yum.repos.d/rocky8-baseos.repo
[rocky8-baseos]
name=Rocky Linux 8 BaseOS
baseurl=file://${MOUNT_POINT}/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
REPO_EOF

        cat <<REPO_EOF > /etc/yum.repos.d/rocky8-appstream.repo
[rocky8-appstream]
name=Rocky Linux 8 AppStream
baseurl=file://${MOUNT_POINT}/rocky8/AppStream
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
REPO_EOF

        cat <<REPO_EOF > /etc/yum.repos.d/rocky8-rhel-installed.repo
[rocky8-rhel-installed]
name=Rocky Linux 8 Installed RHEL
baseurl=file://${MOUNT_POINT}/installed_rhel8
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
REPO_EOF

        log_node_ok "Temporary repository configuration profiles applied."

        log_node_info "Flushing package manager tracking logs..."
        dnf clean all > /dev/null
        
        log_node_info "Building isolated local metadata cache..."
        dnf makecache --disablerepo=* --enablerepo=rocky8-baseos,rocky8-appstream,rocky8-rhel-installed > /dev/null

        log_node_info "Starting structural system patching..."
        
        TMP_LOG=$(mktemp)
        set +e
        dnf update -y --disablerepo=* --enablerepo=rocky8-baseos,rocky8-appstream,rocky8-rhel-installed --allowerasing --nobest -x glibc*,libstdc++*,perl*,gcc* 2>&1 | tee "$TMP_LOG"
        DNF_EXIT_CODE=${PIPESTATUS[0]}
        set -e

        PATCH_OUTPUT=$(cat "$TMP_LOG")
        rm -f "$TMP_LOG"

        if [ $DNF_EXIT_CODE -ne 0 ]; then
            log_node_fail "DNF transaction failed with exit status $DNF_EXIT_CODE. Aborting patch cycle to prevent damage."
            NEEDS_REBOOT=false
        else
            if echo "$PATCH_OUTPUT" | grep -qE "Installed:|Upgraded:|Updated:|Verifying"; then
                NEEDS_REBOOT=true
                log_node_ok "System patches applied successfully."
            else
                NEEDS_REBOOT=false
                log_node_info "No updates required. Node packages match repository snapshot exactly."
            fi
        fi

        log_node_info "Initiating system baseline rollback operations..."
        rm -f /etc/yum.repos.d/rocky8-baseos.repo \
              /etc/yum.repos.d/rocky8-appstream.repo \
              /etc/yum.repos.d/rocky8-rhel-installed.repo
        
        if [ -d "/etc/yum.repos.d/${BACKUP_DIR_NAME}" ]; then
            if ls /etc/yum.repos.d/${BACKUP_DIR_NAME}/*.repo &>/dev/null; then
                mv /etc/yum.repos.d/${BACKUP_DIR_NAME}/*.repo /etc/yum.repos.d/
            fi
            rmdir /etc/yum.repos.d/${BACKUP_DIR_NAME}
            log_node_ok "Original production repositories restored successfully."
        else
            log_node_fail "Backup repository directory not found! Tracking integrity anomaly."
        fi

        log_node_info "Detaching shared ISO repository volume cleanly..."
        umount -l ${MOUNT_POINT} || true
        
        # FIXED: Cleans out the mount point mapping string from /etc/fstab completely (Replicates state: absent)
        sed -i "\#${MOUNT_POINT}#d" /etc/fstab
        log_node_ok "Volume unmounted and clean fstab lifecycle verification complete."

        if [ "$NEEDS_REBOOT" = true ]; then
            log_node_ok "Reboot required. Scheduling system reboot in 1 minute..."
            shutdown -r +1 "Automated offline patching cycle completed. System rebooting." &
        else
            if [ $DNF_EXIT_CODE -ne 0 ]; then
                log_node_fail "Node run halted due to earlier errors. Check the logs above."
                exit 1
            else
                log_node_ok "No reboot lifecycle required for this node. Process Complete."
            fi
        fi
EOF
}

# -----------------------------------------------------------------------------
# RUN ORCHESTRATION PIPELINE
# -----------------------------------------------------------------------------
print_header "OFFLINE INFRASTRUCTURE PATCHING ORCHESTRATOR"
log_info "Targeting nodes: ${TARGET_NODES[*]}"
echo ""

LOG_DIR=$(mktemp -d)
declare -A NODE_PIDS

# 1. Touch all log files first so they exist immediately for our stream engine
for NODE in "${TARGET_NODES[@]}"; do
    NODE=$(echo "$NODE" | xargs)
    touch "${LOG_DIR}/${NODE}.log"
done

# 2. Start the Live Stream Engine in the background
log_info "Initializing live tracking streams..."
echo "----------------------------------------------------------------------"
tail -q -f "${LOG_DIR}"/*.log | while read -r line; do
    echo -e "$line"
done &
STREAM_PID=$!

# 3. Dispatch the Parallel Node Operations
for NODE in "${TARGET_NODES[@]}"; do
    NODE=$(echo "$NODE" | xargs)
    
    (
        NODE_LOG="${LOG_DIR}/${NODE}.log"
        {
            echo -e "${COLOR_BLUE}[$NODE] ${COLOR_RESET}======================================================================"
            echo -e "${COLOR_BLUE}[$NODE] PROCESSING AGENT NODE WORKFLOW${COLOR_RESET}"
            echo -e "${COLOR_BLUE}[$NODE] ======================================================================"
            
            # FIXED: Added DEFAULT_GW into the exported environmental layer passing down to the worker
            EXPORT_ENV="COLOR_INFO='${COLOR_INFO}' COLOR_OK='${COLOR_OK}' COLOR_FAIL='${COLOR_FAIL}' COLOR_BLUE='${COLOR_BLUE}' COLOR_RESET='${COLOR_RESET}' REPO_MOUNT='${REPO_MOUNT}' MOUNT_POINT='${MOUNT_POINT}' CIFS_USER='${CIFS_USER}' CIFS_PASS='${CIFS_PASS}' BACKUP_DIR_NAME='${BACKUP_DIR_NAME}' DEFAULT_GW='${DEFAULT_GW}'"

            if [ "$NODE" = "localhost" ] || [ "$NODE" = "127.0.0.1" ]; then
                if eval "$EXPORT_ENV; $(node_lifecycle_worker)" 2>&1 | sed "s/^/\x1b[0;34m[$NODE]\x1b[0m /"; then
                    exit 0
                else
                    exit 1
                fi
            else
                if sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "${SSH_USER}@${NODE}" "$EXPORT_ENV bash -s" << EOF 2>&1 | sed "s/^/\x1b[0;34m[$NODE]\x1b[0m /"
$(node_lifecycle_worker)
EOF
                then
                    exit 0
                else
                    exit 1
                fi
            fi
        } >> "$NODE_LOG"
    ) &
    NODE_PIDS["$NODE"]=$!
done

# 4. Wait for all target systems to finish tasks
declare -A NODE_STATUSES
for NODE in "${!NODE_PIDS[@]}"; do
    PID=${NODE_PIDS[$NODE]}
    wait "$PID"
    NODE_STATUSES["$NODE"]=$?
done

# Stop the background log viewer stream engine safely
sleep 1
kill "$STREAM_PID" 2>/dev/null
wait "$STREAM_PID" 2>/dev/null
echo ""

# 5. Output Summary Table
print_header "COMPLETED SYSTEM PATCHING ORCHESTRATION PROFILE SUMMARY"
printf "%-35s | %-10s\n" "NODE TARGET" "STATUS"
echo "----------------------------------------------------------------------"
for NODE in "${TARGET_NODES[@]}"; do
    NODE=$(echo "$NODE" | xargs)
    STATUS_CODE=${NODE_STATUSES["$NODE"]}
    if [ "$STATUS_CODE" -eq 0 ]; then
        printf "%-35s | ${COLOR_OK}SUCCESS${COLOR_RESET}\n" "$NODE"
    else
        printf "%-35s | ${COLOR_FAIL}FAILED (Exit: %s)${COLOR_RESET}\n" "$NODE" "$STATUS_CODE"
    fi
done
echo "----------------------------------------------------------------------"

rm -rf "$LOG_DIR"
