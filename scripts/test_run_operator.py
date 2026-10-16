"""Offline operator transport tests: never call AWS or execute application code."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("run-operator.py")
spec = importlib.util.spec_from_file_location("run_operator", SCRIPT)
operator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(operator)
ACCOUNT = "123456789012"
REGION = "us-east-1"
PREFIX = f"arn:aws:ecs:{REGION}:{ACCOUNT}:"
CLUSTER = PREFIX + "cluster/example-services"
WORKERS = PREFIX + "cluster/example-workers"
TASK = PREFIX + "task/example-services/" + "a" * 32


def outputs():
    return {
        "service_cluster_arn": CLUSTER,
        "worker_cluster_arn": WORKERS,
        "task_subnet_ids": ["subnet-123abc", "subnet-456def"],
        "task_assign_public_ip": False,
        "database_initializer": {"task_definition_arn": PREFIX + "task-definition/example-db-init:1",
                                 "security_group_id": "sg-123abc"},
        "activation": {"task_definition_arn": PREFIX + "task-definition/example-activation:2",
                       "security_group_id": "sg-456def"},
    }


def task_for(request):
    return {"taskArn": TASK, "clusterArn": request["cluster"],
            "taskDefinitionArn": request["taskDefinition"]}


class FakeAws:
    def __init__(self, result=None, fail=False, receipt=None):
        self.result = result
        self.fail = fail
        self.receipt = receipt
        self.calls = []
        self.checked = False

    def verify_identity(self):
        self.checked = True

    def call(self, service, action, payload):
        self.calls.append((service, action, payload))
        if action == "run-task":
            assert self.checked
            assert json.loads(self.receipt.read_text())["status"] == "prepared"
            assert os.stat(self.receipt).st_mode & 0o777 == 0o600
        if self.fail:
            raise operator.OperationError("Synthetic uncertain outcome.")
        return self.result


class OperatorTests(unittest.TestCase):
    def test_create_command_and_network_is_private(self):
        request, container = operator.request_for(outputs(), "database-create", ACCOUNT, REGION)
        self.assertEqual(container, "database-init")
        self.assertEqual(request["count"], 1)
        self.assertFalse(request["enableExecuteCommand"])
        self.assertEqual(request["networkConfiguration"]["awsvpcConfiguration"]["assignPublicIp"], "DISABLED")
        self.assertEqual(request["overrides"]["containerOverrides"][0]["command"][-2:],
                         ["--create", "--confirm-services-stopped"])

    def test_verify_and_activation_do_not_reuse_create_command(self):
        request, _ = operator.request_for(outputs(), "database-verify", ACCOUNT, REGION)
        self.assertEqual(request["overrides"]["containerOverrides"][0]["command"][-1], "--verify")
        request, _ = operator.request_for(outputs(), "activate", ACCOUNT, REGION)
        self.assertNotIn("overrides", request)

    def test_output_envelope_supported(self):
        envelope = {key: {"value": value, "type": "synthetic", "sensitive": False}
                    for key, value in outputs().items()}
        self.assertEqual(operator.request_for(envelope, "activate", ACCOUNT, REGION),
                         operator.request_for(outputs(), "activate", ACCOUNT, REGION))
        envelope["activation"]["sensitive"] = True
        with self.assertRaises(operator.OperationError):
            operator.request_for(envelope, "activate", ACCOUNT, REGION)

    def test_wrong_account_region_worker_cluster_and_unpinned_definition_refused(self):
        bad_outputs = []
        for key, value in [("cluster_arn", WORKERS),
                           ("task_definition_arn", PREFIX + "task-definition/example:latest"),
                           ("task_definition_arn", PREFIX + "task-definition/example"),
                           ("security_group_id", "sg-invalid")]:
            value_outputs = outputs()
            value_outputs["activation"][key] = value
            bad_outputs.append(value_outputs)
        bad_outputs.append({**outputs(), "activation": None})
        for value in bad_outputs:
            with self.subTest(outputs=value), self.assertRaises(operator.OperationError):
                operator.request_for(value, "activate", ACCOUNT, REGION)
        for account, region in [("999999999999", REGION), (ACCOUNT, "us-west-2")]:
            with self.assertRaises(operator.OperationError):
                operator.request_for(outputs(), "activate", account, region)

    def test_submit_records_intent_before_single_call_and_refuses_existing_receipt(self):
        request, container = operator.request_for(outputs(), "activate", ACCOUNT, REGION)
        with tempfile.TemporaryDirectory() as directory:
            receipt_path = Path(directory, "receipt.json")
            aws = FakeAws({"tasks": [task_for(request)]}, receipt=receipt_path)
            receipt = operator.submit(aws, request, container, "activate", ACCOUNT, REGION, receipt_path)
            self.assertEqual(receipt["status"], "submitted")
            self.assertEqual(receipt["task_arn"], TASK)
            self.assertEqual(len(aws.calls), 1)
            self.assertEqual(aws.calls[0][2]["clientToken"], receipt["client_token"])
            self.assertEqual(aws.calls[0][2]["startedBy"], receipt["client_token"])
            with self.assertRaises(operator.OperationError):
                operator.submit(aws, request, container, "activate", ACCOUNT, REGION, receipt_path)
            self.assertEqual(len(aws.calls), 1)

    def test_uncertain_submission_keeps_receipt_without_retry(self):
        request, container = operator.request_for(outputs(), "activate", ACCOUNT, REGION)
        with tempfile.TemporaryDirectory() as directory:
            receipt_path = Path(directory, "receipt.json")
            aws = FakeAws(fail=True, receipt=receipt_path)
            with self.assertRaises(operator.OperationError):
                operator.submit(aws, request, container, "activate", ACCOUNT, REGION, receipt_path)
            receipt = json.loads(receipt_path.read_text())
            self.assertEqual(receipt["status"], "uncertain")
            self.assertIsNone(receipt["task_arn"])
            self.assertEqual(len(aws.calls), 1)

    def test_partial_failure_retains_known_task_identity(self):
        request, container = operator.request_for(outputs(), "activate", ACCOUNT, REGION)
        with tempfile.TemporaryDirectory() as directory:
            receipt_path = Path(directory, "receipt.json")
            aws = FakeAws({"tasks": [task_for(request)], "failures": [{"reason": "not-logged"}]}, receipt=receipt_path)
            with self.assertRaises(operator.OperationError):
                operator.submit(aws, request, container, "activate", ACCOUNT, REGION, receipt_path)
            receipt = json.loads(receipt_path.read_text())
            self.assertEqual(receipt["task_arn"], TASK)
            self.assertNotIn("not-logged", receipt_path.read_text())

    def test_exact_stopped_task_and_all_exit_codes_required(self):
        request, _ = operator.request_for(outputs(), "activate", ACCOUNT, REGION)
        receipt = {"schema_version": 1, "account": ACCOUNT, "region": REGION, "operation": "activate",
                   "container": "activation", "task_arn": TASK, "cluster": CLUSTER,
                   "task_definition": request["taskDefinition"]}
        task = {**task_for(request), "lastStatus": "STOPPED", "containers": [
            {"name": "activation", "lastStatus": "STOPPED", "exitCode": 0}]}
        _, code = operator.observe(FakeAws({"tasks": [task]}), receipt, ACCOUNT, REGION)
        self.assertEqual(code, 0)
        for status, exit_code, expected in [("RUNNING", None, 2), ("STOPPED", 1, 1),
                                            ("STOPPED", None, 1), ("STOPPED", False, 1)]:
            changed = copy.deepcopy(task)
            changed["lastStatus"] = status
            changed["containers"][0]["exitCode"] = exit_code
            _, code = operator.observe(FakeAws({"tasks": [changed]}), receipt, ACCOUNT, REGION)
            self.assertEqual(code, expected)
        task["containers"].append({"name": "volume-init", "lastStatus": "STOPPED", "exitCode": 1})
        self.assertEqual(operator.observe(FakeAws({"tasks": [task]}), receipt, ACCOUNT, REGION)[1], 1)
        for response in [{"tasks": []}, {"tasks": [{**task, "taskArn": TASK + "b"}]}]:
            with self.assertRaises(operator.OperationError):
                operator.observe(FakeAws(response), receipt, ACCOUNT, REGION)

    def test_cli_preview_never_calls_aws(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory, "outputs.json")
            file.write_text(json.dumps(outputs()))
            for operation in operator.OPERATIONS:
                command = [sys.executable, str(SCRIPT), "run", "--outputs", str(file),
                           "--operation", operation, "--account", ACCOUNT, "--region", REGION]
                result = subprocess.run(command, capture_output=True, text=True, env={"PATH": directory})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(json.loads(result.stdout)["preview"])
                if operation.startswith("database-"):
                    receipt = Path(directory, "receipt.json")
                    with patch.object(sys, "argv", command[1:] + ["--execute", "--receipt", str(receipt)]), \
                         patch.object(operator, "submit") as submit:
                        self.assertEqual(operator.main(), 1)
                        submit.assert_not_called()
                    self.assertFalse(receipt.exists())

    def test_aws_subprocess_disables_sdk_retries_and_suppresses_raw_failures(self):
        with patch.object(operator.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 1, "private-output", "private-error")
            with self.assertRaises(operator.OperationError) as error:
                operator.Aws(ACCOUNT, REGION).call("ecs", "run-task", {})
            self.assertEqual(run.call_args.kwargs["env"]["AWS_MAX_ATTEMPTS"], "1")
            self.assertNotIn("private", str(error.exception))
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
