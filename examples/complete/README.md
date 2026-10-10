# Complete caller root

This root consumes the module without an application checkout. It starts with
foundation only: null images/application and zero services. Copy it into your
caller repository and replace `source = "../.."` with the module Git URL pinned
to a full commit, or run it from an immutable module checkout. Use your own
restricted state backend and commit the caller provider lockfile. Do not share
state between Terraform and OpenTofu executions against the same installation.

Required foundation variables are `region`, `name`, `availability_zones` (exactly
two distinct zones) and `vpc_cidr`. Before managed ingress, supply `domain.name`
and its existing public Route 53 `zone_id`. The example passes both the regional
AWS provider and `aws.edge` in `us-east-1`; deploy the CloudFront viewer certificate
there even when your application region differs. No example account, domain, certificate, secret
or image is deployable by default. Foundation still creates billable resources. Tasks default to `task_egress =
"public-ip"`, avoiding permanent NAT charges while preserving private ALB/database
and security-group-restricted task ingress. Public IPv4 is billed while tasks run;
`"nat"` instead keeps tasks privately placed behind a billable NAT gateway.
Aurora defaults to 0.5–4 ACUs; select `aurora_min_capacity = 0` with
`aurora_seconds_until_auto_pause = 300` for connection-free auto-pause eligibility.
Running owners still prevent pause; review the provisioned `database_mode = "rds"` alternative and
[idle/active cost comparison](../../releases/idle-cost-estimate.md). No EFS or durable workspace is created.

```sh
# Choose one engine consistently for your installation.
tofu init
tofu validate
tofu plan -out=foundation.plan
tofu apply foundation.plan
```

Terraform uses the same commands with `terraform` instead of `tofu`. Run apply
only after reviewing the saved plan, AWS account and costs. A plan file is private
infrastructure material even when it contains only secret references.

Follow [installation](../../docs/installation.md) to populate the typed
`application` input and immutable image selections, initialize separately and
activate. Secret ARN maps must contain all required names; the module validates
them. Do not substitute a partial bootstrap map or allow fallback to task-local
SQLite. Public HTTP health alone does not establish a successful installation.

This source example is not a recorded fresh-account AWS installation. Engine
validation and offline checks must be reported separately from live acceptance.

For CloudFront, publish the trusted released SPA bundle using the explicit
[publication helper](../../releases/README.md#spa-bundle-and-publication) **before**
selecting its emitted `frontend_release_prefix`. Assets remain shared append-only;
HTML is release-prefixed. Terraform never builds/uploads frontend content.

Use `task_subnet_ids` and `task_assign_public_ip` for operator launches, not hardcoded
private subnets/public-IP disabling. The private subnet output remains available
for database/network consumers, not as the selected task placement contract.
Managed-domain ingress shares one private ALB with isolated listener ports:
443 viewer API, 8830 launcher control and 8443 worker callbacks. A caller-owned
public API ALB retains separate private control ingress.
