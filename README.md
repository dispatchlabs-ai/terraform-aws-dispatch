# Dispatch on AWS

A standalone Terraform/OpenTofu module for Dispatch's PostgreSQL-backed backend,
launcher and per-conversation ECS Fargate workers. It creates a dedicated VPC,
private PostgreSQL, S3 artifacts, ECS clusters, task definitions, scoped
IAM/security groups and HTTPS ingress. The baseline extension adds Aurora
Serverless v2 (with a small-RDS alternative), managed ACM/Route 53, a CloudFront
SPA/API entry point and sampled application tracing. Terraform registers the worker definition;
Dispatch's launcher creates and retires conversation tasks. The low-idle profile
avoids permanent NAT, shares private managed ingress, and supports conditional
zero-ACU Aurora plus explicit operator sleep/wake; no automatic idle timer is added.

**Status:** module **v0.1.0** is an early-stage source release; live AWS qualification
remains pending. This repository is public. Dispatch [0.2.0 archives](https://github.com/dispatchlabs-ai/dispatch/releases/tag/v0.2.0)
are available; [import them into ECR without rebuilding](docs/releases.md#import-020-archives-into-ecr).
Public registry images, module registry registration and an independently
qualified fresh-account installation remain pending. Do not use sample identities
or fabricated image digests to activate tasks.

Licensed under [MIT](LICENSE).

## Start here

- [Architecture explained and AWS diagram](docs/architecture.md)
- [Complete caller example](examples/complete/README.md)
- [Installation and activation](docs/installation.md)
- [Security and retention](docs/operations.md)
- [Monthly AWS cost estimate](releases/cost-estimate.md) and [conditional idle/active comparison](releases/idle-cost-estimate.md)
- [Changelog](CHANGELOG.md) and [release and acceptance contract](docs/releases.md)

You supply the AWS provider/region and restricted state backend, final HTTPS
domain/Route 53 zone, regional AWS and `aws.edge` (`us-east-1`) providers, trusted
CA material, secret **ARN references**, and compatible controller/worker image
digests plus a verified SPA release bundle. The module renders internal service/store and
bootstrap configuration. No application checkout, Nix build or customer-specific
runbook should be needed by a release consumer.

Pin the module to an immutable release or full commit. Until registry registration
is complete, use the `v0.1.0` Git release in your caller's module block:

```hcl
source = "git::https://github.com/dispatchlabs-ai/terraform-aws-dispatch.git?ref=v0.1.0"
```

After registration in each registry, the intended module address is
`dispatchlabs-ai/dispatch/aws` with `version = "0.1.0"`. Terraform and OpenTofu
resolve that shorthand through their respective default registries; registration
in one does not register the other. See the [v0.1.0 source checks](docs/releases.md#v010-source-release)
for tested engine/provider versions and qualification limits.

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

Sleeping is not the default: `aurora_min_capacity = 0` and all database connections
closed are required for auto-pause, with supported engine/region settings. Sleep
requires explicit operator action, incurs wake latency, and remains unqualified
on live AWS. The module initially defaults to zero controllers; retained
infrastructure still costs money.

See the [detailed cost breakdown, assumptions and AWS rate sources](releases/cost-estimate.md)
and [idle/active duty cycles and sleep/wake caveats](releases/idle-cost-estimate.md).
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
