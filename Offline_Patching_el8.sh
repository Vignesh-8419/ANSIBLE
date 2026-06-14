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
    echo "  --node=    Comma-separated list of IP addresses or hostnames to patch."
    echo "             Use 'localhost' to include the master server."
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
    # Quoting 'EOF' prevents local master server bash shell expansion errors over SSH
    cat << 'EOF'
        set -e

        log_node_info() { echo -e "${COLOR_INFO}  -> [INFO] $1${COLOR_RESET}"; }
        log_node_ok()   { echo -e "${COLOR_OK}  -> [OK] $1${COLOR_RESET}"; }
        log_node_fail() { echo -e "${COLOR_FAIL}  -> [FAIL] $1${COLOR_RESET}"; }

        log_node_info "Kernel Release: $(uname -r)"

        # 1. Backup original repositories
        log_node_info "Backing up original repositories..."
        mkdir -p /etc/yum.repos.d/${BACKUP_DIR_NAME}
        
        if ls /etc/yum.repos.d/*.repo &>/dev/null; then
            find /etc/yum.repos.d/ -maxdepth 1 -type f -name "*.repo" -exec mv {} /etc/yum.repos.d/${BACKUP_DIR_NAME}/ \;
        fi
        log_node_ok "Repository backup saved to /etc/yum.repos.d/${BACKUP_DIR_NAME}/"

        # 2. Check and Mount CIFS Share
        log_node_info "Checking network ISO share mount status..."
        mkdir -p ${MOUNT_POINT}
        
        if ! findmnt -rn ${MOUNT_POINT} > /dev/null; then
            log_node_info "ISO share not detected. Mounting target volume..."
            mount -t cifs "${REPO_MOUNT}" "${MOUNT_POINT}" \
                -o username="${CIFS_USER}",password="${CIFS_PASS}",rw,dir_mode=0777,file_mode=0777,vers=3.0 || {
                    log_node_fail "Mount failed! Restoring original repos before exit..."
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

        # 3. Create Offline Repo Configurations
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

        # 4. Patch Execution with real-time streaming and dependency relaxation
        log_node_info "Flushing package manager tracking logs..."
        dnf clean all > /dev/null
        
        log_node_info "Starting structural system patching (Streaming live progress)..."
        
        TMP_LOG=$(mktemp)
        
        set +e
        # Using global exclusions explicitly to stop chasing the lagging baseline packages cleanly
        dnf update -y --allowerasing --nobest -x glibc*,libstdc++*,perl*,gcc* 2>&1 | tee "$TMP_LOG"
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

        # 5. Restore Environment & Unmount
        log_node_info "Initiating system baseline rollback operations..."
        
        # Explicit target cleanup ensures isolation
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

        log_node_info "Detaching shared ISO repository volume..."
        umount -l ${MOUNT_POINT} || true
        log_node_ok "Volume unmounted."

        # 6. Reboot Strategy Handling
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

for NODE in "${TARGET_NODES[@]}"; do
    NODE=$(echo "$NODE" | xargs)
    print_header "PROCESSING AGENT NODE: ${NODE}"
    
    EXPORT_ENV="COLOR_INFO='${COLOR_INFO}' COLOR_OK='${COLOR_OK}' COLOR_FAIL='${COLOR_FAIL}' COLOR_BLUE='${COLOR_BLUE}' COLOR_RESET='${COLOR_RESET}' REPO_MOUNT='${REPO_MOUNT}' MOUNT_POINT='${MOUNT_POINT}' CIFS_USER='${CIFS_USER}' CIFS_PASS='${CIFS_PASS}' BACKUP_DIR_NAME='${BACKUP_DIR_NAME}'"

    if [ "$NODE" = "localhost" ] || [ "$NODE" = "127.0.0.1" ]; then
        log_info "Executing local lifecycle loop operations on Master Server directly..."
        if eval "$EXPORT_ENV; $(node_lifecycle_worker)"; then
            log_ok "Master Server patching pipeline executed cleanly."
        else
            log_fail "Master Server update run experienced an execution fault."
        fi
    else
        log_info "Connecting to remote system node via SSH: ${NODE}..."
        
        if sshpass -p "${SSH_PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "${SSH_USER}@${NODE}" "$EXPORT_ENV bash -s" << EOF
$(node_lifecycle_worker)
EOF
        then
            log_ok "Node Execution Workflow completed for system target: ${NODE}"
        else
            log_fail "Critical communication or process breakdown observed on Node target: ${NODE}"
        fi
    fi
    echo ""
done

print_header "COMPLETED SYSTEM PATCHING ORCHESTRATION PROFILE SUMMARY"
