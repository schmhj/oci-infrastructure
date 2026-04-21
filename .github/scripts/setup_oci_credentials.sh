#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Validate required environment variables
require_env "OCI_TENANCY"
require_env "OCI_USER"
require_env "OCI_FINGERPRINT"
require_env "OCI_PRIVATE_KEY"

REGION="${OCI_REGION:-$DEFAULT_REGION}"
if [ -z "$REGION" ]; then
  fail "No OCI region specified. Set OCI_REGION or DEFAULT_REGION"
fi

mkdir -p ~/.oci
trap 'rm -f ~/.oci/oci_api_key.pem.tmp' EXIT

printf '[DEFAULT]\nuser=%s\nfingerprint=%s\ntenancy=%s\nregion=%s\nkey_file=%s\n' \
  "$OCI_USER" "$OCI_FINGERPRINT" "$OCI_TENANCY" "$REGION" "$HOME/.oci/oci_api_key.pem" \
  > ~/.oci/config || fail "Failed to write OCI config"

printf '%s' "$OCI_PRIVATE_KEY" | tr -d '\r' > ~/.oci/oci_api_key.pem.tmp || fail "Failed to write private key"
mv ~/.oci/oci_api_key.pem.tmp ~/.oci/oci_api_key.pem

chmod 600 ~/.oci/oci_api_key.pem || fail "Failed to set key permissions"
chmod 600 ~/.oci/config || fail "Failed to set config permissions"

require_cmd "oci"
oci setup repair-file-permissions --file ~/.oci/config

success "OCI credentials configured for region: $REGION"
