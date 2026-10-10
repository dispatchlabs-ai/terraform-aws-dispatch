"""Offline release-selection contract tests; all hashes and image refs are synthetic."""

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("select-artifacts.py")
spec = importlib.util.spec_from_file_location("select_artifacts", SCRIPT)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def fixture():
    return {
        "schema_version": 1,
        "application_version": "0.1.0-alpha.1",
        "application_revision": "a" * 40,
        "worker_packaging_revision": "b" * 40,
        "module_versions": ["0.1.0", "0.1.1"],
        "images": {
            platform: {
                "controller": "registry.example/dispatch/controller@sha256:" + digest * 64,
                "worker": "registry.example/dispatch/worker@sha256:" + digest * 64,
            }
            for platform, digest in [("linux/arm64", "c"), ("linux/amd64", "d")]
        },
    }


class SelectionTests(unittest.TestCase):
    def test_both_platforms_select_exact_digests(self):
        manifest = fixture()
        original = copy.deepcopy(manifest)
        for platform, architecture in selector.PLATFORMS.items():
            with self.subTest(platform=platform):
                result = selector.select(manifest, "0.1.0", platform)
                self.assertEqual(result, {
                    "image": manifest["images"][platform]["controller"],
                    "worker_image": manifest["images"][platform]["worker"],
                    "cpu_architecture": architecture,
                })
        self.assertEqual(manifest, original)

    def test_incompatible_or_missing_selection(self):
        for version, platform in [("0.2.0", "linux/arm64"), ("v0.1.0", "linux/arm64"),
                                  ("0.1.0", "darwin/arm64")]:
            with self.subTest(version=version, platform=platform), self.assertRaises(ValueError):
                selector.select(fixture(), version, platform)
        manifest = fixture()
        del manifest["images"]["linux/amd64"]
        with self.assertRaises(ValueError):
            selector.select(manifest, "0.1.0", "linux/amd64")

    def test_bad_schema_and_types(self):
        mutations = [
            ("schema_version", True), ("schema_version", 2),
            ("application_version", "latest"), ("application_revision", "abc123"),
            ("worker_packaging_revision", None), ("module_versions", []),
            ("module_versions", ["~> 0.1"]), ("module_versions", ["0.1.0", "0.1.0"]),
            ("images", []), ("images", {}),
        ]
        for key, value in mutations:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                manifest = fixture()
                manifest[key] = value
                selector.select(manifest, "0.1.0", "linux/arm64")
        for manifest in [None, [], {**fixture(), "typo": "value"}]:
            with self.assertRaises(ValueError):
                selector.select(manifest, "0.1.0", "linux/arm64")

    def test_rejects_unpinned_or_credential_bearing_images(self):
        for image in ["dispatch:latest", "registry.example/dispatch:v1.0.0",
                      "https://registry.example/dispatch@sha256:" + "c" * 64,
                      "user:secret@registry.example/dispatch@sha256:" + "c" * 64,
                      "registry.example/dispatch@sha256:abc", None]:
            with self.subTest(image=image), self.assertRaises(ValueError):
                manifest = fixture()
                manifest["images"]["linux/arm64"]["controller"] = image
                selector.select(manifest, "0.1.0", "linux/arm64")

    def test_all_platforms_are_validated(self):
        manifest = fixture()
        del manifest["images"]["linux/amd64"]["worker"]
        with self.assertRaises(ValueError):
            selector.select(manifest, "0.1.0", "linux/arm64")

    def test_duplicate_json_fields_rejected(self):
        with self.assertRaises(ValueError):
            json.loads('{"schema_version": 1, "schema_version": 1}',
                       object_pairs_hook=selector.unique_object)

    def test_cli_is_usable_outside_checkout_and_failure_has_no_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "release.json")
            path.write_text(json.dumps(fixture()))
            command = [sys.executable, str(SCRIPT.resolve()), str(path),
                       "--module-version", "0.1.0", "--platform", "linux/arm64"]
            result = subprocess.run(command, cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["cpu_architecture"], "ARM64")
            self.assertEqual(result.stderr, "")
            path.write_text('{"private-token": "must-not-appear"}')
            result = subprocess.run(command, cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, "")
            self.assertNotIn("must-not-appear", result.stderr)
            self.assertNotIn(directory, result.stderr)


if __name__ == "__main__":
    unittest.main()
