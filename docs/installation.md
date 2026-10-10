# Installation

Use a fresh dedicated installation. This guide does not convert another store,
reuse a customer's environment or authorize an AWS apply. The
[complete example](../examples/complete/README.md) is the owning caller root.

## 1. Prepare the caller

Choose one engine, its supported version, AWS provider lockfile, region, two
availability zones and a restricted remote state backend. Check the AWS identity
before planning. Restrict state/plan access even though secret values are not
module inputs. Choose the final HTTPS origin before enrollment: changing the
hostname changes the passkey relying-party identity.

Supply `domain = { name, zone_id }` for an existing public Route 53 hosted zone
that you control. The baseline manages ACM validation and DNS aliases, using the
regional AWS provider and an `aws.edge` alias in `us-east-1` for CloudFront's
viewer certificate. The viewer origin is `https://<domain.name>`; it must match
`application.origin`. The API ALB stays private behind CloudFront's VPC origin;
private S3/OAC serves the SPA. Do not add a public API-origin bypass.
Validate regional availability and network reachability for image pulls, logs,
tracing and selected model/MCP providers before reviewing the plan.
`task_egress = "public-ip"` places running tasks in public subnets with public IPv4
for outbound access, avoiding a permanent NAT gateway. Task ingress remains
security-group restricted; ALB/database stay private. `"nat"` keeps tasks privately
placed behind NAT. This choice applies to ordinary and maintenance tasks.

## 2. Apply foundation only

Keep `application`, `image` and `worker_image` null, `desired_count = 0`, and
operator-task switches false. Review the actual saved plan/cost, then apply.
ALB, database storage, secrets, DNS and other retained foundation resources incur
costs at zero tasks; the optional NAT mode adds permanent NAT/EIP charges.
`database_mode = "aurora-serverless"` defaults to a writer with 0.5–4 ACUs, no
reader/proxy. For auto-pause eligibility select `aurora_min_capacity = 0` and
`aurora_seconds_until_auto_pause` (300–86400 seconds; default 300). Every Dispatch
and maintenance database owner must close its connections before the idle interval
can begin; no queries does not mean no connections. The alternative `"rds"` preserves small
provisioned PostgreSQL. Review the dated regional cost comparison and workload
assumptions; retained owner connections matter and serverless is not automatically
cheapest. Select a region-supported pinned database version, not an unverified
"latest" string.
Read `database_address` and the RDS-managed `database_master_secret_arn`; only a
one-off database initializer may receive master authority.

## 3. Prepare retained secrets and trust

Create/populate installation-owned Secrets Manager values through your trusted
private secret-management workflow, **not Terraform secret-version resources**.
The renderer takes exact ARN references and writes restricted task-local files.
Retain matching versions outside task storage. Never regenerate keys on restart.

Populate `application` with:

| Input | Requirement |
| --- | --- |
| `installation_id`, `company_id`, `company_name` | Stable installation/company identity, not credentials |
| `origin` | Final HTTPS origin |
| `configuration_revision` | Shared backend/launcher worker-configuration identity |
| `database_ca_pem` | Reviewed PostgreSQL CA trust, verified against the RDS hostname |
| `backend_ca_pem` | Private backend peer TLS trust |
| `callback_ca_pem` | Required for managed domain: public ACM callback certificate CA trust, separate from peer TLS |
| `backend_certificate_pem` | Backend leaf certificate/chain covering `backend.<name>.internal` |
| `backend_private_key_secret_arn` | Exact secret reference for its matching private key |
| `database_url_secret_arns` | Seven distinct URL secrets: `auth`, `provider`, `catalog`, `directory`, `routing`, `launcher`, `workers` |
| `encryption_key_secret_arns` | Three retained key secrets: `auth`, `provider`, `catalog` |
| `token_secret_arns` | Five retained tokens: `worker`, `launcher`, `operator`, `backend_peer`, `launcher_peer` |

Key secret values are canonical padded base64 for 32 random bytes. Token values
are retained base64url text. All seven URL secrets use the actual RDS endpoint,
distinct lowercase role/database names and distinct passwords generated from at
least 32 random bytes as unpadded base64url. Do not add URL query parameters or
SSL overrides. The initializer validates these requirements before mutation.
`catalog` holds the MCP connection catalog; `workers` is the per-conversation
provisioner store. The renderer supplies all six persistent backend configurations
and the separate launcher journal; do not substitute a partial map that could
fall back to disposable SQLite.

For the managed domain, regional ACM covers `callbacks.<domain.name>` and private
DNS resolves it to the isolated callback listener on port **8443**; workers must trust its public ACM CA
chain through `callback_ca_pem`. This is separate from your private backend peer
leaf/CA and CloudFront viewer certificate. Never send peer private keys to ACM.
For the caller-owned certificate alternative, the private callback certificate
must cover `backend_callback_hostname`; supply matching callback CA trust and
keep `launcher_internal_alb = true`. Certificates/CA text are public configuration;
private keys, credential-bearing URLs and tokens remain secret. Supply
`secret_kms_key_arns` for customer-managed encryption keys.

Select compatible digest-pinned controller and Ubuntu-worker images for the
same Linux architecture. The [release contract](releases.md) explains artifact
selection. Missing public release artifacts are a release blocker, not permission
to use fabricated digests. Keep counts zero while preparing definitions.

## 4. Prepare the frontend release

Use the released, SHA-256-verified SPA bundle compatible with the selected
controller release. It contains `index.html` and built assets, not source, secrets
or customer configuration. Do not require an application checkout or Nix build
from an independent caller. Artifact publication remains gated on the open-source
release; absence of that bundle is a release blocker, not permission to use a
fabricated archive or an unrelated local build.

The caller exports `frontend_bucket`, `frontend_distribution_id` and
`frontend_release_prefix`. The artifact selector derives the immutable prefix
`releases/sha256-<archive-digest>` from the trusted release manifest. Publication
is an explicit operator action outside Terraform:

```sh
# Run from the caller root; outputs contain references, not resolved secrets.
tofu output -json > /path/to/operator-outputs.json
# From the module checkout, preview offline; use your actual qualified version/platform.
python3 scripts/publish-frontend.py /path/to/dispatch-release.json \
  /path/to/dispatch-frontend.tar.gz --module-version "$MODULE_VERSION" \
  --platform linux/arm64 --outputs /path/to/operator-outputs.json \
  --account "$AWS_ACCOUNT_ID" --region "$AWS_REGION"
# Repeat the reviewed command with --execute --receipt /private/NEW-publication.json
```

Use `linux/amd64` when appropriate; it must match the selected application release.
Only explicit execution calls AWS. The helper verifies archive bytes/safe paths,
account, bucket owner/region and conditional object checksums. It publishes shared
append-only `assets/*` first and release-prefixed `index.html` last, without
retries, overwrites or deletes. An interrupted upload requires inspection of its
receipt; an intentional new invocation verifies existing identical objects and
uploads only missing ones. A mismatch blocks publication, never an overwrite.
See the [publisher contract](../releases/README.md#spa-bundle-and-publication).

On first foundation, the empty bucket/distribution is not a serving installation;
finish verified publication before enrollment/readiness acceptance. For updates,
upload the next bundle **before** selecting its `frontend_release_prefix` in a
reviewed apply. Explicitly invalidate cached navigation after selection (a reviewed
`/*` CloudFront invalidation is one option); verify browser/API behavior afterward.
Keep old prefixes and shared assets: retained directories alone cannot preserve
an open client's absolute `/assets/<hash>` URLs. Never use `s3 sync --delete`.
A successful upload or apply does not establish CDN delivery or application
activation, and public artifacts remain release-gated.

CloudFront routes `/api` and `/api/*` to the private ALB with caching disabled,
while a static-only rewrite handles SPA navigation. Verify authenticated errors
remain API errors, cookies and the original request origin reach the backend,
and SSE streams are not converted into cached or buffered static responses.
Private activation and worker callback paths must never become viewer routes.
The public MCP OAuth callback remains `/api/connections/oauth/callback`: CloudFront
strips its GET query before the ALB, not from the browser address. Callback HTML
reads the browser URL and POSTs completion JSON; other API queries remain intact.
Verify that flow separately before declaring real provider authorization works.

## 5. Initialize and verify explicitly

Enable `enable_database_initializer`, plan/apply the one-off definition while
controllers/workers remain stopped, and independently confirm actual task
termination. Zero desired count alone is not termination proof. The operator runs
in the **service cluster**, never the worker-only cluster.

The default initializer operation is read-only verification. For fresh creation,
explicitly invoke the released image's command override:

```text
dispatch-bootstrap database-init --config /tmp/dispatch-bootstrap/database-init.json --create --confirm-services-stopped
```

From the caller root, export nonsecret operator outputs privately with
`tofu output -json > /path/to/operator-outputs.json` (or `terraform output -json`).
From the module checkout, preview first using Python 3.10+ and AWS CLI:

```sh
python3 scripts/run-operator.py run --outputs /path/to/operator-outputs.json \
  --operation database-create --account "$AWS_ACCOUNT_ID" --region "$AWS_REGION" \
  --confirm-services-stopped
```

After independently confirming stopped owners and reviewing the preview, add
`--execute --receipt /path/to/create-receipt.json` to submit **once**. A successful
submission is not command completion. Observe the exact recorded task:

```sh
python3 scripts/run-operator.py observe --receipt /path/to/create-receipt.json \
  --account "$AWS_ACCOUNT_ID" --region "$AWS_REGION" --wait-seconds 600
```

Then run a separate verification task with `--operation database-verify`, the
same stopped-owner assertion and a new receipt path. Inspect the
actual task STOPPED state and **all** container exit codes for each invocation.
A stop request, waiter timeout or healthy database is not success. Observation
exit code 2 means incomplete; observe the same receipt again, do not rerun `run`.
If submission itself is uncertain, preserve its prewritten receipt/client token
and reconcile privately; this helper does not automatically replay RunTask. On failure or
uncertain create result, preserve the original secrets and partial database state;
inspect privately. Do not automatically retry, reset roles or delete databases.
`--verify` checks a complete contract; it does not repair a partial result.

Remove the temporary initializer definition/authority after successful bootstrap
without deleting stores or secrets. The application owns schema startup; this
operator is not a schema migration engine.

## 6. Enroll and authorize while the backend is stopped

Remove `enable_database_initializer` after verification. Keep backend desired
count zero and independently confirm backend, workers and earlier maintenance
tasks STOPPED. Set `enable_credential_maintenance = true`, review/apply its scoped
definition, then refresh the caller outputs. The terminal receives **only** auth
and provider credentials; it has no RDS master, activation token or application
endpoint access. It uses its own maintenance cluster, not the worker cluster.

The receipt helper deliberately does not launch this interactive task. Using
AWS CLI v2 (with the Session Manager plugin) or your private AWS operator console,
launch exactly one task from `credential_maintenance.task_definition_arn` in
`credential_maintenance.cluster_arn`, with `task_subnet_ids`, its own
`security_group_id`, and `assignPublicIp` set to `ENABLED` when
`task_assign_public_ip` is true (`DISABLED` otherwise). Enable ECS Exec for this
one-off terminal only. Retain the exact task ARN/client token privately before
continuing; reconcile an uncertain launch instead of launching again. Check the
volume initializer completed and the terminal container is running before Exec.

Attach a private, unrecorded shell session to container `credential-maintenance`:

```sh
aws ecs execute-command --cluster "$MAINTENANCE_CLUSTER_ARN" \
  --task "$MAINTENANCE_TASK_ARN" --container credential-maintenance \
  --interactive --command /bin/bash --region "$AWS_REGION"
```

Those variables are nonsecret identifiers from caller outputs/the confirmed task.
The cluster disables session-output logging and the terminal container has no
container logging. ECS Exec **command strings remain audited**: pass only the
shell command, never an email, invitation, token, OAuth URL/code or credential.
Disable shell history/session capture inside this private terminal. Check the
actual effective UID: Exec runs as root despite the configured container UID.
Materialize and invoke the CLI under the same effective UID; don't chown existing
inputs or reuse another task's bootstrap directory.

Inside the first fresh terminal task, read the intended account address privately
into `ACCOUNT_EMAIL`, then run:

```sh
# Run only inside the private terminal, not as an ECS command override.
HISTFILE=/dev/null
set +o history
read -r -s -p 'Account email: ' ACCOUNT_EMAIL; printf '\n'
dispatch-bootstrap auth invite \
  --auth-store-config /tmp/dispatch-bootstrap/auth.json --email "$ACCOUNT_EMAIL"
unset ACCOUNT_EMAIL
```

This explicitly selects PostgreSQL; omitting `--auth-store-config` could silently
select task-local SQLite. Deliver the single-use invitation privately, never in
logs/receipts. Let the CLI close its store, exit the session, stop that exact
terminal task and confirm STOPPED before another maintenance invocation.

For provider authorization, launch a **separate fresh** maintenance task/session
with the same retained inputs and stopped-backend check. Inside it, use:

```sh
dispatch-bootstrap provider-auth login --provider openai-codex --type oauth \
  --config /tmp/dispatch-bootstrap/provider.json --confirm-backend-retired
```

Select the provider/type that your installation actually uses; the Codex command
is an example, not an account eligibility promise. Answer secret prompts only in
this unrecorded TTY. Device-code verification requires an authorized human; never
copy a developer's Pi login or expose loopback callback ports publicly. Let the
CLI finish and close its store, then stop and confirm that terminal task. A second
bootstrap in the same task is intentionally refused because its private directory
already exists. If login fails or is cancelled, await CLI exit and confirm task
termination before starting the backend. Do not force owner recovery to skip this.

Remove the maintenance definition/authority by disabling
`enable_credential_maintenance` and reviewing/applying its removal plan, without
deleting retained stores/secrets. Only then start the backend. Provider
authorization does not select a model; choose one from that provider after login.

## 7. Start and activate


Set `desired_count = 1` with `service_desired_counts = { backend = 0 }`
while starting the launcher; verify its selected worker definition/revision and
permissions. Clear the override to start the backend and enable
`enable_activation`. Fresh installation admission is closed. Reach the backend
**privately**, using the operator token and reviewed CA supplied to the activation-only task, and invoke
`POST /internal/undrain` before waiting for backend readiness. The backend also
undrains its launcher. The registered activation task performs this call with
verified TLS, without token argv or database credentials. Public and callback listeners are not maintenance routes.
Waiting for readiness first can deadlock this intentional admission gate.

Use the dedicated activation-only operator path; credential maintenance has a
stopped-backend precondition and must not be repurposed. Do not pass a token on
argv or expose maintenance publicly. Export current caller outputs again, then preview/execute `--operation activate`
with `scripts/run-operator.py` and a **new** activation receipt path. Do not pass
`--confirm-services-stopped` as evidence for activation: controllers must be
started. Observe that receipt read-only until successful termination.
Confirm the activation helper has terminated,
then verify controller readiness, ALB targets and signed-out HTTPS.


## 8. Verify the result

Sign in, create a chat, obtain a real model response and harmless tool result,
reload retained history and check attachments if enabled. Verify one executor per
conversation and confirmed old-worker termination before a replacement starts.
Record exact module/image revisions and scoped outcomes. This handoff is not
complete because a landing page returns HTTP 200. See
[release acceptance](releases.md#fresh-install-acceptance).
