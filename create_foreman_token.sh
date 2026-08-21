#!/bin/bash

TOKEN_NAME="ansible-api-token"
TOKEN_VALUE="_bkE_ov7gKb68d3aR01m5A"
FOREMAN_USER="admin"

foreman-rake console <<EOF
user = User.find_by(login: '${FOREMAN_USER}')

if user.nil?
  puts "ERROR: Foreman user '${FOREMAN_USER}' not found"
  exit 1
end

existing = PersonalAccessToken.find_by(token: '${TOKEN_VALUE}')

if existing
  puts "TOKEN ALREADY EXISTS"
  puts "Name    : #{existing.name}"
  puts "User    : #{existing.user.login}"
  puts "Revoked : #{existing.revoked}"
else
  token = PersonalAccessToken.create!(
    user: user,
    name: '${TOKEN_NAME}',
    token: '${TOKEN_VALUE}',
    revoked: false
  )

  puts "============================================"
  puts "FOREMAN API TOKEN CREATED SUCCESSFULLY"
  puts "============================================"
  puts "User  : #{token.user.login}"
  puts "Name  : #{token.name}"
  puts "Token : #{token.token}"
  puts "============================================"
end
EOF
