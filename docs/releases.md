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

## Recorded source checks — October 10, 2026

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

**Remaining acceptance:** actual public image pulls, registry registration,
fresh-account AWS initialization/activation, private enrollment/provider terminal,
model/tool/browser workflow, controller/worker replacement and measured rollout
latency remain unverified. The repository remains private pending authorized
open-source publication. Source publication is verified separately from these
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
installation remain **unverified**. Public artifacts/registry registration remain
gated on the open-source release; source publication is not that qualification.

## Idle-cost source acceptance — October 10, 2026

Module `192c6ce` and application `a502fc8` implement the operator-driven low-idle
profile. Source review by Pi/Deslop has no remaining blocker in scope. Retirement
reuses existing admission/native inspection and launcher evidence; planned-health
acceptance does not reopen public admission. Read-only owner-status polling precedes
one activation POST. Fresh controller identities/counts are rechecked after gating
and before mutations; actual STOPPED/clean-exit checks remain required.

Deployer reports independent Git-archive/external-caller passes at `8b8ee00` on
Terraform **1.13.5** / OpenTofu **1.12.6**, provider **6.67.0**: **28 mock plans per
engine**, **33 Python checks**, **9 operator-request cases** and edge checks.
`192c6ce` adds a drift-refusal guard/test and corrects output wording, not different
infrastructure. Pi verifies all **11 lifecycle checks**. Documenter independently
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
