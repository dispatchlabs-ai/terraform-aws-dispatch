# Idle and active cost comparison — October 10, 2026

**Planning estimates, not measured bills or verified sleep/wake behavior.** USD,
us-east-1, 730 hours/month, ARM64, public On-Demand rates; no free tiers or credits.
Rate sources and general exclusions are in the [baseline estimate](cost-estimate.md#rate-evidence-and-reproduction).

The low-idle design retains one private ALB for managed-domain CloudFront ingress
and private control/callback listeners. Tasks use public IPv4 for outbound access,
with ingress restricted by security-group references; the database remains private.
No NAT gateway, additional wake service or RDS Proxy is assumed. The selected wake
path is an explicit IAM-authorized operator action, not an anonymous browser wake.
A sleeping application is not immediately available: accepting that interruption
is the tradeoff for turning off its compute. Networking and lifecycle integration
must be qualified before treating these scenarios as achievable operating costs.

## Residual sleeping cost

Assume **all controllers, workers and operator tasks have stopped**, every database
connection has closed, and Aurora has actually auto-paused. Keep the same 20 GB of
database data, 17 Secrets Manager secrets and three hosted-zone charges as the
baseline. The retained ALB does not incur public IPv4 charges.

| Retained resource | Calculation | Monthly |
|---|---|---:|
| One private ALB | 730 × $0.0225/hour | $16.43 |
| Aurora storage | 20 GB × $0.10/GB-month | $2.00 |
| Secrets Manager | 17 × $0.40/month | $6.80 |
| Hosted zones | 3 × $0.50/month | $1.50 |
| **Fixed/assumed-storage subtotal** | Sum before display rounding | **$26.73** |

S3 storage, retained logs/backups, Cloud Map API calls, ALB LCU usage, requests,
maintenance wakes and operator-task time are additional. For example, 5 GB of
S3 Standard objects adds about $0.12/month before requests. Storage grows with
retained data and assets. This is not a $27 bill guarantee or a zero-cost service.

For comparison, keeping the old two-ALB/NAT network while stopping all tasks and
pausing Aurora leaves **$79.65/month** fixed/assumed-storage. Keeping controllers
and the database awake on the new single-ALB/public-IP network instead costs
**$111.86/month**, before workers and usage, assuming Aurora remains at 0.5 ACU.
Browser inactivity alone does not stop tasks or establish eligibility for sleep.

## Active-use scenarios

For the single-private-ALB/public-IP design, calculate the subtotal as:

```text
$26.725
+ controller task-hours × ($0.02331 Fargate + $0.005 public IPv4)
+ worker task-hours × ($0.02331 Fargate + $0.005 public IPv4)
+ database ACU-hours × $0.12
```

Count **billed task lifetime**, not only model-call time: image startup, idle time,
draining and rolling overlap count too. Operator tasks and any different task
sizes must be added separately. Database ACU-hours include warm-up, the final
connection-free auto-pause interval and maintenance; they are not necessarily
equal to active application hours. Controllers remain On-Demand.

The following simplified duty cycles assume both controllers run for the stated
hours, Aurora runs for the same hours at the stated average capacity, and all
compute sleeps otherwise. They exclude the extra intervals and usage just listed;
worker-hours are workload assumptions, **not an enforced retirement policy**.

| Hours awake/month | Average ACUs while awake | Aggregate worker-hours | Subtotal |
|---:|---:|---:|---:|
| 0 | 0 | 0 | $26.73 |
| 40 | 0.5 | 40 | $32.52 |
| 176 (22 × 8-hour days) | 0.5 | 300 | $55.74 |
| 176 | 1 | 300 | $66.30 |
| 730 | 0.5 | 730 | $132.52 |

For 300 worker-hours alone, On-Demand plus IPv4 is **$8.49**. Hypothetical 50%/70%
Spot discounts on **compute only** produce **$5.00/$3.60**, respectively; the $1.50
IPv4 component is not discounted. These are not actual Spot quotes. Capacity,
interruption recovery and lost disposable workspace files remain separate concerns.

Public IPv4 replaces the NAT/EIP's $36.50/month fixed cost with a per-task charge.
Ignoring NAT processing, that breaks even at **7,300 aggregate public-IP hours**
per month (ten tasks continuously present). Beyond that, the NAT alternative can
be cheaper; add its processing and any cross-AZ charges before comparing. An
IPv6-only approach is not assumed: external model/tool endpoints and required AWS
services must be checked for end-to-end compatibility first.

## Aurora auto-pause is conditional

The module accepts `aurora_min_capacity = 0` and
`aurora_seconds_until_auto_pause = 300` (whole seconds, range 300–86400). A nonzero
minimum disables auto-pause and omits the interval from the AWS request. The
minimum defaults to 0.5 unless the caller explicitly selects zero; this input does
not stop application tasks. Confirm the selected engine version's zero-ACU and
regional Serverless support before applying.

AWS's [auto-pause documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2-auto-pause.html),
reviewed October 10, 2026, establishes:

- **Any open user connection prevents pause**, even without queries. Dispatch's
  ownership connections must close gracefully after work and admission are safely
  settled. Do not kill connections underneath active tools or weaken ownership.
- A connection attempt, even with invalid credentials, wakes the instance. Keep
  PostgreSQL private; avoid health checks, session validation or polling that
  reopen it while asleep. RDS Proxy's retained connections prevent auto-pause.
- Typical database resume is about **15 seconds**; after more than 24 hours asleep,
  deeper sleep can take **30 seconds or longer**. Initial connection budgets must
  tolerate this. Increasing that budget must not reconnect a failed owner or replay
  an uncertain transaction. End-to-end wake also includes ECS scheduling, image
  pull, application startup, activation and health checks; it is not a 15-second SLA.
- The pause timer begins after the **last** user connection closes, not when the
  browser disconnects. At 0.5 ACU, a five-minute tail is $0.005; at 4 ACUs it is
  $0.04. Thirty such tails cost $0.15–$1.20 under those constant-capacity assumptions.
- Maintenance can wake a paused instance; AWS waits at least 20 minutes after an
  administrative wake before pausing again. Storage and applicable I/O remain
  billable. Aurora does not wake itself for database `pg_cron` jobs.
- A paused instance still reports `Available`. Verify actual zero capacity using
  `ServerlessDatabaseCapacity` and pause/resume events, not instance status or
  `ACUUtilization` alone. Fetching database logs can itself resume the instance.

No live AWS pause, wake, latency, security-path or billing verification is claimed
here. Offline Terraform/mock success verifies configuration only. The operational
sleep/wake procedure must preserve pending/background work, confirmed old-executor
termination, retained crash-recovery latches and explicit activation. A lower
estimate does not authorize cancelling work, deleting durable state or silently
changing user authentication.
