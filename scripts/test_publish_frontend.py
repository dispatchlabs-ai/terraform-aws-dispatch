"""Synthetic offline asset-publication checks; no AWS requests."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("publish-frontend.py")
spec = importlib.util.spec_from_file_location("publisher", SCRIPT)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def archive(path, entries):
    with tarfile.open(path, "w:gz") as tar:
        for name, body, kind in entries:
            info = tarfile.TarInfo(name)
            info.type = kind
            info.size = len(body) if kind == tarfile.REGTYPE else 0
            tar.addfile(info, io.BytesIO(body) if kind == tarfile.REGTYPE else None)
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FakeAws:
    account = "123456789012"
    region = "us-east-1"

    def __init__(self):
        self.data = {}
        self.puts = []
        self.verified = False

    def verify_identity(self):
        self.verified = True

    def call(self, service, action, payload, extra=()):
        assert self.verified
        assert payload["ExpectedBucketOwner"] == self.account
        key = payload.get("Key", "")
        if action == "get-bucket-location":
            return {"LocationConstraint": None}
        if action == "list-objects-v2":
            return {"Contents": [{"Key": k} for k in self.data if k.startswith(payload["Prefix"])]}
        if action == "put-object":
            assert payload["IfNoneMatch"] == "*" and key not in self.data
            data = Path(extra[1]).read_bytes()
            assert payload["ChecksumSHA256"] == p.checksum(data)
            self.data[key] = {"ChecksumSHA256": p.checksum(data), "ContentLength": len(data),
                              "ContentType": payload["ContentType"], "CacheControl": payload["CacheControl"]}
            self.puts.append(key)
            return {}
        if action == "head-object":
            return self.data[key]
        raise AssertionError(action)


class FrontendTests(unittest.TestCase):
    def test_verified_bundle_and_shared_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp, "bundle.tgz")
            digest = archive(path, [("./index.html", b"index", tarfile.REGTYPE),
                                    ("./assets/app-abc.js", b"javascript", tarfile.REGTYPE)])
            files = p.bundle_files(path, digest)
            self.assertEqual(set(p.objects(files, "releases/sha256-" + digest)),
                             {"releases/sha256-" + digest + "/index.html", "assets/app-abc.js"})
            with self.assertRaises(p.Error):
                p.bundle_files(path, "a" * 64)

    def test_unsafe_and_duplicate_entries_refused(self):
        for name, kind in [("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                           ("assets/.env", tarfile.REGTYPE), ("assets/link", tarfile.SYMTYPE),
                           ("index.html", tarfile.REGTYPE)]:
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as temp:
                path = Path(temp, "bundle.tgz")
                digest = archive(path, [("index.html", b"index", tarfile.REGTYPE), (name, b"x", kind)])
                with self.assertRaises(p.Error):
                    p.bundle_files(path, digest)

    def test_publish_and_repeat_verify_without_overwrite(self):
        aws = FakeAws()
        with tempfile.TemporaryDirectory() as temp:
            files = {"index.html": b"index", "assets/app-abcd.js": b"js"}
            receipt = Path(temp, "receipt.json")
            result = p.publish(aws, "test-bucket", "releases/example", files, receipt)
            self.assertEqual(result["status"], "uploaded-and-verified")
            self.assertEqual(aws.puts[-1], "releases/example/index.html")
            self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)
            p.publish(aws, "test-bucket", "releases/example", files, Path(temp, "repeat.json"))
            self.assertEqual(len(aws.puts), 2)
            with self.assertRaises(FileExistsError):
                p.publish(aws, "test-bucket", "releases/example", files, receipt)

    def test_existing_different_content_is_never_overwritten(self):
        aws = FakeAws()
        aws.data["assets/app-abcd.js"] = {"ChecksumSHA256": "different", "ContentLength": 2}
        with tempfile.TemporaryDirectory() as temp:
            receipt = Path(temp, "receipt.json")
            with self.assertRaises(p.Error):
                p.publish(aws, "test-bucket", "releases/example", {"assets/app-abcd.js": b"js"}, receipt)
            self.assertEqual(aws.puts, [])
            self.assertEqual(json.loads(receipt.read_text())["status"], "incomplete-or-uncertain")

    def test_wrong_region_refused_before_receipt_or_put(self):
        aws = FakeAws()
        aws.region = "us-west-2"
        with tempfile.TemporaryDirectory() as temp:
            receipt = Path(temp, "receipt.json")
            with self.assertRaises(p.Error):
                p.publish(aws, "test-bucket", "releases/example", {"index.html": b"x"}, receipt)
            self.assertFalse(receipt.exists())
            self.assertFalse(aws.puts)

    def test_preview_needs_no_aws_cli_or_credentials(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bundle = root / "bundle.tgz"
            digest = archive(bundle, [("index.html", b"index", tarfile.REGTYPE)])
            (root / "outputs.json").write_text(json.dumps({"frontend_bucket": "example-bucket"}))
            result = subprocess.run([sys.executable, str(SCRIPT.resolve()), str(bundle), "--sha256", digest, "--outputs", str(root / "outputs.json"),
                "--account", "123456789012", "--region", "us-east-1"],
                cwd=temp, env={"PATH": "/nonexistent"}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["preview"])
            self.assertEqual(json.loads(result.stdout)["frontend_release_prefix"], "releases/sha256-" + digest)
            self.assertEqual(list(root.glob("receipt*")), [])


if __name__ == "__main__":
    unittest.main()
