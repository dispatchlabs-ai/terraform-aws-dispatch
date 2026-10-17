# Platform IAM policy provenance

`aws-load-balancer-controller-v3.6.0.json` is the unmodified upstream installation policy from:

https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.0/docs/install/iam_policy.json

SHA-256: `16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a`

Upstream source: https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/v3.6.0 (Apache-2.0). Its license is retained in [LICENSE.aws-load-balancer-controller](LICENSE.aws-load-balancer-controller); the module's MIT license does not replace that upstream license. The controller uses an IRSA role bound exclusively to `system:serviceaccount:kube-system:aws-load-balancer-controller`, not the application or the node instance profile. Review the policy and chart together when changing the controller version.
