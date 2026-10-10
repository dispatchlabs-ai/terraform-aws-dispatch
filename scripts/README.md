# Operator helpers

Use Python 3.10+; live operator submission additionally requires AWS CLI v2 with
customer-owned credentials and permission to invoke the selected ECS task and pass
its scoped roles. These helpers do not install tools, create credentials, apply
Terraform, or access a customer repository. They do not create a public release.

## Select release artifacts

[`select-artifacts.py`](select-artifacts.py) validates a trusted publisher manifest
and prints the selected image inputs offline. See the [image release contract](../releases/README.md)
for format, provenance requirements and verification limits.

## Invoke a registered operator task

[`run-operator.py`](run-operator.py) supports only these explicit operations:

| Operation | Registered output | Container behavior |
| --- | --- | --- |
| `database-create` | `database_initializer` | Released `dispatch-bootstrap database-init --config /tmp/dispatch-bootstrap/database-init.json --create --confirm-services-stopped` |
| `database-verify` | `database_initializer` | Same released initializer with `--verify`, not `--create` |
| `activate` | `activation` | Registered one-shot activation command, without overrides |

Terraform registers these optional tasks but never executes them. Enable the
selected task in the customer root first and inspect/apply the intended plan.
The helper does not enable an operator or change service counts. `activate` runs
against the private backend; it is not a readiness probe or public URL request.
Its success depends on the registered command checking the actual activation
response. Observe it before waiting for backend readiness on a fresh installation.

Export only the module's nonsecret output object to an operator file outside Git.
For a root exposing `output "dispatch" { value = module.dispatch }`, use:

```sh
tofu output -json dispatch > /private/operator/module-outputs.json
```

`terraform output -json dispatch` works the same way. A direct module-root
`output -json` envelope is also accepted. Required keys are
`service_cluster_arn`, `worker_cluster_arn`, `private_subnet_ids`, and the selected
operator output with `task_definition_arn` and `security_group_id` (optionally
`cluster_arn`). No secret values belong in these outputs. The helper never prints
unused output fields. Ensure the private directory already exists.

Preview is the default; it performs **no AWS calls**:

```sh
python3 scripts/run-operator.py run \
  --outputs /private/operator/module-outputs.json --operation activate \
  --account 123456789012 --region us-east-1 --profile customer
```

Replace the example account, region, profile and paths with the customer's values.
After reviewing the request, submit exactly once using a **new receipt path**:

```sh
python3 scripts/run-operator.py run \
  --outputs /private/operator/module-outputs.json --operation activate \
  --account 123456789012 --region us-east-1 --profile customer \
  --execute --receipt /private/operator/activation-1.json
```

The helper verifies STS account identity, checks ARN account/region and revision-pinned
task identity, refuses the worker-only cluster, disables public task addressing and
Exec, and records an exclusive mode-0600 intent receipt before calling `RunTask`.
AWS SDK retries are disabled. The random client token and `startedBy` marker support
reconciliation; they do not authorize a second submission. An existing receipt path
is refused even if its earlier operation failed. Keep one operator mutation at a time.

A successful `run` exit means **submitted**, not completed. Use read-only observation:

```sh
python3 scripts/run-operator.py observe \
  --receipt /private/operator/activation-1.json \
  --account 123456789012 --region us-east-1 --profile customer --wait-seconds 600
```

`observe` never submits, stops or repairs a task. Without `--wait-seconds` it performs
one lookup; with a bounded wait it polls read-only state. It returns:

- **0:** the exact task is STOPPED, the expected application container is present,
  and every reported container is STOPPED with exit code 0.
- **2:** the task has not stopped by the observation deadline; outcome pending.
- **1:** failure or uncertain/unavailable state, including a nonzero/missing exit
  code. A missing task is not evidence of termination.

The task ARN, status and container exit codes are printed, not raw logs, secret
values, private response bodies or AWS error payloads. Observe can be repeated
safely for a known task; it does not modify the original submission receipt. This
transport evidence is not full application/browser acceptance.

### Database operations and uncertain outcomes

Both database operations require `--confirm-services-stopped`, including previews.
Before supplying it, independently confirm the exact previous backend, launcher,
worker and maintenance executors actually STOPPED. Desired count zero, expired
leases, missing inventory and an available database lock are not that confirmation.
The flag is an operator assertion, **not an automatic cloud-wide retirement check**.
Never initialize an installation that already has application stores.

Use a separate explicit `database-verify` invocation only after the successful
creation task is confirmed STOPPED. Verification is not a repair operation and
must not run concurrently with another owner. Remove the optional initializer
resources through the reviewed customer-root plan before normal activation.

If submission times out or disconnects, the receipt remains `prepared` or `uncertain`.
**Do not rerun with a fresh receipt, replay creation/activation, or assume no task ran.**
Reconcile the recorded client token/`startedBy` through ECS/CloudTrail with the
customer operator. If the task ARN is recorded, use `observe`. Otherwise establish
the exact task/cluster/definition independently before recording its ARN for
read-only observation. Even a definitely failed database-create task can have
partially created stores; investigate using the application initializer guidance,
not an automatic retry/reset. Credential maintenance and interactive enrollment
remain separate operator procedures; this helper deliberately has no arbitrary
command or credential arguments.

## Offline checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

All fixtures and AWS responses are synthetic. Checks cover preview without AWS,
private networking, operation selection, output/identity guards, intent-before-call,
refusal to overwrite/replay, ambiguous submission and exact-task/all-container
completion. Passing them does not establish AWS IAM, secret delivery, image pulls,
private networking, database creation or activation behavior in a real account.
