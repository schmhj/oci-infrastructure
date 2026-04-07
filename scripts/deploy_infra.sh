#!/bin/bash
# deploy.sh

set -e  # exit on any error

echo "=== Stage 1: Provisioning OKE Cluster ==="
cd ./infra
terraform init
terraform apply -auto-approve

echo "=== Waiting for cluster nodes to be ready ==="

echo "=== Done ==="