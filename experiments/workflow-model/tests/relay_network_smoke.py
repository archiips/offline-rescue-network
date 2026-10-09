#!/usr/bin/env python3
"""Separate public, relay and responder Mac processes with nonoverlapping endpoint contacts.

Real Keychain identities at endpoints only, real loopback sockets and SQLite stores; synthetic data.
Sequential process contacts on one Mac: not radio, firewall isolation or distributed machines, and no
latency benchmark (no timings are recorded).
"""
import argparse
from contextlib import closing
import hashlib
from pathlib import Path
import queue
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

from measure_exchange import HarnessError, require, store_facts, unused_port

TIMEOUT = 15
MAX_LINE = 4096
MAX_LINES = 512
ERROR_PREFIXES = ('COMMAND ERROR:', 'UPLOAD ERROR:', 'INBOUND ERROR:', 'ADMIT ERROR:', 'STARTUP ERROR:')
LOCATION = b'Training Building A'
FACTS = [
    'cards-paired-before-contacts',
    'relay-startup-failure-bounded',
    'upload-refused-while-relay-absent',
    'custody-id-stable-across-restarts',
    'responder-absent-flush-retained',
    'lost-response-exact-retry-one-sos',
    'receipt-held-origin-pending',
    'delayed-receipt-device-received',
    'acknowledgment-separate-and-reply-delivered',
    'stores-empty-no-direct-path',
    'relay-holds-no-keys-or-plaintext',
]


def fields(line):
    return dict(re.findall(r'(\w+)=([^\s]+)', line))


class Child:
    """Owns one child process. Output is read off-thread into a bounded queue; every wait is bounded."""
    def __init__(self, argv, name, timeout=TIMEOUT):
        self.name = name
        self.timeout = timeout
        self.lines = queue.Queue(maxsize=MAX_LINES)
        self.reader_error = None
        self.process = subprocess.Popen([str(a) for a in argv], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.ready, _ = self.wait(lambda line: line.startswith('READY '))
        except BaseException:
            self.close(kill=True)
            raise

    def _read(self):
        try:
            while True:
                line = self.process.stdout.readline(MAX_LINE + 1)
                if len(line) > MAX_LINE:
                    self.reader_error = self.name + ': output line exceeded bound'
                    return
                try:
                    self.lines.put_nowait(line.rstrip('\n') if line else None)
                except queue.Full:
                    self.reader_error = self.name + ': output queue exceeded bound'
                    return
                if not line:
                    return
        except (OSError, ValueError):
            self.reader_error = self.name + ': output unavailable'

    def alive(self):
        return self.process.poll() is None

    def wait(self, predicate):
        deadline = time.monotonic() + self.timeout
        observed = []
        while time.monotonic() < deadline:
            require(self.reader_error is None, self.reader_error or 'reader failed')
            try:
                line = self.lines.get(timeout=min(.1, max(.001, deadline - time.monotonic())))
            except queue.Empty:
                continue
            if line is None:
                status = self.process.wait(timeout=3)
                raise HarnessError(f'{self.name} exited ({status}) before expected output: ' + ' | '.join(observed[-5:]))
            observed.append(line)
            require(len(observed) <= MAX_LINES, self.name + ': too many lines before expected output')
            if predicate(line):
                return line, observed
        raise HarnessError(self.name + ': output deadline exceeded')

    def send(self, text):
        require(self.alive(), self.name + ' is not running')
        self.process.stdin.write(text + '\n')
        self.process.stdin.flush()

    def command(self, text, expected=(), allow=()):
        """Each host command ends with exactly one STATE line; error lines fail unless allowed."""
        self.send(text)
        line, observed = self.wait(lambda value: value.startswith('STATE '))
        unexpected = [v for v in observed if v.startswith(ERROR_PREFIXES) and not v.startswith(tuple(allow))]
        require(not unexpected, f'{self.name} {text!r}: ' + ' | '.join(unexpected))
        values = fields(line)
        for item in expected:
            key, value = item.split('=', 1)
            require(values.get(key) == value, f'{self.name} {text!r}: expected {item}, got {line}')
        return values, observed

    def quit(self):
        if self.alive():
            self.send('quit')
            try:
                self.process.wait(timeout=self.timeout)
            except subprocess.TimeoutExpired:
                pass
        self.close()

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
        for stream in (self.process.stdin, self.process.stdout):
            try:
                stream.close()
            except (OSError, ValueError):
                pass


def assert_absent(role, port, children):
    """The named endpoint has no running owned process and nothing accepts on its port."""
    require(not any(child.alive() for child in children), role + ' process still running during contact')
    with socket.socket() as probe:
        probe.settimeout(1)
        require(probe.connect_ex(('127.0.0.1', port)) != 0, role + ' port accepted a connection during contact')


def line_with(observed, prefix):
    matches = [line for line in observed if line.startswith(prefix)]
    require(len(matches) == 1, f'expected one {prefix!r} line, saw {len(matches)}')
    return fields(matches[0])


def relay_rows(store):
    with closing(sqlite3.connect(store.as_uri() + '?mode=ro', uri=True, timeout=2)) as database:
        return database.execute('SELECT id,attempts,payload FROM relay_items ORDER BY admitted').fetchall()


def endpoint_store(folder):
    stores = [p for p in folder.glob('secure-*/*.sqlite') if not p.name.endswith('.relay-cache.sqlite')]
    require(len(stores) == 1, 'expected one endpoint session store in ' + str(folder))
    return stores[0]


def delete_keychain_items(folders):
    """Deletes only this run's test-owned login-Keychain items by account hash; never reads them.
    Foundation may spell the root with or without /private, so exactly one spelling must exist."""
    failures = []
    for role, folder in enumerate(folders):
        spellings = {str(folder), str(folder).removeprefix('/private')}
        deleted = 0
        for spelling in spellings:
            account = hashlib.sha256((spelling + '\0role=' + str(role)).encode()).hexdigest()
            try:
                status = subprocess.run(['security', 'delete-generic-password', '-s', 'offline-rescue.secure-sample-endpoint',
                                         '-a', account], capture_output=True, timeout=15).returncode
                deleted += status == 0
            except (OSError, subprocess.TimeoutExpired):
                continue
        if deleted != 1:
            failures.append(role)
    return failures


def run(binary, report=print):
    facts = []
    def fact(name, detail):
        require(name == FACTS[len(facts)], 'fact order: ' + name)
        facts.append((name, detail))
        report(f'PASS {name}: {detail}')

    scratch = Path(tempfile.mkdtemp(prefix='rescue-net-relay-', dir='/private/tmp'))
    folders = [scratch / 'public', scratch / 'responder']
    relay_store = scratch / 'relay' / 'relay.sqlite'
    children = dict(public=[], responder=[], relay=[])
    try:
        ports = dict(public=unused_port(), responder=unused_port(), relay=unused_port())
        for folder in folders:
            folder.mkdir()
        relay_store.parent.mkdir()

        def endpoint(role):
            name = ('public', 'responder')[role]
            child = Child([binary, 'endpoint', role, folders[role], ports[name], ports['relay']], name)
            children[name].append(child)
            card = child.wait(lambda line: line.startswith('CARD '))[0][5:]
            child.command('state')
            return child, card

        def relay():
            child = Child([binary, 'relay', relay_store, ports['relay'], cards[0], ports['public'], cards[1], ports['responder']], 'relay')
            children['relay'].append(child)
            return child

        def stop(name):
            for child in children[name]:
                child.quit()

        public, public_card = endpoint(0)
        responder, responder_card = endpoint(1)
        cards = [public_card, responder_card]
        public.command('pair ' + responder_card, ['pending=0'])
        responder.command('pair ' + public_card, ['pending=0'])
        _, observed = public.command('send ' + str(ports['responder']), ['pending=0'], allow=['COMMAND ERROR:'])
        require(any(line.startswith('COMMAND ERROR:') for line in observed), 'endpoint accepted a direct-send command')
        fact(FACTS[0], 'both endpoints exchanged public cards while running; neither has a direct-send command')

        stop('responder')
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1', 0))
            occupied.listen(1)
            blocked = subprocess.run([str(binary), 'relay', str(scratch / 'blocked.sqlite'), str(occupied.getsockname()[1]),
                                      cards[0], str(ports['public']), cards[1], str(ports['responder'])],
                                     capture_output=True, text=True, timeout=TIMEOUT, stdin=subprocess.DEVNULL)
        require(blocked.returncode != 0 and 'STARTUP ERROR' in blocked.stdout, 'occupied relay port did not fail startup')
        fact(FACTS[1], f'relay on an occupied port exited {blocked.returncode} within the bounded wait')

        public.command('sos', ['pending=1', 'requests=1'])
        assert_absent('responder', ports['responder'], children['responder'])
        _, observed = public.command('upload', ['pending=1'], allow=['UPLOAD ERROR:'])
        require(any(line.startswith('UPLOAD ERROR:') for line in observed), 'upload succeeded without a relay')
        fact(FACTS[2], 'upload with no relay process failed; public outbox kept the SOS')

        relay_child = relay()
        assert_absent('responder', ports['responder'], children['responder'])
        _, observed = public.command('upload', ['pending=1'])
        sos_id = line_with(observed, 'UPLOADED ')['id']
        relay_child.wait(lambda line: line.startswith('ADMITTED ') and fields(line).get('id') == sos_id)
        relay_child.command('state', ['count=1'])
        relay_child.close(kill=True)
        public.close(kill=True)
        relay_child = relay()
        relay_child.command('state', ['count=1'])
        public, restored = endpoint(0)
        require(restored == public_card, 'public Keychain identity changed on restart')
        _, observed = public.command('upload', ['pending=1'])
        require(line_with(observed, 'UPLOADED ')['id'] == sos_id, 'packet ID changed after relay/public restart')
        relay_child.command('state', ['count=1'])
        rows = relay_rows(relay_store)
        require([row[0] for row in rows] == [sos_id], 'relay store does not hold exactly the SOS')
        payload = rows[0][2]
        require(358 <= len(payload) <= 4096 and payload[:4] == b'ORL1' and payload[113:117] == b'ORS1'
                and hashlib.sha256(payload).hexdigest() == sos_id and LOCATION not in payload, 'custody is not the exact signed ciphertext')
        fact(FACTS[3], f'SOS {sos_id[:12]} kept one custody row and one ID across killed relay and public restarts')

        stop('public')
        assert_absent('public', ports['public'], children['public'])
        assert_absent('responder', ports['responder'], children['responder'])
        _, observed = relay_child.command('flush', ['count=1'])
        require(line_with(observed, 'FLUSH ')['result'] == 'failed', 'flush to absent responder did not fail')
        fact(FACTS[4], 'flush with the responder absent failed and kept custody')

        responder, restored = endpoint(1)
        require(restored == responder_card, 'responder Keychain identity changed on restart')
        assert_absent('public', ports['public'], children['public'])
        _, observed = relay_child.command('flush-drop', ['count=1'])
        dropped = line_with(observed, 'FLUSH ')
        require(dropped['result'] == 'dropped' and dropped['id'] == sos_id and dropped['attempts'] == '2', 'flush-drop: ' + str(dropped))
        responder.wait(lambda line: line.startswith('INBOUND ') and fields(line).get('id') == sos_id)
        responder.command('state', ['requests=1', 'pending=0'])
        responder.quit()
        responder, _ = endpoint(1)
        assert_absent('public', ports['public'], children['public'])
        _, observed = relay_child.command('flush', ['count=1'])
        delivered = line_with(observed, 'FLUSH ')
        require(delivered['result'] == 'delivered' and delivered['id'] == sos_id and delivered['attempts'] == '3', 'retry: ' + str(delivered))
        receipt_id = delivered['returned']
        responder.wait(lambda line: line.startswith('INBOUND ') and fields(line).get('id') == sos_id)
        responder.command('state', ['requests=1', 'pending=0'])
        fact(FACTS[5], 'response dropped after commit; exact ciphertext retried after responder restart; one SOS saved')

        rows = relay_rows(relay_store)
        require([row[0] for row in rows] == [receipt_id] and rows[0][1] == 0, 'receipt not durable in relay custody')
        stop('responder')
        assert_absent('responder', ports['responder'], children['responder'])
        public, _ = endpoint(0)
        public.command('state', ['pending=1', 'delivery=waiting'])
        fact(FACTS[6], f'receipt {receipt_id[:12]} held by the relay while the public outbox still waited')

        assert_absent('responder', ports['responder'], children['responder'])
        _, observed = relay_child.command('flush', ['count=0'])
        line = line_with(observed, 'FLUSH ')
        require(line['result'] == 'delivered' and line['id'] == receipt_id and line['returned'] == 'none', 'receipt: ' + str(line))
        public.wait(lambda value: value.startswith('INBOUND ') and fields(value).get('id') == receipt_id)
        public.command('state', ['pending=0', 'delivery=deviceReceived'])
        fact(FACTS[7], 'delayed reverse receipt cleared the public outbox: deviceReceived, not humanAcknowledged')

        def carry(source, action, destination_name, expected):
            """Source acts and uploads alone; it leaves; the destination starts; the relay delivers both ways."""
            source_name = 'responder' if source == 1 else 'public'
            child, _ = endpoint(source)
            assert_absent(destination_name, ports[destination_name], children[destination_name])
            child.command(action, ['pending=1'])
            _, seen = child.command('upload', ['pending=1'])
            event_id = line_with(seen, 'UPLOADED ')['id']
            stop(source_name)
            target, _ = endpoint(1 - source)
            assert_absent(source_name, ports[source_name], children[source_name])
            _, seen = relay_child.command('flush', ['count=1'])
            result = line_with(seen, 'FLUSH ')
            require(result['result'] == 'delivered' and result['id'] == event_id, action + ': ' + str(result))
            target.command('state', expected)
            stop(destination_name)
            child, _ = endpoint(source)
            assert_absent(destination_name, ports[destination_name], children[destination_name])
            _, seen = relay_child.command('flush', ['count=0'])
            require(line_with(seen, 'FLUSH ')['id'] == result['returned'], action + ' receipt not returned')
            child.command('state', ['pending=0'])
            stop(source_name)

        stop('public')
        carry(1, 'ack', 'public', ['delivery=humanAcknowledged', 'pending=0'])
        carry(1, 'reply', 'public', ['delivery=humanAcknowledged', 'messages=3'])
        fact(FACTS[8], 'acknowledgment and reply each crossed separate nonoverlapping contacts with their own receipts')

        for role in (0, 1):
            child, _ = endpoint(role)
            child.command('state', ['pending=0'])
            stop(('public', 'responder')[role])
        relay_child.command('state', ['count=0'])
        for role, folder in enumerate(folders):
            facts_ = store_facts(endpoint_store(folder), role)
            require(facts_['history_count'] == 6 and not facts_['pending_ids'], 'endpoint history/outbox mismatch')
            require(facts_['original_ids'] == ['command-1', 'command-2', 'public-1'], 'unexpected originals')
        fact(FACTS[9], 'both endpoint outboxes and relay custody empty; histories hold one SOS, ack, reply and three receipts')

        relay_child.quit()
        stored = [p.name for p in relay_store.parent.iterdir()]
        require(stored == ['relay.sqlite'], 'relay folder holds unexpected files: ' + str(stored))
        require(LOCATION not in relay_store.read_bytes(), 'relay store exposes the synthetic location')
        require(not any(scratch.glob('relay/secure-*')), 'relay folder holds endpoint state')
        fact(FACTS[10], 'relay folder contains only its custody SQLite file, without endpoint keys or plaintext location')
        return facts
    finally:
        original = sys.exception()
        cleanup_errors = []
        try:
            for group in children.values():
                for child in group:
                    try: child.close(kill=True)
                    except (OSError, subprocess.TimeoutExpired, HarnessError) as error:
                        cleanup_errors.append('owned child cleanup: ' + str(error))
            try:
                leftover = delete_keychain_items(folders)
                if leftover: cleanup_errors.append('test Keychain cleanup failed for roles ' + str(leftover))
            except (OSError, subprocess.TimeoutExpired) as error:
                cleanup_errors.append('test Keychain cleanup: ' + str(error))
        finally:
            try: shutil.rmtree(scratch)
            except OSError as error: cleanup_errors.append('scratch cleanup: ' + str(error))
        if cleanup_errors:
            detail = '; '.join(cleanup_errors)
            if original is not None: original.add_note(detail)
            else: raise HarnessError(detail)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    arguments = parser.parse_args()
    require(arguments.host.is_absolute() and arguments.host.is_file(), 'Use an existing absolute rescue-relay-host binary')
    run(arguments.host)
    print('PASS: separate-process signed relay contacts, restarts, lost response and delayed receipts')
