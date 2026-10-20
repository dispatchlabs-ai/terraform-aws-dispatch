# Complete AWS infrastructure example

This root composes the EKS/PostgreSQL foundation with a private, encrypted,
versioned S3 bucket, backend-only EKS Pod Identity and an ECR repository. It uses
the local module source, so it works from a reviewed Git checkout before a
Kubernetes registry release exists. Two nodes do not make this installation HA:
PostgreSQL and NAT remain single-instance.

## Prepare

Use Terraform or OpenTofu 1.11 or later, below 2.0, and credentials authorized for
the intended account. `account_id` guards against provisioning in another
account. The provider uses your normal AWS credential chain.

Copy `terraform.tfvars.example` to a private `terraform.tfvars`. Replace the
sample account, IAM operator role, operator public CIDR and globally unique
bucket. Review region, availability zones and network ranges. Check the pinned
Kubernetes/add-on/PostgreSQL versions against the chosen region using
`aws eks describe-addon-versions` and `aws rds describe-db-engine-versions`;
example pins are not regional availability guarantees.

Configure a protected remote backend in this root before applying. This example
does not choose your state account, bucket or credentials. Commit the dependency
lockfile in your calling repository.

```sh
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=foundation.plan
terraform apply foundation.plan
terraform output -json installation
terraform output -json helm_values > cloud-values.json
```

`cloud-values.json` is a non-secret partial Helm values file. Merge it with
your application and platform values; it deliberately omits image digests,
private keys, database credentials, public hostname and activation.

Use `tofu` instead of `terraform` for the same commands. Review the full plan
before apply. Use fresh state/resources; this example cannot migrate ECS state.

## Install the application

1. Install the pinned Cilium AWS-CNI chaining platform and AWS Load Balancer
   Controller described in the foundation README. The bootstrap taint keeps
   application Pods off nodes until Cilium is ready. Configure the controller
   with the output role ARN, VPC and public subnet IDs.
2. Arrange the private PostgreSQL operator path. Its security group permits
   access from this EKS cluster; an initializer Pod on the cluster is the
   intended path. A separate operator host needs an explicit security-group
   grant. The EKS public API admits only the supplied operator CIDRs.
3. Publish reviewed backend/launcher/worker images to the output ECR `registry`
   and record immutable digests. Nodes have ECR pull access without S3 access.
4. Fetch and verify the RDS CA bundle. Use `postgres.host` with `verify-full`.
   The output master secret ARN is an operator reference, never a backend
   credential. A trusted initializer retrieves that credential outside
   Terraform, initializes the seven isolated databases and retains scoped
   application credentials and encryption/signing keys separately.
5. Install the shared Dispatch chart and reusable Kubernetes platform
   gateway/policies from the reviewed release, initially disabled. Use output
   `namespace` and `backend_service_account`; default Helm release `dispatch`
   produces `dispatch-backend`. Configure artifacts using `kind: s3`,
   `endpoint`, `region`, `bucket`, `prefix` and `credentialsMode: podIdentity`.
   There is no IRSA annotation for the application; the Pod Identity association
   supplies its identity.
6. Allow only the backend to reach Pod Identity at `169.254.170.23/32:80`.
   Verify projected token/agent health and scoped S3 access. Launcher and workers
   must not receive artifact identity or metadata access.
7. Install gateway HTTPS/DNS and backend callback TLS, initialize the stores,
   and verify real worker network isolation before activating the application.
   The external load-balancer address is created by the platform installation;
   Terraform outputs its controller integration inputs.

The backend can get/conditionally create objects only under the installation
prefix. A bucket policy denies its unconditional writes, and it cannot list or
delete objects. TLS, bucket-owner ownership, encryption and versioning are
enforced. No rule expires current or noncurrent objects independently of backups.

## Ownership and recovery

Terraform owns cloud metadata, not SQL contents, object contents, Kubernetes
Secrets or credential values. The artifact bucket uses S3's authenticated public
HTTPS endpoint with public access blocked. The application remains a separate
Helm installation.

Drain application ownership and positively terminate workers before planned
node changes. Retain PostgreSQL snapshots, object versions and corresponding
keys together, then qualify restoration. Deletion protection and versioning
alone do not establish recovery.

For existing buckets, registries or networking, compose the foundation with
your approved resources in your own root instead of importing this example
blindly. This example has static CLI/provider validation; a fresh cloud apply
and complete application qualification remain required.

Install Helm with the output `installation.release` and `installation.namespace`.
The `release_name` input derives the backend ServiceAccount name used by workload
identity; changing it also requires a deliberately reviewed Helm release migration.
