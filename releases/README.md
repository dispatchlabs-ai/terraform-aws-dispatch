# Application artifact release contract

The module and Dispatch images have independent versions. This repository selects
images; it does not compile Dispatch during `plan` or `apply`. A customer needs
released images, not the application source checkout or a Nix installation.

**Current status:** the selector and metadata format below are implemented. No
public image release or fresh AWS installation is established by this repository.
There is intentionally no fabricated deployable release manifest. Module-source
publication, image publication, public-registry registration and AWS deployment
are separate outcomes.

## Publisher manifest

The application publisher supplies a trusted `dispatch-release.json` with these
exact schema-version-1 fields:

```json
{
  "schema_version": 1,
  "application_version": "0.1.0-alpha.1",
  "application_revision": "REPLACE_WITH_40_CHARACTER_SOURCE_COMMIT",
  "worker_packaging_revision": "REPLACE_WITH_40_CHARACTER_PACKAGING_COMMIT",
  "module_versions": ["0.1.0"],
  "frontend": {
    "url": "https://RELEASE_HOST/dispatch-frontend.tar.gz",
    "sha256": "REPLACE_WITH_64_CHARACTER_ARCHIVE_SHA256"
  },
  "images": {
    "linux/arm64": {
      "controller": "REGISTRY/REPOSITORY@sha256:REPLACE_WITH_REGISTRY_DIGEST",
      "worker": "REGISTRY/REPOSITORY@sha256:REPLACE_WITH_REGISTRY_DIGEST"
    },
    "linux/amd64": {
      "controller": "REGISTRY/REPOSITORY@sha256:REPLACE_WITH_REGISTRY_DIGEST",
      "worker": "REGISTRY/REPOSITORY@sha256:REPLACE_WITH_REGISTRY_DIGEST"
    }
  }
}
```

This is a **nondeployable template**; its placeholders deliberately fail validation.
Versions have no `v` prefix. `module_versions` lists exact module releases qualified
with this application, not ranges or a claim about all future versions. Source
revisions are full lowercase Git commit hashes. Both image roles contain the stated
application revision; worker packaging may come from a separate stated commit.

Each listed platform must have both controller and Ubuntu-worker references, pinned
to registry manifest digests rather than local Docker image IDs or archive hashes.
Publish platform-specific child manifests here. A separately published multi-platform
index may reference them, but its existence does not establish both architectures
were built or qualified. Omit an unqualified platform instead of supplying a guessed
digest. Do not use mutable `latest` or version tags as deployment identities.

Before issuing a real manifest, the publisher must inspect each pulled image's
platform and embedded source, verify the declared module/application combination,
and make the images accessible to its intended consumers. Public anonymous pulls
and ECS startup are separate verification steps. Once public, direct public-registry
pulls are the intended simple route; a customer may mirror identical artifacts to
its own ECR and record the resulting references. Do not present private installation
images as a generally available application release.

## Select images without deploying

Obtain the manifest from the application's trusted release channel and verify its
publisher/provenance using that release's published verification instructions.
A SHA256 pin alone is not publisher authentication. This offline helper does not
fetch a manifest, authenticate its author, pull images, inspect their platform or
execute Terraform. The declared compatibility remains a publisher assertion.

With Python 3.10+ and this module checkout (no application checkout needed):

```sh
python3 scripts/select-artifacts.py /path/to/dispatch-release.json \
  --module-version 0.1.0 --platform linux/arm64 > /tmp/dispatch-images.json
```

On success, the output is a JSON object with `image`, `worker_image`,
`cpu_architecture` and `frontend_release_prefix`. Supply those values to the module in the customer's own root;
the root must expose matching variables before this file can be used as `-var-file`.
A root choosing the Ubuntu environment must separately enable
`worker_package_installation = true`. The selector does not change networking,
activation, module source/version, secrets or Terraform state. Check its exit code
before copying or using the output file; shell redirection creates a file even when
validation fails. Preserve the selected module pin and manifest with the customer's
nonsecret release selections.

No compatibility ranges, unknown platforms, duplicate JSON fields or tag-only image
references are accepted. The helper validates metadata only and never automatically
retries deployments or replaces running workers. Customers intentionally selecting
an unreleased commit can supply image inputs directly; that does not constitute a
qualified versioned application release.

## Maintainer checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_select_artifacts.py' -v
```

All fixtures are synthetic and offline. These checks cover schema/selection failures,
ARM64/AMD64 output mapping and invoking the selector outside the checkout. They do
not qualify registry access, image contents, Terraform planning or AWS execution.
Public module registration requires an explicitly authorized public repository and
semantic-version tags; creating this private source repository does not publish it
to either public registry.


## SPA bundle and publication

Application publishers build `nix build .#frontend` from the selected release
commit. It reuses the locked application build and emits `dispatch-frontend.tar.gz`
and `SHA256SUMS`, with sorted paths, normalized ownership/mtime and timestamp-free
gzip. Publish the archive alongside the images; record its HTTPS URL and SHA256 in
`frontend`. These fields are required in the initial unreleased manifest schema;
there is no legacy manifest compatibility path or fabricated public release.
The manifest's application revision applies to the bundle as well as the controller.

Consumers obtain the manifest and archive from the authenticated release channel,
not from a source checkout. `publish-frontend.py` independently hashes the complete
archive, validates safe regular-file paths and rejects symlinks, duplicate paths
and oversized archives before any AWS operation. The checksum does not authenticate
the publisher: verify release provenance first. The helper does not download URLs.

```sh
# Export the foundation caller's outputs (without secret values).
tofu output -json > /tmp/dispatch-outputs.json
python3 scripts/publish-frontend.py /path/to/dispatch-release.json   /path/to/dispatch-frontend.tar.gz --module-version 0.1.0 --platform linux/arm64   --outputs /tmp/dispatch-outputs.json --account 123456789012 --region us-east-1
# Inspect preview, then repeat with:
# --execute --receipt /private/new-frontend-publication.json
```

The release prefix is derived from the archive hash: `releases/sha256-<digest>`.
`assets/*` is published to a shared stable location, **not beneath the release
prefix**, and retained append-only for old open tabs. All other files go under the
immutable release prefix; `index.html` is uploaded last. Configure CloudFront's
`/assets/*` behavior against the shared origin and navigation against the release
origin. The helper validates STS account and bucket owner/region, sends checksum-
verified conditional S3 puts (`If-None-Match: *`), verifies returned object checksums,
and never deletes or overwrites existing content. It sets correct content types,
immutable asset caching and no-cache HTML/nonhashed files. Existing objects must
match bytes, length and cache/content-type headers. Do not use `s3 sync --delete`.

A mode-0600 receipt is written before uploads and updated after each verified
object. Failure stops immediately; no mutation retries or automatic Terraform/CDN
changes occur. On interruption, inspect the receipt; an explicitly repeated
publication with a **new** receipt verifies already matching objects and publishes
only missing objects. A mismatch must be investigated, not overwritten. Successful
upload is not CloudFront verification or application activation.

Select the emitted `frontend_release_prefix` only **after** upload verification,
then explicitly apply the reviewed caller change. Invalidate cached navigation
responses when switching releases (for example, a deliberate CloudFront `/*`
invalidation; do not delete shared assets), and verify browser/API behavior. Keep
previous prefixes plus shared assets for rollback and old clients. Deleting old
assets requires a separate reviewed retirement policy. Public publication and
actual S3/CloudFront delivery remain unqualified by these offline helper checks.
