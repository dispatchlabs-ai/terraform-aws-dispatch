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

**Status:** source baseline implemented and offline-reviewed; live qualification pending. This
repository is private pending the open-source release. Public images, registry
registration and an independently qualified fresh-account installation are not
established by this source. Do not use sample identities or fabricated image
digests to activate tasks.

Licensed under [MIT](LICENSE).

## Start here

- [Complete caller example](examples/complete/README.md)
- [Installation and activation](docs/installation.md)
- [Security and retention](docs/operations.md)
- [Regional cost estimates](releases/cost-estimate.md) and [provisional idle/active comparison](releases/idle-cost-estimate.md)
- [Release and acceptance contract](docs/releases.md)

You supply the AWS provider/region and restricted state backend, final HTTPS
domain/Route 53 zone, regional AWS and `aws.edge` (`us-east-1`) providers, trusted
CA material, secret **ARN references**, and compatible controller/worker image
digests plus a verified SPA release bundle. The module renders internal service/store and
bootstrap configuration. No application checkout, Nix build or customer-specific
runbook should be needed by a release consumer.

Pin the module to an immutable release or commit. During this private preparation
phase, Git access is required; no public registry version is advertised. After
publication the same module source supports Terraform and OpenTofu; engine and
provider compatibility must be verified for each release.

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
