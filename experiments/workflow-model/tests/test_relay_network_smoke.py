import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import relay_network_smoke as smoke
from measure_exchange import HarnessError


def fake(folder, body):
    """Executable stand-in for the host; stdlib Python only."""
    path = Path(folder) / 'fake-host'
    path.write_text('#!' + sys.executable + '\nimport sys, time, os\n' + body)
    path.chmod(0o755)
    return path


def reaped(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


class ChildProcessTests(unittest.TestCase):
    def test_ready_deadline_kills_and_reaps_silent_child(self):
        with tempfile.TemporaryDirectory() as folder:
            pid_file = Path(folder) / 'pid'
            exe = fake(folder, f'open({str(pid_file)!r}, "w").write(str(os.getpid()))\ntime.sleep(60)\n')
            start = time.monotonic()
            with self.assertRaises(HarnessError):
                smoke.Child([exe], 'silent', timeout=.5)
            self.assertLess(time.monotonic() - start, 5)
            self.assertTrue(reaped(int(pid_file.read_text())))

    def test_early_exit_reports_status_without_waiting_for_deadline(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("STARTUP ERROR: synthetic", flush=True)\nsys.exit(1)\n')
            start = time.monotonic()
            with self.assertRaises(HarnessError) as caught:
                smoke.Child([exe], 'early', timeout=10)
            self.assertLess(time.monotonic() - start, 5)
            self.assertIn('STARTUP ERROR', str(caught.exception))

    def test_command_error_lines_fail_unless_explicitly_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("READY mode=fake", flush=True)\nfor line in sys.stdin:\n'
                               ' print("COMMAND ERROR: synthetic", flush=True)\n print("STATE pending=1", flush=True)\n')
            child = smoke.Child([exe], 'errors', timeout=3)
            try:
                with self.assertRaises(HarnessError):
                    child.command('sos')
                fields, observed = child.command('sos', ['pending=1'], allow=['COMMAND ERROR:'])
                self.assertEqual(fields['pending'], '1')
                self.assertTrue(any(line.startswith('COMMAND ERROR:') for line in observed))
            finally:
                child.close()
            self.assertIsNotNone(child.process.poll())

    def test_state_fields_must_match_exactly(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("READY mode=fake", flush=True)\nfor line in sys.stdin: print("STATE pending=12", flush=True)\n')
            child = smoke.Child([exe], 'fields', timeout=3)
            try:
                with self.assertRaises(HarnessError):
                    child.command('state', ['pending=1'])
            finally:
                child.close()

    def test_output_lines_are_bounded(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("x" * 5000, flush=True)\ntime.sleep(5)\n')
            with self.assertRaises(HarnessError):
                smoke.Child([exe], 'long', timeout=3)

    def test_close_is_idempotent_and_quit_is_bounded(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("READY mode=fake", flush=True)\nfor line in sys.stdin:\n if line.strip() == "quit": sys.exit(0)\n')
            child = smoke.Child([exe], 'quit', timeout=3)
            child.quit()
            self.assertEqual(child.process.returncode, 0)
            child.close()
            child.close()
            self.assertFalse(child.alive())


class TopologyTests(unittest.TestCase):
    def test_absence_requires_no_live_child_and_refused_port(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(1)
            with self.assertRaises(HarnessError):
                smoke.assert_absent('responder', listener.getsockname()[1], [])
        smoke.assert_absent('responder', smoke.unused_port(), [])
        with tempfile.TemporaryDirectory() as folder:
            exe = fake(folder, 'print("READY mode=fake", flush=True)\ntime.sleep(30)\n')
            child = smoke.Child([exe], 'alive', timeout=3)
            try:
                with self.assertRaises(HarnessError):
                    smoke.assert_absent('responder', smoke.unused_port(), [child])
            finally:
                child.close()

    def test_fact_names_are_unique_and_cover_the_spec_sequence(self):
        self.assertEqual(len(smoke.FACTS), len(set(smoke.FACTS)))
        for name in ['custody-id-stable-across-restarts', 'lost-response-exact-retry-one-sos',
                     'receipt-held-origin-pending', 'delayed-receipt-device-received',
                     'relay-holds-no-keys-or-plaintext']:
            self.assertIn(name, smoke.FACTS)


class CleanupTests(unittest.TestCase):
    def test_keychain_failure_attempts_remaining_owned_accounts(self):
        outcomes = [subprocess.TimeoutExpired('security', 15),
                    subprocess.CompletedProcess([], 44),
                    subprocess.CompletedProcess([], 0),
                    subprocess.CompletedProcess([], 44)]
        with patch.object(smoke.subprocess, 'run', side_effect=outcomes) as command:
            self.assertEqual(smoke.delete_keychain_items([Path('/private/tmp/public'), Path('/private/tmp/responder')]), [0])
            self.assertEqual(command.call_count, 4)

    def test_failed_scenario_removes_scratch_and_preserves_error_with_cleanup_note(self):
        with tempfile.TemporaryDirectory() as folder:
            scratch = Path(folder) / 'owned'
            scratch.mkdir()
            with patch.object(smoke.tempfile, 'mkdtemp', return_value=str(scratch)), \
                 patch.object(smoke, 'unused_port', return_value=1234), \
                 patch.object(smoke, 'Child', side_effect=HarnessError('original scenario failure')), \
                 patch.object(smoke, 'delete_keychain_items', return_value=[0, 1]):
                with self.assertRaises(HarnessError) as caught:
                    smoke.run('/unused', report=lambda _: None)
            self.assertIn('original scenario failure', str(caught.exception))
            self.assertTrue(any('cleanup' in note for note in caught.exception.__notes__))
            self.assertFalse(scratch.exists())


HOST = os.environ.get('RESCUE_RELAY_HOST')


@unittest.skipUnless(HOST, 'set RESCUE_RELAY_HOST to the built rescue-relay-host for real process checks')
class RealHostTests(unittest.TestCase):
    def run_host(self, *args):
        return subprocess.run([HOST, *map(str, args)], capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL)

    def test_usage_and_startup_errors_exit_nonzero_without_creating_stores(self):
        with tempfile.TemporaryDirectory(prefix='rescue-net-usage-', dir='/private/tmp') as folder:
            for args in [(), ('endpoint',), ('endpoint', 2, folder, 1, 2), ('endpoint', 0, 'relative', 1, 2),
                         ('endpoint', 0, folder, 0, 2), ('relay', 'relative.sqlite', 1, 'a', 2, 'b', 3), ('bogus',)]:
                result = self.run_host(*args)
                self.assertEqual(result.returncode, 2, args)
                self.assertIn('USAGE', result.stdout)
            store = Path(folder) / 'relay.sqlite'
            result = self.run_host('relay', store, smoke.unused_port(), 'not-a-card', smoke.unused_port(), 'not-a-card', smoke.unused_port())
            self.assertEqual(result.returncode, 1)
            self.assertIn('STARTUP ERROR', result.stdout)
            self.assertFalse(store.exists())
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_explicit_new_session_rotates_card_and_preserves_old_store(self):
        with tempfile.TemporaryDirectory(prefix='rescue-net-reset-', dir='/private/tmp') as folder:
            root = Path(folder)
            listen, relay = smoke.unused_port(), smoke.unused_port()
            children = []
            try:
                first = smoke.Child([HOST, 'endpoint', 0, root, listen, relay], 'first')
                children.append(first)
                old_card = first.wait(lambda line: line.startswith('CARD '))[0][5:]
                first.quit()
                old_store = smoke.endpoint_store(root)
                original = old_store.read_bytes()
                fresh = smoke.Child([HOST, 'endpoint', '--new-session', 0, root, listen, relay], 'new')
                children.append(fresh)
                new_card = fresh.wait(lambda line: line.startswith('CARD '))[0][5:]
                fresh.command('state', ['pending=0'])
                fresh.quit()
                self.assertNotEqual(new_card, old_card)
                self.assertEqual(old_store.read_bytes(), original)
                self.assertEqual(len(list(root.glob('secure-public/*.sqlite'))), 2)
            finally:
                for child in children:
                    child.close(kill=True)
                self.assertEqual(smoke.delete_keychain_items([root]), [])

    def test_separate_processes_relay_sos_receipt_ack_and_reply(self):
        facts = smoke.run(Path(HOST))
        self.assertEqual([name for name, _ in facts], smoke.FACTS)


if __name__ == '__main__':
    unittest.main()
