"""Offline lifecycle transport checks. No AWS or application execution."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installation', Path(__file__).with_name('run-installation.py'))
i = importlib.util.module_from_spec(spec)
spec.loader.exec_module(i)
A, R = '123456789012', 'us-east-1'
P = f'arn:aws:ecs:{R}:{A}:'
C, W = P + 'cluster/services', P + 'cluster/workers'
S = {r: {'arn': P + 'service/services/' + r, 'task_definition_arn': P + 'task-definition/' + r + ':1'} for r in ['backend', 'launcher']}
T = {r: P + 'task/services/' + c * 32 for r, c in [('backend', 'a'), ('launcher', 'b')]}
IP = {'backend': '10.80.0.10', 'launcher': '10.80.0.11'}
LB = {r: [{'targetGroupArn': f'arn:aws:elasticloadbalancing:{R}:{A}:targetgroup/{name}/' + 'a' * 16,
           'containerName': r, 'containerPort': 3001 if r == 'backend' else 8830}
          for name in (['backend', 'callbacks'] if r == 'backend' else ['launcher'])] for r in S}


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
        self.load_balancers = copy.deepcopy(LB)
        self.health_checks = {'backend': [], 'launcher': ['launcher']}
        self.health = {'backend': 'UNKNOWN', 'launcher': 'HEALTHY'}
        self.target_health = {lb['targetGroupArn']: 'healthy' for lbs in LB.values() for lb in lbs}
    def verify_identity(self):
        self.checked = True
    def call(self, service, action, payload, extra_args=()):
        self.calls.append((action, payload))
        if action in ['run-task', 'update-service']:
            assert self.checked
        if action == 'describe-services':
            return {'services': [{'serviceArn': S[r]['arn'], 'clusterArn': C, 'status': 'ACTIVE',
                                 'taskDefinition': S[r]['task_definition_arn'], 'desiredCount': n, 'runningCount': n,
                                 'pendingCount': 0, 'loadBalancers': self.load_balancers[r],
                                 'deployments': [{'rolloutState': 'COMPLETED'}]} for r, n in self.counts.items()]}
        if action == 'describe-task-definition':
            r = next(r for r in S if S[r]['task_definition_arn'] == payload['taskDefinition'])
            return {'taskDefinition': {'taskDefinitionArn': payload['taskDefinition'], 'containerDefinitions': [
                {'name': 'volume-init', 'essential': False},
                {'name': r, 'essential': True, **({'healthCheck': {'command': ['CMD', 'check']}} if r in self.health_checks[r] else {})},
                {'name': 'tracing', 'essential': False, 'healthCheck': {'command': ['CMD', 'check']}},
            ]}}
        if action == 'describe-target-health':
            assert service == 'elbv2' and self.operator is not None, 'Readiness must follow activation'
            r = next(r for r in self.load_balancers if any(lb['targetGroupArn'] == payload['TargetGroupArn'] for lb in self.load_balancers[r]))
            assert payload['Targets'] == [{'Id': IP[r], 'Port': 3001 if r == 'backend' else 8830}]
            return {'TargetHealthDescriptions': [{'Target': payload['Targets'][0], 'TargetHealth': {'State': self.target_health[payload['TargetGroupArn']]}}]}
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
                                  'lastStatus': 'RUNNING' if self.counts[r] else 'STOPPED', 'healthStatus': self.health[r],
                                  'containers': [{'name': r, 'lastStatus': 'RUNNING' if self.counts[r] else 'STOPPED',
                                                  'healthStatus': self.health[r], 'networkInterfaces': [{'privateIpv4Address': IP[r]}],
                                                  'exitCode': 137 if self.unclean else 0},
                                                 {'name': 'tracing', 'lastStatus': 'RUNNING', 'healthStatus': 'UNHEALTHY'}]})
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
    def execute(self, aws, operation, path, wait_seconds=1):
        clock = [0.0]
        def sleep(seconds):
            clock[0] += seconds
        with patch.object(i.time, 'monotonic', side_effect=lambda: clock[0]), patch.object(i.time, 'sleep', side_effect=sleep):
            return i.lifecycle(aws, outputs(), operation, A, R, path, wait_seconds)
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
    def test_completed_deployment_does_not_override_unhealthy_or_unknown_task(self):
        for status in ['UNHEALTHY', 'UNKNOWN', None]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as d:
                aws = Fake(running=0)
                aws.health['launcher'] = status
                path = Path(d, 'receipt.json')
                with self.assertRaises(i.Error): self.execute(aws, 'wake', path)
                self.assertEqual(json.loads(path.read_text())['status'], 'incomplete-or-uncertain')
                self.assertEqual(sum(a == 'update-service' for a, _ in aws.calls), 2)
                self.assertEqual(sum(a == 'run-task' for a, _ in aws.calls), 1)

    def test_healthy_task_does_not_hide_an_unready_essential_container(self):
        for state in ['UNHEALTHY', 'UNKNOWN', 'STOPPED', 'missing']:
            class UnreadyContainer(Fake):
                def call(self, service, action, payload, extra_args=()):
                    result = super().call(service, action, payload, extra_args)
                    if action == 'describe-tasks':
                        for task in result['tasks']:
                            if task['taskArn'] == T['launcher']:
                                if state == 'missing':
                                    task['containers'] = []
                                elif state == 'STOPPED':
                                    task['containers'][0]['lastStatus'] = state
                                else:
                                    task['containers'][0]['healthStatus'] = state
                    return result
            with self.subTest(state=state), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(i.Error): self.execute(UnreadyContainer(running=0), 'wake', Path(d, 'receipt.json'))

    def test_wake_requires_every_attached_target_group_to_be_healthy(self):
        for lbs in LB.values():
            for lb in lbs:
                for state in ['initial', 'unhealthy', 'unused', 'draining', 'unavailable', None]:
                    with self.subTest(group=lb['targetGroupArn'], state=state), tempfile.TemporaryDirectory() as d:
                        aws = Fake(running=0)
                        aws.target_health[lb['targetGroupArn']] = state
                        path = Path(d, 'receipt.json')
                        with self.assertRaises(i.Error): self.execute(aws, 'wake', path)
                        self.assertEqual(json.loads(path.read_text())['status'], 'incomplete-or-uncertain')

    def test_wake_polls_current_task_and_target_health_without_replaying_mutations(self):
        class Warming(Fake):
            def __init__(self):
                super().__init__(running=0)
                self.health['launcher'] = 'UNKNOWN'
                self.target_health = {arn: 'initial' for arn in self.target_health}
            def call(self, service, action, payload, extra_args=()):
                result = super().call(service, action, payload, extra_args)
                if action == 'describe-tasks' and self.operator and T['launcher'] in payload['tasks']:
                    self.health['launcher'] = 'HEALTHY'
                if action == 'describe-target-health':
                    self.target_health[payload['TargetGroupArn']] = 'healthy'
                return result
        with tempfile.TemporaryDirectory() as d:
            aws = Warming()
            self.assertEqual(self.execute(aws, 'wake', Path(d, 'receipt.json'), 30)['status'], 'controllers-ready')
            self.assertEqual(sum(a == 'update-service' for a, _ in aws.calls), 2)
            self.assertEqual(sum(a == 'run-task' for a, _ in aws.calls), 1)
            self.assertGreater(sum(a == 'describe-target-health' for a, _ in aws.calls), 3)

    def test_health_of_a_different_target_or_missing_target_is_not_readiness(self):
        for mismatch in ['address', 'port', 'missing']:
            class WrongTarget(Fake):
                def call(self, service, action, payload, extra_args=()):
                    result = super().call(service, action, payload, extra_args)
                    if action == 'describe-target-health':
                        if mismatch == 'missing':
                            result['TargetHealthDescriptions'] = []
                        else:
                            result['TargetHealthDescriptions'][0]['Target'] = {
                                **payload['Targets'][0], **({'Id': '10.80.0.99'} if mismatch == 'address' else {'Port': 9999})}
                    return result
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as d:
                with self.assertRaises(i.Error): self.execute(WrongTarget(running=0), 'wake', Path(d, 'receipt.json'))

    def test_wake_accepts_unknown_ecs_health_only_without_essential_checks(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(running=0)
            aws.health_checks['launcher'] = []
            aws.health['launcher'] = 'UNKNOWN'
            self.assertEqual(self.execute(aws, 'wake', Path(d, 'receipt.json'))['status'], 'controllers-ready')

    def test_essential_container_health_can_prove_readiness_without_an_alb(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(running=0)
            aws.load_balancers['launcher'] = []
            self.assertEqual(self.execute(aws, 'wake', Path(d, 'receipt.json'))['status'], 'controllers-ready')

    def test_wake_without_a_readiness_signal_is_refused_before_mutations(self):
        with tempfile.TemporaryDirectory() as d:
            aws = Fake(running=0)
            aws.load_balancers['backend'] = []
            with self.assertRaises(i.Error): self.execute(aws, 'wake', Path(d, 'receipt.json'))
            self.assertFalse(any(a in ['run-task', 'update-service'] for a, _ in aws.calls))

    def test_controller_termination_during_readiness_is_refused(self):
        class Replacement(Fake):
            def call(self, service, action, payload, extra_args=()):
                result = super().call(service, action, payload, extra_args)
                if action == 'describe-tasks' and self.operator:
                    for task in result['tasks']:
                        if task['taskArn'] == T['backend']:
                            task['lastStatus'] = 'STOPPED'
                return result
        with tempfile.TemporaryDirectory() as d:
            aws = Replacement(running=0)
            with self.assertRaises(i.Error): self.execute(aws, 'wake', Path(d, 'receipt.json'))
            self.assertEqual(sum(a == 'run-task' for a, _ in aws.calls), 1)

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
