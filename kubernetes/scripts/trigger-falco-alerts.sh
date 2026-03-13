#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# trigger-falco-alerts.sh - Simulate security events that Falco should detect
#
# Creates a test pod and performs actions that should trigger Falco alerts:
#   1. Terminal shell in container
#   2. Sensitive file access (/etc/shadow)
#   3. Unexpected outbound network connection
#   4. File permission change (chmod)
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
TEST_POD="falco-test-pod"
TEST_IMAGE="busybox:latest"
FALCO_LABEL="app.kubernetes.io/name=falco"
LOG_TAIL_LINES=50
WAIT_SECONDS=10

TOTAL=0
DETECTED=0
MISSED=0
RESULTS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
detected() {
    local desc="$1"
    (( TOTAL++ ))
    (( DETECTED++ ))
    RESULTS+=("${GREEN}DETECTED${NC}  ${desc}")
    echo -e "  ${GREEN}DETECTED${NC}  ${desc}"
}

missed() {
    local desc="$1"
    (( TOTAL++ ))
    (( MISSED++ ))
    RESULTS+=("${YELLOW}MISSED${NC}    ${desc}")
    echo -e "  ${YELLOW}MISSED${NC}    ${desc}"
}

wait_for_pod() {
    local ns="$1"
    local name="$2"
    local retries=30

    info "Waiting for pod ${name} to be ready..."
    while (( retries > 0 )); do
        local phase
        phase=$(kubectl get pod "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        if [[ "$phase" == "Running" ]]; then
            return 0
        fi
        sleep 2
        (( retries-- ))
    done

    error "Pod ${name} did not become ready in time"
    return 1
}

# check_falco_logs - Search Falco pod logs for a pattern
#
# Checks the most recent LOG_TAIL_LINES lines from all Falco pods.
# Falco runs as a DaemonSet, so we use -l (label selector) to get
# logs from all instances and --all-containers to include sidecars.
check_falco_logs() {
    local pattern="$1"
    local log_output

    log_output=$(kubectl logs -l "$FALCO_LABEL" -n "$SEC_NS" --tail="$LOG_TAIL_LINES" --all-containers 2>/dev/null || echo "")

    if echo "$log_output" | grep -qi "$pattern"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Pod lifecycle
# ---------------------------------------------------------------------------
create_test_pod() {
    info "Creating test pod '${TEST_POD}' in namespace '${APP_NS}'..."

    if kubectl get pod "$TEST_POD" -n "$APP_NS" &>/dev/null; then
        info "Test pod already exists, reusing it"
    else
        kubectl run "$TEST_POD" \
            --namespace "$APP_NS" \
            --image "$TEST_IMAGE" \
            --labels="app=falco-test,role=security-testing" \
            --restart=Never \
            --command -- sleep 3600 \
            2>/dev/null
    fi

    wait_for_pod "$APP_NS" "$TEST_POD"
    success "Test pod is ready"
}

cleanup_test_pod() {
    info "Cleaning up test pod..."
    kubectl delete pod "$TEST_POD" -n "$APP_NS" --ignore-not-found --grace-period=0 --force 2>/dev/null || true
    success "Test pod cleaned up"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_terminal_shell() {
    echo ""
    info "Test 1: Terminal Shell in Container"
    info "  Executing /bin/sh inside the test pod..."

    kubectl exec "$TEST_POD" -n "$APP_NS" -- /bin/sh -c "echo 'shell-access-test'" 2>/dev/null || true

    info "  Waiting ${WAIT_SECONDS}s for Falco to process the event..."
    sleep "$WAIT_SECONDS"

    if check_falco_logs "Terminal shell\|shell was spawned\|A shell was spawned"; then
        detected "Terminal Shell in Container"
    else
        missed "Terminal Shell in Container (may need more time or Falco rule not enabled)"
    fi
}

test_sensitive_file_read() {
    echo ""
    info "Test 2: Sensitive File Access (/etc/shadow)"
    info "  Reading /etc/shadow inside the test pod..."

    kubectl exec "$TEST_POD" -n "$APP_NS" -- /bin/sh -c "cat /etc/shadow" 2>/dev/null || true

    info "  Waiting ${WAIT_SECONDS}s for Falco to process the event..."
    sleep "$WAIT_SECONDS"

    if check_falco_logs "sensitive.*file\|shadow\|Sensitive file opened"; then
        detected "Sensitive File Access (/etc/shadow)"
    else
        missed "Sensitive File Access (/etc/shadow) (may need more time or Falco rule not enabled)"
    fi
}

test_outbound_connection() {
    echo ""
    info "Test 3: Unexpected Outbound Connection"
    info "  Attempting outbound connection from the test pod..."

    kubectl exec "$TEST_POD" -n "$APP_NS" -- /bin/sh -c "wget -q -O /dev/null --timeout=3 http://1.1.1.1 2>&1 || true" 2>/dev/null || true

    info "  Waiting ${WAIT_SECONDS}s for Falco to process the event..."
    sleep "$WAIT_SECONDS"

    if check_falco_logs "outbound\|Unexpected outbound\|network connection\|Contact K8S API"; then
        detected "Unexpected Outbound Connection"
    else
        missed "Unexpected Outbound Connection (may need custom Falco rule or more time)"
    fi
}

test_file_permission_change() {
    echo ""
    info "Test 4: File Permission / Ownership Change"
    info "  Changing file permissions inside the test pod..."

    kubectl exec "$TEST_POD" -n "$APP_NS" -- /bin/sh -c "touch /tmp/testfile && chmod 777 /tmp/testfile" 2>/dev/null || true

    info "  Waiting ${WAIT_SECONDS}s for Falco to process the event..."
    sleep "$WAIT_SECONDS"

    if check_falco_logs "chmod\|permission\|Set Setuid\|File permission"; then
        detected "File Permission Change"
    else
        missed "File Permission Change (may need custom Falco rule or more time)"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================================"
    echo "  Falco Alert Trigger Summary"
    echo "============================================================"

    for r in "${RESULTS[@]}"; do
        echo -e "  ${r}"
    done

    echo "============================================================"
    echo -e "  Total: ${TOTAL}   ${GREEN}Detected: ${DETECTED}${NC}   ${YELLOW}Missed: ${MISSED}${NC}"
    echo "============================================================"

    if [[ "$MISSED" -gt 0 ]]; then
        warn "Some events were not detected in Falco logs."
        warn "This may be due to:"
        warn "  - Falco rules not yet loaded for these event types"
        warn "  - Insufficient wait time for log propagation"
        warn "  - Custom rules needing to be applied"
        echo ""
        info "Check Falco logs manually with:"
        info "  kubectl logs -l ${FALCO_LABEL} -n ${SEC_NS} --tail=100"
    else
        success "All simulated events were detected by Falco!"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Falco Alert Trigger - Kubernetes Security Ops Platform"
    echo "============================================================"

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach a Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # Verify Falco is running
    local falco_pods
    falco_pods=$(kubectl get pods -l "$FALCO_LABEL" -n "$SEC_NS" --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$falco_pods" -eq 0 ]]; then
        error "No Falco pods found in namespace ${SEC_NS}."
        error "Deploy Falco first with: ./deploy-all.sh"
        exit 1
    fi

    info "Found ${falco_pods} Falco pod(s) running"

    # Ensure applications namespace exists
    if ! kubectl get namespace "$APP_NS" &>/dev/null; then
        error "Namespace '${APP_NS}' does not exist. Deploy the platform first."
        exit 1
    fi

    trap cleanup_test_pod EXIT

    create_test_pod

    test_terminal_shell
    test_sensitive_file_read
    test_outbound_connection
    test_file_permission_change

    print_summary
}

main "$@"
