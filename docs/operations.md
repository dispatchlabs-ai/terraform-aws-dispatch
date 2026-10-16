# Operations, costs and boundaries

## Costs and availability

Use the [current baseline estimate](../releases/cost-estimate.md) and
[conditional idle/active comparison](../releases/idle-cost-estimate.md), their
architecture, workload and duty-cycle assumptions—not a quote or spend ceiling.
Rates checked October 14, 2026 give a ~$112/month always-on subtotal before
workers/usage, or roughly $120–$140 for light use, on the shared-private-ALB/public-IP
network in us-east-1. Stopping all tasks still leaves ~$71/month with the default
0.5-ACU minimum; the ~$27 sleeping subtotal requires eligible zero-ACU auto-pause.
The earlier ~$166/month NAT/two-private-ALB scenario is a historical comparison,
not the current default. Small RDS removes Aurora's automatic compute scaling/
auto-pause, even when cheaper for a continuously running workload.

`task_egress = "public-ip"` avoids permanent NAT costs; public IPv4 is billed only
while each task runs. Security groups still restrict ingress and the managed-domain
ALB/database remain private. Managed ingress shares one ALB with isolated ports:
443 viewer API, 8830 launcher control, 8443 worker callbacks. A caller-owned public
API ALB retains separate private control ingress. Optional `"nat"` mode uses one
NAT gateway, not multi-AZ egress availability. Two subnets do not imply HA.

Zero controller counts do not stop retained ALB/storage/DNS/secrets costs. Aurora
can pause only after all database connections close, not merely when queries stop.
Worker activity adds compute, IPv4 charges and database connections. This module
is not a production capacity, recovery or security certification.

## Authority

Execution roles pull images/read explicitly referenced secrets; task roles own
application access. Do not add master RDS credentials or AWS administration to
controllers or workers. Keep worker task-role and per-conversation database
permissions separate from both controllers. Root Ubuntu workers with writable
root/default container capabilities are intended for trusted coding and package
installation, **not hostile-code isolation**. Coding tools can use all authority
available to their service identity. Controllers remain non-root/read-only.

Private bootstrap files and source-environment removal reduce incidental
exposure; they do not hide ECS-injected secrets from authorized operators. Logs,
Terraform state, plan files, task definitions and screenshots require deliberate
access/retention controls. Never publish authenticated captures, invitation links,
private credential URLs or raw account records as qualification evidence.

## Updates and retirement

Select new compatible image digests, inspect the plan for unintended storage
changes and apply. Separate module, application and packaging identities. Preserve
matched key/secret versions and retained PostgreSQL/S3 data. Routine image-only
development updates need no automatic manual RDS snapshot or initialization rerun.
Database-changing or destructive maintenance needs its own reviewed procedure.

Controller-only replacement is not installation drain and must leave conversation
workers running. Rolling uses handover-capable images and private role-scoped
peer communication; stop-first allows bounded downtime. `deregistration_delay_seconds` defaults to 30 and `idle_timeout_seconds` to
300. The caller may deliberately select shorter development values accepting
interrupted requests; these budgets affect cleanup, not authority to overlap conversation executors.
Observe readiness/time-to-serving and actual predecessor STOPPED separately.

A new worker task-definition revision does not update existing tasks. Explicitly
retire an existing conversation attempt and confirm actual ECS termination before
its replacement adopts the new image. StopTask acknowledgement, missing inventory,
expired leases and lost connections are not termination proof. Reconcile the same
immutable attempt after uncertainty; never silently allocate another one.

## Optional warm spare

Set `worker_warm_spare = true` with warm-spare-capable Dispatch controller and
worker images to keep one unassigned task ready for the next chat. The launcher
binds it once to a conversation attempt and replenishes capacity. A burst before
the replacement is ready uses ordinary cold launches; this is a target, not an
availability guarantee. Existing conversation tasks are not recycled or moved.
The spare uses the configured worker CPU, memory, architecture and image and adds
one worker's running compute/network cost. See the hourly worker estimate above.

The module permits private launcher-to-worker TCP 8831 for authenticated
assignment and reconciliation, including tasks previously assigned while the
option was enabled. Workers receive no new AWS permissions. Physical ECS tags
retain the spare's original identity; the launcher journal records its assigned
conversation/attempt. Use launcher status for that mapping, not task tags alone.

Drain retires spare capacity and suspends replenishment. Explicit
activation resumes it. Disabling the option retires the unassigned spare while retaining
already assigned workers. Keep compatible images while any warm-assignment
journal records remain; an older launcher cannot interpret those records. Do not
erase the journal to downgrade. Record actual claim/replenishment and startup
latency observations for each installation; module validation is not runtime
qualification.

## Worker startup tuning

`worker_cpu` and `worker_memory` select the Fargate task size for newly launched
conversation attempts; defaults remain 512 CPU units and 2048 MiB. Use an
[AWS-supported combination](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html).
Changing these inputs registers a worker definition and rolls the launcher to
that definition. Existing conversation tasks retain their original resources.

For lazy image loading, publish the worker and its tracing collector as SOCI
index manifest v2 images in private ECR. Pin `worker_image` and
`worker_tracing_collector_image` to those index digests, and include their
repository ARNs in `image_pull_repository_arns`. The collector override applies
only to workers; controller collectors retain `tracing_collector_image`.
Fargate's task metadata must report `Snapshotter: soci` for each container before
claiming lazy loading. Measure admission through application readiness separately
from ECS image pull and task start timestamps; lazy loading defers file reads and
does not guarantee a startup deadline. See [AWS's Fargate SOCI requirements](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html#lazy-loading-container-images-using-seekable-oci).

Run standalone diagnostics in the services cluster. The dedicated worker
cluster is exclusively for launcher-owned, identity-tagged conversation tasks;
even stopped unowned tasks can block its strict inventory while ECS retains them.

## Maintenance and recovery

Database/provider maintenance requires sealed admission, settled writes and
confirmed stopped controllers/workers. Stop and confirm the backend while the
launcher remains reachable, then stop/confirm the launcher. Do not scale both down
simultaneously and assume orderly drain occurred. Restart launcher first, inspect
its configuration/RunTask policy, then start the normal flag-free backend and
activate privately. Operator tasks are one-off and outside the worker-only cluster.

Keep admission closed on failure. Application recovery commands inspect an exact
owner/phase record and require independent old-task termination evidence. Do not
clear journals manually, grant master authority to the application or put recovery
flags into a retained service definition. Image rollback requires schema/authority
compatibility; image pins do not establish it. This initial extraction does not
include existing-state moves or compatibility shims.

Retain PostgreSQL, S3 artifacts and matched encryption/signing/derivation secrets
under a restricted recovery policy. Worker local disk, runtime-installed packages
and unpushed commits are disposable; durable tool history is not a filesystem
backup. Push useful project progress and version required environment setup.

## Teardown

RDS and artifacts have retention/destruction guards; ECR/S3 are not force-deleted.
Do not remove protection merely to obtain a successful destroy. Review physical
data deletion, version retention and recovery authority separately and obtain
explicit authorization. The module cannot determine whether a caller's data is
safe to discard.

## Infrastructure baseline — October 10, 2026

The [pre-implementation audit](https://github.com/dispatchlabs-ai/terraform-aws-dispatch/blob/b5fffb4/docs/operations.md#infrastructure-baseline-review--october-10-2026)
records the initial extraction's gaps. The baseline extension implements managed
ACM/Route 53, CloudFront SPA/S3 OAC with a private ALB API origin, ALB access logs,
rolling controller defaults, Aurora Serverless v2, and optional worker Spot plus
sampled tracing. These are source features, not live AWS or zero-downtime proof.

- `domain` supplies an existing public hosted zone; `aws.edge` in `us-east-1`
  manages CloudFront's certificate. The API origin is private; viewer routes must
  never expose operator maintenance or private callbacks. Upload verified static
  release bundles separately; an apply does not publish the SPA.
- Aurora uses 0.5–4 ACUs by default, no reader/proxy. Set `aurora_min_capacity = 0`
  for eligible auto-pause after `aurora_seconds_until_auto_pause` (300 by default),
  with all application/maintenance connections closed. `database_mode =
  "rds"` is the small provisioned alternative. Changing mode is not a migration.
  Region/version availability, real connection loss and cost need qualification;
  retained owner connections prevent assuming an auto-pausing idle workload.
- Controllers stay On-Demand. `worker_capacity_provider = "FARGATE_SPOT"` opts
  workers into Spot; the default is `"FARGATE"`. **Automatic idle retirement is not
  implemented:** a started worker can remain billable between turns. The estimate's
  300 worker-hours is an assumed workload, not an enforced limit; count actual
  running-task hours, not just model/tool activity. Spot workers can lose capacity
  or be interrupted;
  confirmed termination still precedes replacement. Durable history is not a
  workspace snapshot or exactly-once external-effects guarantee. No EFS or S3
  Files filesystem is added without an actual durability requirement.
- CloudWatch application/collector logs use `log_retention_days` (seven by default;
  supported values 1/3/5/7/14/30). ALB access logs use
  `access_log_retention_days` (seven by default). **They can contain request
  paths/query strings:** unlike sanitized application spans, they are not a
  credential-safe transcript. Restrict bucket reads and keep invitation/OAuth
  material out of public URLs wherever possible. Lifecycle expiry is asynchronous.
  The API
  viewer-request function strips query parameters **only** from GET
  `/api/connections/oauth/callback` before forwarding to the ALB. The browser URL
  remains intact: its callback HTML reads the response and POSTs completion JSON.
  Ordinary API queries are preserved. This protects that callback's codes from
  ALB access logs, not browser history, future CDN viewer logs or arbitrary URLs.
- ADOT collectors receive OTLP on task loopback and export to X-Ray with write-only
  task permissions. `trace_sample_ratio = 0.1` controls local trace-ID-ratio sampling; `enable_tracing`
  disables/enables ordinary task collection. X-Ray retains traces for its fixed
  30-day service period, not the configurable application-log retention.
- Application HTTP/RPC spans and sampled structured request logs use safe route
  templates/status/duration/trace identities. HTTP/SSE timing is **response-header
  latency**, not stream-completion or token latency. No SQL, model/tool payloads,
  raw URLs/headers or Pi durable execution traces are exported. Health polling is
  excluded; shutdown export is bounded/best-effort and telemetry cannot replay
  application calls. Operator/credential tasks have no collector; maintenance
  terminals remain unrecorded.

Review the cost estimate's regional/workload assumptions, collector/task sizing,
network and storage costs before applying. Sampling/short retention reduce cost,
not authorization or leakage risk. Actual log delivery, trace export, CDN/API/SSE,
Aurora failover and Spot interruption remain separately qualified outcomes.
