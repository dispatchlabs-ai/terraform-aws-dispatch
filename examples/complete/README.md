# Complete caller root

This root consumes the module without an application checkout. It starts with
foundation only: null images/application and zero services. Copy it into your
caller repository and replace `source = "../.."` with the module Git URL pinned
to a full commit, or run it from an immutable module checkout. Use your own
restricted state backend and commit the caller provider lockfile. Do not share
state between Terraform and OpenTofu executions against the same installation.

Required foundation variables are `region`, `name`, `availability_zones` (exactly
two distinct zones) and `vpc_cidr`. No example account, domain, certificate, secret
or image is deployable by default. Foundation still creates billable resources.

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
