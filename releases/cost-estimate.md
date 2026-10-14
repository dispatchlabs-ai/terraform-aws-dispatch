# AWS planning estimate — October 14, 2026

**USD, us-east-1, 730 hours/month, Linux ARM64, public On-Demand rates.** Rates
were rechecked against AWS public pricing on October 14, 2026. This is a planning
estimate, not a measured bill, capacity benchmark, regional availability check or
approval to deploy. No AWS account was queried. No free tiers, credits, Savings
Plans, taxes or negotiated discounts are assumed.

**Budget roughly $120–$140/month for light always-on usage**, including a modest
number of worker-hours, if Aurora stays near 0.5 ACU. Model and tool API charges
are separate. The [idle/active comparison](idle-cost-estimate.md) covers explicit
sleep/wake and part-time use; sleeping is not the default.

## Current always-on baseline

This prices an **activated managed-domain installation** using the current
network defaults: `task_egress = "public-ip"`, `internal_alb = true`, and
`launcher_internal_alb = true`. The backend API, launcher control and backend
callbacks share **one private ALB**; no NAT gateway is created. Tasks receive
public IPv4 for outbound access, while security groups restrict ingress and the
database stays private.

Assume one backend and one launcher (`desired_count = 1`), each 0.5 vCPU / 2 GiB,
one Aurora Serverless v2 Standard writer averaging its default 0.5-ACU floor,
20 GB of database data, 17 retained Secrets Manager secrets, and three allocated
hosted-zone charges (public zone, private callback zone and Cloud Map's private
namespace). Aurora storage is actual consumed storage, not a 20-GB allocation.

| Component | Rate / calculation | Monthly |
|---|---|---:|
| Two Fargate controllers | 2 × 730 × (0.5 × $0.03238 + 2 × $0.00356) | $34.03 |
| Controller public IPv4 | 2 × 730 × $0.005/hour | $7.30 |
| Aurora Standard Serverless v2 compute | 0.5 × 730 × $0.12/ACU-hour | $43.80 |
| Aurora Standard storage | 20 GB × $0.10/GB-month | $2.00 |
| One private ALB | 730 × $0.0225/hour | $16.43 |
| Secrets | 17 × $0.40/month | $6.80 |
| Hosted zones | 3 × $0.50/month | $1.50 |
| **Fixed/assumed-storage subtotal** | Sum before display rounding; before usage, workers or inference | **$111.86** |

The 17-secret assumption includes 16 caller-supplied application secrets (seven
DB URLs, three encryption keys, five tokens and one backend private key) plus the
RDS-managed master secret. The public hosted zone already belongs to the caller;
a shared existing zone may have no incremental hosted-zone cost (subtract $0.50
from this allocated estimate). Counts and storage must be adjusted to the caller.

The module defaults to `image = null`, `application = null`, `domain = null` and
`desired_count = 0`, preparing foundation rather than activating this full profile.
With a full installation retained but all tasks stopped, the default
`aurora_min_capacity = 0.5` still leaves **$70.53/month** before usage under the
same storage/secret/zone assumptions. Zero desired controllers is not zero cost.
A minimal foundation without application secrets or a managed domain has a
different bill; this table does not assume those caller-owned resources exist.

The nonessential ADOT collector has a 256-MiB limit / 64-MiB reservation **inside
the existing 2-GiB task**, not a separately billed Fargate task. It consumes that
budget and CPU; it is not free application capacity. If measurements require
larger task sizes, recalculate controllers and workers. Default Fargate 20-GiB
ephemeral storage is included; no EFS, S3 Files, reader, proxy or telemetry cluster
is provisioned. VPC/subnets, security groups, IAM, the S3 gateway endpoint and
non-exportable public ACM certificates used here have no separate standing fee.
Private CloudFront VPC origins avoid public ALB IPv4 charges.

### Modest-traffic allowance

A concrete example adds **$7.33/month** using these assumptions:

- The shared ALB averages 0.1 LCU: $0.58 ($0.008/LCU-hour).
- Tasks send 5 GB of internet egress at $0.09/GB: $0.45. No NAT processing fee
  applies in this profile. Actual paths/cross-AZ transfers can change this;
  S3 uses the gateway endpoint.
- Aurora performs 5 million billable I/Os: $1.00 ($0.20/million).
- CloudWatch ingests 5 GB of logs: $2.50; seven-day steady-state retained volume:
  approximately $0.03 at $0.03/GB-month, before compression. Short retention does
  **not** reduce ingestion charges; payload-heavy logging is not acceptable.
- S3 holds 5 GB of assets/artifacts plus seven days of 1 GB/month ALB log generation:
  approximately $0.12 at $0.023/GB-month; 50,000 PUT/LIST and 100,000 GET requests:
  $0.29 ($0.005/1,000 PUT/LIST and $0.0004/1,000 GET).
- 100,000 recorded X-Ray traces (e.g. one million eligible roots sampled at 10%):
  $0.50 at $5/million recorded traces. Real span/root counts must be measured;
  trace retrieval/scanning adds $0.50/million accessed. X-Ray retention is its
  service-defined **30 days**, not the seven-day CloudWatch setting.
- CloudFront delivers 10 GB to North America and serves 100,000 HTTPS requests:
  $0.95 ($0.085/GB and $0.01/10,000 requests), plus 100,000 edge-function
  executions: $0.01 ($0.10/million). Free allowances are deliberately ignored.
- 10,000 Secrets Manager API calls and 100,000 billable non-alias DNS queries:
  $0.09. Eligible AWS alias queries are not billed as ordinary DNS queries.
- Private ECR holds 5 GB of images: $0.50 ($0.10/GB-month). Same-region image
  pulls to Fargate have no ECR data-transfer fee; optional NAT processing is separate.
- Cloud Map retains three registered resources (backend, launcher and callback
  ingress): $0.30 ($0.10/resource-month). HTTP discovery calls, if used, add
  $1/million; DNS queries are budgeted above.

That is **about $119.19/month before workers**, or **$127.68/month with 300
worker-hours**, before temporary rolling overlap and any usage beyond these
assumptions. Use **$120–$140/month** as a light-use planning range, not a price
ceiling. Component amounts are rounded for display; totals use unrounded values.

## Database choice and scaling sensitivity

| Compute assumption | Aurora v2 Standard/month |
|---|---:|
| Constant 0.5 ACU (default minimum) | $43.80 |
| Average 1 ACU | $87.60 |
| Average 2 ACUs | $175.20 |
| Constant configured 4-ACU ceiling | $350.40 |

Storage and I/O are additional. The ceiling bounds compute scaling, not total
spend. An average one-ACU database raises the baseline by $43.80/month; a constant
four-ACU database raises it by $306.60/month. While Dispatch owners remain running,
their persistent connections **prevent auto-pause**; do not estimate zero compute
from browser inactivity alone. An explicit zero-ACU setting can permit Aurora to
pause only after every connection closes; see the [idle comparison and wake
constraints](idle-cost-estimate.md). Failover/connection-loss recovery is a
separate application qualification, not transparent reconnect promised by Serverless.

The selectable small-RDS alternative is **db.t4g.small**, $0.032/hour = $23.36/month,
plus 20 GiB gp3 at $0.115/GiB-month = $2.30/month. Replacing Aurora's minimum
compute/storage with these gives a **$91.72 subtotal**, roughly $20/month less,
before workers and usage. It lacks automatic compute scaling/auto-pause and is
single-AZ. Sustained CPU beyond the burstable allowance can cost extra;
memory/connections and CPU credits must be measured. Aurora is the autoscaling
default, **not claimed to be cheapest** for a small steady workload. I/O-Optimized
Aurora costs $0.16/ACU-hour and $0.225/GB-month; it is not selected by this module.

## Workers: pay for running time, not just model-call time

At the current 0.5-vCPU / 2-GiB ARM64 size, On-Demand compute is
**$0.02331/task-hour**, plus **$0.005/public-IP-hour** in the default network:
**$0.02831 per running worker-hour**. These are aggregate **running-task hours**,
including startup, idle lifetime and draining. Spot discounts below are explicit
planning scenarios, **not current Spot quotes**; they discount compute only.
Capacity may be unavailable and interruption/recovery can offset savings.

| Aggregate worker hours/month | On-Demand + IPv4 | At 50% compute Spot discount + IPv4 | At 70% compute Spot discount + IPv4 |
|---|---:|---:|---:|
| 100 | $2.83 | $1.67 | $1.20 |
| 300 (about 10 hours/day total) | $8.49 | $5.00 | $3.60 |
| 730 (one task always running) | $20.67 | $12.16 | $8.75 |
| 3,000 | $84.93 | $49.97 | $35.98 |

Controllers stay On-Demand. There is no automatic Spot-to-On-Demand replay after
an uncertain launch. Do not size savings from peak conversation count alone, or
promise exactly-once tools / preserved uncommitted workspace files after interruption.
At this small size, shared database/ingress/controllers dominate; Spot is not a
substitute for bounded worker lifetimes. Ten continuously retained workers cost
about $207/month On-Demand including IPv4, in addition to the shared installation.

## Optional networks and historical comparison

Setting `task_egress = "nat"` keeps tasks private and adds one permanent NAT gateway
and EIP: **$36.50/month** ($0.045/hour NAT + $0.005/hour IPv4), plus $0.045/GB NAT
processing. Remove each task's public-IP charge when comparing. With the same
shared private ALB and two always-on controllers, the subtotal becomes
**$141.06/month**, before workers and usage. The [idle comparison](idle-cost-estimate.md)
explains the 7,300 aggregate task-hour break-even before processing/cross-AZ fees.

A caller-owned internet-facing API ALB also retains a separate private control
ALB: budget an extra **$16.43/month** ALB fee and at least **$7.30/month** for two
public ALB IPv4 addresses, plus its LCU usage. This is not the managed-domain profile.

The earlier estimate assumed **two private ALBs plus NAT/EIP**: $157.48 before
workers/usage, roughly $166 with its traffic allowance. That is a **historical
comparison, not the current managed-domain default or a selectable two-private-ALB
profile**. Keeping NAT does not by itself restore a second ALB.

## Exclusions and operational implications

Inference/provider subscriptions, model and tool API bills are **not included** and
can exceed AWS infrastructure. Also excluded beyond the examples above: domain
registration, caller-owned KMS keys/requests, optional private CA services,
unusually large backup/snapshot retention, RDS CPU-credit overage, CloudWatch
queries/alarms, heavy trace retrieval, CI/image builds, enhanced image scanning,
extra egress/cross-AZ traffic, larger tasks and larger image/artifact storage.
Backups beyond included allowances, versioned artifacts and retained old SPA/image
releases must be budgeted. No reserved LCU capacity or enterprise monitoring stack
is assumed. One writer (and one NAT in optional NAT mode) is deliberately economical,
not a multi-AZ compute failover guarantee. Do not reduce availability/ownership
guarantees merely to fit the estimate.

## Rate evidence and reproduction

Fetched public AWS price lists and reviewed linked pricing pages on **October 14,
2026**. The checked rates used here are unchanged from the earlier October 10
estimate; the primary correction is pricing the current topology and including
small ECR/Cloud Map/edge-function allowances. For each price list, join
`products[sku].attributes` to `terms.OnDemand[sku].*.priceDimensions.*`; select
us-east-1, Linux ARM64, Aurora PostgreSQL Standard or PostgreSQL Single-AZ as above.
Exclude Aurora Serverless v1, I/O-Optimized, Outposts and free-tier dimensions.
CloudFront uses US edge delivery prices; Route 53 hosted zones use global prices.
Amounts are ordinary rate × quantity calculations, rounded only for display.

- [Fargate price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonECS/current/us-east-1/index.json): ARM vCPU $0.03238/hour and memory $0.00356/GiB-hour.
- [RDS/Aurora price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/us-east-1/index.json): `Aurora:ServerlessV2Usage` $0.12/ACU-hour, Standard storage $0.10/GB-month and I/O $0.20/million; PostgreSQL Single-AZ `db.t4g.small` $0.032/hour and gp3 $0.115/GiB-month.
- [ALB price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/us-east-1/index.json): `LoadBalancing:Application` $0.0225/hour and $0.008/LCU-hour; [IPv4 price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-east-1/index.json): in-use address $0.005/hour; [NAT/egress pricing examples](https://aws.amazon.com/vpc/pricing/).
- [CloudWatch](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudWatch/current/us-east-1/index.json), [X-Ray](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSXRay/current/us-east-1/index.json), [S3](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/us-east-1/index.json), [Secrets Manager](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSSecretsManager/current/us-east-1/index.json).
- [CloudFront](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudFront/current/index.json), [Route 53](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRoute53/current/index.json), [private ECR](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonECR/current/us-east-1/index.json) and [Cloud Map pricing](https://aws.amazon.com/cloud-map/pricing/).

`current` URLs change. Re-price the selected region and actual saved plan before
any apply, then check real utilization/billing after an authorized deployment.
