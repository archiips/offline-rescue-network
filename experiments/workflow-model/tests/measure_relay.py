#!/usr/bin/env python3
"""Repeated signed-relay loopback recovery scenarios, with command and delayed-contact timings.

All timestamps are observed by one Python controller, not device/radio latency. No app changes.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import time

import relay_network_smoke as smoke
from measure_exchange import HarnessError, require, write_report


class Recorder:
    def __init__(self):
        self.commands = []
        self.confirmations = []
        self.active = None
        self.uploaded = set()
        self.accepted_events = set()

    def finished(self, role, text, start, end, state, observed, error=None):
        action = text.split()[0]
        require(end >= start, 'performance clock moved backwards')
        result = {}
        metric = 'control'
        if error:
            metric = 'command_error'
        elif action == 'upload':
            if any(v.startswith('UPLOAD ERROR:') for v in observed):
                metric = 'upload_refused'
            else:
                result = smoke.line_with(observed, 'UPLOADED ')
                metric = 'upload_duplicate_custody' if result['id'] in self.uploaded else 'upload_custody'
                self.uploaded.add(result['id'])
        elif action in ('flush', 'flush-drop'):
            result = smoke.line_with(observed, 'FLUSH ')
            outcome = result['result']
            if outcome == 'delivered':
                metric = 'flush_receipt' if result.get('returned') == 'none' else (
                    'flush_repeat_event' if result['id'] in self.accepted_events else 'flush_event')
                if result.get('returned') != 'none':
                    self.accepted_events.add(result['id'])
            else:
                require(outcome in ('failed', 'dropped'), 'unexpected flush result')
                metric = 'flush_' + outcome
                if outcome == 'dropped':
                    self.accepted_events.add(result['id'])
        elif action in ('sos', 'ack', 'reply'):
            metric = 'action_' + action
        # Deliberately exclude arbitrary stdout, pair arguments, cards, fingerprint and location.
        record = dict(role=role, action=action, metric=metric, start_ns=start, end_ns=end, completed=error is None, elapsed_ns=end-start,
                      state={k: state[k] for k in ('pending', 'delivery', 'count', 'requests', 'messages') if k in state},
                      result={k: result[k] for k in ('id', 'returned', 'attempts', 'bytes', 'kind', 'result') if k in result})
        if error:
            record['error_type'] = error
        self.commands.append(record)
        if error:
            return
        if action in ('sos', 'ack', 'reply'):
            require(self.active is None, 'overlapping original measurement')
            require(state.get('pending') == '1', 'original action not queued')
            self.active = dict(role=role, action=action, start=start, event_id=None,
                               receipt_id=None, receipt_delivered=False)
        active = self.active
        if active is None:
            return
        if metric in ('upload_custody', 'upload_duplicate_custody') and role == active['role']:
            require(active['event_id'] in (None, result['id']), 'retry identity changed')
            active['event_id'] = result['id']
        if metric in ('flush_event', 'flush_repeat_event') and result.get('id') == active['event_id']:
            require(result.get('returned') not in (None, 'none'), 'event has no reverse receipt')
            active['receipt_id'] = result['returned']
        if metric == 'flush_receipt' and result.get('id') == active['receipt_id']:
            active['receipt_delivered'] = True
        if action == 'state' and role == active['role'] and state.get('pending') == '0' and active['receipt_delivered']:
            self.confirmations.append(dict(action=active['action'], elapsed_ns=end-active['start'],
                                           event_id=active['event_id'], receipt_id=active['receipt_id']))
            self.active = None


def run_trial(binary, number):
    recorder = Recorder()
    facts = []
    lifecycle = []
    fact_times = []
    start = time.perf_counter_ns()

    class TimedChild(smoke.Child):
        def __init__(self, argv, name, **kwargs):
            before = time.perf_counter_ns()
            try:
                super().__init__(argv, name, **kwargs)
            except (Exception, KeyboardInterrupt):
                lifecycle.append(dict(role=name, operation='spawn_to_ready', completed=False,
                                      elapsed_ns=time.perf_counter_ns()-before))
                raise
            lifecycle.append(dict(role=name, operation='spawn_to_ready', completed=True,
                                  elapsed_ns=time.perf_counter_ns()-before))

        def quit(self):
            if not self.alive():
                return super().quit()
            before = time.perf_counter_ns()
            try:
                return super().quit()
            finally:
                lifecycle.append(dict(role=self.name, operation='quit', completed=not self.alive(),
                                      elapsed_ns=time.perf_counter_ns()-before))

        def command(self, text, expected=(), allow=()):
            before = time.perf_counter_ns()
            try:
                values, observed = super().command(text, expected, allow)
            except (Exception, KeyboardInterrupt) as error:
                recorder.finished(self.name, text, before, time.perf_counter_ns(), {}, [], type(error).__name__)
                raise
            recorder.finished(self.name, text, before, time.perf_counter_ns(), values, observed)
            return values, observed

    result = dict(number=number, passed=False, interrupted=False, cleanup_failed=False)
    def observe_fact(line):
        name = line.split(':', 1)[0].removeprefix('PASS ')
        facts.append(name)
        fact_times.append(dict(name=name, elapsed_ns=time.perf_counter_ns()-start))
    try:
        smoke.run(binary, report=observe_fact,
                  child_factory=TimedChild)
        require(facts == smoke.FACTS, 'incomplete scenario facts')
        require([r['action'] for r in recorder.confirmations] == ['sos', 'ack', 'reply'] and recorder.active is None,
                'incomplete source confirmations')
        result['passed'] = True
    except (Exception, KeyboardInterrupt) as error:
        result['interrupted'] = isinstance(error, KeyboardInterrupt)
        result['cleanup_failed'] = 'cleanup' in str(error).lower() or any('cleanup' in note.lower() for note in getattr(error, '__notes__', []))
        result['error_type'] = type(error).__name__
        # Never copy arbitrary exception text: pairing command errors may embed a public card.
        result['error'] = (re.sub(r'[A-Za-z0-9+/=]{80,}', '[redacted]', str(error))
                           if isinstance(error, HarnessError) else 'External scenario operation failed')
        result['cleanup_notes'] = [re.sub(r'[A-Za-z0-9+/=]{80,}', '[redacted]', note)
                                   for note in getattr(error, '__notes__', [])]
    result.update(elapsed_ns=time.perf_counter_ns()-start, facts=facts, fact_times=fact_times, lifecycle=lifecycle,
                  scenario_complete=facts == smoke.FACTS, commands=recorder.commands,
                  confirmations=recorder.confirmations)
    return result


def summary(values):
    if not values:
        return {'n': 0}
    ordered = sorted(values)
    return dict(n=len(values), min_ns=ordered[0], median_ns=statistics.median(ordered),
                p95_ns=ordered[math.ceil(.95*len(ordered))-1], max_ns=ordered[-1])


def build_report(trials, metadata, planned=None):
    capture_valid = metadata.get('host_sha256') == metadata.get('host_sha256_after', metadata.get('host_sha256'))
    passed = [t for t in trials if t['passed']]
    groups = {}
    coverage = {}
    incomplete = {}
    for trial in trials:
        for command in trial['commands']:
            metric = command['metric']
            if metric == 'command_error':
                action = command['action']
                incomplete[action] = incomplete.get(action, 0) + 1
            elif metric != 'control':
                counts = coverage.setdefault(metric, dict(passed_trial_samples=0, failed_trial_samples=0))
                counts['passed_trial_samples' if trial['passed'] else 'failed_trial_samples'] += 1
    for trial in passed:
        groups.setdefault('scenario_including_setup_cleanup', []).append(trial['elapsed_ns'])
        for command in trial['commands']:
            if command['metric'] != 'control':
                groups.setdefault(command['metric'], []).append(command['elapsed_ns'])
        for confirmation in trial['confirmations']:
            groups.setdefault(confirmation['action']+'_delayed_confirmation', []).append(confirmation['elapsed_ns'])
    counts = dict(attempted=len(trials), passed=len(passed), failed=len(trials)-len(passed))
    if planned is not None:
        counts.update(planned=planned, not_run=planned-len(trials))
    return dict(schema='signed-relay-evaluation-v1', environment=metadata, capture_valid=capture_valid,
                interrupted=metadata.get('interrupted_between_trials', False) or any(t.get('interrupted', False) for t in trials),
                counts=counts,
                metric_coverage=coverage, incomplete_commands_by_action=incomplete,
                percentile='nearest rank: ceil(0.95*n), one-based',
                timing_scope='Python command-to-STATE observations; delayed confirmations include restart/contact gaps; scenario includes setup and cleanup',
                passed_trial_metrics={k: summary(v) for k, v in sorted(groups.items())} if capture_valid else {}, trials=trials)


def environment(binary, configuration):
    root = Path(__file__).resolve().parents[3]
    package = root / 'experiments/workflow-model'
    sources = set()
    for folder in ('Sources/RelayNetworkHost', 'swift', 'bridge', 'src', 'include'):
        sources.update(p for p in (package/folder).rglob('*') if p.is_file() and p.suffix in ('.swift', '.cpp', '.hpp', '.h'))
    sources.update(package/'tests'/name for name in ('measure_relay.py', 'relay_network_smoke.py', 'measure_exchange.py', 'test_measure_relay.py'))
    sources.add(package/'Package.swift')
    clock = time.get_clock_info('perf_counter')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True, timeout=5).strip()
    compiler = subprocess.check_output(['swift', '--version'], text=True, timeout=15).strip()
    return dict(captured_utc=datetime.now(timezone.utc).isoformat(), os=platform.system(), os_version=platform.mac_ver()[0],
                architecture=platform.machine(), python=platform.python_version(), compiler=compiler,
                build_configuration_declared=configuration, load_average_before=os.getloadavg(),
                transport='TCP 127.0.0.1; sequential nonoverlapping endpoint contacts on one Mac',
                clock=dict(name='perf_counter_ns', monotonic=clock.monotonic, resolution_seconds=clock.resolution),
                git_revision=git('rev-parse', 'HEAD'), dirty_worktree=bool(git('status', '--porcelain')),
                host_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                source_sha256={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--configuration', choices=('debug', 'release'), required=True)
    parser.add_argument('--trials', type=int, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.trials <= 100:
        parser.error('Trials must be between 1 and 100')
    if not args.host.is_absolute() or not args.host.is_file() or not os.access(args.host, os.X_OK):
        parser.error('Host must be an existing absolute executable')
    if os.path.lexists(args.output) or not args.output.parent.is_dir():
        parser.error('Output must be a new file in an existing directory')
    metadata = environment(args.host, args.configuration)
    trials = []
    try:
        for number in range(1, args.trials+1):
            trial = run_trial(args.host, number)
            trials.append(trial)
            print(f"Trial {number}/{args.trials}: {'PASS' if trial['passed'] else 'FAIL'}; facts={len(trial['facts'])}", flush=True)
            if trial['interrupted'] or trial['cleanup_failed']:
                break
    except KeyboardInterrupt:
        metadata['interrupted_between_trials'] = True
    try:
        metadata['host_sha256_after'] = hashlib.sha256(args.host.read_bytes()).hexdigest()
    except OSError:
        metadata['host_sha256_after'] = None
    metadata['load_average_after'] = os.getloadavg()
    report = build_report(trials, metadata, planned=args.trials)
    try:
        write_report(args.output, report)
    except OSError:
        parser.error('Could not exclusively publish report; existing output preserved')
    print(json.dumps(report['counts']))
    for metric, values in report['passed_trial_metrics'].items():
        print(metric, json.dumps(values))
    return int(report['counts']['failed'] != 0 or report['counts']['not_run'] != 0 or not report['capture_valid'] or report['interrupted'])


if __name__ == '__main__':
    raise SystemExit(main())
