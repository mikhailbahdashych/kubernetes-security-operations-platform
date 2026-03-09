#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# verify-rbac.sh - Automated RBAC verification for all 4 security tiers
#
# Tests permission boundaries for:
#   Tier 1 - Cluster Admin
#   Tier 2 - Security Operator
#   Tier 3 - App Operator
#   Tier 4 - Auditor
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
# Counters
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0
RESULTS=()

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

# check_allowed <description> <kubectl auth can-i args...>
# Expects the action to be ALLOWED (yes).
check_allowed() {
    local desc="$1"; shift
    (( TOTAL++ ))
    local result
    result=$(kubectl auth can-i "$@" 2>&1 || true)

    if [[ "$result" == "yes" ]]; then
        (( PASSED++ ))
        RESULTS+=("${GREEN}PASS${NC}  ${desc}")
        echo -e "  ${GREEN}PASS${NC}  ${desc}"
    else
        (( FAILED++ ))
        RESULTS+=("${RED}FAIL${NC}  ${desc}  (expected: allowed, got: ${result})")
        echo -e "  ${RED}FAIL${NC}  ${desc}  (expected: allowed, got: ${result})"
    fi
}

# check_denied <description> <kubectl auth can-i args...>
# Expects the action to be DENIED (no).
check_denied() {
    local desc="$1"; shift
    (( TOTAL++ ))
    local result
    result=$(kubectl auth can-i "$@" 2>&1 || true)

    if [[ "$result" == "no" ]]; then
        (( PASSED++ ))
        RESULTS+=("${GREEN}PASS${NC}  ${desc}")
        echo -e "  ${GREEN}PASS${NC}  ${desc}"
    else
        (( FAILED++ ))
        RESULTS+=("${RED}FAIL${NC}  ${desc}  (expected: denied, got: ${result})")
        echo -e "  ${RED}FAIL${NC}  ${desc}  (expected: denied, got: ${result})"
    fi
}

# ---------------------------------------------------------------------------
# Tier 1 - Cluster Admin
# ---------------------------------------------------------------------------
test_cluster_admin() {
    echo ""
    info "===== Tier 1: Cluster Admin (group: cluster-admins) ====="

    check_allowed "CAN create deployments in any namespace" \
        create deployments --as-group=cluster-admins --as=cluster-admin-user -n default

    check_allowed "CAN delete nodes" \
        delete nodes --as-group=cluster-admins --as=cluster-admin-user

    check_allowed "CAN access secrets in any namespace" \
        get secrets --as-group=cluster-admins --as=cluster-admin-user -n kube-system

    check_allowed "CAN create clusterroles" \
        create clusterroles --as-group=cluster-admins --as=cluster-admin-user

    check_allowed "CAN create namespaces" \
        create namespaces --as-group=cluster-admins --as=cluster-admin-user
}

# ---------------------------------------------------------------------------
# Tier 2 - Security Operator
# ---------------------------------------------------------------------------
test_security_operator() {
    echo ""
    info "===== Tier 2: Security Operator (SA: security-monitoring/security-operator) ====="

    local sa="--as=system:serviceaccount:security-monitoring:security-operator"

    check_allowed "CAN get pods in all namespaces" \
        get pods $sa --all-namespaces

    check_allowed "CAN create deployments in security-monitoring" \
        create deployments $sa -n security-monitoring

    check_allowed "CAN get configmaps in security-monitoring" \
        get configmaps $sa -n security-monitoring

    check_allowed "CAN list events in security-monitoring" \
        list events $sa -n security-monitoring

    check_denied "CANNOT delete deployments in applications" \
        delete deployments $sa -n applications

    check_denied "CANNOT create clusterroles" \
        create clusterroles $sa

    check_denied "CANNOT delete namespaces" \
        delete namespaces $sa

    check_denied "CANNOT access secrets in kube-system" \
        get secrets $sa -n kube-system
}

# ---------------------------------------------------------------------------
# Tier 3 - App Operator
# ---------------------------------------------------------------------------
test_app_operator() {
    echo ""
    info "===== Tier 3: App Operator (SA: applications/app-operator) ====="

    local sa="--as=system:serviceaccount:applications:app-operator"

    check_allowed "CAN create deployments in applications" \
        create deployments $sa -n applications

    check_allowed "CAN create services in applications" \
        create services $sa -n applications

    check_allowed "CAN get pods in applications" \
        get pods $sa -n applications

    check_allowed "CAN create configmaps in applications" \
        create configmaps $sa -n applications

    check_denied "CANNOT get pods in security-monitoring" \
        get pods $sa -n security-monitoring

    check_denied "CANNOT create namespaces" \
        create namespaces $sa

    check_denied "CANNOT delete clusterroles" \
        delete clusterroles $sa

    check_denied "CANNOT access secrets in kube-system" \
        get secrets $sa -n kube-system
}

# ---------------------------------------------------------------------------
# Tier 4 - Auditor
# ---------------------------------------------------------------------------
test_auditor() {
    echo ""
    info "===== Tier 4: Auditor (SA: default/auditor) ====="

    local sa="--as=system:serviceaccount:default:auditor"

    check_allowed "CAN get pods in any namespace" \
        get pods $sa --all-namespaces

    check_allowed "CAN list deployments in any namespace" \
        list deployments $sa --all-namespaces

    check_allowed "CAN list services in any namespace" \
        list services $sa --all-namespaces

    check_allowed "CAN list namespaces" \
        list namespaces $sa

    check_denied "CANNOT create deployments" \
        create deployments $sa -n applications

    check_denied "CANNOT delete pods" \
        delete pods $sa -n applications

    check_denied "CANNOT create secrets" \
        create secrets $sa -n default

    check_denied "CANNOT delete namespaces" \
        delete namespaces $sa
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================================"
    echo "  RBAC Verification Summary"
    echo "============================================================"

    for r in "${RESULTS[@]}"; do
        echo -e "  ${r}"
    done

    echo "============================================================"
    echo -e "  Total: ${TOTAL}   ${GREEN}Passed: ${PASSED}${NC}   ${RED}Failed: ${FAILED}${NC}"
    echo "============================================================"

    if [[ "$FAILED" -gt 0 ]]; then
        error "Some RBAC checks failed. Review the results above."
        return 1
    else
        success "All RBAC checks passed!"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  RBAC Verification - Kubernetes Security Operations Platform"
    echo "============================================================"

    # Verify connectivity
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach a Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    test_cluster_admin
    test_security_operator
    test_app_operator
    test_auditor

    print_summary
}

main "$@"
