"""Checks reporting truthfulness and real failure/recovery boundaries."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import measure_exchange as measure


class EvidenceTests(unittest.TestCase):
    def test_nearest_rank_p95_and_median_have_hand_checked_values(self):
        self.assertEqual(measure.summarize([4, 1, 3, 2]),
                         dict(count=4, minimum_ms=1, median_ms=2.5, p95_ms=4, maximum_ms=4))
        self.assertIsNone(measure.summarize([]))
        self.assertEqual(measure.summarize([7])['p95_ms'], 7)

    def test_invalid_durations_cannot_become_benchmark_results(self):
        for values in [[-1], [float('nan')], [float('inf')]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                measure.summarize(values)

    def test_failed_trials_are_visible_but_excluded_from_passed_trial_summary(self):
        trials = [dict(trial=1, passed=True, timings_ms={'sos_transfer': 2}),
                  dict(trial=2, passed=False, phase='restart', error='sample failure',
                       timings_ms={'sos_transfer': 0.01})]
        report = measure.build_report(trials, {'fixture': True})
        self.assertEqual(report['counts'], dict(requested=2, passed=1, failed=1))
        self.assertEqual(report['trials'], trials)
        self.assertEqual(report['passed_trial_metrics']['sos_transfer']['median_ms'], 2)
        self.assertIsNone(measure.build_report([trials[1]], {})['passed_trial_metrics']['sos_transfer'])


class BoundaryTests(unittest.TestCase):
    def test_frame_reads_fragmented_header_and_body_without_losing_bytes(self):
        frame = struct.pack('!I', 5) + b'hello'
        a, b = socket.socketpair()
        with a, b:
            a.settimeout(1)
            def write():
                for chunk in [frame[:1], frame[1:3], frame[3:6], frame[6:]]:
                    b.sendall(chunk)
            thread = threading.Thread(target=write)
            thread.start()
            self.assertEqual(measure.read_frame(a), frame)
            thread.join(1)
            self.assertFalse(thread.is_alive())

    def test_proxy_rejects_invalid_length_and_truncated_stream(self):
        for payload in [struct.pack('!I', 0), struct.pack('!I', 4097), b'\x00\x00',
                        struct.pack('!I', 3) + b'x']:
            with self.subTest(payload=payload):
                a, b = socket.socketpair()
                with a, b:
                    a.settimeout(1)
                    b.sendall(payload)
                    b.shutdown(socket.SHUT_WR)
                    with self.assertRaises(measure.HarnessError):
                        measure.read_frame(a)

    def test_closed_child_reports_failure_without_waiting_for_full_deadline(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(measure.HarnessError):
                measure.Host(Path('/usr/bin/true'), 0, Path(d)/'sample.sqlite', timeout=.5)

    def test_cli_rejects_bad_trials_missing_host_and_existing_output(self):
        script = Path(measure.__file__)
        with tempfile.TemporaryDirectory() as d:
            output = Path(d)/'existing.json'
            output.write_text('preserve me')
            for args in [['--host', '/missing/fixture-host', '--trials', '1'],
                         ['--host', '/usr/bin/true', '--trials', '0'],
                         ['--host', '/usr/bin/true', '--trials', '101'],
                         ['--host', '/usr/bin/true', '--trials', '1', '--output', str(output)]]:
                if '--output' not in args:
                    args += ['--output', str(Path(d)/'unused.json')]
                result = subprocess.run([sys.executable, str(script)] + args,
                                        capture_output=True, text=True, timeout=3)
                self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_text(), 'preserve me')
            self.assertFalse((Path(d)/'unused.json').exists())

    def test_child_output_is_bounded(self):
        with tempfile.TemporaryDirectory() as d:
            exe = Path(d)/'noisy-host'
            exe.write_text('#!/usr/bin/env python3\nprint("x" * 5000, flush=True)\n')
            exe.chmod(0o700)
            with self.assertRaises(measure.HarnessError):
                measure.Host(exe, 0, Path(d)/'sample.sqlite', timeout=1)

    def test_status_followed_by_error_cannot_be_reported_as_success(self):
        with tempfile.TemporaryDirectory() as d:
            exe = Path(d)/'error-host'
            exe.write_text('#!/usr/bin/env python3\nimport sys\nprint("READY sample", flush=True)\nfor command in sys.stdin:\n print("STATE pending=1 messages=1", flush=True)\n if command.strip() != "state": print("ERROR: fixture save failure", flush=True)\n')
            exe.chmod(0o700)
            host = measure.Host(exe, 0, Path(d)/'sample.sqlite', timeout=1)
            try:
                with self.assertRaisesRegex(measure.HarnessError, 'action/storage'):
                    host.command('sos', ['pending=1'])
            finally:
                host.close()

    def test_state_numeric_prefix_does_not_match_different_count(self):
        with tempfile.TemporaryDirectory() as d:
            exe = Path(d)/'count-host'
            exe.write_text('#!/usr/bin/env python3\nimport sys\nprint("READY sample", flush=True)\nfor command in sys.stdin: print("STATE pending=12 messages=1", flush=True)\n')
            exe.chmod(0o700)
            host = measure.Host(exe, 0, Path(d)/'sample.sqlite', timeout=1)
            try:
                with self.assertRaisesRegex(measure.HarnessError, 'Unexpected command state'):
                    host.command('sos', ['pending=1'])
            finally:
                host.close()

    def test_programming_error_is_not_disguised_as_network_trial_failure(self):
        with patch.object(measure, 'Host', side_effect=NameError('fixture programmer error')):
            with self.assertRaises(NameError):
                measure.run_trial(Path('/usr/bin/true'), 1)

    def test_invalid_report_never_leaves_partial_output_or_overwrites(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d)/'report.json'
            with self.assertRaises(ValueError):
                measure.write_report(path, {'invalid': float('nan')})
            self.assertFalse(path.exists())
            self.assertEqual(list(Path(d).iterdir()), [])
            measure.write_report(path, {'valid': 1})
            with self.assertRaises(FileExistsError):
                measure.write_report(path, {'valid': 2})
            self.assertEqual(json.loads(path.read_text()), {'valid': 1})
            self.assertEqual(list(Path(d).iterdir()), [path])

    def test_cli_retains_failed_trial_and_returns_failure(self):
        with tempfile.TemporaryDirectory() as d:
            output = Path(d)/'failed.json'
            result = subprocess.run([sys.executable, measure.__file__, '--host', '/usr/bin/true',
                                     '--trials', '1', '--output', str(output)],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            report = json.loads(output.read_text())
            self.assertEqual(report['counts'], dict(requested=1, passed=0, failed=1))
            self.assertFalse(report['trials'][0]['passed'])
            self.assertIn('Host closed', report['trials'][0]['error'])
            self.assertEqual(report['trials'][0]['error_type'], 'HarnessError')
            self.assertIsNone(report['passed_trial_metrics']['sos_transfer'])


@unittest.skipUnless(os.environ.get('RESCUE_EXCHANGE_HOST'), 'set built host path for real integration')
class RealExchangeTests(unittest.TestCase):
    def test_restart_lost_receipt_and_duplicate_original_preserve_exact_histories(self):
        trial = measure.run_trial(Path(os.environ['RESCUE_EXCHANGE_HOST']), 1)
        self.assertTrue(trial['passed'], trial)
        self.assertEqual(set(trial['timings_ms']),
                         {'sos_transfer', 'responder_return_batch', 'correction_retry'})
        self.assertTrue(all(x >= 0 for x in trial['timings_ms'].values()))
        for key in ['refused_connection_retained', 'restart_retained',
                    'lost_receipt_retained', 'duplicate_receipts_equal', 'retry_no_duplicates']:
            self.assertTrue(trial['checks'][key])
        for role in ['public', 'command']:
            self.assertEqual(trial['final_stores'][role]['history_count'], 8)
            self.assertEqual(trial['final_stores'][role]['original_ids'],
                             ['command-1', 'command-2', 'public-1', 'public-2'])
            self.assertEqual(trial['final_stores'][role]['pending_ids'], [])



if __name__ == '__main__':
    unittest.main()
