#!/bin/bash
###############################################################################
# common.sh
#
# Common utility functions for Foreman/Katello Bootstrap
###############################################################################

###############################################################################
# Check if command exists
###############################################################################

check_command() {

    local CMD="$1"

    if command -v "$CMD" >/dev/null 2>&1
    then
        log_success "$CMD found"
    else
        log_error "$CMD is not installed"
        exit 1
    fi
}

###############################################################################
# Verify Foreman API connectivity
###############################################################################

check_foreman() {

    log_info "Connecting to Foreman..."

    if $CURL \
        --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
        "${FOREMAN_URL}/api/status" \
        >/dev/null 2>&1
    then
        log_success "Foreman API reachable"
    else
        log_error "Unable to connect to Foreman API"
        exit 1
    fi
}

###############################################################################
# Verify Repository Server
###############################################################################

check_repo_server() {

    log_info "Checking repository server..."

    if curl -ks --connect-timeout 5 "${HTTP_SERVER}" >/dev/null
    then
        log_success "Repository server reachable"
    else
        log_error "Repository server not reachable"
        exit 1
    fi
}

###############################################################################
# Verify Smart Proxies
###############################################################################

check_smart_proxies() {

    log_info "Checking Smart Proxies..."

    if $HAMMER proxy list | grep -q "$CENTOS_PROXY"
    then
        log_success "$CENTOS_PROXY found"
    else
        log_warn "$CENTOS_PROXY not found"
    fi

    if $HAMMER proxy list | grep -q "$ROCKY_PROXY"
    then
        log_success "$ROCKY_PROXY found"
    else
        log_warn "$ROCKY_PROXY not found"
    fi
}

###############################################################################
# Verify Organization
###############################################################################

check_organization() {

    if $HAMMER organization list | awk '{print $2,$3,$4}' | \
        grep -Fxq "$ORG"
    then
        log_success "Organization exists: $ORG"
    else
        log_error "Organization not found: $ORG"
        exit 1
    fi
}

###############################################################################
# Verify Location
###############################################################################

check_location() {

    if $HAMMER location list | grep -Fq "$LOCATION"
    then
        log_success "Location exists: $LOCATION"
    else
        log_warn "Location not found: $LOCATION"
    fi
}

###############################################################################
# Verify Domain
###############################################################################

check_domain() {

    if $HAMMER domain list | grep -Fq "$DOMAIN"
    then
        log_success "Domain exists: $DOMAIN"
    else
        log_warn "Domain not found: $DOMAIN"
    fi
}

###############################################################################
# Verify Architecture
###############################################################################

check_architecture() {

    if $HAMMER architecture list | grep -Fq "$ARCH"
    then
        log_success "Architecture exists: $ARCH"
    else
        log_error "Architecture missing: $ARCH"
        exit 1
    fi
}

###############################################################################
# Verify Partition Table
###############################################################################

check_partition_table() {

    if $HAMMER partition-table list | grep -Fq "$PARTITION_TABLE"
    then
        log_success "Partition table exists"
    else
        log_error "Partition table missing"
        exit 1
    fi
}

###############################################################################
# Verify Lifecycle Environment
###############################################################################

check_lifecycle() {

    if $HAMMER lifecycle-environment list \
        --organization "$ORG" \
        | grep -Fq "$LIFECYCLE"
    then
        log_success "Lifecycle Environment exists"
    else
        log_error "Lifecycle Environment missing"
        exit 1
    fi
}

###############################################################################
# Verify Content View
###############################################################################

check_content_view() {

    local CV="$1"

    if $HAMMER content-view list \
        --organization "$ORG" \
        | grep -Fq "$CV"
    then
        log_success "Content View exists: $CV"
    else
        log_warn "Content View missing: $CV"
    fi
}

###############################################################################
# Verify Product
###############################################################################

check_product() {

    local PRODUCT="$1"

    if $HAMMER product list \
        --organization "$ORG" \
        | grep -Fq "$PRODUCT"
    then
        log_success "Product exists: $PRODUCT"
    else
        log_warn "Product missing: $PRODUCT"
    fi
}

###############################################################################
# Verify Repository
###############################################################################

check_repository() {

    local PRODUCT="$1"
    local REPO="$2"

    if $HAMMER repository list \
        --organization "$ORG" \
        --product "$PRODUCT" \
        | grep -Fq "$REPO"
    then
        log_success "Repository exists: $REPO"
    else
        log_warn "Repository missing: $REPO"
    fi
}

###############################################################################
# Wait for Foreman API
###############################################################################

wait_for_foreman() {

    log_info "Waiting for Foreman API..."

    local COUNT=0

    until $CURL \
        --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
        "${FOREMAN_URL}/api/status" \
        >/dev/null 2>&1
    do
        sleep 5

        COUNT=$((COUNT + 1))

        if [[ $COUNT -ge 24 ]]
        then
            log_error "Foreman did not become ready within 2 minutes."
            exit 1
        fi
    done

    log_success "Foreman is ready"
}

###############################################################################
# End of Part 1D-1
###############################################################################

###############################################################################
# Part 1D-2
#
# Generic Hammer Helper Functions
###############################################################################

###############################################################################
# Execute Hammer Command
###############################################################################

hammer_exec() {

    local CMD="$*"

    log_info "$HAMMER $CMD"

    if $HAMMER $CMD >>"$LOG_FILE" 2>&1
    then
        return 0
    else
        log_error "Hammer command failed"

        echo
        echo "$HAMMER $CMD"
        echo

        return 1
    fi
}

###############################################################################
# Generic CSV Search
###############################################################################

csv_exists() {

    local CMD="$1"
    local VALUE="$2"

    eval "$HAMMER $CMD --csv" 2>/dev/null \
        | awk -F',' -v v="$VALUE" '
            NR>1 {
                for(i=1;i<=NF;i++)
                    if($i==v){found=1}
            }
            END{exit !found}
        '
}

###############################################################################
# Return ID from CSV
###############################################################################

csv_get_id() {

    local CMD="$1"
    local VALUE="$2"

    eval "$HAMMER $CMD --csv" 2>/dev/null \
        | awk -F',' -v v="$VALUE" '
            NR>1{
                for(i=2;i<=NF;i++)
                    if($i==v){
                        print $1
                        exit
                    }
            }
        '
}

###############################################################################
# Generic Object Exists
###############################################################################

object_exists() {

    local CMD="$1"
    local NAME="$2"

    csv_exists "$CMD" "$NAME"
}

###############################################################################
# Require Object
###############################################################################

require_object() {

    local CMD="$1"
    local NAME="$2"

    if object_exists "$CMD" "$NAME"
    then
        log_success "$NAME already exists"
        return 0
    fi

    return 1
}

###############################################################################
# Create Object
###############################################################################

create_object() {

    local CHECK_CMD="$1"
    local NAME="$2"

    shift 2

    if require_object "$CHECK_CMD" "$NAME"
    then
        return 0
    fi

    log_info "Creating $NAME"

    hammer_exec "$*"
}

###############################################################################
# Wait Until Object Exists
###############################################################################

wait_for_object() {

    local CMD="$1"
    local NAME="$2"

    local WAIT=0

    until object_exists "$CMD" "$NAME"
    do
        sleep 2

        WAIT=$((WAIT+2))

        if [[ $WAIT -gt 120 ]]
        then
            log_error "Timed out waiting for $NAME"
            exit 1
        fi
    done

    log_success "$NAME available"
}

###############################################################################
# Repository Synchronization Wait
###############################################################################

wait_for_sync() {

    local PRODUCT="$1"
    local REPO="$2"

    log_info "Waiting for repository synchronization..."

    while true
    do

        STATUS=$(
            $HAMMER repository info \
                --organization "$ORG" \
                --product "$PRODUCT" \
                --name "$REPO" |
                awk -F': ' '/Sync State/{print $2}'
        )

        case "$STATUS" in

            Finished*)
                log_success "$REPO synchronized"
                break
                ;;

            Failed*)
                log_error "$REPO synchronization failed"
                exit 1
                ;;

            *)
                sleep 10
                ;;
        esac

    done

}

###############################################################################
# Get Object IDs
###############################################################################

get_os_id() {

    csv_get_id "os list" "$1"

}

get_template_id() {

    csv_get_id "template list" "$1"

}

get_product_id() {

    csv_get_id \
        "product list --organization \"$ORG\"" \
        "$1"

}

get_repository_id() {

    local PRODUCT="$1"
    local REPO="$2"

    csv_get_id \
        "repository list --organization \"$ORG\" --product \"$PRODUCT\"" \
        "$REPO"

}

get_content_view_id() {

    csv_get_id \
        "content-view list --organization \"$ORG\"" \
        "$1"

}

get_activation_key_id() {

    csv_get_id \
        "activation-key list --organization \"$ORG\"" \
        "$1"

}

###############################################################################
# Retry Wrapper
###############################################################################

retry() {

    local COUNT=1
    local MAX=5

    until "$@"
    do

        if [[ $COUNT -ge $MAX ]]
        then
            return 1
        fi

        COUNT=$((COUNT+1))

        sleep 5

    done

    return 0
}

###############################################################################
# End Part 1D-2
###############################################################################
