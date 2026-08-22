#!/bin/bash
#
#DELETION COMMAND BELOW
#foreman-rake console -s 'user=User.find_by!(login:"admin"); PersonalAccessToken.where(user:user,name:"admin").destroy_all; puts "ADMIN TOKEN DELETED"'
#user=User.find_by!(login:"admin"); PersonalAccessToken.where(user:user,name:"admin").destroy_all; puts "ADMIN TOKEN DELETED"
#puts PersonalAccessToken.where(user:user,name:"admin").count
#exit
# ============================================================
# FOREMAN CUSTOM PERSONAL ACCESS TOKEN CREATOR
# ============================================================
# Creates this exact API credential:
#
#   Username : admin
#   Token    : _bkE_ov7gKb68d3aR01m5A
#
# Authentication:
#   curl -k -u "admin:_bkE_ov7gKb68d3aR01m5A" ...
#
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

FOREMAN_URL="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"

TOKEN_NAME="admin"
TOKEN_VALUE="_bkE_ov7gKb68d3aR01m5A"

TOKEN_FILE="/root/foreman_api_token.env"

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

header() {
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

# ------------------------------------------------------------
# PRECHECKS
# ------------------------------------------------------------

header "FOREMAN CUSTOM PERSONAL ACCESS TOKEN CREATOR"

if [[ "${EUID}" -ne 0 ]]; then
    error "Run this script as root."
    exit 1
fi

if ! command -v foreman-rake >/dev/null 2>&1; then
    error "foreman-rake command not found."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    error "curl command not found."
    exit 1
fi

info "Foreman URL  : ${FOREMAN_URL}"
info "Foreman User : ${FOREMAN_USER}"
info "Token Name   : ${TOKEN_NAME}"
info "Token Value  : ${TOKEN_VALUE}"

# ------------------------------------------------------------
# CREATE / RECREATE CUSTOM TOKEN
# ------------------------------------------------------------

header "STEP 1 - CREATING CUSTOM FOREMAN PAT"

FOREMAN_OUTPUT=$(
foreman-rake console <<RUBY
user = User.find_by(login: '${FOREMAN_USER}')

if user.nil?
  puts "RESULT=ERROR"
  puts "MESSAGE=Foreman user '${FOREMAN_USER}' not found"
  exit
end

custom_token = '${TOKEN_VALUE}'

# Find existing token with this name
existing = PersonalAccessToken.where(
  user: user,
  name: '${TOKEN_NAME}'
).first

if existing
  existing_hash = PersonalAccessToken.hash_token(
    user,
    custom_token,
    :bcrypt
  )

  if existing.token == existing_hash &&
     existing.revoked == false &&
     existing.expires_at.nil?

    puts "RESULT=EXISTS_VALID"
    puts "TOKEN_ID=#{existing.id}"
    puts "TOKEN_NAME=#{existing.name}"
    puts "TOKEN_USER=#{existing.user.login}"

  else

    existing.destroy!

    token = PersonalAccessToken.create!(
      user: user,
      name: '${TOKEN_NAME}',
      token: PersonalAccessToken.hash_token(
        user,
        custom_token,
        :bcrypt
      ),
      revoked: false,
      expires_at: nil
    )

    puts "RESULT=RECREATED"
    puts "TOKEN_ID=#{token.id}"
    puts "TOKEN_NAME=#{token.name}"
    puts "TOKEN_USER=#{token.user.login}"
  end

else

  token = PersonalAccessToken.create!(
    user: user,
    name: '${TOKEN_NAME}',
    token: PersonalAccessToken.hash_token(
      user,
      custom_token,
      :bcrypt
    ),
    revoked: false,
    expires_at: nil
  )

  puts "RESULT=CREATED"
  puts "TOKEN_ID=#{token.id}"
  puts "TOKEN_NAME=#{token.name}"
  puts "TOKEN_USER=#{token.user.login}"
end

# Internal authentication verification
if PersonalAccessToken.authenticate_user(user, custom_token)
  puts "AUTH_TEST=SUCCESS"
else
  puts "AUTH_TEST=FAILED"
end
RUBY
)

echo "${FOREMAN_OUTPUT}"

# ------------------------------------------------------------
# CHECK INTERNAL RESULT
# ------------------------------------------------------------

if echo "${FOREMAN_OUTPUT}" | grep -q '^RESULT=ERROR'; then
    error "Failed to create Foreman PAT."
    exit 1
fi

if echo "${FOREMAN_OUTPUT}" | grep -q '^AUTH_TEST=FAILED'; then
    error "Internal Foreman PAT authentication test failed."
    exit 1
fi

if ! echo "${FOREMAN_OUTPUT}" | grep -q '^AUTH_TEST=SUCCESS'; then
    error "Unable to verify internal PAT authentication."
    exit 1
fi

RESULT=$(echo "${FOREMAN_OUTPUT}" | grep '^RESULT=' | tail -1 | cut -d= -f2)

case "${RESULT}" in
    CREATED)
        ok "Custom Foreman PAT created successfully."
        ;;
    RECREATED)
        ok "Existing token replaced successfully."
        ;;
    EXISTS_VALID)
        ok "Existing custom token is already valid."
        ;;
    *)
        error "Unexpected token creation result: ${RESULT}"
        exit 1
        ;;
esac

ok "Internal Foreman authentication test successful."

# ------------------------------------------------------------
# SAVE TOKEN CONFIGURATION
# ------------------------------------------------------------

header "STEP 2 - SAVING API CREDENTIALS"

umask 077

cat > "${TOKEN_FILE}" <<EOF
# ============================================================
# Foreman API Credentials
# Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
# ============================================================

export FOREMAN_URL="${FOREMAN_URL}"
export FOREMAN_USER="${FOREMAN_USER}"
export FOREMAN_TOKEN="${TOKEN_VALUE}"
EOF

chmod 600 "${TOKEN_FILE}"

ok "Credentials saved successfully."
info "File        : ${TOKEN_FILE}"
info "Permissions : $(stat -c '%a' "${TOKEN_FILE}")"

# ------------------------------------------------------------
# EXTERNAL API TEST
# ------------------------------------------------------------

header "STEP 3 - TESTING FOREMAN API"

TEST_FILE=$(mktemp)

HTTP_CODE=$(
    curl -k \
        -sS \
        -o "${TEST_FILE}" \
        -w "%{http_code}" \
        -u "${FOREMAN_USER}:${TOKEN_VALUE}" \
        -H "Accept: version=2,application/json" \
        "${FOREMAN_URL}/api/status"
)

if [[ "${HTTP_CODE}" == "200" ]]; then
    ok "FOREMAN API AUTHENTICATION SUCCESSFUL."
    echo
    cat "${TEST_FILE}"
    echo
else
    error "FOREMAN API AUTHENTICATION FAILED."
    echo "HTTP Status: ${HTTP_CODE}"
    echo
    cat "${TEST_FILE}" 2>/dev/null || true
    echo
    rm -f "${TEST_FILE}"
    exit 1
fi

rm -f "${TEST_FILE}"

# ------------------------------------------------------------
# SMART PROXY TEST
# ------------------------------------------------------------

header "STEP 4 - TESTING SMART PROXIES API"

TEST_FILE=$(mktemp)

HTTP_CODE=$(
    curl -k \
        -sS \
        -o "${TEST_FILE}" \
        -w "%{http_code}" \
        -u "${FOREMAN_USER}:${TOKEN_VALUE}" \
        -H "Accept: version=2,application/json" \
        "${FOREMAN_URL}/api/smart_proxies"
)

if [[ "${HTTP_CODE}" == "200" ]]; then
    ok "SMART PROXIES API AUTHENTICATION SUCCESSFUL."
    echo
    cat "${TEST_FILE}"
    echo
else
    error "SMART PROXIES API TEST FAILED."
    echo "HTTP Status: ${HTTP_CODE}"
    echo
    cat "${TEST_FILE}" 2>/dev/null || true
    echo
    rm -f "${TEST_FILE}"
    exit 1
fi

rm -f "${TEST_FILE}"

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

header "FOREMAN CUSTOM PAT CONFIGURATION COMPLETE"

echo "Status       : SUCCESS"
echo "Foreman URL  : ${FOREMAN_URL}"
echo "Username     : ${FOREMAN_USER}"
echo "Token Name   : ${TOKEN_NAME}"
echo "Token File   : ${TOKEN_FILE}"
echo
echo "API Authentication:"
echo
echo "  Username : ${FOREMAN_USER}"
echo "  Token    : ${TOKEN_VALUE}"
echo
echo "Example:"
echo
echo "curl -k -u '${FOREMAN_USER}:${TOKEN_VALUE}' \\"
echo "  -H 'Accept: version=2,application/json' \\"
echo "  '${FOREMAN_URL}/api/smart_proxies'"
echo
echo "============================================================"
