#!/bin/bash
# deploy.sh

set -e  # exit on any error

echo "=== Stage 2: Deploying Kubernetes Config + Helm Charts ==="
cd ../k8s
terraform init
terraform apply -auto-approve

echo "=== Done ==="