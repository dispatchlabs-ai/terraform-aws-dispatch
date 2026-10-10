"""Offline lifecycle transport checks. No AWS or application execution."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installation', Path(__file__).with_name('run-installation.py'))
i = importlib.util.module_from_spec(spec)
spec.loader.exec_module(i)
A, R = '123456789012', 'us-east-1'
P = f'arn:aws:ecs:{R}:{A}:'
C, W = P + 'cluster/services', P + 'cluster/workers'
S = {r: {'arn': P + 'service/services/' + r, 'task_definition_arn': P + 'task-definition/' + r + ':1'} for r in ['backend', 'launcher']}
T = {r: P + 'task/services/' + c * 32 for r, c in [('backend', 'a'), ('launcher', 'b')]}


def outputs():
    return {'service_cluster_arn': C, 'worker_cluster_arn': W, 'controller_services': S,
            'task_subnet_ids': ['subnet-123abc'], 'task_assign_public_ip': True,
            'activation': {'task_definition_arn': P + 'task-definition/activation:1', 'security_group_id': 'sg-123abc'},
            'sleep': {'task_definition_arn': P + 'task-definition/sleep:1', 'security_group_id': 'sg-123abc'}}


class Fake:
    def __init__(self, running=1, gate=0, fail_update=False, worker=None, unclean=False):
        self.counts = {r: running for r in S}
        self.gate, self.fail_update, self.worker, self.unclean = gate, fail_update, worker, unclean
        self.calls, self.checked, self.operator = [], False, None
    def verify_identity(self):
        self.checked = True
    def call(self, service, action, payload, extra_args=()):
        self.calls.append((action, payload))
        if action in ['run-task', 'update-service']:
            assert self.checked
        if action == 'describe-services':
            return {'services': [{'serviceArn': S[r]['arn'], 'clusterArn': C, 'status': 'ACTIVE',
                                 'taskDefinition': S[r]['task_definition_arn'], 'desiredCount': n, 'runningCount': n,
                                 'pendingCount': 0, 'deployments': [{'rolloutState': 'COMPLETED'}]} for r, n in self.counts.items()]}
        if action == 'list-tasks':
            if payload['cluster'] == W:
                return {'taskArns': [P + 'task/workers/' + 'c' * 32] if self.worker and payload['desiredStatus'] == 'STOPPED' else []}
            r = payload['serviceName']
            return {'taskArns': [T[r]] if (self.counts[r] == 1) == (payload['desiredStatus'] == 'RUNNING') else []}
        if action == 'run-task':
            self.operator = {**payload, 'taskArn': P + 'task/services/' + 'd' * 32}
            return {'tasks': [{'taskArn': self.operator['taskArn'], 'clusterArn': C, 'taskDefinitionArn': payload['taskDefinition']}]}
        if action == 'describe-tasks':
            tasks = []
            for task in payload['tasks']:
                if self.operator and task == self.operator['taskArn']:
                    name = 'sleep' if 'sleep' in self.operator['taskDefinition'] else 'activation'
                    tasks.append({'taskArn': task, 'clusterArn': C, 'taskDefinitionArn': self.operator['taskDefinition'],
                                  'lastStatus': 'STOPPED', 'containers': [{'name': name, 'lastStatus': 'STOPPED', 'exitCode': self.gate}]})
                elif task in T.values():
                    r = next(r for r in T if T[r] == task)
                    tasks.append({'taskArn': task, 'clusterArn': C, 'taskDefinitionArn': S[r]['task_definition_arn'],
                                  'lastStatus': 'RUNNING' if self.counts[r] else 'STOPPED',
                                  'containers': [{'name': r, 'lastStatus': 'STOPPED', 'exitCode': 137 if self.unclean else 0}]})
                else:
                    tasks.append({'taskArn': task, 'clusterArn': W, 'lastStatus': self.worker})
            return {'tasks': tasks}
        if action == 'update-service':
            if self.fail_update:
                raise i.Error('Uncertain update')
            r = next(r for r in S if S[r]['arn'] == payload['service'])
            self.counts[r] = payload['desiredCount']
            return {'service': {'serviceArn': payload['service']}}
        raise AssertionError(action)


class Tests(unittest.TestCase):
    def execute(self, aws, operation, path):
        return i.lifecycle(aws, outputs(), operation, A, R, path, 1)
    def test_sleep_gate_precedes_shutdown_and_has_exact_stopped_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake()
            result = self.execute(aws, 'sleep', Path(d, 'receipt.json'))
            self.assertEqual(result['status'], 'controllers-stopped')
            updates = [p for a, p in aws.calls if a == 'update-service']
            self.assertEqual([p['service'] for p in updates], [S['backend']['arn'], S['launcher']['arn']])
            self.assertEqual(sum(a == 'run-task' for a, _ in aws.calls), 1)
            self.assertLess(next(n for n, (a, _) in enumerate(aws.calls) if a == 'run-task'), next(n for n, (a, _) in enumerate(aws.calls) if a == 'update-service'))
    def test_controller_replacement_during_sleep_gate_refuses_all_count_changes(self):
        class Replacement(Fake):
            def call(self, service, action, payload, extra_args=()):
                result = super().call(service, action, payload, extra_args)
                if action == 'run-task':
                    self.replaced = True
                if action == 'list-tasks' and getattr(self, 'replaced', False) and payload.get('serviceName') == 'backend':
                    result['taskArns'] = [T['backend'].replace('a' * 32, 'e' * 32)] if payload['desiredStatus'] == 'RUNNING' else []
                if action == 'describe-tasks' and any('e' * 32 in t for t in payload['tasks']):
                    result = {'tasks': [{'taskArn': payload['tasks'][0], 'clusterArn': C,
                                        'taskDefinitionArn': S['backend']['task_definition_arn'], 'lastStatus': 'RUNNING'}]}
                return result
        with tempfile.TemporaryDirectory() as d:
            aws = Replacement()
            with self.assertRaises(i.Error): self.execute(aws, 'sleep', Path(d, 'receipt.json'))
            self.assertFalse(any(a == 'update-service' for a, _ in aws.calls))

    def test_refused_gate_never_changes_counts(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(gate=1)
            path = Path(d, 'receipt.json')
            with self.assertRaises(i.Error): self.execute(aws, 'sleep', path)
            self.assertFalse(any(a == 'update-service' for a, _ in aws.calls))
            self.assertEqual(json.loads(path.read_text())['status'], 'incomplete-or-uncertain')
    def test_uncertain_update_is_not_replayed(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(fail_update=True)
            with self.assertRaises(i.Error): self.execute(aws, 'sleep', Path(d, 'receipt.json'))
            self.assertEqual(sum(a == 'update-service' for a, _ in aws.calls), 1)
    def test_unclean_backend_exit_does_not_stop_launcher(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(unclean=True)
            with self.assertRaises(i.Error): self.execute(aws, 'sleep', Path(d, 'receipt.json'))
            self.assertEqual(aws.counts['launcher'], 1)
    def test_wake_starts_launcher_then_backend_then_activates(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(running=0)
            self.assertEqual(self.execute(aws, 'wake', Path(d, 'receipt.json'))['status'], 'controllers-ready')
            self.assertEqual([p['service'] for a, p in aws.calls if a == 'update-service'], [S['launcher']['arn'], S['backend']['arn']])
    def test_actual_stopping_worker_blocks_wake_even_with_desired_stopped(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(running=0, worker='STOPPING')
            with self.assertRaises(i.Error): self.execute(aws, 'wake', Path(d, 'receipt.json'))
            self.assertFalse(any(a in ['run-task', 'update-service'] for a, _ in aws.calls))
    def test_old_stopped_workers_are_not_billable(self):
        i.assert_workers_absent(Fake(worker='STOPPED'), W)
    def test_foreign_service_identity_is_refused(self):
        bad = outputs()
        bad['controller_services'] = {**S, 'backend': {**S['backend'], 'arn': S['backend']['arn'].replace(A, '999999999999')}}
        with self.assertRaises(i.Error): i.metadata(bad, A, R)
    def test_existing_receipt_is_not_replayed(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d, 'receipt.json'); path.write_text('{}')
            aws = Fake()
            with self.assertRaises(OSError): self.execute(aws, 'sleep', path)
            self.assertFalse(any(a in ['run-task', 'update-service'] for a, _ in aws.calls))
    def test_preview_requires_no_aws(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d, 'outputs.json'); path.write_text(json.dumps(outputs()))
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('run-installation.py')), 'sleep', '--outputs', str(path), '--account', A, '--region', R], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)['preview'])


if __name__ == '__main__': unittest.main()
