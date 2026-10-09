import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import measure_relay as measure
from measure_exchange import HarnessError


class RecorderTests(unittest.TestCase):
    def test_custody_cannot_finish_confirmation(self):
        r = measure.Recorder()
        r.finished('public', 'sos', 0, 10, {'pending': '1'}, [])
        r.finished('public', 'upload', 10, 20, {'pending': '1'}, ['UPLOADED id=event kind=event bytes=503'])
        r.finished('public', 'state', 20, 30, {'pending': '0'}, [])
        self.assertEqual(r.confirmations, [])
        self.assertIsNotNone(r.active)

    def test_only_correlated_return_receipt_finishes_confirmation(self):
        r = measure.Recorder()
        r.finished('public', 'sos', 100, 110, {'pending': '1'}, [])
        r.finished('public', 'upload', 120, 140, {'pending': '1'}, ['UPLOADED id=event kind=event bytes=503'])
        r.finished('relay', 'flush', 200, 230, {'count': '1'}, ['FLUSH result=delivered id=event attempts=3 returned=receipt'])
        r.finished('relay', 'flush', 240, 250, {'count': '0'}, ['FLUSH result=delivered id=other returned=none attempts=1'])
        r.finished('public', 'state', 260, 270, {'pending': '0'}, [])
        self.assertEqual(r.confirmations, [])
        r.finished('relay', 'flush', 300, 320, {'count': '0'}, ['FLUSH result=delivered id=receipt returned=none attempts=1'])
        r.finished('responder', 'state', 330, 340, {'pending': '0'}, [])
        self.assertEqual(r.confirmations, [])
        r.finished('public', 'state', 350, 400, {'pending': '0'}, [])
        self.assertEqual(r.confirmations, [{'action': 'sos', 'elapsed_ns': 300, 'event_id': 'event', 'receipt_id': 'receipt'}])

    def test_failure_and_receipt_populations_are_separate(self):
        r = measure.Recorder()
        for i, (role, action, line) in enumerate([
            ('public', 'upload', 'UPLOADED id=a bytes=503'),
            ('public', 'upload', 'UPLOAD ERROR: refused'),
            ('relay', 'flush', 'FLUSH result=failed id=a attempts=1'),
            ('relay', 'flush-drop', 'FLUSH result=dropped id=a attempts=2'),
            ('relay', 'flush', 'FLUSH result=delivered id=a attempts=3 returned=b'),
            ('relay', 'flush', 'FLUSH result=delivered id=b attempts=1 returned=none')]):
            r.finished(role, action, i * 10, i * 10 + 5, {}, [line])
        self.assertEqual([v['metric'] for v in r.commands], ['upload_custody', 'upload_refused', 'flush_failed', 'flush_dropped', 'flush_repeat_event', 'flush_receipt'])
        self.assertEqual([v['elapsed_ns'] for v in r.commands], [5] * 6)

    def test_pairing_cards_never_enter_raw_commands(self):
        r = measure.Recorder()
        r.finished('public', 'pair SECRET_CARD', 0, 10, {'pending': '0'}, ['PAIRED SECRET_CARD'])
        self.assertNotIn('SECRET_CARD', json.dumps(r.commands))

    def test_incomplete_command_retained_as_error_without_success_population(self):
        r = measure.Recorder()
        r.finished('public', 'upload', 0, 100, {}, [], 'HarnessError')
        self.assertEqual(r.commands[0]['metric'], 'command_error')
        self.assertEqual(r.commands[0]['elapsed_ns'], 100)

    def test_duplicate_upload_and_repeat_delivery_are_not_pooled(self):
        r = measure.Recorder()
        r.finished('public', 'upload', 0, 10, {}, ['UPLOADED id=a bytes=503'])
        r.finished('public', 'upload', 10, 20, {}, ['UPLOADED id=a bytes=503'])
        r.finished('relay', 'flush-drop', 20, 30, {}, ['FLUSH result=dropped id=a attempts=2'])
        r.finished('relay', 'flush', 30, 40, {}, ['FLUSH result=delivered id=a attempts=3 returned=b'])
        r.finished('responder', 'upload', 40, 50, {}, ['UPLOADED id=c bytes=487'])
        r.finished('relay', 'flush', 50, 60, {}, ['FLUSH result=delivered id=c attempts=1 returned=d'])
        self.assertEqual([v['metric'] for v in r.commands], ['upload_custody', 'upload_duplicate_custody', 'flush_dropped', 'flush_repeat_event', 'upload_custody', 'flush_event'])


class ReportTests(unittest.TestCase):
    def test_nearest_rank_p95_and_singleton(self):
        self.assertEqual(measure.summary([1, 2, 3, 4, 100]), {'n': 5, 'min_ns': 1, 'median_ns': 3, 'p95_ns': 100, 'max_ns': 100})
        self.assertEqual(measure.summary([7])['p95_ns'], 7)
        self.assertEqual(measure.summary([]), {'n': 0})

    def test_failed_trial_retained_excluded_from_validated_timing_summary(self):
        trials = [dict(number=1, passed=True, commands=[dict(metric='upload_custody', elapsed_ns=10)], confirmations=[], elapsed_ns=100),
                  dict(number=2, passed=False, error_type='HarnessError', commands=[dict(metric='upload_custody', elapsed_ns=999)], confirmations=[], elapsed_ns=1000)]
        report = measure.build_report(trials, {'host_sha256': 'same', 'host_sha256_after': 'same', 'dirty_worktree': False, 'source_sha256': {}, 'source_sha256_after': {}})
        self.assertEqual(report['counts'], {'attempted': 2, 'passed': 1, 'failed': 1})
        self.assertEqual(report['passed_trial_metrics']['upload_custody']['max_ns'], 10)
        self.assertEqual(report['trials'][1]['commands'][0]['elapsed_ns'], 999)

    def test_scenario_failure_preserves_partial_commands_and_cleanup_notes(self):
        def broken(binary, report, child_factory):
            child = child_factory([binary], 'public')
            try:
                child.command('sos')
                error = HarnessError('synthetic failure')
                error.add_note('test Keychain cleanup failed for roles [0]')
                raise error
            finally:
                child.close(kill=True)
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'host'
            binary.write_text('#!/usr/bin/env python3\nimport sys\nprint("READY mode=fake", flush=True)\nfor line in sys.stdin: print("STATE pending=1", flush=True)\n')
            binary.chmod(0o755)
            with patch.object(measure.smoke, 'run', side_effect=broken):
                result = measure.run_trial(binary, 1)
            self.assertFalse(result['passed'])
            self.assertEqual(result['commands'][0]['action'], 'sos')
            self.assertIn('cleanup', result['cleanup_notes'][0].lower())

    def test_unexpected_scenario_exception_and_interrupt_are_preserved(self):
        for error in (KeyError('missing field'), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__), patch.object(measure.smoke, 'run', side_effect=error):
                trial = measure.run_trial(Path('/unused'), 1)
            self.assertFalse(trial['passed'])
            self.assertEqual(trial['error_type'], type(error).__name__)
            self.assertEqual(trial['interrupted'], isinstance(error, KeyboardInterrupt))

    def test_cleanup_failure_distinct_from_all_scenario_facts_passing(self):
        def fail_cleanup(binary, report, child_factory):
            for name in measure.smoke.FACTS:
                report('PASS '+name+': synthetic')
            raise HarnessError('test Keychain cleanup failed for roles [0]')
        with patch.object(measure.smoke, 'run', side_effect=fail_cleanup):
            trial = measure.run_trial(Path('/unused'), 1)
        self.assertFalse(trial['passed'])
        self.assertTrue(trial['scenario_complete'])
        self.assertTrue(trial['cleanup_failed'])

    def test_capture_invalidated_by_binary_change(self):
        metadata = {'host_sha256': 'before', 'host_sha256_after': 'after', 'dirty_worktree': False, 'source_sha256': {}, 'source_sha256_after': {}}
        report = measure.build_report([], metadata, planned=20)
        self.assertFalse(report['capture_valid'])
        self.assertEqual(report['counts']['not_run'], 20)
        self.assertEqual(report['passed_trial_metrics'], {})

    def test_cli_interrupt_publishes_partial_report_and_stops_remaining_trials(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'host'
            binary.write_text('synthetic executable')
            binary.chmod(0o755)
            output = Path(folder) / 'result.json'
            argv = ['measure_relay.py', '--host', str(binary), '--configuration', 'debug', '--trials', '3', '--output', str(output)]
            trial = dict(number=1, passed=False, interrupted=True, cleanup_failed=False, facts=[], commands=[], confirmations=[], elapsed_ns=100)
            with patch.object(measure, 'environment', return_value={'host_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'dirty_worktree': False, 'source_sha256': {}}), patch.object(measure, 'run_trial', return_value=trial), patch('sys.argv', argv):
                self.assertEqual(measure.main(), 1)
            report = json.loads(output.read_text())
            self.assertEqual(report['counts'], {'attempted': 1, 'passed': 0, 'failed': 1, 'planned': 3, 'not_run': 2})
            self.assertTrue(report['trials'][0]['interrupted'])

    def test_cli_host_disappears_after_trial_still_publishes_invalid_capture(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'host'
            binary.write_text('synthetic executable')
            binary.chmod(0o755)
            output = Path(folder) / 'result.json'
            argv = ['measure_relay.py', '--host', str(binary), '--configuration', 'debug', '--trials', '1', '--output', str(output)]
            def remove_host(*args):
                binary.unlink()
                return dict(number=1, passed=True, interrupted=False, cleanup_failed=False, facts=[], commands=[], confirmations=[], elapsed_ns=100)
            with patch.object(measure, 'environment', return_value={'host_sha256': 'before', 'dirty_worktree': False, 'source_sha256': {}}), patch.object(measure, 'run_trial', side_effect=remove_host), patch('sys.argv', argv):
                self.assertEqual(measure.main(), 1)
            self.assertFalse(json.loads(output.read_text())['capture_valid'])

    def test_cli_interrupt_between_trials_still_publishes_report(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'host'
            binary.write_text('synthetic executable')
            binary.chmod(0o755)
            output = Path(folder) / 'result.json'
            argv = ['measure_relay.py', '--host', str(binary), '--configuration', 'debug', '--trials', '3', '--output', str(output)]
            with patch.object(measure, 'environment', return_value={'host_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(), 'dirty_worktree': False, 'source_sha256': {}}), patch.object(measure, 'run_trial', side_effect=KeyboardInterrupt()), patch('sys.argv', argv):
                self.assertEqual(measure.main(), 1)
            report = json.loads(output.read_text())
            self.assertTrue(report['interrupted'])
            self.assertEqual(report['counts']['not_run'], 3)

    def test_failed_trial_metric_coverage_is_visible(self):
        trials = [dict(number=1, passed=True, commands=[dict(metric='upload_custody', elapsed_ns=10)], confirmations=[], elapsed_ns=100),
                  dict(number=2, passed=False, commands=[dict(metric='upload_custody', elapsed_ns=999), dict(metric='command_error', action='flush', elapsed_ns=1000)], confirmations=[], elapsed_ns=2000)]
        report = measure.build_report(trials, {'host_sha256': 'same', 'host_sha256_after': 'same', 'dirty_worktree': False, 'source_sha256': {}, 'source_sha256_after': {}})
        self.assertEqual(report['metric_coverage']['upload_custody'], {'passed_trial_samples': 1, 'failed_trial_samples': 1})
        self.assertEqual(report['incomplete_commands_by_action'], {'flush': 1})

    def test_dirty_or_changed_source_capture_is_invalid(self):
        base = dict(host_sha256='same', host_sha256_after='same', dirty_worktree=False, source_sha256={'file': 'before'}, source_sha256_after={'file': 'before'})
        self.assertTrue(measure.build_report([], base)['capture_valid'])
        self.assertFalse(measure.build_report([], dict(base, dirty_worktree=True))['capture_valid'])
        self.assertFalse(measure.build_report([], dict(base, source_sha256_after={'file': 'after'}))['capture_valid'])

    def test_interrupt_cleanup_status_unknown_and_error_output_redacted(self):
        with patch.object(measure.smoke, 'run', side_effect=KeyboardInterrupt()):
            trial = measure.run_trial(Path('/unused'), 1)
        self.assertEqual(trial['cleanup_status'], 'unknown')
        with patch.object(measure.smoke, 'run', side_effect=HarnessError('expected store in /private/tmp/private-root; location=Floor4 FINGERPRINT 1234 5678')):
            trial = measure.run_trial(Path('/unused'), 1)
        self.assertNotIn('/private/tmp', trial['error'])
        self.assertNotIn('Floor4', trial['error'])
        self.assertNotIn('1234', trial['error'])

    def test_quit_lifecycle_distinguishes_forced_exit(self):
        def scenario(binary, report, child_factory):
            child = child_factory([binary], 'public', timeout=.5)
            child.quit()
            raise HarnessError('synthetic stop')
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / 'host'
            binary.write_text('#!/usr/bin/env python3\nimport time\nprint("READY mode=fake", flush=True)\ntime.sleep(30)\n')
            binary.chmod(0o755)
            with patch.object(measure.smoke, 'run', side_effect=scenario):
                trial = measure.run_trial(binary, 1)
            quit_record = [r for r in trial['lifecycle'] if r['operation'] == 'quit'][0]
            self.assertFalse(quit_record['graceful'])
            self.assertNotEqual(quit_record['returncode'], 0)

    def test_exclusive_publication_preserves_existing_and_dangling_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'report.json'
            path.write_text('original')
            with self.assertRaises(FileExistsError):
                measure.write_report(path, {'x': 1})
            self.assertEqual(path.read_text(), 'original')
            link = Path(folder) / 'link'
            link.symlink_to(Path(folder) / 'absent')
            with self.assertRaises(FileExistsError):
                measure.write_report(link, {'x': 1})
            self.assertTrue(link.is_symlink())


if __name__ == '__main__':
    unittest.main()
