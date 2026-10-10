#!/usr/bin/env python3
"""Verify a released SPA bundle; preview or explicitly publish immutable S3 objects."""

import argparse
import base64
import hashlib
import io
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import runpy
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
selector = runpy.run_path(str(HERE / "select-artifacts.py"))
operator = runpy.run_path(str(HERE / "run-operator.py"))
require = operator["require"]
Error = operator["OperationError"]
MAX_BYTES = 256 * 1024 * 1024


def bundle_files(path, digest):
    require(path.stat().st_size <= 64 * 1024 * 1024, "Compressed bundle exceeds limit.")
    data = path.read_bytes()
    require(hashlib.sha256(data).hexdigest() == digest, "Bundle checksum does not match trusted manifest.")
    files, total = {}, 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for index, member in enumerate(archive):
            require(index < 10000, "Too many archive entries.")
            name = member.name.removeprefix("./")
            if name in ("", ".") and member.isdir():
                continue
            parts = name.rstrip("/").split("/")
            require(all(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", p) for p in parts),
                    "Unsafe archive path.")
            require(member.isdir() or member.isfile(), "Links and special archive entries are forbidden.")
            if member.isdir():
                continue
            total += member.size
            require(member.size <= 32 * 1024 * 1024 and total <= MAX_BYTES, "Expanded bundle exceeds limit.")
            require(name not in files, "Duplicate archive path.")
            files[name] = archive.extractfile(member).read()
    require("index.html" in files and files["index.html"], "Bundle must contain root index.html.")
    return files


def objects(files, prefix):
    # Hashed Vite assets retain stable URLs across release-prefix switches.
    # Do not delete them when retiring an index release: old tabs may still use them.
    return {("" if name.startswith("assets/") else prefix + "/") + name: data
            for name, data in files.items()}


def checksum(data):
    return base64.b64encode(hashlib.sha256(data).digest()).decode("ascii")


def publish(aws, bucket, prefix, files, receipt_path):
    aws.verify_identity()
    owner = {"Bucket": bucket, "ExpectedBucketOwner": aws.account}
    location = aws.call("s3api", "get-bucket-location", owner).get("LocationConstraint")
    region = {None: "us-east-1", "EU": "eu-west-1"}.get(location, location)
    require(region == aws.region, "Frontend bucket is not in the selected region.")
    receipt = {"schema_version": 1, "account": aws.account, "region": aws.region,
               "bucket": bucket, "frontend_release_prefix": prefix,
               "status": "prepared", "verified_objects": []}
    fd = os.open(receipt_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w") as handle, tempfile.TemporaryDirectory(prefix="dispatch-frontend-") as temp:
        save = lambda: operator["save_receipt"](handle, receipt)
        save()
        try:
            # Each exact-key list distinguishes absent objects from permission errors.
            # No bucket scans, extraction to caller paths, deletes or overwrites.
            for key, data in sorted(objects(files, prefix).items(), key=lambda item: item[0] == prefix + "/index.html"):
                query = {**owner, "Prefix": key, "MaxKeys": 1}
                listed = aws.call("s3api", "list-objects-v2", query, ["--no-paginate"])
                existing = any(o.get("Key") == key for o in listed.get("Contents", []))
                mime = {".js": "application/javascript", ".css": "text/css", ".html": "text/html"}.get(
                    PurePosixPath(key).suffix, mimetypes.guess_type(key)[0] or "application/octet-stream")
                cache = "public,max-age=31536000,immutable" if key.startswith("assets/") else "no-cache"
                if not existing:
                    body = Path(temp, "object")
                    body.write_bytes(data)
                    aws.call("s3api", "put-object", {
                        **owner, "Key": key, "IfNoneMatch": "*", "ChecksumAlgorithm": "SHA256",
                        "ChecksumSHA256": checksum(data), "ContentType": mime, "CacheControl": cache,
                    }, ["--body", str(body)])
                actual = aws.call("s3api", "head-object", {**owner, "Key": key, "ChecksumMode": "ENABLED"})
                require(actual.get("ChecksumSHA256") == checksum(data) and actual.get("ContentLength") == len(data)
                        and actual.get("ContentType") == mime and actual.get("CacheControl") == cache,
                        "Existing or uploaded object differs; immutable content must not be overwritten.")
                receipt["verified_objects"].append(key)
                save()
            receipt["status"] = "uploaded-and-verified"
            save()
        except Exception:
            receipt["status"] = "incomplete-or-uncertain"
            save()
            raise
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--module-version", required=True)
    parser.add_argument("--platform", choices=selector["PLATFORMS"], required=True)
    parser.add_argument("--outputs", type=Path, required=True)
    parser.add_argument("--account", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(), object_pairs_hook=selector["unique_object"])
        selected = selector["select"](manifest, args.module_version, args.platform)
        files = bundle_files(args.bundle, manifest["frontend"]["sha256"])
        prefix = selected["frontend_release_prefix"]
        bucket = operator["output"](operator["read_json"](args.outputs), "frontend_bucket")
        require(isinstance(bucket, str) and re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket),
                "Invalid frontend bucket output.")
        require(re.fullmatch(r"[0-9]{12}", args.account) and re.fullmatch(r"[a-z0-9-]+", args.region),
                "Invalid expected account/region.")
        if not args.execute:
            print(json.dumps({"preview": True, "bucket": bucket, "frontend_release_prefix": prefix,
                              "objects": len(files), "bytes": sum(map(len, files.values()))}, indent=2))
            return 0
        require(args.receipt is not None, "Execution requires a new receipt path.")
        aws = operator["Aws"](args.account, args.region, args.profile)
        aws.region = args.region
        result = publish(aws, bucket, prefix, files, args.receipt)
        print(json.dumps({k: v for k, v in result.items() if k != "verified_objects"}, indent=2))
        return 0
    except (Error, OSError, ValueError, TypeError, KeyError, tarfile.TarError):
        print("Frontend verification/publication failed. Inspect the receipt; do not select an incomplete release.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
