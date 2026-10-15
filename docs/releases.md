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
direct public-image pulls separately; customer ECR imports must verify
configuration identity and record destination manifest digests. A registry
representation change can change a manifest digest without changing the image
configuration; do not substitute a local image ID. No fabricated manifest should stand in for publication.

## v0.2.0 source release

Module **v0.2.0**, dated October 15, 2026, adds opt-in warm-spare workers,
conversation-worker idle timeout configuration and backend-only GitHub credential
service access. See [CHANGELOG.md](../CHANGELOG.md) for details. These features
require compatible Dispatch images; matching module/application version numbers
do not establish compatibility. Live AWS and application-combination qualification
remain pending.

### Source validation

Separate Git-archive copies of module source `5d7bb17` pass the following checks
on Linux AMD64 with AWS provider **6.67.0**, without AWS credentials:

| Engine | Checks |
| --- | --- |
| Terraform 1.14.5 | Format, backend-disabled init, generated caller validation, 32 mock plans |
| OpenTofu 1.12.6 | Format, backend-disabled init, generated caller validation, 32 mock plans |

All **47 Python tests** pass under **Python 3.14.4**. **Node.js 24.14.1** passes
activation-template syntax checking, **nine offline operator-request cases** and
edge-function checks. The known Cloud Map `failure_threshold` deprecation warning
remains non-blocking. These are offline source checks, not AWS plans/applies,
image pulls, warm-spare/idle-retirement runtime checks or GitHub service qualification.

Terraform Registry indexing of `v0.2.0` must be confirmed after pushing the tag;
`0.1.0` remains the latest registry version confirmed in this record. OpenTofu
registration remains pending. The pinned Git source works without either registry.

## v0.1.0 source release

Module **v0.1.0**, dated October 14, 2026, is the initial early-stage source
release. Its features, fixes and limitations are recorded in [CHANGELOG.md](../CHANGELOG.md).
It is not a Dispatch application/image release and does not qualify an application
combination or live AWS installation. Version **0.1.0** is published in the
[public Terraform Registry](https://registry.terraform.io/modules/dispatchlabs-ai/dispatch/aws/0.1.0)
from Git tag `v0.1.0`. OpenTofu registry registration remains pending; the Git tag
is usable without either registry.

### Source validation

The release checks use separate module-only Git archives, copied complete callers,
credential-empty environments, and independent engine data/lockfile contexts on
Linux AMD64:

| Engine | AWS provider | Checks |
| --- | --- | --- |
| Terraform 1.14.5 | 6.67.0 | Format, backend-disabled init, generated and complete caller validation, 31 mock plans |
| OpenTofu 1.12.6 | 6.67.0 | Format, backend-disabled init, generated and complete caller validation, 31 mock plans |

All **47 Python tests** pass under both **Python 3.10.20** and **3.14.4**.
**Node.js 24.14.1** passes activation-template syntax checking, **nine offline
operator-request cases**, and edge-function checks. These include current-task
readiness, all attached ALB targets, bounded sleep count propagation, exact clean
termination, and refusal to replay mutations. The mock plans also cover default
worker sizing, worker-only resource/collector overrides, their explicit ECR pull
grant, and rejection of an unpinned worker collector image. These checks do not
qualify SOCI lazy loading or worker startup performance on AWS.

The pinned provider emits a known deprecation warning for Cloud Map's explicit
`failure_threshold`; validation and mock plans still pass. OpenTofu rewrites its
isolated lockfile's provider hostname to its own registry. Keep caller lockfiles
and state contexts separate between engines.

No live AWS plan/apply, secret lookup, image pull or runtime qualification is
established by these checks. Engine constraints are broader than the exact
versions tested above. The [fresh-install acceptance](#fresh-install-acceptance)
requirements remain open.

## Publishing

The public repository follows `terraform-aws-dispatch` naming and standard module
layout. Releases use immutable semantic-version Git tags, beginning with `v0.1.0`.
Maintain forthcoming changes under **Unreleased** in [CHANGELOG.md](../CHANGELOG.md),
then move them into a dated version section and record verification before tagging.
Never move a published tag to correct a release; issue a new version instead.

### Registry publication status

- **Terraform Registry — published October 14, 2026:**
  [`dispatchlabs-ai/dispatch/aws` version `0.1.0`](https://registry.terraform.io/modules/dispatchlabs-ai/dispatch/aws/0.1.0).
  The [public registry API](https://registry.terraform.io/v1/modules/dispatchlabs-ai/dispatch/aws/0.1.0)
  confirms the version and source tag `v0.1.0`. Terraform callers can use
  `source = "dispatchlabs-ai/dispatch/aws"` with `version = "0.1.0"`.
- **OpenTofu Registry — registration pending:** use the pinned Git source in the
  [README](../README.md#start-here) until registration is complete. Terraform and
  OpenTofu use different default registries for the same shorthand address;
  publication in one does not register the other.

Initial registry registration is a one-time operator action for each registry.
Terraform registration is complete. Its public listing is managed in
[HCP Terraform](https://app.terraform.io/) under **Registry → Public namespaces →
dispatchlabs-ai**, not **Private library**. To publish a new public module, use
**Publish → Module** within the public namespace and select its GitHub repository.
Adding a module to the private library does not publish it to the public registry.
For subsequent versions of this module, push a new semantic-version Git tag; the
registry uses its GitHub webhook to index it. Confirm the version appears in the
public listing before advertising it as available.

For OpenTofu, submit the same repository through its
[new module issue form](https://github.com/opentofu/registry/issues/new?assignees=&labels=module%2Csubmission&projects=&template=module.yml&title=Module%3A+).
Its submission process requires the GitHub issue-form UI, not a CLI/API-created
issue or a direct registry-data pull request. Confirm that version `0.1.0` resolves
in the OpenTofu registry before advertising its shorthand installation as available.

See the [Terraform publication requirements](https://developer.hashicorp.com/terraform/registry/modules/publish),
[HCP public namespace publishing workflow](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/organizations/public-namespace/artifacts#publish-artifacts),
and [OpenTofu registration instructions](https://github.com/opentofu/registry#adding-providers-modules-or-gpg-keys-to-the-opentofu-registry).
Both registries can use the same source and release tags; no duplicate module
implementation is needed. Git source pinned to the release tag or a full commit
also works without a registry. Private sources require explicitly granted access.
Registry-rendered documentation comes from the tagged snapshot. Updating `main`
does not change the README shown for `v0.1.0`; documentation corrections will
appear with a new release.

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
initial source extraction. Terraform module registration is complete; OpenTofu
registration and public container image/qualified release-manifest publication
remain pending. A public module listing does not qualify application artifacts
or a live installation.

## Import 0.2.0 archives into ECR

Dispatch [0.2.0](https://github.com/dispatchlabs-ai/dispatch/releases/tag/v0.2.0)
publishes the AMD64 controller, matching Ubuntu worker and frontend as archives.
GHCR publication and a qualified schema-v1 registry manifest remain pending.
You can import the images into your own ECR and supply the resulting digest-pinned
`image` and `worker_image` inputs directly. No application checkout, Nix build or
GHCR credential is required. This is a source-reviewed operator procedure, not
an executed AWS installation or a module/application compatibility qualification.

Use AWS CLI with your existing authorization and a Docker Engine that supports
both Docker-save and OCI archive loading, and `docker image push --platform`
(API 1.46+). The worker archive is OCI layout; an older Docker image store may
not load it. Do not rebuild or convert it with `docker import` to work around
an unsupported loader. Use a dedicated daemon/context, or ensure the local tags
below are absent or already identify these bytes: loading can replace tag mappings.

### Download, verify and load

Download these files from the trusted release page into a new directory:
`dispatch-controller-b8dda02-amd64.tar.gz`,
`dispatch-worker-ubuntu-b8dda02-amd64.tar.gz`, `dispatch-frontend.tar.gz` and
`SHA256SUMS`. On Linux:

```sh
for name in dispatch-controller-b8dda02-amd64.tar.gz dispatch-worker-ubuntu-b8dda02-amd64.tar.gz dispatch-frontend.tar.gz; do
  awk -v n="$name" '$2 == n { print }' SHA256SUMS | sha256sum --check --strict || exit 1
done
```

Require each explicit `OK` before continuing. On macOS use `shasum -a 256 -c -`
instead of `sha256sum --check --strict`. Checksums from this trusted release
channel verify integrity, not independent publisher identity; no Dispatch
publisher signature is claimed.

```sh
docker load -i dispatch-controller-b8dda02-amd64.tar.gz
docker load -i dispatch-worker-ubuntu-b8dda02-amd64.tar.gz
docker image inspect dispatch-web:b8dda02325cf dispatch-agent:b8dda02325cf-amd64 \
  --format '{{.Os}}/{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
```

Both must report `linux/amd64` and application revision
`b8dda02325cff7978f413ecc4d41641b74801089`. Loading/inspection does not start containers.

### Push into the intended repository

Select your own nonsecret profile/region and existing repository outputs. Do not
create replacement infrastructure as part of this transfer:

```sh
export AWS_PROFILE='YOUR_PROFILE'
export AWS_REGION='YOUR_REGION'
export ECR_REPOSITORY_URL='YOUR_ECR_REPOSITORY_URL'
export ECR_REPOSITORY_NAME='YOUR_ECR_REPOSITORY_NAME'
registry=${ECR_REPOSITORY_URL%%/*}
controller_tag=0.2.0-b8dda02325cf-controller-amd64
worker_tag=0.2.0-b8dda02325cf-worker-ubuntu-amd64
aws sts get-caller-identity
aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME"
```

Confirm the account, region, repository URL and tag immutability. Check both tags
with `aws ecr describe-images` before pushing: existing tags must be inspected,
not overwritten/deleted. An authorization/network error is not proof a tag is absent.
Retain the original archives and prior installation images. Prefer the ECR Docker
credential helper; otherwise use short-lived login via password-stdin:

```sh
aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$registry"
docker tag dispatch-web:b8dda02325cf "$ECR_REPOSITORY_URL:$controller_tag"
docker tag dispatch-agent:b8dda02325cf-amd64 "$ECR_REPOSITORY_URL:$worker_tag"
docker image push --platform linux/amd64 "$ECR_REPOSITORY_URL:$controller_tag"
docker image push --platform linux/amd64 "$ECR_REPOSITORY_URL:$worker_tag"
```

Stop on any failure; do not delete images to make a retry succeed. Never print,
paste or commit the login password. Platform-specific pushes publish image
manifests rather than a multi-platform index.

### Verify destination identities

For each tag, obtain `imageDigest` with `aws ecr describe-images` and compare it
with the successful push output. Retrieve the manifest **by that digest** using
`aws ecr batch-get-image`. Verify its `config.digest` against the configuration
blob independently hashed from the reviewed release archive:

| Image | Expected configuration digest — not a deployment manifest digest |
| --- | --- |
| Controller | `sha256:27d9aa77710667b670b7bf88f8089c72a9cca4b815e34d9c43a225939f54952c` |
| Ubuntu worker | `sha256:af6501ed9f5a5e07b9a17bc4781f2c51912ea59cea9c302f02726e03184a7338` |

Pull each image by its ECR manifest digest and inspect the platform/revision
again. Keep the manifests, push output and resulting references with your
installation receipt. Supply `image` and `worker_image` as
`<your-ECR-repository>@sha256:<verified-role-manifest-digest>` and
`cpu_architecture = "X86_64"`. Archive checksums, configuration digests and local
Docker image IDs are **not** these deployment inputs.

Keep your reviewed module pin. Stage the frontend through your installation's
publication workflow to a new immutable release prefix while retaining shared
hashed assets and earlier prefixes. Its archive SHA-256 is
`59654ea1d75f9308013d3e22cca5bfc8bd6d43917df25a9c9cf8bf34a0d37214`;
frontend packaging revision is `2af772e74c551e62f988db7bc5a971a94c3e1db1`.
The current `publish-frontend.py` requires a schema-v1 registry manifest with an
exact qualified module-version claim; do not fabricate that claim merely to run
the helper. Resolve that contract with the owning publisher or use your existing
frontend publication workflow. Image import alone does not apply Terraform,
switch the frontend, initialize a database or qualify hosted/model/worker behavior.

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

## Recorded source checks — October 10, 2026

The dated acceptance records below preserve the evidence and outstanding work
at the time of each check. For current module registry availability, see
[Registry publication status](#registry-publication-status).

At module `0edd7f19ed461f55de466aa2e91d34936f34100d`, Documenter inspected
Developer's integrated check output: format/init/validate and all **eight mock
plan scenarios** passed under OpenTofu **1.13.1** and Terraform **1.13.5**, using
AWS provider **6.67.0**. The scenarios cover foundation, public-image inputs,
invalid pins/zones/pull authority, scoped activation, initializer separation and
rolling configuration. Activation overrides the image ENTRYPOINT so its
read-only operator task does not run the ordinary writable-state entrypoint.

The same output records **17 offline helper tests** (seven artifact selector,
ten operator receipt/observation checks) and activation-template syntax success.
All scenarios are mock plans: no mock applies or AWS calls. Terraform's plan-time
mock option is added only to an ignored fixture copy; OpenTofu runs the committed
fixture, preserving the assertions. These are inspected owner-produced checks,
not Documenter's repeated execution or Fargate startup proof. Pi Durable Expert
completed final configuration/lifecycle source review of `0edd7f1` without a
blocking finding; container hardening, scope separation and no-replay handling
remain intact. That review is not ECS or fresh-install qualification.

Independent consumer verification also passed at **`0edd7f1`**: Deployer used
module-only Git archives and a separately copied complete caller under Terraform
**1.13.5** and OpenTofu **1.12.6**, with AWS provider **6.67.0**. Caller
init/validate, all eight mock plans per engine and all 17 offline helper tests
passed. Documenter inspected the retained check logs. Both engine processes used
temporary HOME/credential-empty environments; no application checkout, AWS API,
apply, image pull or customer access was used. This closes the external-caller
**source** check, not the live fresh-install acceptance above.

**Remaining acceptance at the time of these checks:** actual public image pulls,
registry registration, fresh-account AWS initialization/activation, private
enrollment/provider terminal,
model/tool/browser workflow, controller/worker replacement and measured rollout
latency remain unverified. The repository is now public; that visibility does not qualify
the runtime or registry distribution. Source publication is verified separately from these
runtime and distribution outcomes.


## Baseline gap-fill acceptance

The October 10 implementation authorization extends the earlier source checks;
those earlier passes do not qualify the added infrastructure. Record separate
source checks and actual runtime evidence for:

- ALB access-log delivery/lifecycle, ACM validation and Route 53 routing.
- Stable append-only hashed-asset URLs across frontend index-prefix changes;
  retained old directories alone do not preserve absolute `/assets/<hash>` URLs.
- CloudFront SPA/assets delivery without authenticated-response caching, lost
  cookies/origin checks, API error-to-index rewriting or broken SSE streaming.
- Rolling controllers without unnecessary worker replacement; Spot interruption
  with confirmed old-executor termination before replacement and no mutation replay.
- Aurora version/region compatibility, effective credential-safe settings,
  workload-aware cost comparison and fail-closed recovery after connection loss.
- Safe sampled spans exported from ordinary services/workers, short operational
  retention, and no recording of credential-maintenance terminals.

No EFS or speculative workspace filesystem is required. Keep temporary working
files disposable and artifacts durable in ordinary S3. Independent-engine mock
plans and source builds remain distinct from AWS/CDN/database/Spot execution.

Cost estimates are an explicit completion requirement (October 10). Provide a
dated regional estimate with prices/sources and workload assumptions: fixed
foundation/control-plane costs at zero workers; Aurora Serverless v2 versus small
RDS at idle and active use; On-Demand versus Spot worker-hours; logs/traces,
ALB/LCUs, NAT/data transfer, CloudFront, DNS, S3 and storage/backup costs. State
architecture/task sizing, expected ACU-hours, retained connections and exclusions.
Separate AWS usage costs from model/MCP charges, taxes and discounts; do not
present a sizing estimate as an invoice or a universal cheapest configuration.


## Baseline source acceptance — October 10, 2026

**Source implementation and cost estimates accepted; runtime/public distribution
remain unqualified.** At `fc216e9`, independent module-only Git archives plus
external callers passed init/validate and **20 mock plans per engine** under
Terraform **1.13.5** and OpenTofu **1.12.6**, AWS provider **6.67.0**. **23 offline
helper checks** and edge-function checks also passed. Documenter inspected these
retained consumer logs. Both engines used temporary HOME/credential-empty
contexts; no application checkout, AWS apply or customer access was needed.
Developer's integrated checks also pass on OpenTofu **1.13.1**/Terraform **1.13.5**.
Changes through `f040bd7` add documentation and the publisher-check Makefile entry,
not different infrastructure. Mock plans are not cloud plans/applies.

Pi source-reviewed module `f6ff8d5` and application `4f48d7b` with no remaining
blocking finding in scope. Rolling defaults share normalized peer-network rules,
shared assets preserve old absolute chunk URLs, and only the outer HTTP boundary
logs request summaries. Deslop reviewed those fixes and collector cost accounting
without additional complexity blockers. Callback GET queries are removed before
ALB logging while browser URLs/ordinary API queries remain unchanged; offline edge
checks do not establish real provider authorization.

Application slices `f5c9674`/`8d91d98` passed owner-reported Nix-shell application,
Apple Silicon Nix build, flake evaluation and source/whitespace review; no runtime
tests. Deterministic `nix build .#frontend` packaging at `b888a1c` passed
owner-reported build/flake checks. Deployer reports offline publisher verification
of the actual **342-file** bundle and a network-disabled collector startup check,
not public publication or AWS trace delivery. Documenter independently passed
caller init/validate on Terraform 1.13.5/OpenTofu 1.13.1 and all 23 helper checks.

The [regional estimate](../releases/cost-estimate.md) supplies dated prices,
three-zone/accounting and workload assumptions, controller/collector headroom,
Aurora/RDS comparison, worker/Spot scenarios and exclusions. It is planning
evidence, not real billing or a universal cheapest configuration. Consumers use
verified bundles/images; no application checkout or build is required.

Actual CDN/API/SSE behavior, log/trace delivery, Aurora initialization/failover,
Spot interruption, provider login, zero-downtime continuity and fresh-account
installation remain **unverified**. At the time of these checks, public artifact
publication and registry registration remained gated on the open-source release;
source publication alone did not establish those outcomes.

## Idle-cost source acceptance — October 10, 2026

Module `192c6ce` and application `a502fc8` implement the operator-driven low-idle
profile. Source review by Pi/Deslop has no remaining blocker in scope. Retirement
reuses existing admission/native inspection and launcher evidence; planned-health
acceptance does not reopen public admission. Read-only owner-status polling precedes
one activation POST. Fresh controller identities/counts are rechecked after gating
and before mutations; actual STOPPED/clean-exit checks remain required.

Deployer reports independent Git-archive/external-caller passes at `192c6ce` on
Terraform **1.13.5** / OpenTofu **1.12.6**, provider **6.67.0**: **28 mock plans per
engine**, **34 Python checks**, **9 operator-request cases** and edge checks.
Controller-drift refusal is included; Pi verifies all **11 lifecycle checks**. Documenter independently
reran **34 Python checks**, the **9 operator-request cases**, and complete caller
init/validate on Terraform **1.13.5** / OpenTofu **1.13.1** after the correction.
These are offline/source checks, not AWS plans/applies or application runtime tests.

For application `a502fc8`, Developer reports integrated npm type/build checks,
Apple Silicon Nix application/frontend builds and flake evaluation passed; zero
runnable Darwin checks and incompatible Linux checks omitted. Pi's `1114256` slice
has matching reviewed server source and owner-reported build/whitespace passes.

The [idle/active model](../releases/idle-cost-estimate.md) prices the stated sleeping
installation at **$26.73/month fixed/assumed-storage**, conditional on stopped tasks
and genuinely paused Aurora, with usage/wake exclusions. A sleeping conversation
has no task/IP cost, but still shares this installation's retained floor. This is
not a measured bill, demonstrated global minimum or automatic idle policy.

Actual non-cancelling busy/background refusal, clean sleep/reopen, Aurora pause,
complete wake latency and billing remain **unverified**. No customer/live AWS
access, migration or image/registry publication is established by this acceptance.
