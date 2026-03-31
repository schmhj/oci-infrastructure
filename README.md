# oci-infrastructure
Oracle Kubernetes Cluster

Ref:https://cloud.oracle.com/containers/clusters/ocid1.cluster.oc1.iad.aaaaaaaalcqljk7ijagr6baxianyuaxfsbkgnb5rvhaomglb3cjhwdtej27a/details?region=us-ashburn-1

## OCI CLI Setup

```
# setup
oci setup config

# list compartments
oci iam compartment list -c <tenancy-ocid>
```

## Terraform Setup

```
# init
terraform init

# create oci-infra
terraform apply -auto-approve -var-file=../terraform.tfvars

# create k8s-infra
terraform apply -auto-approve -var-file=../terraform.tfvars
```





