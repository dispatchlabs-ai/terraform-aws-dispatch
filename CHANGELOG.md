# Changelog

## Unreleased — Kubernetes experiment

- Select a separate Cilium policy owner for distributed workers while AWS VPC CNI
  retains address allocation. Expose the policy-provider contract to callers and
  document explicit stopped-owner migration before changing an existing cluster.
  Platform installation remains outside Terraform. This source change has not
  been applied to the retained installation.
