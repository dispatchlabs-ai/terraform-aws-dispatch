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
peer communication; stop-first allows bounded downtime. Short configurable drain
budgets affect cleanup, not authority to overlap conversation executors.
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
