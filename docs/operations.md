# Operations, costs and boundaries

## Costs and availability

Use the [dated regional estimate](../releases/cost-estimate.md), its architecture,
workload and duty-cycle assumptions—not a quote or spend ceiling. The earlier
~$166/month scenario includes NAT/two ALBs and continuously running controllers;
it is not the new profile's sleeping price. Small RDS removes Aurora's automatic
compute scaling/auto-pause, even when cheaper for a continuously running workload.

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

## Idle sleep and wake boundaries

The low-idle networking/zero-ACU inputs do not themselves retire application tasks.
Sleep/wake for this slice is explicitly IAM operator-driven, not automatic browser
wake or a background idle scheduler. Session authentication currently reads
PostgreSQL; contacting it can resume Aurora before user validation succeeds.

**Do not use the existing `/internal/drain` as proof of harmless idle shutdown:**
it cancels work. Non-cancelling sleep requires sealed admission and native task /
unsettled-submission inspection, including background work; busy or unknown state
must refuse sleep. `waitForIdle()` alone excludes background tasks. Until that gate
and the operator procedure are implemented/reviewed, safe idle sleep remains
unavailable—not an achieved $27/month runtime result. Never clear recovery latches
or replay uncertain writes to make wake succeed. Review connection deadlines and
report complete controller/database readiness, not only Aurora's advertised resume.

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
