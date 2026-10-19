# Dispatch Kubernetes foundation on AWS — experiment

**Branch:** `experiment/kubernetes`. This greenfield EKS foundation is a source experiment. It requires a fresh state backend and new resources; it does not migrate existing ECS installations or replace a published module release.

## Ownership

- This module owns the dedicated VPC/subnets/NAT, EKS control plane/access entries, managed AMD64 node group, scoped platform workload identities and pinned EKS networking/DNS/EBS add-ons.
- The caller owns AWS account/region/provider configuration, restricted remote state, DNS/certificates, release pins and installation evidence.
- The platform operator separately installs the pinned AWS Load Balancer Controller and a retained encrypted gp3 StorageClass after EKS exists. Terraform does not bootstrap a Kubernetes/Helm provider during cluster creation.
- The unpublished application-owned shared chart lives under `dispatch/charts/dispatch`. Helm owns its stable application resources. There are no ECS resources, ECS options or ECS state imports in this implementation.

The first milestone runs the published Dispatch 0.6.0 **standalone application** unchanged, using one retained encrypted EBS PVC for SQLite application/native state, keys, credentials, attachments and workspace. This is not the later distributed PostgreSQL/backend/launcher/worker-Pod model. It deliberately proves a fresh Kubernetes installation before changing application behavior.

## Optional distributed-worker database

Set `distributed_postgres` to an object with an explicit PostgreSQL 17 `engine_version` to add a separate private database for a fresh distributed installation. Its default is `null`, so existing standalone callers keep their current resources. The default database size is a single-AZ `db.t4g.small` with 20 GiB encrypted gp3 storage, growth capped at 100 GiB, seven days of automated backups and retained automated backups on deletion. Deletion protection, a final snapshot and Terraform `prevent_destroy` require a separate reviewed removal plan. Minor-version changes are explicit; no automatic HA or database failover is claimed.

The database security group permits PostgreSQL only from this cluster's node security group. Platform NetworkPolicies must separately admit only the intended backend, launcher, worker and stopped-service operator paths. Clients must use the verified RDS CA and exact endpoint; `rds.force_ssl` requires TLS. The parameter group also enforces the credential-safe logging settings required by the existing initializer and worker-role provisioner.

The `distributed_postgres` output contains endpoint information and the RDS-managed operator password's secret ARN, never its value. Only the separate trusted initializer may receive that master credential. It creates the seven isolated application databases/roles; the backend gets six scoped URLs, the launcher only its journal URL, and workers receive conversation-scoped credentials through the authenticated backend. Terraform does not initialize roles, fetch credentials or create Kubernetes Secrets. Preserve the installation's encryption/signing keys and paired data backups outside ephemeral Pods.

This database option adds no S3 bucket, application IAM role or Pod Identity agent/association. The experimental distributed application chart now uses S3-compatible artifacts through unified blob storage, superseding its earlier filesystem/PVC draft. The platform must separately supply a private encrypted/versioned bucket and backend-only scoped credentials, either a restricted Secret or EKS Pod Identity. No application artifact resources have been provisioned by this module. The database's backups do not back up artifact objects or verify whole-application restore. Standalone's retained volume is unchanged.

## Safety and cost

The default one-node experiment is **not HA**. One NAT serves two private subnets; a NAT/AZ outage interrupts egress. There is no autoscaler. The node group has one additional permitted node for explicit maintenance, not automatic capacity scaling. All ordinary cloud/application costs continue while the experiment is running.

Budget approximately **$180–$220/month** in `us-east-1` for the EKS standard-support control plane, one on-demand t3.medium, one NAT/EIP, a public ALB/IPv4 addresses, gp3 volumes and modest logs, before traffic and model charges. This is an architectural estimate, not a measured bill or spend ceiling. EKS extended-support pricing is disabled; plan a supported Kubernetes upgrade before standard support ends.

Application ownership must remain singular. The chart uses Recreate, an RWOP volume and indefinite not-ready/unreachable tolerations. Do not force-delete a Pod, force-detach its volume, roll nodes or start a second owner while old execution is uncertain. Positively stop/fence the old node/process before recovery. PVC/StorageClass retention is separate from backups; an EBS volume alone is not an independent recovery copy.

Use only trusted users/agents. A container, namespace or NetworkPolicy is not hostile-code isolation. The application receives neither an IAM role nor a service-account token; node IMDS requires v2 and hop limit 1. Platform controllers use service-account-specific OIDC roles.

## Consumption

Use a local path or a pinned experimental Git commit while developing; do not claim the public registry's ECS versions contain this implementation. The checked-in caller at `dispatch-infra/environments/surton/dispatch-kubernetes` defines explicit account guards, versions and a fresh remote-state key. Apply the foundation before installing platform controllers or the application.

Do not use this module against existing ECS state. Never rename/reuse existing backend keys, domains, VPCs, databases or source volumes to create a supposedly fresh installation. No legacy state, Slack integration or migration is part of this milestone.

Checks: `terraform fmt`, backend-disabled initialization/validation and a reviewed caller plan. No automated tests are added or run.
