# Dispatch on AWS

A standalone Terraform/OpenTofu module for Dispatch's PostgreSQL-backed backend,
launcher and per-conversation ECS Fargate workers. It creates a dedicated VPC,
private PostgreSQL, S3 artifacts, ECS clusters, task definitions, scoped
IAM/security groups and HTTPS ingress. The baseline extension adds Aurora
Serverless v2 (with a small-RDS alternative), managed ACM/Route 53, a CloudFront
SPA/API entry point and sampled application tracing. Terraform registers the worker definition;
Dispatch's launcher creates and retires conversation tasks. The low-idle profile
avoids permanent NAT and shares private managed ingress. Compatible Dispatch images also
retire inactive conversation workers automatically; the application owns that
lifecycle. `worker_idle_timeout_seconds` optionally overrides its timeout without
stopping controllers or the warm spare. Omit this input when using older images.

**Status:** module **v0.2.0** is an early-stage source release. Use the pinned Git
source below until its Terraform Registry indexing is confirmed. Version **0.1.0**
is already available in the
[public Terraform Registry](https://registry.terraform.io/modules/dispatchlabs-ai/dispatch/aws/0.1.0).
Live AWS qualification remains pending. This repository is public. Dispatch
[0.2.0 archives](https://github.com/dispatchlabs-ai/dispatch/releases/tag/v0.2.0)
are available; [import them into ECR without rebuilding](docs/releases.md#import-020-archives-into-ecr).
Public container registry images, OpenTofu registry registration and an independently
qualified fresh-account installation remain pending. Do not use sample identities
or fabricated image digests to activate tasks.

Licensed under [MIT](LICENSE).

## Start here

- [Architecture explained and AWS diagram](docs/architecture.md)
- [Complete caller example](examples/complete/README.md)
- [Installation and activation](docs/installation.md)
- [Security and retention](docs/operations.md)
- [Monthly AWS cost estimate](releases/cost-estimate.md)
- [Changelog](CHANGELOG.md) and [release and acceptance contract](docs/releases.md)

You supply the AWS provider/region and restricted state backend, final HTTPS
domain/Route 53 zone, regional AWS and `aws.edge` (`us-east-1`) providers, trusted
CA material, secret **ARN references**, and compatible controller/worker image
digests plus a verified SPA release bundle. The module renders internal service/store and
bootstrap configuration. No application checkout, Nix build or customer-specific
runbook should be needed by a release consumer.

Compatible images support optional `application.github` with `broker_origin`,
`token_secret_arn`, and `manager_user_ids`. The origin must use HTTPS; the user IDs
are authenticated Dispatch identities allowed to manage company connections.
ECS supplies the broker credential only to the backend. The external credential
service independently authorizes its client installations and retains App keys;
workers receive only repository-scoped tokens. Project repository/grant changes
use Dispatch's UI and do not require Terraform. Omit this input for older images
or installations without GitHub access. See the application-owned
[GitHub access contract](https://github.com/dispatchlabs-ai/dispatch/blob/main/packages/web/docs/github-integration.md).

Pin the module to an immutable release or full commit. For Terraform, the latest
confirmed published registry version is shown below; use `version = "0.2.0"` only
after confirming it is indexed, or use the Git source for the new features:

```hcl
source  = "dispatchlabs-ai/dispatch/aws"
version = "0.1.0"
```

OpenTofu registry registration remains pending. Terraform and OpenTofu resolve
that shorthand through their respective default registries; registration in one
does not register the other. Until OpenTofu registration is complete, use the Git
source below with OpenTofu; it also works with Terraform without either registry:

```hcl
source = "git::https://github.com/dispatchlabs-ai/terraform-aws-dispatch.git?ref=v0.2.0"
```

For a Git source, omit `version`; the `ref` selects the release. See the
[v0.2.0 source checks](docs/releases.md#v020-source-release) for tested
engine/provider versions and qualification limits.

## Estimated monthly cost

Rates checked **October 14, 2026**. For one activated managed-domain installation
in **us-east-1**, using ARM64, one shared private ALB, public-IP task egress
(no NAT), and Aurora averaging 0.5 ACU:

| Scenario | Monthly USD, before usage/model API charges |
|---|---:|
| Always-on backend + launcher, no workers | ~$112 |
| Same, plus 300 aggregate worker-hours | ~$120 |
| Same, plus one continuously running worker | ~$133 |
| All tasks stopped, default 0.5-ACU database retained | ~$71 |
| All tasks stopped, Aurora successfully auto-paused (opt-in) | ~$27 |

**Budget roughly $120–$140/month for light always-on AWS usage**, excluding LLM
and tool API bills. These estimates assume 730 hours/month, 20 GB of database data,
17 secrets and three allocated hosted zones, with no free tiers or discounts.
Workers cost about **$0.02831/running hour**, including IPv4. Aurora scaling,
logging, storage and traffic can increase the bill. The small single-AZ RDS
alternative lowers the always-on/no-worker subtotal to about **$92/month**.

Aurora auto-pause requires `aurora_min_capacity = 0`, all database connections
closed and supported engine/region settings. Running controllers keep connections
open. The module initially defaults to zero controllers; retained infrastructure
still costs money. Whole-installation sleep/wake tooling was removed on October
16, 2026; the stopped-task rows above are infrastructure cost scenarios.

See the [detailed cost breakdown, assumptions and AWS rate sources](releases/cost-estimate.md)
for the current topology.
These are planning estimates, not measured bills or spend ceilings.

## Ownership

Dispatch owns released images and runtime/lifecycle commands. This repository
owns infrastructure and installation instructions. Your caller repository owns
account settings, state, domain/hosted-zone authority, secret references and
deployment receipts. It must
not copy secret values into Terraform, command arguments, logs or source control.
Database initialization and activation are explicit operator actions, not hidden
Terraform provisioners. No customer installation is a dependency of this module.

## Updates

Select compatible new image digests, review a fresh plan, apply and verify
readiness. Do not rebuild images, regenerate retained secrets or repeat database
initialization for ordinary image-only updates. Controller-only replacement must
not retire conversation workers. New worker task definitions affect newly launched
attempts; existing workers require explicit, confirmed retirement before adoption.

Rolling is the baseline controller policy; explicit stop-first is an intentional
downtime choice through `service_deployment_mode`. Rolling requires
handover-capable images and generated peer configuration; it does not relax
exclusive conversation execution. Fast-development drain budgets may allow brief
downtime, but uncertain old-executor termination still blocks replacement.
Measure time-to-serving separately from old-task cleanup. See
[operations](docs/operations.md) for maintenance and failure boundaries.
