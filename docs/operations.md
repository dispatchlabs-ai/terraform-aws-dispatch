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

## Operator sleep and wake

**Source tooling, not verified AWS sleep/wake.** The low-idle inputs do not
schedule retirement. There is no idle timer or anonymous browser wake; current
session authentication reads PostgreSQL and can wake it before validation.
Use compatible sleep-capable images, `enable_activation = true`, and re-export
`sleep`, `activation`, `controller_services`, both cluster ARNs, `task_subnet_ids`
and `task_assign_public_ip`. The complete caller does this; refresh its private
`terraform output -json` file after applying the registered definitions.

Preview is local and does not call AWS:

```sh
python3 scripts/run-installation.py sleep --outputs OUTPUTS \
  --account "$AWS_ACCOUNT_ID" --region "$AWS_REGION"
python3 scripts/run-installation.py wake --outputs OUTPUTS \
  --account "$AWS_ACCOUNT_ID" --region "$AWS_REGION"
```

After reviewing identities/costs and holding exclusive lifecycle control, execute
one selected operation with `--execute --confirm-exclusive-control --receipt
/private/NEW-lifecycle.json`. No concurrent operator, Terraform apply or scheduler
may change counts/admission. The helper also reserves a sibling `.task.json`
receipt before the one operator task; never overwrite/reuse either file.

Sleep requires both single-instance controllers steady and their exact identities
observable. The private `/internal/sleep` gate seals new work, inspects native
foreground/background tasks and unsettled submissions, and retires only idle
workers through existing launcher termination evidence. **`/internal/drain`
cancels work and is not a safe idle gate.** `waitForIdle()` alone is insufficient.
A successful gate is necessary but not sufficient: revalidate fresh controller
counts and exact running identities after the gate and before each scale-down.
Identity drift must refuse the operation, not let an older task's exit stand in
for the current owner. After each accepted scale-down, the helper polls any stale
pre-update desired count within `--wait-seconds`; it never resubmits the update.
Unexpected counts still refuse the operation, and a count that never converges
leaves an incomplete receipt. Observe backend actual `STOPPED` with clean exit,
then launcher actual termination/clean exit; counts or missing inventory alone
are not confirmation. Support callbacks stay open
while admitted work finishes. Planned-quiescence health may remain green while
new-work admission is sealed; it does not mean idle or publicly serving. Persisted cold drain does not
authorize planned-quiescence readiness; lost ownership/unhealthy stores still fail
ECS/ALB readiness. The separate liveness route is not admission or idle evidence.
A busy/unknown result must not stop controllers;
partial refusal can already have retired idle workers. Reconcile state, then use
explicit private activation/undrain to reopen surviving admission when safe.

Wake requires both controllers stopped, with worker/task inventory described by
actual state: pending, running, stopping or unknown identities refuse wake. Desired
`STOPPED` is not actual `STOPPED`; empty desired-PENDING discovery proves nothing. Start launcher,
then backend; poll authenticated read-only `/internal/status` until owner
initialization before the **single** private activation request. ECS `RUNNING`,
`/internal/health` and admission-dependent readiness cannot authorize that request.
Then observe readiness separately: all configured essential-container health checks
and every attached ALB target group must report healthy for the current tasks.
ALB checks select each task's exact private IP and container port; a healthy old
target or a previous deployment's `COMPLETED` status is not readiness evidence.
Tasks without container health checks normally report ECS health `UNKNOWN`; their
ALB targets provide the health signal instead. Wake refuses configurations with
neither signal before starting controllers. Use readiness-capable health checks,
not process liveness, when configuring these services.

The lifecycle operator needs `ecs:DescribeTaskDefinition` for the selected
controller definitions and `elasticloadbalancing:DescribeTargetHealth` in addition
to its existing ECS lifecycle permissions. Health observation is read-only and
bounded by `--wait-seconds`; a timeout or permission error leaves an incomplete
receipt without replaying activation or service updates. Retired workers return
through fresh attempts and disposable-workspace recovery, not restored local files.

On refusal, timeout or uncertainty, inspect both receipts and exact task/service
state; **do not rerun mutations**. Partial lifecycle state requires reconciliation,
not a new wake or sleep request. Never clear recovery latches or replay uncertain
writes. Reconcile the intended service counts in the caller before a later apply,
which can otherwise undo imperative sleep. Controller termination does not prove
Aurora paused: verify zero `ServerlessDatabaseCapacity` and pause events without
opening a database connection. Retained ALB/storage/secrets/DNS still cost money;
report complete cold-wake latency, not only Aurora's advertised resume interval.

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
