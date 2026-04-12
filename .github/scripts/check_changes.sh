#!/usr/bin/env bash

set -euo pipefail

# Usage: check_changes.sh <path-prefix> [<path-prefix2> ...]
# Example: check_changes.sh oci
# Example: check_changes.sh ".github/argocd" ".github/scripts"

if [ $# -eq 0 ]; then
  echo "Usage: $0 <path-prefix> [<path-prefix2> ...]" >&2
  exit 2
fi

PREFIXES=("$@")

# Provide default values when run outside GitHub Actions for local testing
GITHUB_EVENT_NAME=${GITHUB_EVENT_NAME:-${GITHUB_EVENT_NAME:-}}
WORKFLOW_INPUT_ACTION=${WORKFLOW_INPUT_ACTION:-${WORKFLOW_INPUT_ACTION:-}}

# If GITHUB_EVENT_NAME is empty, try to detect a reasonable default
if [ -z "${GITHUB_EVENT_NAME:-}" ]; then
  GITHUB_EVENT_NAME="local"
fi

# Check if any of the provided prefixes have changed
CHANGED=false
if git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  for PREFIX in "${PREFIXES[@]}"; do
    if git diff --name-only HEAD^ HEAD | grep -q "^${PREFIX}/"; then
      CHANGED=true
      break
    fi
  done
else
  # No previous commit — treat as changed if any prefix exists in tree
  for PREFIX in "${PREFIXES[@]}"; do
    if git ls-files | grep -q "^${PREFIX}/"; then
      CHANGED=true
      break
    fi
  done
fi

echo "changed=$CHANGED" >> "${GITHUB_OUTPUT:-/dev/stdout}"

RUN_PLAN=false
if [ "$GITHUB_EVENT_NAME" = "pull_request" ] && [ "$CHANGED" = "true" ]; then
  RUN_PLAN=true
fi
if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ] && { [ "$WORKFLOW_INPUT_ACTION" = "plan" ] || [ "$WORKFLOW_INPUT_ACTION" = "plan_and_apply" ]; }; then
  RUN_PLAN=true
fi

echo "run_plan=$RUN_PLAN" >> "${GITHUB_OUTPUT:-/dev/stdout}"

RUN_APPLY=false
if [ "$GITHUB_EVENT_NAME" = "push" ] && [ "$CHANGED" = "true" ]; then
  RUN_APPLY=true
fi
if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ] && { [ "$WORKFLOW_INPUT_ACTION" = "apply" ] || [ "$WORKFLOW_INPUT_ACTION" = "plan_and_apply" ]; }; then
  RUN_APPLY=true
fi

echo "run_apply=$RUN_APPLY" >> "${GITHUB_OUTPUT:-/dev/stdout}"

exit 0
