# Operations, costs and boundaries

## Costs and availability

Start with the [dated regional estimate](../releases/cost-estimate.md): roughly
**$166/month before workers/inference** for its stated modest-traffic ARM64
scenario, not a quote or spend ceiling. Small RDS reduces that scenario by about
$20/month but removes automatic compute scaling. Review actual regional prices
and the saved caller plan. RDS, NAT/EIP, public and
private ALBs, running controller/worker tasks, logs, S3 and image storage can incur
charges. Zero controller counts do not stop foundation costs. The baseline has
one NAT gateway, not multi-AZ egress availability; two subnets alone do not imply
HA. Worker activity adds compute and database connections. This module is not a
production capacity, recovery or security certification.

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
- Aurora uses 0.5–4 ACUs by default, no reader/proxy/auto-pause. `database_mode =
  "rds"` is the small provisioned alternative. Changing mode is not a migration.
  Region/version availability, real connection loss and cost need qualification;
  retained owner connections prevent assuming an auto-pausing idle workload.
- Controllers stay On-Demand. `worker_capacity_provider = "FARGATE_SPOT"` opts
  workers into Spot; the default is `"FARGATE"`. Spot workers can lose capacity or be interrupted;
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
