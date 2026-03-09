# Deploy & Teardown Runbook

## Full Deployment (from zero)

### Step 1: Deploy Infrastructure

```bash
cd terraform/environments/dev

# First time: create S3 backend bucket (or use local state)
# aws s3 mb s3://ksop-terraform-state-ACCOUNT_ID --region eu-central-1
# aws dynamodb create-table --table-name ksop-terraform-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST --region eu-central-1

terraform init
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

### Step 2: Configure kubectl

```bash
# Use the output from terraform
aws eks update-kubeconfig --region eu-central-1 --name ksop-dev

# Verify
kubectl get nodes
# Should show 2 Ready nodes
```

### Step 3: Deploy Platform

```bash
./kubernetes/scripts/deploy-all.sh
```

This deploys in order:
1. Namespaces (with Pod Security Standards)
2. RBAC (ClusterRoles, Roles, Bindings)
3. Network Policies (default-deny + allow rules)
4. OPA Gatekeeper + constraint templates + constraints
5. Prometheus + Grafana (kube-prometheus-stack)
6. Falco + Falcosidekick
7. Demo application (frontend + backend)
8. Falco custom rules + Grafana dashboards

### Step 4: Verify

```bash
./kubernetes/scripts/verify-rbac.sh
./kubernetes/scripts/test-network-policies.sh
./kubernetes/scripts/test-gatekeeper.sh
./kubernetes/scripts/trigger-falco-alerts.sh
```

### Step 5: Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:3000 -n security-monitoring
# Open http://localhost:3000
# Default credentials: admin / admin
```

## Teardown

### Remove Kubernetes Components

```bash
# Remove Helm releases
helm uninstall falcosidekick -n security-monitoring 2>/dev/null || true
helm uninstall falco -n security-monitoring 2>/dev/null || true
helm uninstall kube-prometheus-stack -n security-monitoring 2>/dev/null || true
helm uninstall gatekeeper -n security-enforcement 2>/dev/null || true

# Remove manifests
kubectl delete -f kubernetes/manifests/demo-app/ --ignore-not-found
kubectl delete -f kubernetes/manifests/wazuh-agents/ --ignore-not-found
kubectl delete -f kubernetes/manifests/network-policies/ --ignore-not-found
kubectl delete -f kubernetes/manifests/rbac/ --ignore-not-found
kubectl delete -f kubernetes/manifests/namespaces/ --ignore-not-found
```

### Destroy Infrastructure

```bash
cd terraform/environments/dev
terraform destroy
```

## Deploy Wazuh (Optional)

### Enable Wazuh Server

```bash
cd terraform/environments/dev
# Edit terraform.tfvars: set deploy_wazuh = true
terraform apply
```

### Configure Wazuh Agent

```bash
# Get Wazuh server IP
WAZUH_IP=$(terraform output -raw wazuh_private_ip)

# Update agent config
kubectl create configmap wazuh-agent-config \
  --from-literal=WAZUH_MANAGER_IP=$WAZUH_IP \
  -n wazuh-agents --dry-run=client -o yaml | kubectl apply -f -

# Deploy agents
./kubernetes/scripts/deploy-all.sh --wazuh
```

### Access Wazuh Dashboard

```bash
WAZUH_URL=$(terraform output -raw wazuh_dashboard_url)
echo "Open: $WAZUH_URL"
# Default credentials: admin / SecretPassword
```

## Daily Start/Stop (Cost Saving)

### Stop (evening)

```bash
cd terraform/environments/dev
terraform destroy -auto-approve
```

### Start (morning)

```bash
cd terraform/environments/dev
terraform apply -auto-approve
aws eks update-kubeconfig --region eu-central-1 --name ksop-dev
./kubernetes/scripts/deploy-all.sh
```

Estimated savings: ~50-60% of monthly cost if running only 8-10 hours/day.
