#!/usr/bin/env python3
"""Select digest-pinned images from a trusted Dispatch release manifest, offline."""

import argparse
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit

PLATFORMS = {"linux/arm64": "ARM64", "linux/amd64": "X86_64"}
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")
REVISION = re.compile(r"[0-9a-f]{40}")
# Require an explicit registry and repository, not a URL, credential or mutable tag.
IMAGE = re.compile(r"[a-z0-9]+(?:[.-][a-z0-9]+)*(?::[0-9]+)?/[a-z0-9]+(?:[._/-][a-z0-9]+)*@sha256:[0-9a-f]{64}")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def matches(pattern, value):
    return isinstance(value, str) and pattern.fullmatch(value) is not None


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON field")
        result[key] = value
    return result


def select(manifest, module_version, platform):
    require(isinstance(manifest, dict), "manifest must be an object")
    fields = {
        "schema_version", "application_version", "application_revision",
        "worker_packaging_revision", "module_versions", "images", "frontend",
    }
    require(set(manifest) == fields, "manifest fields do not match schema version 1")
    require(type(manifest["schema_version"]) is int and manifest["schema_version"] == 1,
            "unsupported schema version")
    require(matches(VERSION, manifest["application_version"]), "invalid application version")
    for field in ("application_revision", "worker_packaging_revision"):
        require(matches(REVISION, manifest[field]), "invalid source revision")
    frontend = manifest["frontend"]
    require(isinstance(frontend, dict) and set(frontend) == {"url", "sha256"}, "invalid frontend artifact")
    require(matches(re.compile(r"[0-9a-f]{64}"), frontend["sha256"]), "invalid frontend checksum")
    require(isinstance(frontend["url"], str), "invalid frontend URL")
    url = urlsplit(frontend["url"])
    require(url.scheme == "https" and url.hostname and not url.username and not url.password
            and not url.query and not url.fragment and url.path.endswith(".tar.gz"), "invalid frontend URL")
    versions = manifest["module_versions"]
    require(isinstance(versions, list) and versions and all(matches(VERSION, v) for v in versions),
            "module_versions must list exact versions, without a v prefix or ranges")
    require(len(set(versions)) == len(versions), "duplicate module version")
    require(module_version in versions, "selected module version is not declared compatible")
    images = manifest["images"]
    require(isinstance(images, dict) and images and set(images) <= set(PLATFORMS),
            "images must contain supported Linux platforms")
    for pair in images.values():
        require(isinstance(pair, dict) and set(pair) == {"controller", "worker"},
                "each platform requires controller and worker images")
        require(all(matches(IMAGE, ref) for ref in pair.values()),
                "images must be explicit registry/repository@sha256 digests")
    require(platform in PLATFORMS and platform in images, "selected platform is unavailable")
    return {
        "image": images[platform]["controller"],
        "worker_image": images[platform]["worker"],
        "cpu_architecture": PLATFORMS[platform],
        "frontend_release_prefix": "releases/sha256-" + frontend["sha256"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--module-version", required=True, help="exact module release, e.g. 0.1.0")
    parser.add_argument("--platform", choices=PLATFORMS, required=True)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
        result = select(manifest, args.module_version, args.platform)
    except (OSError, UnicodeError, ValueError):
        # Do not echo file contents, paths or malformed credential-bearing values.
        print("Invalid/unreadable release manifest or incompatible module/platform selection.", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
