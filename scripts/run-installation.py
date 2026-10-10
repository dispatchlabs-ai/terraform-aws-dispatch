#!/usr/bin/env python3
"""Explicit IAM-authorized sleep/wake. Preview by default; no mutation replay."""
import argparse
import os
from pathlib import Path
import re
import runpy
import sys
import time

ops = runpy.run_path(str(Path(__file__).with_name('run-operator.py')))
require, Error = ops['require'], ops['OperationError']


def metadata(outputs, account, region):
    require(re.fullmatch(r'[0-9]{12}', account) and re.fullmatch(r'[a-z0-9-]+', region), 'Invalid account/region.')
    cluster = ops['arn'](ops['output'](outputs, 'service_cluster_arn'), 'cluster', account, region)
    workers = ops['arn'](ops['output'](outputs, 'worker_cluster_arn'), 'cluster', account, region)
    services = ops['output'](outputs, 'controller_services')
    require(cluster != workers and isinstance(services, dict) and set(services) == {'backend', 'launcher'}, 'Invalid controller scope.')
    for item in services.values():
        require(isinstance(item, dict), 'Invalid controller metadata.')
        require(re.fullmatch(r'arn:aws(?:-cn|-us-gov)?:ecs:' + re.escape(region) + ':' + account + ':service/' + re.escape(cluster.split('/')[-1]) + r'/[A-Za-z0-9_-]+', item.get('arn', '')), 'Service identity is outside selected cluster/account/region.')
        ops['arn'](item.get('task_definition_arn'), 'definition', account, region)
    require(services['backend']['arn'] != services['launcher']['arn'], 'Controller services must differ.')
    return cluster, workers, services


def inventory(aws, cluster, services):
    result = aws.call('ecs', 'describe-services', {'cluster': cluster, 'services': [s['arn'] for s in services.values()]})
    require(not result.get('failures') and len(result.get('services', [])) == 2, 'Both exact services must be observable.')
    found = {s.get('serviceArn'): s for s in result['services']}
    require(set(found) == {s['arn'] for s in services.values()}, 'Observed services differ from operator scope.')
    for item in services.values():
        actual = found[item['arn']]
        require(actual.get('clusterArn') == cluster and actual.get('status') == 'ACTIVE'
                and actual.get('taskDefinition') == item['task_definition_arn'], 'Controller scope/revision changed; reconcile before continuing.')
        require(len(actual.get('deployments', [])) == 1, 'Controller rollout is in progress; refuse lifecycle operation.')
    return found


def observed_tasks(aws, cluster, service=None):
    identities = set()
    for status in ['RUNNING', 'STOPPED']:
        token, seen = None, set()
        for _ in range(100):
            payload = {'cluster': cluster, 'desiredStatus': status, 'maxResults': 100}
            if service:
                payload['serviceName'] = service['arn'].split('/')[-1]
            if token:
                payload['nextToken'] = token
            result = aws.call('ecs', 'list-tasks', payload, ['--no-paginate'])
            require(isinstance(result.get('taskArns'), list), 'Task inventory is unavailable.')
            identities.update(result['taskArns'])
            token = result.get('nextToken')
            if not token:
                break
            require(token not in seen, 'Task inventory pagination did not advance.')
            seen.add(token)
        else:
            raise Error('Task inventory exceeds the bounded observation size.')
    observed = []
    ordered = sorted(identities)
    for index in range(0, len(ordered), 100):
        exact = ordered[index:index + 100]
        result = aws.call('ecs', 'describe-tasks', {'cluster': cluster, 'tasks': exact})
        require(not result.get('failures') and len(result.get('tasks', [])) == len(exact)
                and {t.get('taskArn') for t in result['tasks']} == set(exact), 'Exact task identities are unavailable.')
        for task in result['tasks']:
            require(task.get('clusterArn') == cluster and isinstance(task.get('lastStatus'), str), 'Task scope/state is unresolved.')
        observed.extend(result['tasks'])
    return observed


def assert_workers_absent(aws, workers):
    require(all(t['lastStatus'] == 'STOPPED' for t in observed_tasks(aws, workers)),
            'A worker is running, stopping or unresolved; lifecycle operation refused.')


def controller_tasks(aws, cluster, service):
    tasks = [t for t in observed_tasks(aws, cluster, service) if t['lastStatus'] != 'STOPPED']
    require(all(t.get('taskDefinitionArn') == service['task_definition_arn'] for t in tasks), 'Controller task revision differs from selected scope.')
    return tasks


def wait_until(check, seconds):
    deadline = time.monotonic() + seconds
    while not check():
        require(time.monotonic() < deadline, 'Observation deadline expired; do not replay mutations.')
        time.sleep(min(5, max(0, deadline - time.monotonic())))


def lifecycle(aws, outputs, operation, account, region, path, wait_seconds):
    cluster, workers, services = metadata(outputs, account, region)
    aws.verify_identity()
    found = inventory(aws, cluster, services)
    desired = 1 if operation == 'sleep' else 0
    require(all(s.get('desiredCount') == desired and s.get('pendingCount') == 0 and s.get('runningCount') == desired for s in found.values()), 'Sleep requires two steady controllers; wake requires both stopped. Reconcile partial states first.')
    task_request, container = ops['request_for'](outputs, 'sleep' if operation == 'sleep' else 'activate', account, region, False)
    # Capture controller tasks before sleep so scale-down needs authoritative STOPPED,
    # not merely an empty eventually consistent ListTasks result.
    captured = {role: [t['taskArn'] for t in controller_tasks(aws, cluster, item)] for role, item in services.items()}
    require(all(len(tasks) == desired for tasks in captured.values()), 'Controller task inventory disagrees with service counts.')
    if operation == 'wake':
        assert_workers_absent(aws, workers)
    expected_counts = {role: desired for role in services}
    expected_tasks = {role: list(tasks) for role, tasks in captured.items()}
    def revalidate():
        current = inventory(aws, cluster, services)
        for role, item in services.items():
            actual = current[item['arn']]
            require(actual.get('desiredCount') == expected_counts[role] and actual.get('runningCount') == expected_counts[role]
                    and actual.get('pendingCount') == 0, 'Controller counts drifted; lifecycle mutation refused.')
            require({t['taskArn'] for t in controller_tasks(aws, cluster, item)} == set(expected_tasks[role]),
                    'Controller task identities drifted; lifecycle mutation refused.')
    receipt = {'schema_version': 1, 'operation': operation, 'account': account, 'region': region,
               'cluster': cluster, 'workers': workers, 'services': services, 'captured_tasks': captured,
               'status': 'prepared', 'phase': 'preflight', 'task_receipt': str(path) + '.task.json'}
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as handle:
        def save(phase):
            receipt['phase'] = phase
            ops['save_receipt'](handle, receipt)
        save('preflight')
        try:
            def operator_task():
                save('operator-request-intent')
                task = ops['submit'](aws, task_request, container, 'sleep' if operation == 'sleep' else 'activate', account, region, Path(receipt['task_receipt']))
                def completed():
                    _, code = ops['observe'](aws, task, account, region)
                    require(code != 1, 'Application refused or failed; controller mutations are not authorized. Inspect task receipt; do not replay.')
                    return code == 0
                wait_until(completed, wait_seconds)
                save('operator-request-succeeded')
            if operation == 'sleep':
                operator_task()
                assert_workers_absent(aws, workers)
                revalidate()
            for role in (['backend', 'launcher'] if operation == 'sleep' else ['launcher', 'backend']):
                revalidate()
                save(role + '-update-intent')
                item = services[role]
                updated = aws.call('ecs', 'update-service', {'cluster': cluster, 'service': item['arn'], 'desiredCount': 0 if operation == 'sleep' else 1})
                require(updated.get('service', {}).get('serviceArn') == item['arn'], 'Service update identity is uncertain; do not replay.')
                def settled():
                    current = inventory(aws, cluster, services)[item['arn']]
                    if operation == 'wake':
                        tasks = controller_tasks(aws, cluster, item)
                        return current.get('desiredCount') == 1 and current.get('runningCount') == 1 and current.get('pendingCount') == 0 and len(tasks) == 1 and tasks[0].get('lastStatus') == 'RUNNING'
                    require(current.get('desiredCount') == 0, 'Controller desired count changed concurrently.')
                    exact = aws.call('ecs', 'describe-tasks', {'cluster': cluster, 'tasks': captured[role]})
                    require(not exact.get('failures') and {t.get('taskArn') for t in exact.get('tasks', [])} == set(captured[role]), 'Captured controller termination is unavailable.')
                    stopped = all(t.get('lastStatus') == 'STOPPED' for t in exact['tasks'])
                    require(all(t.get('clusterArn') == cluster and t.get('taskDefinitionArn') == item['task_definition_arn'] for t in exact['tasks']), 'Captured controller identity/revision changed.')
                    if stopped:
                        require(all(any(c.get('name') == role and c.get('lastStatus') == 'STOPPED' and c.get('exitCode') == 0 for c in t.get('containers', [])) for t in exact['tasks']), 'Controller did not confirm clean exit; sleep is incomplete.')
                    return stopped and current.get('runningCount') == 0 and current.get('pendingCount') == 0
                wait_until(settled, wait_seconds)
                expected_counts[role] = 0 if operation == 'sleep' else 1
                expected_tasks[role] = [] if operation == 'sleep' else [t['taskArn'] for t in controller_tasks(aws, cluster, item)]
                receipt['current_tasks'] = expected_tasks
                save(role + '-observed')
            if operation == 'wake':
                revalidate()
                operator_task()  # Readiness requires activation; never wait for ALB ready first.
                def ready():
                    current = inventory(aws, cluster, services)
                    return all(s.get('desiredCount') == 1 and s.get('runningCount') == 1 and s.get('pendingCount') == 0
                               and s['deployments'][0].get('rolloutState') == 'COMPLETED' for s in current.values())
                wait_until(ready, wait_seconds)
            else:
                assert_workers_absent(aws, workers)
            revalidate()
            receipt['status'] = 'controllers-stopped' if operation == 'sleep' else 'controllers-ready'
            save('complete')
        except Exception:
            receipt['status'] = 'incomplete-or-uncertain'
            ops['save_receipt'](handle, receipt)
            raise
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['sleep', 'wake'])
    parser.add_argument('--outputs', type=Path, required=True)
    parser.add_argument('--account', required=True)
    parser.add_argument('--region', required=True)
    parser.add_argument('--profile')
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--confirm-exclusive-control', action='store_true', help='Confirm no other operator, Terraform apply or scheduler changes counts/admission during this operation.')
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--wait-seconds', type=int, default=1200)
    args = parser.parse_args()
    try:
        outputs = ops['read_json'](args.outputs)
        cluster, workers, services = metadata(outputs, args.account, args.region)
        require(0 < args.wait_seconds <= 3600, 'Observation bound must be 1–3600 seconds.')
        if not args.execute:
            ops['request_for'](outputs, 'sleep' if args.operation == 'sleep' else 'activate', args.account, args.region, False)
            import json
            print(json.dumps({'preview': True, 'operation': args.operation, 'cluster': cluster, 'services': services,
                              'warning': 'Exclusive operator control required. Sleep refuses busy work; workspace scratch is disposable. Aurora pause is not proven by task termination.'}, indent=2))
            return 0
        require(args.confirm_exclusive_control and args.receipt is not None, 'Execution requires exclusive-control confirmation and a new receipt.')
        receipt = lifecycle(ops['Aws'](args.account, args.region, args.profile), outputs, args.operation, args.account, args.region, args.receipt, args.wait_seconds)
        print(receipt['status'])
        return 0
    except (Error, OSError, ValueError, TypeError, KeyError, AttributeError):
        print('Lifecycle refused or incomplete. Inspect receipts and exact task/service state; do not replay mutations.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
