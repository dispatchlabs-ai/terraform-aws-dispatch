# Application release artifacts

Use compatible controller and Ubuntu-worker image digests plus the matching
frontend archive from the application's trusted release channel. Module and
application versions are independent; matching version numbers do not establish
compatibility. Record the selected revisions, platform and qualification scope.

Dispatch 0.6.0 publishes Linux/AMD64 images, a frontend archive and `SHA256SUMS`
on its [release page](https://github.com/dispatchlabs-ai/dispatch/releases/tag/v0.6.0).
Select the digest-pinned images directly through `image` and `worker_image`.
Public registry pulls are the normal path; mirroring the same artifacts to a
customer ECR repository is optional. Verify destination digests if mirroring.
Do not substitute archive hashes or local Docker image IDs for registry digests.

## SPA bundle and publication

Publish the frontend with `scripts/publish-frontend.py` and its published SHA-256,
following [installation step 4](../docs/installation.md#4-prepare-the-frontend-release).
The helper verifies the archive and publishes immutable objects. No separate
release manifest, application checkout or rebuild is required. Artifact identity
checks do not establish fresh-installation, upgrade or Fargate qualification.
