# Cost Analysis

## Running 24/7

| Resource | Spec | Monthly Cost |
|----------|------|-------------|
| EKS control plane | 1 cluster | $73.00 |
| Worker nodes | 2x t3.medium spot (~$0.0104/hr) | ~$15.00 |
| NAT Gateway | 1 AZ, ~$0.045/hr + data | ~$32.00 |
| EBS volumes | 80 GB gp3 | ~$8.00 |
| CloudWatch logs | EKS control plane logs | ~$5.00 |
| Wazuh EC2 (optional) | t3.large spot (~$0.025/hr) | ~$22.00 |
| **Total without Wazuh** | | **~$133.00** |
| **Total with Wazuh** | | **~$155.00** |

## Running 8 hours/day (tear down nightly)

| Resource | Reduction | Monthly Cost |
|----------|-----------|-------------|
| EKS control plane | Only charged when running | ~$24.00 |
| Worker nodes | ~33% of full month | ~$5.00 |
| NAT Gateway | ~33% of full month | ~$11.00 |
| EBS volumes | Destroyed with cluster | ~$0.00 |
| CloudWatch logs | Minimal | ~$2.00 |
| **Total without Wazuh** | | **~$42.00** |

## Cost Optimization Strategies Applied

1. **Spot instances** — Worker nodes and Wazuh EC2 use spot pricing (~60% savings)
2. **Single NAT Gateway** — One instead of per-AZ (~$32/mo savings)
3. **24h Prometheus retention** — Minimizes storage costs
4. **Grafana persistence disabled** — Uses ephemeral storage in dev
5. **Wazuh opt-in** — Only deployed when `deploy_wazuh = true`
6. **Tear down when idle** — `terraform destroy` stops all billing

## Spot Pricing Reference (eu-central-1)

| Instance | On-Demand | Spot (avg) | Savings |
|----------|-----------|------------|---------|
| t3.medium | $0.0416/hr | $0.0104/hr | 75% |
| t3.large | $0.0832/hr | $0.0250/hr | 70% |

*Spot prices fluctuate. Check [AWS Spot Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/) for current rates.*
