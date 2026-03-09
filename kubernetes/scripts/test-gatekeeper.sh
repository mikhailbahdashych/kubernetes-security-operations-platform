#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# test-gatekeeper.sh - Gatekeeper (OPA) policy verification
#
# For each test-violation manifest, attempts to apply it and expects
# Gatekeeper to REJECT the resource. Also verifies that a compliant
# resource is ACCEPTED.
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
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VIOLATIONS_DIR="${K8S_DIR}/manifests/gatekeeper-policies/test-violations"

TOTAL=0
PASSED=0
FAILED=0
RESULTS=()

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
pass() {
    local desc="$1"
    (( TOTAL++ ))
    (( PASSED++ ))
    RESULTS+=("${GREEN}PASS${NC}  ${desc}")
    echo -e "  ${GREEN}PASS${NC}  ${desc}"
}

fail() {
    local desc="$1"
    (( TOTAL++ ))
    (( FAILED++ ))
    RESULTS+=("${RED}FAIL${NC}  ${desc}")
    echo -e "  ${RED}FAIL${NC}  ${desc}"
}

# ---------------------------------------------------------------------------
# test_violation - Apply a manifest and expect Gatekeeper to reject it
# ---------------------------------------------------------------------------
test_violation() {
    local name="$1"
    local file="$2"

    info "Testing violation: ${name}"

    local output
    output=$(kubectl apply -f "$file" 2>&1 || true)

    if echo "$output" | grep -qiE "denied|Error from server|admission webhook.*denied|violated|forbidden"; then
        pass "${name} was correctly rejected"
    else
        fail "${name} was NOT rejected - policy may not be working"
        # Clean up the resource if it was accidentally created
        kubectl delete -f "$file" --ignore-not-found 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# test_compliant - Apply a compliant pod and expect it to be accepted
# ---------------------------------------------------------------------------
test_compliant() {
    info "Testing compliant resource (should be ACCEPTED)..."

    local compliant_manifest
    compliant_manifest=$(cat <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: gatekeeper-test-compliant
  namespace: applications
  labels:
    app: compliant-test
    team: platform
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: compliant
      image: docker.io/library/nginx:1.25.4
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop:
            - ALL
      ports:
        - containerPort: 8080
YAML
)

    local output
    output=$(echo "$compliant_manifest" | kubectl apply -f - 2>&1 || true)

    if echo "$output" | grep -qiE "created|configured|unchanged"; then
        pass "Compliant pod was correctly accepted"
        # Clean up
        kubectl delete pod gatekeeper-test-compliant -n applications --ignore-not-found 2>/dev/null || true
    else
        if echo "$output" | grep -qiE "denied|forbidden|violated"; then
            fail "Compliant pod was rejected (policies may be too strict)"
        else
            fail "Compliant pod test had unexpected result: ${output}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# test_individual_violations - Split multi-doc YAML and test each
# ---------------------------------------------------------------------------
test_individual_violations() {
    local file="$1"
    local basename
    basename=$(basename "$file" .yaml)

    # Count documents in the file
    local doc_count
    doc_count=$(grep -c '^---' "$file" 2>/dev/null || echo "0")

    if [[ "$doc_count" -gt 0 ]]; then
        # Multi-document YAML: split and test each
        local idx=0
        local tmpdir
        tmpdir=$(mktemp -d)

        # Use awk to split on --- boundaries
        awk '/^---$/{idx++; next} {print > "'"${tmpdir}"'/doc-" idx ".yaml"}' idx=0 "$file"

        for doc in "${tmpdir}"/doc-*.yaml; do
            if [[ -f "$doc" ]] && [[ -s "$doc" ]]; then
                local kind name
                kind=$(grep -m1 '^kind:' "$doc" | awk '{print $2}' || echo "unknown")
                name=$(grep -m1 'name:' "$doc" | awk '{print $NF}' || echo "unknown")
                test_violation "${basename} (${kind}/${name})" "$doc"
            fi
        done

        rm -rf "$tmpdir"
    else
        # Single-document YAML
        test_violation "$basename" "$file"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================================"
    echo "  Gatekeeper Policy Test Summary"
    echo "============================================================"

    for r in "${RESULTS[@]}"; do
        echo -e "  ${r}"
    done

    echo "============================================================"
    echo -e "  Total: ${TOTAL}   ${GREEN}Passed: ${PASSED}${NC}   ${RED}Failed: ${FAILED}${NC}"
    echo "============================================================"

    if [[ "$FAILED" -gt 0 ]]; then
        error "Some Gatekeeper policy tests failed. Review results above."
        return 1
    else
        success "All Gatekeeper policy tests passed!"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "============================================================"
    echo "  Gatekeeper Policy Tests - Kubernetes Security Ops Platform"
    echo "============================================================"

    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot reach a Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # Verify Gatekeeper is running
    if ! kubectl get crd constrainttemplates.templates.gatekeeper.sh &>/dev/null; then
        error "Gatekeeper CRDs not found. Is Gatekeeper installed?"
        exit 1
    fi

    info "Gatekeeper is installed. Running policy tests..."
    echo ""

    # Test violations
    if [[ ! -d "$VIOLATIONS_DIR" ]]; then
        warn "Test violations directory not found: ${VIOLATIONS_DIR}"
    else
        local violation_files
        violation_files=$(find "$VIOLATIONS_DIR" -name '*.yaml' -o -name '*.yml' | sort)

        if [[ -z "$violation_files" ]]; then
            warn "No test violation files found in ${VIOLATIONS_DIR}"
        else
            info "Found violation test files in ${VIOLATIONS_DIR}"
            echo ""

            while IFS= read -r vfile; do
                test_individual_violations "$vfile"
            done <<< "$violation_files"
        fi
    fi

    echo ""

    # Test that a compliant resource passes
    test_compliant

    print_summary
}

main "$@"
