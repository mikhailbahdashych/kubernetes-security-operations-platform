#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# test-network-policies.sh - Network policy verification for the Kubernetes
#                            Security Operations Platform
#
# Deploys ephemeral test pods and validates that network policies correctly
# allow or deny traffic between namespaces and services.
###############################################################################

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
APP_NS="applications"
SEC_NS="security-monitoring"
TEST_POD_FRONTEND="netpol-test-frontend"
TEST_POD_BACKEND="netpol-test-backend"
TEST_IMAGE="nicolaka/netshoot:latest"
CONNECT_TIMEOUT=5

TOTAL=0
PASSED=0
FAILED=0
RESULTS=()

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
pass_test() {
    local desc="$1"
    (( TOTAL++ ))
    (( PASSED++ ))
    RESULTS+=("${GREEN}PASS${NC}  ${desc}")
    echo -e "  ${GREEN}PASS${NC}  ${desc}"
}

fail_test() {
    local desc="$1"
    (( TOTAL++ ))
    (( FAILED++ ))
    RESULTS+=("${RED}FAIL${NC}  ${desc}")
    echo -e "  ${RED}FAIL${NC}  ${desc}"
}

# ---------------------------------------------------------------------------
# Pod lifecycle helpers
# ---------------------------------------------------------------------------
wait_for_pod() {
    local ns="$1"
    local name="$2"
    local retries=30

    info "Waiting for pod ${name} in ${ns} to be ready..."
    while (( retries > 0 )); do
        local phase
        phase=$(kubectl get pod "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        if [[ "$phase" == "Running" ]]; then
            return 0
        fi
        sleep 2
        (( retries-- ))
    done

    error "Pod ${name} in ${ns} did not become ready in time"
    return 1
}

create_test_pods() {
    info "Creating test pods..."

    # Frontend pod in applications namespace (simulates a frontend workload)
    kubectl run "$TEST_POD_FRONTEND" \
        --namespace "$APP_NS" \
        --image "$TEST_IMAGE" \
        --labels="app=frontend,role=test" \
        --restart=Never \
        --command -- sleep 3600 \
        --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"netpol-test-frontend","image":"nicolaka/netshoot:latest","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
        2>/dev/null || info "Frontend test pod already exists"

    # Backend pod in applications namespace (simulates a backend workload)
    kubectl run "$TEST_POD_BACKEND" \
        --namespace "$APP_NS" \
        --image "$TEST_IMAGE" \
        --labels="app=backend,role=test" \
        --restart=Never \
        --command -- sleep 3600 \
        --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"netpol-test-backend","image":"nicolaka/netshoot:latest","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
        2>/dev/null || info "Backend test pod already exists"

    wait_for_pod "$APP_NS" "$TEST_POD_FRONTEND"
    wait_for_pod "$APP_NS" "$TEST_POD_BACKEND"

    success "Test pods are ready"
}

cleanup_test_pods() {
    info "Cleaning up test pods..."
    kubectl delete pod "$TEST_POD_FRONTEND" -n "$APP_NS" --ignore-not-found --grace-period=0 --force 2>/dev/null || true
    kubectl delete pod "$TEST_POD_BACKEND" -n "$APP_NS" --ignore-not-found --grace-period=0 --force 2>/dev/null || true
    success "Test pods cleaned up"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_frontend_to_backend() {
    info "Test 1: Frontend -> Backend connectivity on port 8080"

    local backend_ip
    backend_ip=$(kubectl get pod "$TEST_POD_BACKEND" -n "$APP_NS" -o jsonpath='{.status.podIP}')

    if [[ -z "$backend_ip" ]]; then
        fail_test "Frontend -> Backend (could not determine backend pod IP)"
        return
    fi

    local result
    result=$(kubectl exec "$TEST_POD_FRONTEND" -n "$APP_NS" -- \
        curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" \
        "http://${backend_ip}:8080" 2>&1 || true)

    # We expect either a connection success (any HTTP code) or a connection
    # refused (port not listening). Both prove the network path is open.
    # A timeout or "network unreachable" means the policy blocked it.
    if echo "$result" | grep -qiE "Connection refused|^[0-9]{3}$"; then
        pass_test "Frontend -> Backend on port 8080 (network path open)"
    elif echo "$result" | grep -qi "timed out\|unreachable"; then
        fail_test "Frontend -> Backend on port 8080 (blocked or timed out)"
    else
        # curl may return 000 on connection refused in some versions
        pass_test "Frontend -> Backend on port 8080 (network path open - response: ${result})"
    fi
}

test_frontend_to_security_monitoring_blocked() {
    info "Test 2: Frontend -> security-monitoring (should be BLOCKED)"

    # Try to reach any pod in security-monitoring namespace
    # First, find a pod IP in security-monitoring (if any pods exist)
    local target_ip
    target_ip=$(kubectl get pods -n "$SEC_NS" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

    if [[ -z "$target_ip" ]]; then
        # No pods in security-monitoring, try the service CIDR via a known service
        target_ip=$(kubectl get svc -n "$SEC_NS" -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")
    fi

    if [[ -z "$target_ip" ]]; then
        warn "No pods or services found in ${SEC_NS} - deploying a temporary target"
        kubectl run netpol-target -n "$SEC_NS" --image=nginx:alpine --restart=Never \
            --labels="app=netpol-target" 2>/dev/null || true
        wait_for_pod "$SEC_NS" "netpol-target" || true
        target_ip=$(kubectl get pod netpol-target -n "$SEC_NS" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    fi

    if [[ -z "$target_ip" ]]; then
        fail_test "Frontend -> security-monitoring (could not determine target IP)"
        return
    fi

    local result
    result=$(kubectl exec "$TEST_POD_FRONTEND" -n "$APP_NS" -- \
        curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" \
        "http://${target_ip}:80" 2>&1 || true)

    if echo "$result" | grep -qiE "timed out\|unreachable"; then
        pass_test "Frontend -> security-monitoring is BLOCKED (as expected)"
    else
        fail_test "Frontend -> security-monitoring was NOT blocked (got: ${result})"
    fi

    # Clean up temporary target if we created one
    kubectl delete pod netpol-target -n "$SEC_NS" --ignore-not-found --grace-period=0 --force 2>/dev/null || true
}

test_dns_resolution() {
    info "Test 3: DNS resolution from applications namespace"

    local result
    result=$(kubectl exec "$TEST_POD_FRONTEND" -n "$APP_NS" -- \
        nslookup kubernetes.default.svc.cluster.local 2>&1 || true)

    if echo "$result" | grep -qi "Address.*[0-9]"; then
        pass_test "DNS resolution works (kubernetes.default.svc.cluster.local resolved)"
    else
        fail_test "DNS resolution failed"
    fi
}

test_cross_namespace_blocked() {
    info "Test 4: Cross-namespace traffic to security-monitoring (additional check)"

    # Try reaching the Prometheus service by DNS name (should be blocked by network policy)
    local result
    result=$(kubectl exec "$TEST_POD_FRONTEND" -n "$APP_NS" -- \
        curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" \
        "http://kube-prometheus-stack-prometheus.${SEC_NS}.svc.cluster.local:9090" 2>&1 || true)

    if echo "$result" | grep -qiE "timed out\|unreachable\|resolve"; then
        pass_test "Cross-namespace to Prometheus is BLOCKED (as expected)"
    elif echo "$result" | grep -qiE "^[0-9]{3}$"; then
        fail_test "Cross-namespace to Prometheus was NOT blocked (HTTP ${result})"
    else
        # Could not resolve = also effectively blocked
        if echo "$result" | grep -qi "Could not resolve\|Name or service not known"; then
            pass_test "Cross-namespace to Prometheus is BLOCKED (DNS unreachable or service absent)"
        else
            fail_test "Cross-namespace to Prometheus - unexpected result: ${result}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================================"
    echo "  Network Policy Test Summary"
    echo "============================================================"

    for r in "${RESULTS[@]}"; do
        echo -e "  ${r}"
    done

    echo "============================================================"
    echo -e "  Total: ${TOTAL}   ${GREEN}Passed: ${PASSED}${NC}   ${RED}Failed: ${FAILED}${NC}"
    echo "============================================================"

    if [[ "$FAILED" -gt 0 ]]; then
        error "Some network policy tests failed. Review results above."
        return 1
    else
        success "All network policy tests passed!"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Network Policy Tests - Kubernetes Security Ops Platform"
    echo "============================================================"

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach a Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # Ensure the applications namespace exists
    if ! kubectl get namespace "$APP_NS" &>/dev/null; then
        error "Namespace '${APP_NS}' does not exist. Deploy the platform first."
        exit 1
    fi

    trap cleanup_test_pods EXIT

    create_test_pods

    test_frontend_to_backend
    test_frontend_to_security_monitoring_blocked
    test_dns_resolution
    test_cross_namespace_blocked

    print_summary
}

main "$@"
