# Threat Model

## Scope

This threat model covers the Kubernetes Security Operations Platform and maps each implemented control to the threats it mitigates.

## Threat Matrix

| # | Threat | MITRE ATT&CK | Control | Implementation |
|---|--------|---------------|---------|----------------|
| T1 | Unauthorized cluster access | Initial Access (T1078) | RBAC | 4-tier role model with least-privilege bindings |
| T2 | Lateral movement between namespaces | Lateral Movement (T1570) | NetworkPolicy | Default-deny all, explicit allow per service |
| T3 | Privileged container escape | Privilege Escalation (T1611) | Gatekeeper + PSS | `no-privileged-containers` constraint, `restricted` PSS |
| T4 | Malicious image deployment | Execution (T1610) | Gatekeeper | `trusted-registries` constraint, `no-latest-tag` |
| T5 | Container shell access | Execution (T1059) | Falco | "Terminal Shell in Container" rule |
| T6 | Credential harvesting | Credential Access (T1552) | Falco | "Sensitive File Access" rule (/etc/shadow) |
| T7 | Data exfiltration | Exfiltration (T1041) | Falco + NetworkPolicy | "Unexpected Outbound Connection" + egress deny |
| T8 | Privilege escalation via setuid | Privilege Escalation (T1548) | Falco + Gatekeeper | "Privilege Escalation Attempt" rule, read-only rootfs |
| T9 | Resource exhaustion (DoS) | Impact (T1499) | Gatekeeper | `required-resource-limits` constraint |
| T10 | Secrets exposure at rest | Collection (T1005) | KMS | Envelope encryption for etcd secrets |
| T11 | Insecure IaC deployment | Initial Access | CI/CD | tfsec, checkov, Trivy scanning in pipeline |
| T12 | Missing audit trail | Defense Evasion (T1562) | EKS audit logs + Wazuh | CloudWatch audit logs, Wazuh SIEM |
| T13 | Container filesystem tampering | Persistence (T1546) | Gatekeeper | `read-only-root-filesystem` constraint |

## Trust Boundaries

```
                    ┌──────────────────────────────┐
                    │       Internet                │
                    └──────────┬───────────────────┘
                               │ Trust Boundary 1
                    ┌──────────▼───────────────────┐
                    │    AWS VPC / EKS API           │
                    │    (IAM + OIDC authentication) │
                    └──────────┬───────────────────┘
                               │ Trust Boundary 2
                    ┌──────────▼───────────────────┐
                    │    K8s Admission Control       │
                    │    (Gatekeeper + PSS)           │
                    └──────────┬───────────────────┘
                               │ Trust Boundary 3
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──┐   ┌────────▼───┐   ┌────────▼───┐
    │ security-* │   │ applications│   │ wazuh-*    │
    │ namespaces │   │ namespace   │   │ namespace   │
    │ (operator  │   │ (app team   │   │ (agent     │
    │  access)   │   │  access)    │   │  only)      │
    └────────────┘   └─────────────┘   └─────────────┘
         NetworkPolicy isolation between namespaces
```

## Residual Risks

| Risk | Severity | Mitigation Status | Notes |
|------|----------|-------------------|-------|
| Spot instance interruption | Low | Accepted | Dev/learning environment; not production |
| Single NAT Gateway (no AZ HA) | Low | Accepted | Cost optimization for non-production |
| Wazuh default passwords | Medium | Documented | Must be changed before any real use |
| No network encryption (mTLS) | Medium | Out of scope | Would add service mesh (Istio/Linkerd) |
| No image signing verification | Medium | Out of scope | Would add Sigstore/Cosign |
| EKS public endpoint | Low | Accepted | Restricted by IAM; private access also enabled |
