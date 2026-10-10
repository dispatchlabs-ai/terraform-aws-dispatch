# Operations, costs and boundaries

## Costs and availability

Review actual regional prices and the saved caller plan. RDS, NAT/EIP, public and
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

## Infrastructure baseline review — October 10, 2026

Source audit at `9407c6a`, not a live-environment audit. The requested direction
is cost-effective Fargate, ALB access logging, ACM/Route 53, rolling deployment,
Secrets Manager, CloudFront for the SPA and short-retention logs/tracing, without
an enterprise-sized platform. Current implementation does **not** meet all of it:

| Area | Current module |
| --- | --- |
| ALB to ECS tasks | Backend ALB is conditional on certificate input; targets are task IPs, not the cluster itself. |
| Fargate | Yes; services and operator/worker tasks use Fargate. |
| ALB access logs | Not configured on the public or private ALBs. |
| ACM / public DNS | Accepts existing ACM certificate ARNs; does not provision certificates or public Route 53 records. |
| Rolling updates | Opt-in for backend/launcher; omitted modes default to stop-first. Rolling is not itself a verified zero-downtime guarantee. |
| Secrets Manager | Yes, scoped secret references and managed database master secret. |
| PostgreSQL | Provisioned single-AZ RDS PostgreSQL with storage growth, not autoscaling Aurora Serverless v2 compute. Compare regional/workload costs before claiming Aurora is cheapest. |
| Durable files | S3 artifacts; no EFS or S3 Files mount. Workspaces remain disposable; add a filesystem only for an actual durability requirement. |
| SPA / CloudFront | No CloudFront distribution or separate static frontend delivery. |
| Fargate Spot | No capacity-provider strategy; worker launcher also explicitly requests ordinary Fargate. |
| Observability | CloudWatch application logs, configurable retention (30-day default); no tracing export configured by the module. |

These gaps require explicit implementation and scoped validation; the earlier
mock-plan acceptance does not close them. Keep any Spot policy compatible with
interruption handling and exclusive-worker ownership. Do not record an untested
latest database version, auto-pause configuration or guaranteed zero downtime as
supported behavior.
