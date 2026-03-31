# !/bin/bash

terraform apply -auto-approve -var-file=../terraform.tfvars

terraform output -json > ../terraform.tfstate.d/terraform.tfstate.json


oci ce cluster create-kubeconfig \
--cluster-id ocid1.cluster.oc1.iad.aaaaaaaaesm5a4hokphp3kjndnrl5qqo5yqrffuwnxiwxc4gvcos7hsiq3oa \
--file ~/.kube/k8s-config \
--region us-ashburn-1 \
--token-version 2.0.0 \
--kube-endpoint PUBLIC_ENDPOINT

export KUBECONFIG=~/.kube/config

