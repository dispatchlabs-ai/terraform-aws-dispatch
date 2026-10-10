#!/usr/bin/env python3
"""Preview/submit one registered operator task; observe its receipt without replay."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

OPERATIONS = {
    "database-create": ("database_initializer", "database-init"),
    "database-verify": ("database_initializer", "database-init"),
    "activate": ("activation", "activation"),
}


class OperationError(Exception):
    """Only fixed, nonsecret messages belong in this exception."""


def require(condition, message):
    if not condition:
        raise OperationError(message)


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise OperationError("Cannot read valid JSON input.") from None


def output(outputs, name):
    require(isinstance(outputs, dict) and name in outputs, "Required module output is absent.")
    value = outputs[name]
    # Accept raw module output objects or the normal `terraform output -json` envelope.
    if isinstance(value, dict) and {"value", "type", "sensitive"} <= set(value):
        require(not value["sensitive"], "Operator metadata must not be a sensitive output.")
        return value["value"]
    return value


def arn(value, kind, account, region):
    match = re.fullmatch(r"arn:(aws(?:-cn|-us-gov)?):ecs:([a-z0-9-]+):([0-9]{12}):(.+)", value or "") if isinstance(value, str) else None
    require(match is not None and match[2] == region and match[3] == account,
            "ECS ARN does not match the selected account/region.")
    patterns = {
        "cluster": r"cluster/[A-Za-z0-9_-]+",
        "definition": r"task-definition/[A-Za-z0-9_-]+:[1-9][0-9]*",
        "task": r"task/(?:[A-Za-z0-9_-]+/)?[a-f0-9-]+",
    }
    require(re.fullmatch(patterns[kind], match[4]) is not None, "Invalid ECS resource identity.")
    return value


def request_for(outputs, operation, account, region, stopped):
    require(re.fullmatch(r"[0-9]{12}", account) is not None, "Invalid expected account.")
    require(re.fullmatch(r"[a-z0-9-]+", region) is not None, "Invalid region.")
    require(operation in OPERATIONS, "Unknown operation.")
    if operation.startswith("database-"):
        require(stopped, "Database operations require independent stopped-owner confirmation.")
    key, container = OPERATIONS[operation]
    operator = output(outputs, key)
    require(isinstance(operator, dict), "Selected operator task is not enabled.")
    cluster = arn(operator.get("cluster_arn") or output(outputs, "service_cluster_arn"), "cluster", account, region)
    worker_cluster = arn(output(outputs, "worker_cluster_arn"), "cluster", account, region)
    require(cluster != worker_cluster, "Operator tasks must not use the worker-only cluster.")
    definition = arn(operator.get("task_definition_arn"), "definition", account, region)
    subnets = output(outputs, "private_subnet_ids")
    group = operator.get("security_group_id")
    require(isinstance(subnets, list) and 0 < len(subnets) <= 16 and
            all(isinstance(s, str) and re.fullmatch(r"subnet-[a-f0-9]+", s) for s in subnets),
            "Invalid private subnet outputs.")
    require(isinstance(group, str) and re.fullmatch(r"sg-[a-f0-9]+", group), "Invalid operator security group.")
    request = {
        "cluster": cluster, "taskDefinition": definition, "count": 1,
        "launchType": "FARGATE", "enableExecuteCommand": False,
        "networkConfiguration": {"awsvpcConfiguration": {
            "subnets": subnets, "securityGroups": [group], "assignPublicIp": "DISABLED",
        }},
    }
    if operation.startswith("database-"):
        command = ["dispatch-bootstrap", "database-init", "--config", "/tmp/dispatch-bootstrap/database-init.json"]
        command += ["--create", "--confirm-services-stopped"] if operation == "database-create" else ["--verify"]
        request["overrides"] = {"containerOverrides": [{"name": container, "command": command}]}
    # Activation uses the registered one-shot command. No secrets/commands are supplied here.
    return request, container


class Aws:
    def __init__(self, account, region, profile=None):
        self.account = account
        self.command = ["aws", "--region", region, "--output", "json", "--no-cli-pager", "--no-cli-auto-prompt"]
        if profile:
            self.command += ["--profile", profile]

    def call(self, service, action, payload):
        env = {**os.environ, "AWS_MAX_ATTEMPTS": "1", "AWS_RETRY_MODE": "standard",
               "AWS_PAGER": "", "AWS_CLI_AUTO_PROMPT": "off"}
        try:
            result = subprocess.run(self.command + [service, action, "--cli-input-json", json.dumps(payload)],
                                    capture_output=True, text=True, timeout=90, env=env)
            require(result.returncode == 0, "AWS call failed or has uncertain outcome; do not replay a mutation.")
            return json.loads(result.stdout)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            raise OperationError("AWS call failed or has uncertain outcome; do not replay a mutation.") from None

    def verify_identity(self):
        require(self.call("sts", "get-caller-identity", {}).get("Account") == self.account,
                "AWS caller is not the expected account.")


def save_receipt(handle, receipt):
    handle.seek(0)
    json.dump(receipt, handle, indent=2)
    handle.write("\n")
    handle.truncate()
    handle.flush()
    os.fsync(handle.fileno())


def submit(aws, request, container, operation, account, region, path):
    aws.verify_identity()
    token = str(uuid.uuid4())
    receipt = {"schema_version": 1, "operation": operation, "account": account, "region": region,
               "cluster": request["cluster"], "task_definition": request["taskDefinition"],
               "container": container, "client_token": token, "status": "prepared", "task_arn": None}
    # Reserve the receipt before the single mutation. Never overwrite an earlier operation.
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except OSError:
        raise OperationError("Cannot reserve a new receipt; existing receipts must not be replayed.") from None
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        save_receipt(handle, receipt)
        try:
            result = aws.call("ecs", "run-task", {**request, "clientToken": token, "startedBy": token})
            tasks = result.get("tasks", [])
            if len(tasks) == 1:
                receipt["task_arn"] = arn(tasks[0].get("taskArn"), "task", account, region)
            require(not result.get("failures") and len(tasks) == 1, "RunTask did not return one unambiguous task.")
            require(tasks[0].get("clusterArn") == request["cluster"] and
                    tasks[0].get("taskDefinitionArn") == request["taskDefinition"],
                    "Returned task does not match the requested operator definition/cluster.")
            receipt["status"] = "submitted"
        except (OperationError, KeyError, TypeError, AttributeError):
            receipt["status"] = "uncertain"
            save_receipt(handle, receipt)
            raise OperationError("Submission uncertain; reconcile receipt/client token in AWS. Do not rerun.") from None
        save_receipt(handle, receipt)
    return receipt


def observe(aws, receipt, account, region):
    require(isinstance(receipt, dict) and receipt.get("schema_version") == 1 and
            receipt.get("account") == account and receipt.get("region") == region,
            "Receipt does not match expected account/region/schema.")
    require(receipt.get("operation") in OPERATIONS and
            receipt.get("container") == OPERATIONS[receipt["operation"]][1], "Invalid operation receipt.")
    task = arn(receipt.get("task_arn"), "task", account, region)
    cluster = arn(receipt.get("cluster"), "cluster", account, region)
    definition = arn(receipt.get("task_definition"), "definition", account, region)
    result = aws.call("ecs", "describe-tasks", {"cluster": cluster, "tasks": [task]})
    tasks = result.get("tasks", [])
    require(not result.get("failures") and len(tasks) == 1, "Exact task is unavailable; termination is unverified.")
    actual = tasks[0]
    require(actual.get("taskArn") == task and actual.get("clusterArn") == cluster and
            actual.get("taskDefinitionArn") == definition, "Observed task identity differs from receipt.")
    containers = actual.get("containers", [])
    stopped = actual.get("lastStatus") == "STOPPED"
    succeeded = stopped and any(c.get("name") == receipt["container"] for c in containers) and all(
        c.get("lastStatus") == "STOPPED" and type(c.get("exitCode")) is int and c["exitCode"] == 0 for c in containers)
    summary = {"task_arn": task, "status": actual.get("lastStatus"), "succeeded": succeeded,
               "containers": [{"name": c.get("name"), "status": c.get("lastStatus"), "exit_code": c.get("exitCode")}
                              for c in containers]}
    # No raw logs, failure reasons, environment or response payloads are printed.
    return summary, 0 if succeeded else (1 if stopped else 2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="preview by default; --execute submits exactly once")
    run.add_argument("--outputs", type=Path, required=True)
    run.add_argument("--operation", choices=OPERATIONS, required=True)
    run.add_argument("--confirm-services-stopped", action="store_true")
    run.add_argument("--execute", action="store_true")
    run.add_argument("--receipt", type=Path)
    watch = commands.add_parser("observe", help="read-only exact-task observation; never submits or stops tasks")
    watch.add_argument("--receipt", type=Path, required=True)
    watch.add_argument("--wait-seconds", type=int, default=0)
    for command in (run, watch):
        command.add_argument("--account", required=True)
        command.add_argument("--region", required=True)
        command.add_argument("--profile")
    args = parser.parse_args()
    try:
        aws = Aws(args.account, args.region, args.profile)
        if args.command == "run":
            request, container = request_for(read_json(args.outputs), args.operation, args.account,
                                             args.region, args.confirm_services_stopped)
            if not args.execute:
                print(json.dumps({"preview": True, "request": request}, indent=2))
                return 0
            require(args.receipt is not None, "Execution requires a new receipt path.")
            receipt = submit(aws, request, container, args.operation, args.account, args.region, args.receipt)
            print(json.dumps(receipt, indent=2))
            return 0  # Submitted, not application completion. Use observe for that result.
        require(0 <= args.wait_seconds <= 3600, "Observation wait must be between 0 and 3600 seconds.")
        receipt = read_json(args.receipt)
        aws.verify_identity()
        deadline = time.monotonic() + args.wait_seconds
        while True:
            summary, code = observe(aws, receipt, args.account, args.region)
            if code != 2 or time.monotonic() >= deadline:
                print(json.dumps(summary, indent=2))
                return code
            time.sleep(min(5, max(0, deadline - time.monotonic())))
    except OperationError as error:
        print(str(error), file=sys.stderr)
        return 1
    except (OSError, KeyError, TypeError, AttributeError, ValueError):
        print("Invalid input or receipt I/O failure; reconcile any submitted operation before proceeding.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
