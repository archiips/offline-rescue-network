"""Measure synthetic independent Mac endpoints over real TCP loopback, never radio."""
import argparse
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import queue
import re
import socket
import sqlite3
import statistics
import struct
import subprocess
import threading
import tempfile
import time

METRICS = {
    'sos_transfer': 'send-command write to public STATE after SOS receipt committed; composition excluded',
    'responder_return_batch': 'send-command write to responder STATE after acknowledgment + reply receipts committed; two originals',
    'correction_retry': 'direct retry send-command write to public STATE after correction receipt committed; outage/startup excluded',
}
TIMEOUT = 12


class HarnessError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise HarnessError(message)


def summarize(values):
    if not values:
        return None
    if any(not math.isfinite(v) or v < 0 for v in values):
        raise ValueError('Durations must be finite and nonnegative')
    ordered = sorted(values)
    return dict(count=len(values), minimum_ms=ordered[0], median_ms=statistics.median(values),
                p95_ms=ordered[math.ceil(.95 * len(values)) - 1], maximum_ms=ordered[-1])


def build_report(trials, metadata):
    passed = [t for t in trials if t['passed']]
    return dict(schema_version=1, environment=metadata, counts=dict(requested=len(trials),
                passed=len(passed), failed=len(trials)-len(passed)),
                metric_definitions=METRICS, summary_population='passed trials only; failed partial timings remain raw',
                percentile_method='nearest rank: sorted[ceil(0.95*n)-1]',
                passed_trial_metrics={m: summarize([t['timings_ms'][m] for t in passed
                                                   if m in t['timings_ms']]) for m in METRICS},
                trials=trials)


def read_frame(connection):
    def exact(count):
        result = bytearray()
        while len(result) < count:
            data = connection.recv(count-len(result))
            require(bool(data), 'Truncated proxy frame')
            result.extend(data)
        return bytes(result)
    header = exact(4)
    length = struct.unpack('!I', header)[0]
    require(1 <= length <= 4096, 'Invalid proxy frame length')
    return header + exact(length)


def unused_port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return connection.getsockname()[1]


class Host:
    """Owns one child; only serialized commands emit STATE, incoming notifications do not."""
    def __init__(self, binary, role, store, timeout=TIMEOUT):
        self.timeout = timeout
        self.port = unused_port()
        self.lines = queue.Queue(maxsize=256)
        self.reader_error = None
        self.process = subprocess.Popen([str(binary), str(role), str(store), str(self.port)],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.wait(lambda line: line.startswith('READY '))
        except Exception:
            self.close()
            raise

    def _read(self):
        try:
            while True:
                line = self.process.stdout.readline(4097)
                if len(line) > 4096:
                    self.reader_error = 'Child output line exceeded bound'
                    return
                try:
                    self.lines.put_nowait(line.rstrip('\n') if line else None)
                except queue.Full:
                    self.reader_error = 'Child output queue exceeded bound'
                    return
                if not line:
                    return
        except (OSError, ValueError):
            self.reader_error = 'Child output unavailable'

    def wait(self, predicate):
        deadline = time.monotonic() + self.timeout
        observed = []
        while time.monotonic() < deadline:
            require(self.reader_error is None, self.reader_error or 'Child output failed')
            try:
                line = self.lines.get(timeout=min(.1, max(.001, deadline-time.monotonic())))
            except queue.Empty:
                continue
            require(line is not None, 'Host closed before expected result')
            observed.append(line)
            require(len(observed) <= 256, 'Too many host lines before command result')
            if predicate(line):
                return line, observed
        raise HarnessError('Host result deadline exceeded')

    def command(self, command, expected, allow_transfer_error=False):
        start = time.perf_counter_ns()
        self.process.stdin.write(command+'\n')
        self.process.stdin.flush()
        line, observed = self.wait(lambda value: value.startswith('STATE '))
        duration = (time.perf_counter_ns()-start)/1_000_000
        # report() emits a possible ERROR after STATE. An untimed state command fences it:
        # the first command's trailing output must precede this probe's STATE.
        self.process.stdin.write('state\n')
        self.process.stdin.flush()
        _, trailing = self.wait(lambda value: value.startswith('STATE '))
        observed += trailing
        require(all(not value.startswith('ERROR:') for value in observed), 'Endpoint action/storage error')
        transfer_error = any(value.startswith('TRANSFER ERROR:') for value in observed)
        require(transfer_error == allow_transfer_error, 'Unexpected transfer success/failure')
        fields = dict(re.findall(r'(\w+)=([^\s]+)', line))
        require(all(fields.get(value.split('=', 1)[0]) == value.split('=', 1)[1]
                    if '=' in value else value in line for value in expected),
                'Unexpected command state: '+line)
        return duration

    def close(self, kill=False):
        if self.process.poll() is None:
            if kill:
                self.process.kill()
            else:
                self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
        self.reader.join(timeout=1)
        self.process.stdin.close()
        self.process.stdout.close()


class DropReceiptProxy:
    """One synthetic correction, delivered twice with equal receipts, neither returned."""
    def __init__(self, target_port):
        self.target_port = target_port
        self.server = socket.socket()
        self.server.settimeout(3)
        self.server.bind(('127.0.0.1', 0))
        self.server.listen(1)
        self.port = self.server.getsockname()[1]
        self.error = None
        self.equal_receipts = False
        self.thread = threading.Thread(target=self._run, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def _run(self):
        try:
            connection, _ = self.server.accept()
            with connection:
                connection.settimeout(3)
                packet = read_frame(connection)
                receipts = []
                for _ in range(2):
                    with socket.create_connection(('127.0.0.1', self.target_port), timeout=3) as peer:
                        peer.sendall(packet)
                        receipts.append(read_frame(peer))
                self.equal_receipts = receipts[0] == receipts[1]
                require(self.equal_receipts, 'Duplicate original returned changed receipt')
                # Closing this stream simulates losing the response after receiver durable acceptance.
        except Exception as error:
            self.error = str(error)

    def verify(self):
        self.thread.join(timeout=TIMEOUT)
        require(not self.thread.is_alive(), 'Proxy did not finish')
        require(self.error is None, 'Proxy failed: '+str(self.error))
        require(self.equal_receipts, 'Proxy did not observe duplicate receipts')

    def __exit__(self, *_):
        self.server.close()
        self.thread.join(timeout=4)


def store_facts(path, role):
    # Observe committed state; never change the owning C++ endpoint's database.
    with closing(sqlite3.connect(path.as_uri()+'?mode=ro', uri=True, timeout=.5)) as database:
        rows = database.execute('SELECT id,kind,ref,author,destination,seq,revision,seen,text,location '
                                'FROM events WHERE area=? ORDER BY position', (role,)).fetchall()
        pending = database.execute('SELECT id FROM events WHERE area=2 ORDER BY position').fetchall()
        actor = database.execute('SELECT actor FROM session WHERE id=1').fetchone()[0]
    require(actor == ('public' if role == 0 else 'command'), 'Store belongs to wrong role')
    originals = [row for row in rows if row[1] != 4]
    receipts = [row for row in rows if row[1] == 4]
    require(len({row[0] for row in rows}) == len(rows), 'Duplicate stored event ID')
    for receipt in receipts:
        source = next((row for row in originals if row[0] == receipt[2]), None)
        require(source is not None and receipt[0] == 'receipt-'+source[0]
                and receipt[3] == source[4] and receipt[4] == source[3], 'Invalid saved receipt relationship')
    return dict(history_count=len(rows), original_ids=sorted(row[0] for row in originals),
                receipt_ids=sorted(row[0] for row in receipts), pending_ids=[r[0] for r in pending],
                history_sha256=hashlib.sha256(json.dumps(rows, ensure_ascii=False).encode()).hexdigest())


def run_trial(binary, number):
    result = dict(trial=number, passed=False, phase='startup', timings_ms={}, checks={})
    hosts = []
    try:
        with tempfile.TemporaryDirectory(prefix='rescue-measure-', dir='/private/tmp') as folder:
            paths = [Path(folder)/'public.sqlite', Path(folder)/'responder.sqlite']
            try:
                public = Host(binary, 0, paths[0]); hosts.append(public)
                responder = Host(binary, 1, paths[1]); hosts.append(responder)
                result['phase'] = 'sos'
                public.command('sos', ['pending=1', 'delivery=0', 'messages=1'])
                result['timings_ms']['sos_transfer'] = public.command(
                    f'send {responder.port}', ['pending=0', 'delivery=1', 'messages=1'])
                responder.command('state', ['request=true', 'messages=1', 'pending=0'])
                result['phase'] = 'acknowledgment_reply'
                responder.command('ack', ['pending=1', 'messages=2'])
                responder.command('reply', ['pending=2', 'messages=3'])
                result['timings_ms']['responder_return_batch'] = responder.command(
                    f'send {public.port}', ['pending=0', 'messages=3'])
                public.command('state', ['delivery=2', 'messages=3', 'pending=0'])
                result['phase'] = 'refused_connection'
                public.command('correction', ['pending=1', 'messages=4', 'Floor 4'])
                before_restart = store_facts(paths[0], 0)
                # Keep the unused port bound without listening so another process cannot claim it.
                with socket.socket() as unavailable:
                    unavailable.bind(('127.0.0.1', 0))
                    public.command(f'send {unavailable.getsockname()[1]}', ['pending=1', 'messages=4'], True)
                require(store_facts(paths[0], 0) == before_restart, 'Refused connection changed saved state')
                result['checks']['refused_connection_retained'] = True
                result['phase'] = 'restart'
                public.close(kill=True)
                public = Host(binary, 0, paths[0]); hosts.append(public)
                public.command('state', ['pending=1', 'messages=4', 'delivery=2'])
                require(store_facts(paths[0], 0) == before_restart, 'Restart changed history/outbox')
                result['checks']['restart_retained'] = True
                result['phase'] = 'lost_receipt_duplicate'
                with DropReceiptProxy(responder.port) as proxy:
                    public.command(f'send {proxy.port}', ['pending=1', 'messages=4'], True)
                    proxy.verify()
                require(store_facts(paths[0], 0) == before_restart, 'Lost receipt falsely confirmed sender')
                received = store_facts(paths[1], 1)
                require(received['history_count'] == 8 and received['pending_ids'] == [],
                        'Receiver duplicated original or lacked committed receipt')
                result['checks']['lost_receipt_retained'] = True
                result['checks']['duplicate_receipts_equal'] = True
                result['phase'] = 'correction_retry'
                result['timings_ms']['correction_retry'] = public.command(
                    f'send {responder.port}', ['pending=0', 'messages=4', 'delivery=2'])
                responder.command('state', ['messages=4', 'Floor 4', 'pending=0'])
                require(store_facts(paths[1], 1) == received, 'Retry changed receiver history')
                result['checks']['retry_no_duplicates'] = True
                result['phase'] = 'final_invariants'
                result['final_stores'] = dict(public=store_facts(paths[0], 0), command=store_facts(paths[1], 1))
                for facts in result['final_stores'].values():
                    require(facts['history_count'] == 8 and facts['pending_ids'] == [] and
                            facts['original_ids'] == ['command-1', 'command-2', 'public-1', 'public-2'] and
                            facts['receipt_ids'] == ['receipt-command-1', 'receipt-command-2',
                                                     'receipt-public-1', 'receipt-public-2'], 'Final persisted invariants failed')
                result['phase'] = 'complete'
                result['passed'] = True
            finally:
                cleanup_failed = False
                for host in reversed(hosts):
                    try:
                        host.close()
                    except (OSError, subprocess.SubprocessError):
                        cleanup_failed = True
                require(not cleanup_failed, 'Host cleanup failed')
    except (HarnessError, OSError, sqlite3.Error, subprocess.SubprocessError) as error:
        result['passed'] = False
        result['error_type'] = type(error).__name__
        # Expected OS/library failures may embed file paths. Keep only controlled messages.
        result['error'] = str(error) if isinstance(error, HarnessError) else 'External operation failed'
    return result


def environment(binary):
    root = Path(__file__).resolve().parents[3]
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True, timeout=3).strip()
    sources = [Path(__file__), root/'experiments/workflow-model/Sources/ExchangeHost/ExchangeHost.swift']
    sources += sorted((root/'experiments/workflow-model/bridge').rglob('*.cpp'))
    sources += sorted((root/'experiments/workflow-model/bridge').rglob('*.hpp'))
    sources += sorted((root/'experiments/workflow-model/bridge').rglob('*.h'))
    sources += sorted((root/'experiments/workflow-model/swift').glob('*.swift'))
    sources += sorted((root/'experiments/workflow-model/src').glob('*.cpp'))
    sources += sorted((root/'experiments/workflow-model/include').glob('*.hpp'))
    sources += [root/'experiments/workflow-model/Package.swift']
    clock = time.get_clock_info('perf_counter')
    return dict(captured_utc=datetime.now(timezone.utc).isoformat(), os=platform.system(),
                os_version=platform.mac_ver()[0], architecture=platform.machine(), python=platform.python_version(),
                transport='TCP 127.0.0.1 loopback; two Mac processes plus test fault proxy',
                clock=dict(name='perf_counter_ns', monotonic=clock.monotonic, resolution_seconds=clock.resolution),
                git_revision=git('rev-parse', 'HEAD'), dirty_worktree=bool(git('status', '--porcelain')),
                host_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                source_sha256={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})


def write_report(path, report):
    """Publish a complete JSON via exclusive hard link; no partial target or overwrite."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.rescue-report-',
                                         suffix='.json', delete=False) as output:
            temporary = Path(output.name)
            json.dump(report, output, indent=2, allow_nan=False)
            output.write('\n')
        os.link(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    parser.add_argument('--trials', type=int, default=20)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.trials <= 100:
        parser.error('Trials must be between 1 and 100')
    if not args.host.is_absolute() or not args.host.is_file() or not os.access(args.host, os.X_OK):
        parser.error('Host must be an absolute executable file')
    if os.path.lexists(args.output):
        parser.error('Output must be a new file')
    if not args.output.parent.is_dir() or not os.access(args.output.parent, os.W_OK):
        parser.error('Output directory must exist and be writable')
    metadata = environment(args.host)
    trials = []
    for number in range(1, args.trials+1):
        trial = run_trial(args.host, number)
        trials.append(trial)
        print(f"Trial {number}/{args.trials}: {'PASS' if trial['passed'] else 'FAIL'} ({trial['phase']})", flush=True)
    report = build_report(trials, metadata)
    try:
        write_report(args.output, report)
    except OSError:
        parser.error('Could not exclusively publish report; existing output is preserved')
    print(json.dumps(report['counts']))
    for metric, summary in report['passed_trial_metrics'].items():
        print(metric, json.dumps(summary))
    return 0 if report['counts']['failed'] == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
