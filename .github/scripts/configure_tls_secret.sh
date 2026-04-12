#!/usr/bin/env bash

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Validate required environment variables
require_env "SECRETS_PRIVATE_KEY"
require_env "SECRETS_PUBLIC_KEY"

SECRETS_DIR="$HOME/.secrets"
SECRETS_PRIV_KEY="${SECRETS_DIR}/sealed-secrets"
SECRETS_PUB_KEY="${SECRETS_DIR}/sealed-secrets.pub"

mkdir -p "$SECRETS_DIR" || fail "Failed to create secrets directory"

echo "$SECRETS_PRIVATE_KEY" > "$SECRETS_PRIV_KEY" || fail "Failed to write private key"
echo "$SECRETS_PUBLIC_KEY" > "$SECRETS_PUB_KEY" || fail "Failed to write public key"
chmod 600 "$SECRETS_PRIV_KEY" || fail "Failed to set private key permissions"

# Create secret using sealed-secrets keys
require_cmd "kubectl"
kubectl create secret tls sealed-secrets-key \
  --cert="$SECRETS_PUB_KEY" \
  --key="$SECRETS_PRIV_KEY" \
  -n kube-system \
  --dry-run=client -o yaml > /tmp/custom-sealed-secret-key.yaml || fail "Failed to create secret manifest"

kubectl apply -f /tmp/custom-sealed-secret-key.yaml || fail "Failed to apply sealed-secrets secret"
rm /tmp/custom-sealed-secret-key.yaml

success "TLS sealed-secrets secret configured"
