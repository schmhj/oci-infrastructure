#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Validate required environment variables
require_env "SECRETS_PRIVATE_KEY"
require_env "SECRETS_PUBLIC_KEY"

require_cmd "kubectl"

# Check if sealed-secrets secret already exists
if kubectl get secret sealed-secrets-key -n kube-system >/dev/null 2>&1; then
  success "Sealed-secrets TLS secret already configured"
  exit 0
fi

success "Setting up sealed-secrets TLS secret..."

SECRETS_DIR="$HOME/.secrets"
SECRETS_PRIV_KEY="${SECRETS_DIR}/sealed-secrets"
SECRETS_PUB_KEY="${SECRETS_DIR}/sealed-secrets.pub"

mkdir -p "$SECRETS_DIR" || fail "Failed to create secrets directory"

echo "$SECRETS_PRIVATE_KEY" > "$SECRETS_PRIV_KEY" || fail "Failed to write private key"
echo "$SECRETS_PUBLIC_KEY" > "$SECRETS_PUB_KEY" || fail "Failed to write public key"
chmod 600 "$SECRETS_PRIV_KEY" || fail "Failed to set private key permissions"

# Create secret using sealed-secrets keys
require_cmd "kubectl"

# Use temporary file with cleanup
TEMP_SECRET=$(mktemp) || fail "Failed to create temporary file"
trap "rm -f $TEMP_SECRET" EXIT

kubectl create secret tls sealed-secrets-key \
  --cert="$SECRETS_PUB_KEY" \
  --key="$SECRETS_PRIV_KEY" \
  -n kube-system \
  --dry-run=client -o yaml > "$TEMP_SECRET" || fail "Failed to create secret manifest"

kubectl apply -f "$TEMP_SECRET" || fail "Failed to apply sealed-secrets secret"

success "TLS sealed-secrets secret configured"
