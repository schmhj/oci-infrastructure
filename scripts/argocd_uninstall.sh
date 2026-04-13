#!/usr/bin/env bash
# ============================================================
# argocd_uninstall.sh
#
# Uninstalls ArgoCD and Sealed Secrets (kubeseal) from the
# cluster after ensuring all managed resources are gone.
#
# Removal order:
#   1. Remove ArgoCD finalizers that could block namespace deletion
#   2. Uninstall ArgoCD (Helm or manifest fallback)
#   3. Uninstall Sealed Secrets (Helm or manifest fallback)
#   4. Delete leftover namespaces
#   5. Clean up cluster-scoped CRDs
#
# Assumes kubeconfig is already configured.
# ============================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
ARGOCD_NAMESPACE="argocd"
SEALED_SECRETS_NAMESPACE="kube-system"
SEALED_SECRETS_RELEASE="sealed-secrets"
ARGOCD_RELEASE="argocd"
NAMESPACE_DELETE_TIMEOUT="120s"
RESOURCE_DELETE_TIMEOUT="60s"

# ArgoCD CRDs to clean up
ARGOCD_CRDS=(
  "applications.argoproj.io"
  "applicationsets.argoproj.io"
  "appprojects.argoproj.io"
  "argocdextensions.argoproj.io"
)

# Sealed Secrets CRDs to clean up
SEALED_SECRETS_CRDS=(
  "sealedsecrets.bitnami.com"
)

# ── Helpers ───────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*" >&2; exit 1; }

namespace_exists() {
  kubectl get namespace "$1" &>/dev/null
}

helm_release_exists() {
  helm status "$1" -n "$2" &>/dev/null 2>&1
}

remove_finalizers_from_resource() {
  local resource_type="$1"
  local namespace="$2"

  log "  Removing finalizers from all $resource_type in namespace '$namespace'..."
  kubectl get "$resource_type" -n "$namespace" --no-headers -o custom-columns=":metadata.name" 2>/dev/null \
  | while read -r name; do
      [[ -z "$name" ]] && continue
      log "    Patching finalizers on $resource_type/$name"
      kubectl patch "$resource_type" "$name" \
        -n "$namespace" \
        --type=merge \
        -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    done
}

wait_for_namespace_deleted() {
  local ns="$1"
  local timeout=120
  local interval=10
  local elapsed=0

  log "Waiting for namespace '$ns' to be fully terminated..."
  while [[ $elapsed -lt $timeout ]]; do
    if ! namespace_exists "$ns"; then
      log "✅ Namespace '$ns' terminated."
      return 0
    fi
    log "  → Namespace '$ns' still terminating. Retrying in ${interval}s..."
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  log "⚠️  Namespace '$ns' did not terminate within ${timeout}s. May need manual cleanup."
}

# ── Step 1: Remove ArgoCD resource finalizers ─────────────────
# Finalizers on Application/AppProject CRs block namespace deletion
if namespace_exists "$ARGOCD_NAMESPACE"; then
  log "Removing finalizers from ArgoCD resources to prevent deletion hangs..."
  remove_finalizers_from_resource "applications.argoproj.io" "$ARGOCD_NAMESPACE"
  remove_finalizers_from_resource "applicationsets.argoproj.io" "$ARGOCD_NAMESPACE"
  remove_finalizers_from_resource "appprojects.argoproj.io" "$ARGOCD_NAMESPACE"

  log "Deleting any remaining ArgoCD Application CRs..."
  kubectl delete applications.argoproj.io --all \
    -n "$ARGOCD_NAMESPACE" \
    --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true

  log "Deleting any remaining ArgoCD AppProject CRs..."
  kubectl delete appprojects.argoproj.io --all \
    -n "$ARGOCD_NAMESPACE" \
    --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
else
  log "ArgoCD namespace '$ARGOCD_NAMESPACE' not found — skipping finalizer cleanup."
fi

# ── Step 2: Uninstall ArgoCD ──────────────────────────────────
log "Uninstalling ArgoCD..."
if helm_release_exists "$ARGOCD_RELEASE" "$ARGOCD_NAMESPACE"; then
  log "  Helm release '$ARGOCD_RELEASE' found. Running helm uninstall..."
  helm uninstall "$ARGOCD_RELEASE" \
    -n "$ARGOCD_NAMESPACE" \
    --timeout 5m \
    --wait
  log "  ✅ ArgoCD Helm release uninstalled."
else
  log "  No Helm release found for ArgoCD. Attempting manifest-based removal..."
  # Fallback: delete by label selector used by standard install manifests
  if namespace_exists "$ARGOCD_NAMESPACE"; then
    kubectl delete all --all -n "$ARGOCD_NAMESPACE" \
      --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
    kubectl delete configmap --all -n "$ARGOCD_NAMESPACE" \
      --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
    kubectl delete secret --all -n "$ARGOCD_NAMESPACE" \
      --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
    kubectl delete serviceaccount --all -n "$ARGOCD_NAMESPACE" \
      --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
    log "  ✅ ArgoCD resources deleted via kubectl."
  fi
fi

# ── Step 3: Uninstall Sealed Secrets ──────────────────────────
log "Uninstalling Sealed Secrets..."
if helm_release_exists "$SEALED_SECRETS_RELEASE" "$SEALED_SECRETS_NAMESPACE"; then
  log "  Helm release '$SEALED_SECRETS_RELEASE' found. Running helm uninstall..."
  helm uninstall "$SEALED_SECRETS_RELEASE" \
    -n "$SEALED_SECRETS_NAMESPACE" \
    --timeout 5m \
    --wait
  log "  ✅ Sealed Secrets Helm release uninstalled."
else
  log "  No Helm release found for Sealed Secrets. Attempting label-based removal..."
  kubectl delete all \
    -l "app.kubernetes.io/name=sealed-secrets" \
    -n "$SEALED_SECRETS_NAMESPACE" \
    --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
  log "  ✅ Sealed Secrets resources deleted via kubectl."
fi

# Delete any remaining SealedSecret CRs cluster-wide
log "Removing any remaining SealedSecret custom resources..."
kubectl delete sealedsecrets.bitnami.com --all --all-namespaces \
  --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true

# ── Step 4: Delete ArgoCD namespace ───────────────────────────
if namespace_exists "$ARGOCD_NAMESPACE"; then
  log "Deleting namespace '$ARGOCD_NAMESPACE'..."
  kubectl delete namespace "$ARGOCD_NAMESPACE" \
    --timeout="$NAMESPACE_DELETE_TIMEOUT" 2>/dev/null || true
  wait_for_namespace_deleted "$ARGOCD_NAMESPACE"
else
  log "Namespace '$ARGOCD_NAMESPACE' already gone."
fi

# ── Step 5: Clean up cluster-scoped RBAC ─────────────────────
log "Removing ArgoCD cluster-scoped RBAC resources..."
kubectl delete clusterrolebinding \
  -l "app.kubernetes.io/part-of=argocd" \
  --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
kubectl delete clusterrole \
  -l "app.kubernetes.io/part-of=argocd" \
  --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true

log "Removing Sealed Secrets cluster-scoped RBAC resources..."
kubectl delete clusterrolebinding \
  -l "app.kubernetes.io/name=sealed-secrets" \
  --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true
kubectl delete clusterrole \
  -l "app.kubernetes.io/name=sealed-secrets" \
  --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || true

# ── Step 6: Remove CRDs ───────────────────────────────────────
log "Removing ArgoCD CRDs..."
for crd in "${ARGOCD_CRDS[@]}"; do
  if kubectl get crd "$crd" &>/dev/null; then
    log "  Deleting CRD: $crd"
    kubectl delete crd "$crd" --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || \
      log "  ⚠️  Could not delete CRD '$crd' — may already be gone."
  else
    log "  CRD not found (already gone): $crd"
  fi
done

log "Removing Sealed Secrets CRDs..."
for crd in "${SEALED_SECRETS_CRDS[@]}"; do
  if kubectl get crd "$crd" &>/dev/null; then
    log "  Deleting CRD: $crd"
    kubectl delete crd "$crd" --timeout="$RESOURCE_DELETE_TIMEOUT" 2>/dev/null || \
      log "  ⚠️  Could not delete CRD '$crd' — may already be gone."
  else
    log "  CRD not found (already gone): $crd"
  fi
done

# ── Final verification ────────────────────────────────────────
log "Running final verification..."
ISSUES=0

if namespace_exists "$ARGOCD_NAMESPACE"; then
  log "⚠️  Namespace '$ARGOCD_NAMESPACE' still exists — may need manual cleanup."
  ISSUES=$((ISSUES + 1))
fi

for crd in "${ARGOCD_CRDS[@]}" "${SEALED_SECRETS_CRDS[@]}"; do
  if kubectl get crd "$crd" &>/dev/null; then
    log "⚠️  CRD '$crd' still exists — may need manual cleanup."
    ISSUES=$((ISSUES + 1))
  fi
done

if [[ $ISSUES -eq 0 ]]; then
  log "✅ ArgoCD and Sealed Secrets fully uninstalled."
else
  log "⚠️  Uninstall completed with $ISSUES warning(s). Review logs above."
fi
