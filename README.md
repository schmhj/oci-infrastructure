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


## Generate TLS Keys and Certificate

```
openssl req -x509 -newkey rsa:4096 -nodes -sha256 \
  -keyout key.pem \
  -out cert.pem \
  -days 36500 \
  -subj "/CN=argocd.local"
```

## Create tls secret

```
kubectl create secret tls sealed-secrets-key \
  --cert=cert.pem \
  --key=key.pem \
  -n kube-system \
  --dry-run=client -o yaml > sealed-secrets-key.yaml
```


