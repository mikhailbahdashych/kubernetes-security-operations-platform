#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# deploy-all.sh - Complete deployment script for the Kubernetes Security
#                 Operations Platform
#
# Usage: ./deploy-all.sh [--wazuh]
#
# Deploys all platform components in the correct order:
#   1. Namespaces
#   2. RBAC
#   3. Network Policies
#   4. Gatekeeper (OPA)
#   5. Prometheus + Grafana (kube-prometheus-stack)
#   6. Falco + Falcosidekick
#   7. Demo Application
#   8. Custom Falco Rules & Grafana Dashboards
#   9. (Optional) Wazuh Agents
###############################################################################

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFESTS_DIR="${K8S_DIR}/manifests"
HELM_VALUES_DIR="${K8S_DIR}/helm-values"

DEPLOY_WAZUH=false
for arg in "$@"; do
    case "$arg" in
        --wazuh) DEPLOY_WAZUH=true ;;
        *)       warn "Unknown argument: $arg" ;;
    esac
done

# ---------------------------------------------------------------------------
# Track deployed components for summary
# ---------------------------------------------------------------------------
DEPLOYED=()
SKIPPED=()
FAILED=()

record_success() { DEPLOYED+=("$1"); }
record_skip()    { SKIPPED+=("$1"); }
record_fail()    { FAILED+=("$1"); }

# ---------------------------------------------------------------------------
# Step 0 - Prerequisites
# ---------------------------------------------------------------------------
check_prerequisites() {
    info "Checking prerequisites..."
    local missing=()

    for cmd in kubectl helm aws; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        error "Please install them before running this script."
        exit 1
    fi

    # Verify kubectl can reach a cluster
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach a Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    success "All prerequisites satisfied"
}

# ---------------------------------------------------------------------------
# Step 1 - Namespaces
# ---------------------------------------------------------------------------
deploy_namespaces() {
    info "Creating namespaces..."
    local ns_dir="${MANIFESTS_DIR}/namespaces"

    if [[ ! -d "$ns_dir" ]] || [[ -z "$(ls -A "$ns_dir" 2>/dev/null)" ]]; then
        warn "No namespace manifests found in ${ns_dir}"
        record_skip "Namespaces"
        return
    fi

    if kubectl apply -f "$ns_dir"; then
        success "Namespaces created/updated"
        record_success "Namespaces"
    else
        error "Failed to apply namespace manifests"
        record_fail "Namespaces"
    fi
}

# ---------------------------------------------------------------------------
# Step 2 - RBAC
# ---------------------------------------------------------------------------
deploy_rbac() {
    info "Applying RBAC resources..."
    local rbac_dir="${MANIFESTS_DIR}/rbac"

    if [[ ! -d "$rbac_dir" ]] || [[ -z "$(ls -A "$rbac_dir" 2>/dev/null)" ]]; then
        warn "No RBAC manifests found in ${rbac_dir}"
        record_skip "RBAC"
        return
    fi

    if kubectl apply -f "$rbac_dir"; then
        success "RBAC resources applied"
        record_success "RBAC"
    else
        error "Failed to apply RBAC manifests"
        record_fail "RBAC"
    fi
}

# ---------------------------------------------------------------------------
# Step 3 - Network Policies
# ---------------------------------------------------------------------------
deploy_network_policies() {
    info "Applying network policies..."
    local np_dir="${MANIFESTS_DIR}/network-policies"

    if [[ ! -d "$np_dir" ]] || [[ -z "$(ls -A "$np_dir" 2>/dev/null)" ]]; then
        warn "No network policy manifests found in ${np_dir}"
        record_skip "Network Policies"
        return
    fi

    if kubectl apply -f "$np_dir"; then
        success "Network policies applied"
        record_success "Network Policies"
    else
        error "Failed to apply network policies"
        record_fail "Network Policies"
    fi
}

# ---------------------------------------------------------------------------
# Step 4 - Gatekeeper (OPA)
# ---------------------------------------------------------------------------
deploy_gatekeeper() {
    info "Installing/upgrading Gatekeeper..."

    helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>/dev/null || true
    helm repo update gatekeeper

    local values_flag=()
    if [[ -f "${HELM_VALUES_DIR}/gatekeeper.yaml" ]]; then
        values_flag=(-f "${HELM_VALUES_DIR}/gatekeeper.yaml")
    else
        warn "No custom values file found at ${HELM_VALUES_DIR}/gatekeeper.yaml, using defaults"
    fi

    if helm upgrade --install gatekeeper gatekeeper/gatekeeper \
        --namespace security-enforcement \
        --create-namespace \
        "${values_flag[@]}" \
        --wait --timeout 5m; then
        success "Gatekeeper installed/upgraded"
        record_success "Gatekeeper"
    else
        error "Gatekeeper installation failed"
        record_fail "Gatekeeper"
        return
    fi

    # Wait for the Gatekeeper webhook to be ready
    info "Waiting for Gatekeeper webhook to become ready..."
    local retries=30
    while (( retries > 0 )); do
        if kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration &>/dev/null; then
            break
        fi
        sleep 5
        (( retries-- ))
    done

    if (( retries == 0 )); then
        warn "Timed out waiting for Gatekeeper webhook; constraint templates may fail to apply"
    fi

    # Apply constraint templates first, then constraints
    local ct_dir="${MANIFESTS_DIR}/gatekeeper-policies/constraint-templates"
    if [[ -d "$ct_dir" ]] && [[ -n "$(ls -A "$ct_dir" 2>/dev/null)" ]]; then
        info "Applying Gatekeeper constraint templates..."
        if kubectl apply -f "$ct_dir"; then
            success "Constraint templates applied"
        else
            error "Failed to apply constraint templates"
            record_fail "Gatekeeper Constraint Templates"
        fi
        # Allow the templates time to register CRDs
        info "Waiting 15s for constraint template CRDs to register..."
        sleep 15
    else
        warn "No constraint templates found in ${ct_dir}"
    fi

    local c_dir="${MANIFESTS_DIR}/gatekeeper-policies/constraints"
    if [[ -d "$c_dir" ]] && [[ -n "$(ls -A "$c_dir" 2>/dev/null)" ]]; then
        info "Applying Gatekeeper constraints..."
        if kubectl apply -f "$c_dir"; then
            success "Constraints applied"
        else
            error "Failed to apply constraints"
            record_fail "Gatekeeper Constraints"
        fi
    else
        warn "No constraints found in ${c_dir}"
    fi
}

# ---------------------------------------------------------------------------
# Step 5 - kube-prometheus-stack (Prometheus + Grafana)
# ---------------------------------------------------------------------------
deploy_prometheus_stack() {
    info "Installing/upgrading kube-prometheus-stack..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update prometheus-community

    local values_flag=()
    if [[ -f "${HELM_VALUES_DIR}/prometheus-stack.yaml" ]]; then
        values_flag=(-f "${HELM_VALUES_DIR}/prometheus-stack.yaml")
    else
        warn "No custom values file found at ${HELM_VALUES_DIR}/prometheus-stack.yaml, using defaults"
    fi

    if helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace security-monitoring \
        --create-namespace \
        "${values_flag[@]}" \
        --wait --timeout 10m; then
        success "kube-prometheus-stack installed/upgraded"
        record_success "kube-prometheus-stack"
    else
        error "kube-prometheus-stack installation failed"
        record_fail "kube-prometheus-stack"
    fi
}

# ---------------------------------------------------------------------------
# Step 6 - Falco
# ---------------------------------------------------------------------------
deploy_falco() {
    info "Installing/upgrading Falco..."

    helm repo add falcosecurity https://falcosecurity.github.io/charts 2>/dev/null || true
    helm repo update falcosecurity

    local values_flag=()
    if [[ -f "${HELM_VALUES_DIR}/falco.yaml" ]]; then
        values_flag=(-f "${HELM_VALUES_DIR}/falco.yaml")
    else
        warn "No custom values file found at ${HELM_VALUES_DIR}/falco.yaml, using defaults"
    fi

    if helm upgrade --install falco falcosecurity/falco \
        --namespace security-monitoring \
        --create-namespace \
        "${values_flag[@]}" \
        --wait --timeout 10m; then
        success "Falco installed/upgraded"
        record_success "Falco"
    else
        error "Falco installation failed"
        record_fail "Falco"
    fi
}

# ---------------------------------------------------------------------------
# Step 7 - Falcosidekick
# ---------------------------------------------------------------------------
deploy_falcosidekick() {
    info "Installing/upgrading Falcosidekick..."

    # falcosidekick chart is in the same falcosecurity repo
    if helm upgrade --install falcosidekick falcosecurity/falcosidekick \
        --namespace security-monitoring \
        --create-namespace \
        --wait --timeout 5m; then
        success "Falcosidekick installed/upgraded"
        record_success "Falcosidekick"
    else
        error "Falcosidekick installation failed"
        record_fail "Falcosidekick"
    fi
}

# ---------------------------------------------------------------------------
# Step 8 - Demo Application
# ---------------------------------------------------------------------------
deploy_demo_app() {
    info "Deploying demo application..."
    local demo_dir="${MANIFESTS_DIR}/demo-app"

    if [[ ! -d "$demo_dir" ]] || [[ -z "$(ls -A "$demo_dir" 2>/dev/null)" ]]; then
        warn "No demo-app manifests found in ${demo_dir}"
        record_skip "Demo App"
        return
    fi

    if kubectl apply -f "$demo_dir"; then
        success "Demo application deployed"
        record_success "Demo App"
    else
        error "Failed to deploy demo application"
        record_fail "Demo App"
    fi
}

# ---------------------------------------------------------------------------
# Step 9 - Custom Falco Rules ConfigMap
# ---------------------------------------------------------------------------
deploy_falco_custom_rules() {
    info "Applying custom Falco rules..."
    local monitoring_dir="${MANIFESTS_DIR}/security-monitoring"

    local falco_rules
    falco_rules=$(find "$monitoring_dir" -name '*falco*rules*' -o -name '*falco*configmap*' 2>/dev/null | head -n 5)

    if [[ -z "$falco_rules" ]]; then
        # Try applying everything in the directory
        if [[ -d "$monitoring_dir" ]] && [[ -n "$(ls -A "$monitoring_dir" 2>/dev/null)" ]]; then
            if kubectl apply -f "$monitoring_dir"; then
                success "Security-monitoring manifests applied"
                record_success "Security Monitoring ConfigMaps"
            else
                error "Failed to apply security-monitoring manifests"
                record_fail "Security Monitoring ConfigMaps"
            fi
        else
            warn "No security-monitoring manifests found"
            record_skip "Security Monitoring ConfigMaps"
        fi
    else
        while IFS= read -r f; do
            info "  Applying ${f}..."
            kubectl apply -f "$f"
        done <<< "$falco_rules"
        success "Custom Falco rules applied"
        record_success "Custom Falco Rules"
    fi
}

# ---------------------------------------------------------------------------
# Step 10 - Grafana Dashboard ConfigMap
# ---------------------------------------------------------------------------
deploy_grafana_dashboards() {
    info "Applying Grafana dashboard ConfigMaps..."
    local monitoring_dir="${MANIFESTS_DIR}/security-monitoring"

    local dashboards
    dashboards=$(find "$monitoring_dir" -name '*grafana*dashboard*' -o -name '*dashboard*configmap*' 2>/dev/null | head -n 5)

    if [[ -n "$dashboards" ]]; then
        while IFS= read -r f; do
            info "  Applying ${f}..."
            kubectl apply -f "$f"
        done <<< "$dashboards"
        success "Grafana dashboards applied"
        record_success "Grafana Dashboards"
    else
        # Already handled by deploy_falco_custom_rules if the whole dir was applied
        info "No separate Grafana dashboard files detected (may have been applied with monitoring manifests)"
        record_skip "Grafana Dashboards (separate)"
    fi
}

# ---------------------------------------------------------------------------
# Step 11 - Wazuh Agents (optional)
# ---------------------------------------------------------------------------
deploy_wazuh() {
    if [[ "$DEPLOY_WAZUH" != "true" ]]; then
        info "Skipping Wazuh agents (pass --wazuh to deploy)"
        record_skip "Wazuh Agents"
        return
    fi

    info "Deploying Wazuh agents..."
    local wazuh_dir="${MANIFESTS_DIR}/wazuh-agents"

    if [[ ! -d "$wazuh_dir" ]] || [[ -z "$(ls -A "$wazuh_dir" 2>/dev/null)" ]]; then
        warn "No Wazuh agent manifests found in ${wazuh_dir}"
        record_skip "Wazuh Agents"
        return
    fi

    if kubectl apply -f "$wazuh_dir"; then
        success "Wazuh agents deployed"
        record_success "Wazuh Agents"
    else
        error "Failed to deploy Wazuh agents"
        record_fail "Wazuh Agents"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================================"
    echo "  Deployment Summary"
    echo "============================================================"

    if [[ ${#DEPLOYED[@]} -gt 0 ]]; then
        echo -e "${GREEN}Deployed successfully:${NC}"
        for item in "${DEPLOYED[@]}"; do
            echo -e "  ${GREEN}+${NC} ${item}"
        done
    fi

    if [[ ${#SKIPPED[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Skipped:${NC}"
        for item in "${SKIPPED[@]}"; do
            echo -e "  ${YELLOW}-${NC} ${item}"
        done
    fi

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo -e "${RED}Failed:${NC}"
        for item in "${FAILED[@]}"; do
            echo -e "  ${RED}x${NC} ${item}"
        done
    fi

    echo "============================================================"
    echo -e "  Deployed: ${GREEN}${#DEPLOYED[@]}${NC}  Skipped: ${YELLOW}${#SKIPPED[@]}${NC}  Failed: ${RED}${#FAILED[@]}${NC}"
    echo "============================================================"

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Kubernetes Security Operations Platform - Deployer"
    echo "============================================================"
    echo ""

    check_prerequisites

    deploy_namespaces
    deploy_rbac
    deploy_network_policies
    deploy_gatekeeper
    deploy_prometheus_stack
    deploy_falco
    deploy_falcosidekick
    deploy_demo_app
    deploy_falco_custom_rules
    deploy_grafana_dashboards
    deploy_wazuh

    print_summary
}

main "$@"
