# Architecture & Design Decisions

## Overview

This platform implements defense-in-depth security on AWS EKS using open-source tools. Each layer addresses a distinct threat category while maintaining operational simplicity.

## Key Design Decisions

### EKS (managed) over self-managed Kubernetes

EKS handles control plane operations (etcd, certificates, API server upgrades), letting this project focus on security operations — the actual work of a security engineer. Self-managed K8s adds operational burden without adding security learning value.

### Wazuh on separate EC2, not inside the cluster

**Rationale:**
- **Circular dependency** — SIEM monitoring a cluster should not live inside that cluster. If the cluster goes down, monitoring goes down with it.
- **Resource requirements** — Wazuh (indexer + manager + dashboard) needs ~6 GB RAM minimum, too heavy for small EKS nodes.
- **Cost** — A single `t3.large` EC2 with Docker Compose is cheaper than scaling the node group.
- **Independence** — Wazuh agents run as a DaemonSet inside EKS and forward to the external manager.

### Single NAT Gateway

Production environments use one NAT Gateway per AZ for HA. This project uses one to save ~$32/mo per additional gateway. Acceptable for a non-production learning environment.

### Spot instances everywhere

Worker nodes and Wazuh EC2 use spot instances. This saves ~60% on compute costs. The tradeoff is potential interruption, which is acceptable for a dev/learning environment.

### Network policy via VPC CNI (not Calico)

EKS 1.25+ supports NetworkPolicy natively through the VPC CNI plugin. This avoids deploying a separate CNI plugin (Calico, Cilium) and reduces complexity while still providing namespace-level microsegmentation.

## Security Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Layer 7: CI/CD Security                                  │
│   tfsec, checkov, kubeconform, Trivy                    │
├─────────────────────────────────────────────────────────┤
│ Layer 6: SIEM / Log Analysis                             │
│   Wazuh (external) ← Wazuh Agent DaemonSet              │
├─────────────────────────────────────────────────────────┤
│ Layer 5: Runtime Detection                               │
│   Falco (eBPF) → Falcosidekick → Prometheus → Grafana  │
├─────────────────────────────────────────────────────────┤
│ Layer 4: Admission Control                               │
│   OPA Gatekeeper (6 constraint templates)                │
├─────────────────────────────────────────────────────────┤
│ Layer 3: Network Segmentation                            │
│   NetworkPolicy: default-deny + explicit allow rules     │
├─────────────────────────────────────────────────────────┤
│ Layer 2: Access Control                                  │
│   4-tier RBAC model (Admin/SecOps/AppOps/Auditor)        │
├─────────────────────────────────────────────────────────┤
│ Layer 1: Infrastructure Hardening                        │
│   Private subnets, KMS encryption, control plane logging│
│   Pod Security Standards (restricted profile)            │
└─────────────────────────────────────────────────────────┘
```

## Namespace Design

| Namespace | PSS Profile | Purpose |
|-----------|-------------|---------|
| `security-monitoring` | `privileged` | Prometheus, Grafana, Falco (needs host access) |
| `security-enforcement` | `baseline` | OPA Gatekeeper |
| `applications` | `restricted` | Demo app, user workloads |
| `wazuh-agents` | `privileged` | Wazuh DaemonSet (needs host log access) |

Security tools like Falco and Wazuh agents need `privileged` because they must access host-level resources (eBPF, /var/log). This is expected and documented as a conscious tradeoff.

## Data Flow

1. **Falco** (DaemonSet) monitors syscalls via eBPF on each node
2. **Falcosidekick** receives Falco alerts and exposes Prometheus metrics
3. **Prometheus** scrapes Falcosidekick and all cluster metrics
4. **Grafana** visualizes security dashboards from Prometheus data
5. **Wazuh agents** (DaemonSet) forward host logs to external Wazuh manager
6. **Gatekeeper** intercepts API server admission requests and enforces policies
7. **NetworkPolicy** (VPC CNI) enforces pod-to-pod traffic rules at the kernel level
