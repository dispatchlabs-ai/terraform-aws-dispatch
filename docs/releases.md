# Releases and acceptance

Module versions and Dispatch image versions are independent. A release must name
an explicitly compatible combination, not infer compatibility from matching tags.
Controller and Ubuntu-worker images must each have qualified Linux ARM64/AMD64
artifacts before advertising a multi-platform index. Record source/packaging
revisions, index and child digests separately. Registry digest identities are not
local Docker image IDs.

The artifact selector and manifest contract are owned by
[`releases/README.md`](../releases/README.md). Metadata validation is offline:
it does not prove registry access, image contents or Fargate execution. Verify
direct public-image pulls separately; optional customer ECR mirrors must retain
verified digest identity. No fabricated manifest should stand in for publication.

## Publishing

Keep the repository private until the authorized open-source release. The public
module root follows `terraform-aws-dispatch` naming and standard module layout;
use immutable semantic-version Git tags for released versions. Register it in the
[Terraform Registry](https://developer.hashicorp.com/terraform/registry/modules/publish)
and submit it to the [OpenTofu Registry](https://github.com/opentofu/registry#adding-providers-modules-or-gpg-keys-to-the-opentofu-registry).
These are independent publication steps, not automatic consequences of creating
a GitHub repository. Git source with a pinned full commit also works without a
registry. Private sources require explicitly granted access.

The module uses the [MIT license](../LICENSE). Before publishing, check extracted
source/license compatibility and review the full public tree for private identities,
secret values and customer-specific material. Do not assume a source-code license
or public visibility from a publishing convention.

## Compatibility record

Each release records supported Terraform/OpenTofu and AWS provider versions,
module version/source SHA, application and packaging source, controller/worker
registry digests, architectures and qualification scope. Current source declares
engine `>= 1.12.6, < 2.0.0` and AWS provider `6.67.0`; those constraints are not
verification that every satisfying engine version works. Record actual validated
versions in the release, including separate engine lockfile/evidence contexts.

No public image combination or live fresh-install qualification is claimed by the
initial source extraction. Public registry registration and artifact publication
remain open-source-release work.

## Fresh-install acceptance

An independent caller must be able to use only an immutable module release,
released images, this example and these instructions—no application checkout,
private runbook, developer machine or undocumented bootstrap map.

Record these outcomes with exact revisions and sanitized evidence:

1. Terraform and OpenTofu independently initialize/validate/plan the external
   caller; distinguish synthetic/offline fixtures from real AWS plans/applies.
2. Fresh foundation, private secret/trust preparation, separate initializer create
   and verify complete with actual operator tasks STOPPED and all exit codes zero.
3. Private activation precedes readiness, enrollment/sign-in works, and a new chat
   returns a model reply and harmless tool output with history retained on reload.
4. Controller-only replacement leaves existing workers alone. Worker replacement
   starts after independently confirmed old-executor termination; durable history
   and artifacts remain available.
5. Record measured time-to-serving separately from old-controller cleanup, public
   ingress refusal of maintenance, configured architecture and remaining limits.

Build/metadata checks, signed-out HTTP 200 and database integrity do not establish
these outcomes. Keep customer task identities, credential references and private
captures in the owning restricted installation evidence, not this public module.
