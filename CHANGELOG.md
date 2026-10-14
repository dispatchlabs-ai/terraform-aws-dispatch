# Changelog

All notable changes to this module are recorded here. Module versions follow
[Semantic Versioning](https://semver.org/) and are independent of Dispatch
application, container-image and frontend-bundle versions. Published release tags
are immutable; corrections ship in a new version.

## [Unreleased]

- Add opt-in `worker_warm_spare` for one launcher-managed unassigned Fargate
  worker, with private launcher-to-worker assignment access. Requires compatible
  Dispatch images; the default keeps ordinary on-demand launching.

## [0.1.0] - 2026-10-14

Initial early-stage source release. **Live AWS qualification remains pending.**

### Added

- Dedicated two-AZ VPC, selectable public-IP or NAT task egress, private
  PostgreSQL, protected S3 artifact storage, and separate controller/worker ECS
  clusters with scoped IAM and security groups.
- Aurora PostgreSQL Serverless v2 with optional connection-free auto-pause, plus
  a small provisioned RDS alternative.
- Optional managed ACM/Route 53 domains, private ALB ingress, and CloudFront
  delivery of a private S3 SPA and uncached backend API.
- Hardened backend/launcher task definitions, readiness-gated rolling deployment
  configuration, optional trusted package-installation workers, and opt-in
  Fargate Spot workers.
- Configurable worker CPU/memory and a worker-only tracing collector image override
  for independently pinned worker images, including caller-published ECR SOCI
  indexes. Controller resource and collector defaults remain unchanged.
- Typed application configuration using secret ARN references, explicit database
  initialization, private credential maintenance, activation, and operator-led
  sleep/wake with non-replayable operation receipts.
- Offline release-artifact selection and checksum-verified, append-only frontend
  publication helpers.
- Short-retention operational logs, optional sampled ADOT/X-Ray tracing, a complete
  caller example, architecture documentation, and provisional cost estimates.

### Fixed

- Explicit Cloud Map custom health configuration prevents replacement drift.
- Wake verifies current essential-container and exact ALB target health instead
  of trusting a previous deployment's completed status. Operators additionally
  need `ecs:DescribeTaskDefinition` and
  `elasticloadbalancing:DescribeTargetHealth`.
- Sleep tolerates bounded propagation of accepted desired-count updates without
  replaying mutations or relaxing exact clean-termination requirements.
- Refreshed cost estimates and the README summary to price the current shared
  private ALB/public-IP topology, distinguish default idle costs from opt-in
  auto-pause, and include worker IPv4 and usage allowances.

### Compatibility and verification

- Declares Terraform/OpenTofu `>= 1.12.6, < 2.0.0` and pins AWS provider `6.67.0`.
- Source checks pass on Linux AMD64 with Terraform `1.14.5` and OpenTofu `1.12.6`:
  formatting, backend-disabled initialization, caller validation, and 31 mock-plan
  scenarios per engine.
- All 47 Python tests pass with Python `3.10.20` and `3.14.4`; Node.js `24.14.1`
  passes activation-template syntax, nine operator-request cases, and edge-function
  checks. See the [release record](docs/releases.md#v010-source-release).

### Known limitations

- Module registry registration is a separate, pending publication step.
- No live fresh-account AWS installation or module/application image combination
  is qualified by this source release. Public registry images and a qualified
  application release manifest remain pending; published Dispatch `0.2.0` archives
  do not by themselves establish compatibility.
- No automatic idle scheduler, durable worker workspace, or high-availability
  guarantee is provided. Root-enabled workers are for trusted code, not hostile
  code isolation. Cost estimates are not measured bills.

[Unreleased]: https://github.com/dispatchlabs-ai/terraform-aws-dispatch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dispatchlabs-ai/terraform-aws-dispatch/tree/v0.1.0
