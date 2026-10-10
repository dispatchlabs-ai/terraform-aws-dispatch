# AWS planning estimate — October 10, 2026

**USD, us-east-1, 730 hours/month, Linux ARM64, public On-Demand rates.** This is
an estimate for the new managed-domain topology, not a bill, capacity benchmark,
regional availability check or approval to deploy. No AWS account was queried.
No free tiers, credits, Savings Plans, taxes or negotiated discounts are assumed.

The [idle/active comparison](idle-cost-estimate.md) prices the low-idle design
separately. The two-ALB/NAT figures below retain the original baseline assumptions;
they are not the single-ALB/public-IP estimate or a measured bill.

## Original always-on baseline

Assume one backend and one launcher (each 0.5 vCPU / 2 GiB), two **private** ALBs,
one NAT gateway/EIP, one Aurora Serverless v2 writer at its 0.5-ACU floor, 20 GB of
database data, 17 retained Secrets Manager secrets, and three allocated hosted-zone
charges (public zone, private callback zone and Cloud Map's private namespace). A shared existing public
zone may have no incremental hosted-zone charge.

| Component | Rate / calculation | Monthly |
|---|---|---:|
| Two Fargate controllers | 2 × 730 × (0.5 × $0.03238 + 2 × $0.00356) | $34.03 |
| Aurora Standard Serverless v2 compute | 0.5 × 730 × $0.12/ACU-hour | $43.80 |
| Aurora Standard storage | 20 GB × $0.10/GB-month | $2.00 |
| One NAT gateway | 730 × $0.045/hour | $32.85 |
| NAT public IPv4 | 730 × $0.005/hour | $3.65 |
| Two ALBs | 2 × 730 × $0.0225/hour | $32.85 |
| Secrets | 17 × $0.40/month | $6.80 |
| Hosted zones | 3 × $0.50/month | $1.50 |
| **Fixed/assumed-storage subtotal** | Before usage, workers or inference | **$157.48** |

The nonessential ADOT collector has a 256-MiB limit / 64-MiB reservation **inside
the existing 2-GiB task**, not a separately billed Fargate task. It consumes that
budget and CPU; it is not free application capacity. If measurements require
larger task sizes, recalculate both controllers and workers. Default Fargate
20-GiB ephemeral storage is included; no EFS, S3 Files, reader, proxy or telemetry
cluster is provisioned. Private CloudFront VPC origins avoid public ALB IPv4
charges. An internet-facing ALB would add at least two billable IPv4 addresses.

### Modest-traffic allowance

A concrete example adds **$7.33/month** using these assumptions:

- Both ALBs average 0.1 LCU each: $1.17 ($0.008/LCU-hour).
- NAT processes 5 GB: $0.23; separately budget 5 GB internet egress at $0.09/GB:
  $0.45. Actual paths/cross-AZ transfers can change this. S3 uses the gateway endpoint.
- Aurora performs 5 million billable I/Os: $1.00 ($0.20/million).
- CloudWatch ingests 5 GB of logs: $2.50; seven-day steady-state retained volume:
  approximately $0.04 at $0.03/GB-month, before compression. Short retention does
  **not** reduce ingestion charges; payload-heavy logging is not acceptable.
- S3 holds 5 GB of assets/artifacts plus seven days of 1 GB/month ALB log generation:
  approximately $0.12; 50,000 PUT/LIST and 100,000 GET requests: $0.29.
- 100,000 recorded X-Ray traces (e.g. one million eligible roots sampled at 10%):
  $0.50 at $5/million recorded traces. Real span/root counts must be measured;
  trace retrieval/scanning adds $0.50/million accessed. X-Ray retention is its
  service-defined **30 days**, not the seven-day CloudWatch setting.
- CloudFront delivers 10 GB to North America and serves 100,000 HTTPS requests:
  $0.95 ($0.085/GB and $0.01/10,000 requests).
- 10,000 Secrets Manager API calls and 100,000 billable non-alias DNS queries:
  $0.09. Eligible AWS alias queries are not billed as ordinary DNS queries.

That is **about $164.81/month before workers**, plus a small allowance for Cloud
Map registrations/discovery API calls and temporary rolling-overlap tasks. Use
**roughly $166/month** as this scenario's planning baseline, not a price ceiling.
The application starts with zero desired controllers until explicit bootstrap;
that saves controller runtime initially but does **not** stop database/NAT/ALB costs.

## Database choice and scaling sensitivity

| Compute assumption | Aurora v2 Standard/month |
|---|---:|
| Constant 0.5 ACU (minimum) | $43.80 |
| Average 1 ACU | $87.60 |
| Average 2 ACUs | $175.20 |
| Constant configured 4-ACU ceiling | $350.40 |

Storage and I/O are additional. The ceiling bounds compute scaling, not total
spend. An average one-ACU database raises the baseline by $43.80/month.
While Dispatch owners remain running, their persistent connections **prevent
auto-pause**; do not estimate zero compute from browser inactivity alone. An
explicit zero-ACU setting can permit Aurora to pause only after every connection
closes; see the [idle comparison and wake constraints](idle-cost-estimate.md).
Failover/connection-loss recovery is a separate
application qualification, not transparent reconnect promised by Serverless.

The selectable small-RDS alternative is **db.t4g.small**, $0.032/hour = $23.36/month,
plus 20 GiB gp3 at $0.115 = $2.30/month. Replacing Aurora's minimum compute/storage
with these gives a **$137.34 subtotal**, roughly $20/month less, before usage.
It lacks automatic compute scaling and is single-AZ. Sustained CPU beyond the
burstable allowance can cost extra; memory/connections and CPU credits must be
measured. Aurora is the autoscaling default, **not claimed to be cheapest** for a
small steady workload. I/O-Optimized Aurora starts at $0.16/ACU-hour and $0.225/GB-month;
its higher floor is not selected for the small baseline.

## Workers: pay for running time, not just model-call time

At the current 0.5-vCPU / 2-GiB ARM64 size, On-Demand is **$0.02331/task-hour**.
These are aggregate **running-task hours**, including startup and idle lifetime.
Spot discounts below are explicit planning scenarios, **not current Spot quotes**;
capacity may be unavailable and interruption/recovery can offset savings.

| Aggregate worker hours/month | On-Demand | At 50% Spot discount | At 70% Spot discount |
|---|---:|---:|---:|
| 100 | $2.33 | $1.17 | $0.70 |
| 300 (about 10 hours/day total) | $6.99 | $3.50 | $2.10 |
| 730 (one task always running) | $17.02 | $8.51 | $5.10 |
| 3,000 | $69.93 | $34.97 | $20.98 |

Controllers stay On-Demand. There is no automatic Spot-to-On-Demand replay after
an uncertain launch. Do not size savings from peak conversation count alone, or
promise exactly-once tools / preserved uncommitted workspace files after interruption.
At this small size, NAT/ALB/database dominate; Spot is not a substitute for bounded
worker lifetimes. Ten continuously retained workers cost about $170/month On-Demand.

## Exclusions and operational implications

Inference/provider subscriptions, model and tool API bills are **not included** and
can exceed AWS infrastructure. Also excluded: domain registration, optional private
CA services, unusually large backup/snapshot retention, RDS CPU-credit overage,
CloudWatch queries/alarms, heavy trace retrieval, optional ECR mirroring, CI/image
builds, extra egress/cross-AZ traffic, larger tasks and larger artifact storage.
Backups beyond included allowances and retained old SPA releases must be budgeted.
No reserved LCU capacity or enterprise monitoring stack is assumed. One NAT and
one writer are deliberately economical, not multi-AZ compute failover guarantees.
Do not reduce availability/ownership guarantees merely to fit the estimate.

## Rate evidence and reproduction

Fetched public AWS price lists on **October 10, 2026**. For each list, join
`products[sku].attributes` to `terms.OnDemand[sku].*.priceDimensions.*`; select
us-east-1, Linux ARM64, Aurora PostgreSQL Standard or PostgreSQL Single-AZ as above.
Amounts are ordinary rate × quantity calculations, rounded only for display.

- [Fargate price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonECS/current/us-east-1/index.json), published September 11.
- [RDS/Aurora price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/us-east-1/index.json), published October 6.
- [ALB price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/us-east-1/index.json), [IPv4 price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-east-1/index.json), and [NAT/egress pricing examples](https://aws.amazon.com/vpc/pricing/).
- [CloudWatch](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudWatch/current/us-east-1/index.json), [X-Ray](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSXRay/current/us-east-1/index.json), [S3](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/us-east-1/index.json), [Secrets Manager](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSSecretsManager/current/us-east-1/index.json).
- [CloudFront](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudFront/current/index.json), [Route 53](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRoute53/current/index.json).

`current` URLs change. Re-price the selected region and actual saved plan before
any apply, then check real utilization/billing after an authorized deployment.
