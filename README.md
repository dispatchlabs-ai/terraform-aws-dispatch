# Dispatch Kubernetes foundation on AWS — experiment

**Branch:** `experiment/kubernetes`. This greenfield EKS foundation is a source experiment. It requires a fresh state backend and new resources; it does not migrate existing ECS installations or replace a published module release.

## Ownership

- This module owns the dedicated VPC/subnets/NAT, EKS control plane/access entries, managed AMD64 node group, scoped platform workload identities and pinned EKS networking/DNS/EBS add-ons, plus the optional Pod Identity Agent.
- The caller owns AWS account/region/provider configuration, restricted remote state, DNS/certificates, application artifact storage/identity, release pins and installation evidence.
- The platform operator separately installs Cilium in AWS-CNI chaining mode, the pinned AWS Load Balancer Controller and any retained encrypted gp3 StorageClass after EKS exists. Terraform does not bootstrap a Kubernetes/Helm provider during cluster creation.
- The unpublished application-owned shared chart lives under `dispatch/charts/dispatch`. Helm owns its stable application resources. There are no ECS resources, ECS options or ECS state imports in this implementation.

The current shared chart runs the distributed PostgreSQL/backend/launcher/worker-Pod
model. The caller enables the database option below and supplies artifact storage
and scoped identities separately. The original standalone milestone used published
Dispatch 0.6.0 and one retained EBS PVC; its chart and recovery values are historical
source, retained by the caller rather than a second current installation path.

## Optional distributed-worker database

Set `distributed_postgres` to an object with an explicit PostgreSQL 17 `engine_version` to add a separate private database for a fresh distributed installation. Its default is `null`, so existing standalone callers keep their current resources. The default database size is a single-AZ `db.t4g.small` with 20 GiB encrypted gp3 storage, growth capped at 100 GiB, seven days of automated backups and retained automated backups on deletion. Deletion protection, a final snapshot and Terraform `prevent_destroy` require a separate reviewed removal plan. Minor-version changes are explicit; no automatic HA or database failover is claimed.

The database security group permits PostgreSQL only from this cluster's node security group. Platform NetworkPolicies must separately admit only the intended backend, launcher, worker and stopped-service operator paths. Clients must use the verified RDS CA and exact endpoint; `rds.force_ssl` requires TLS. The parameter group also enforces the credential-safe logging settings required by the existing initializer and worker-role provisioner.

The `distributed_postgres` output contains endpoint information and the RDS-managed operator password's secret ARN, never its value. Only the separate trusted initializer may receive that master credential. It creates the seven isolated application databases/roles; the backend gets six scoped URLs, the launcher only its journal URL, and workers receive conversation-scoped credentials through the authenticated backend. Terraform does not initialize roles, fetch credentials or create Kubernetes Secrets. Preserve the installation's encryption/signing keys and paired data backups outside ephemeral Pods.

This database option adds no S3 bucket, application IAM role or Pod Identity association. The shared application chart uses native S3, Azure Blob or Google Cloud Storage through unified blob storage, superseding its earlier filesystem/PVC draft. This AWS caller must separately supply a private encrypted/versioned S3 bucket and backend-only scoped credentials, either a restricted Secret or EKS Pod Identity. This module does not manage application artifact resources. The database's backups do not back up artifact objects or verify whole-application restore. Standalone's retained volume is unchanged.

## Optional EKS Pod Identity Agent

Set `pod_identity_agent_version` to an explicit add-on version after verifying its compatibility with the cluster's Kubernetes version and regional add-on configuration schema. The default is `null`, leaving existing callers unchanged. This adds only the platform `eks-pod-identity-agent` add-on; it does not change existing add-ons, node IAM policies or application releases. The agent binds to IPv4 `169.254.170.23`, matching this foundation's IPv4 network. Its node role already has `eks-auth:AssumeRoleForPodIdentity` through `AmazonEKSWorkerNodePolicy`; no artifact permissions belong on that role.

The caller owns each application IAM role and exact cluster/namespace/ServiceAccount association. Use the `cluster_arn` output to constrain role trust alongside the namespace and ServiceAccount request tags, leaving Pod Identity session tags enabled. For distributed artifacts, associate only the backend ServiceAccount and grant only the installation prefix's object permissions. Installing the agent does not give standalone, launcher or worker Pods artifact authority.

The node-hosted agent must reach the EKS Auth API through the existing NAT route or a separately provisioned `eks-auth` VPC endpoint. The backend's NetworkPolicy must allow TCP 80 to `169.254.170.23/32`; launcher and worker policies must not add that access. Verify agent health, projected-token delivery and scoped credential behavior before runtime activation. See AWS's [agent setup](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html), [IPv4 binding](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-config-ipv6.html), [private-cluster networking](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html) and [role trust](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-role.html) guidance.

## Safety and cost

`network_policy_provider = "cilium"` is the distributed default. AWS VPC CNI
continues to allocate Pod addresses, with its network-policy agent disabled;
the separate platform install owns Cilium policy enforcement. Install Cilium in
`aws-cni` chaining mode with `policyEnforcementMode: always` before application
Pods, then qualify allowed and denied traffic from an actual ownerless worker
Pod. The caller's `platform/README.md` pins the chart, system-policy allowance,
API-server entity policy and migration sequence. Never switch a running
installation's policy engine by applying Terraform alone. Its previous owners
must first drain and positively terminate, and existing Pods/nodes require the
reviewed CNI transition. The historical `aws-vpc-cni` option is retained only for
the standalone baseline: AWS does not guarantee policy enforcement for ownerless
Pods and its default startup mode permits traffic before policy installation.

The default one-node experiment is **not HA**. One NAT serves two private subnets; a NAT/AZ outage interrupts egress. There is no autoscaler. The node group has one additional permitted node for explicit maintenance, not automatic capacity scaling. All ordinary cloud/application costs continue while the experiment is running.

Budget approximately **$180–$220/month** in `us-east-1` for the EKS standard-support control plane, one on-demand t3.medium, one NAT/EIP, a public ALB/IPv4 addresses, gp3 volumes and modest logs, before traffic and model charges. This is an architectural estimate, not a measured bill or spend ceiling. EKS extended-support pricing is disabled; plan a supported Kubernetes upgrade before standard support ends.

Application ownership must remain singular. The distributed chart uses one backend,
one launcher, Recreate and indefinite not-ready/unreachable tolerations; workers
are one-shot Pods. The historical standalone owner additionally used an RWOP
volume. Do not force-delete a Pod, force-detach its volume, roll nodes or start a
second owner while old execution is uncertain. Positively stop/fence the old
node/process before recovery. PVC/StorageClass retention is separate from backups;
an EBS volume alone is not an independent recovery copy.

Use only trusted users/agents. A container, namespace or NetworkPolicy is not hostile-code isolation. The standalone application receives neither an IAM role nor a service-account token; node IMDS requires v2 and hop limit 1. Platform controllers use service-account-specific OIDC roles. Optional distributed backend Pod Identity uses a separate caller-owned association and audience-specific projected token.

## Consumption

Use a local path or a pinned experimental Git commit while developing; do not claim the public registry's ECS versions contain this implementation. The checked-in caller at `dispatch-infra/environments/surton/dispatch-kubernetes` defines explicit account guards, versions and a fresh remote-state key. Apply the foundation before installing platform controllers or the application.

Do not use this module against existing ECS state. Never rename/reuse existing backend keys, domains, VPCs, databases or source volumes to create a supposedly fresh installation. No legacy state, Slack integration or migration is part of this milestone.

Checks: `terraform fmt`, backend-disabled initialization/validation and a reviewed caller plan. No automated tests are added or run.
