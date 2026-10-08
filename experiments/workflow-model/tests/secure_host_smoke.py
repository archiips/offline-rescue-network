#!/usr/bin/env python3
"""Real Keychain/independent-process secure synthetic exchange; no latency benchmark."""
import argparse
import hashlib
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading

from measure_exchange import Host, require, unused_port, store_facts


def frame(connection):
    def exact(count):
        data = bytearray()
        while len(data) < count:
            part = connection.recv(count - len(data))
            require(bool(part), 'Truncated secure frame')
            data.extend(part)
        return bytes(data)
    header = exact(4)
    count = struct.unpack('!I', header)[0]
    require(181 <= count <= 4276, 'Invalid secure envelope length')
    payload = exact(count)
    require(payload[:4] == b'ORS1', 'Plain or unsupported envelope observed')
    require(b'Training Building A' not in payload, 'Sample location visible in envelope')
    return header + payload


def run(binary):
    hosts = []
    with tempfile.TemporaryDirectory(prefix='rescue-secure-smoke-', dir='/tmp') as scratch:
        # Use Foundation's observed /tmp spelling; Path.resolve() adds /private on macOS.
        root = Path(scratch)
        folders = [root / 'public', root / 'responder']
        for folder in folders:
            folder.mkdir()
        try:
            public = Host(binary, 0, folders[0]); hosts.append(public)
            responder = Host(binary, 1, folders[1]); hosts.append(responder)
            public_card = public.wait(lambda line: line.startswith('CARD '))[0][5:]
            responder_card = responder.wait(lambda line: line.startswith('CARD '))[0][5:]
            public.command('pair ' + responder_card, ['pending=0'])
            responder.command('pair ' + public_card, ['pending=0'])
            public.command('sos', ['pending=1'])
            public.command('send ' + str(responder.port), ['pending=0', 'delivery=1'])
            responder.command('ack', ['pending=1'])
            responder.command('reply', ['pending=2'])
            responder.command('send ' + str(public.port), ['pending=0'])
            public.command('correction', ['pending=1'])
            public.close(kill=True)
            public = Host(binary, 0, folders[0]); hosts.append(public)
            restored_card = public.wait(lambda line: line.startswith('CARD '))[0][5:]
            require(restored_card == public_card, 'Keychain identity changed on process restart')
            public.command('state', ['pending=1', 'delivery=2', 'messages=4'])
            public.command('send ' + str(unused_port()), ['pending=1'], allow_transfer_error=True)

            errors = []
            with socket.socket() as proxy:
                proxy.bind(('127.0.0.1', 0)); proxy.listen(1); proxy.settimeout(5)
                def lose_receipts():
                    try:
                        client, _ = proxy.accept()
                        with client:
                            client.settimeout(5)
                            request = frame(client)
                            responses = []
                            for _ in range(2):
                                with socket.create_connection(('127.0.0.1', responder.port), timeout=5) as peer:
                                    peer.sendall(request)
                                    responses.append(frame(peer))
                            require(responses[0] != responses[1], 'Receipt did not use fresh encryption')
                            # Neither encrypted receipt returns to the original sender.
                    except Exception as error:
                        errors.append(error)
                thread = threading.Thread(target=lose_receipts, daemon=True)
                thread.start()
                public.command('send ' + str(proxy.getsockname()[1]), ['pending=1'], allow_transfer_error=True)
                thread.join(6)
                require(not thread.is_alive() and not errors, 'Secure loss/replay proxy failed')
            public.command('send ' + str(responder.port), ['pending=0', 'messages=4'])
            for role, folder in enumerate(folders):
                databases = list(folder.glob('secure-*/*.sqlite'))
                require(len(databases) == 1, 'Unexpected session database count')
                facts = store_facts(databases[0], role)
                require(facts['history_count'] == 8 and not facts['pending_ids'], 'Incorrect committed secure history')
                expected = ['command-1', 'command-2', 'public-1', 'public-2']
                require(facts['original_ids'] == expected and facts['receipt_ids'] == ['receipt-' + item for item in expected],
                        'Wrong originals or device receipts after secure replay')
        finally:
            for host in hosts:
                host.close()
            # Delete only this run's exact test-owned login-Keychain items; never read private records.
            cleanup = []
            for role, folder in enumerate(folders):
                account = hashlib.sha256((str(folder) + '\0role=' + str(role)).encode()).hexdigest()
                status = subprocess.run(['security', 'delete-generic-password', '-s',
                    'offline-rescue.secure-sample-endpoint', '-a', account], capture_output=True).returncode
                if status != 0:
                    cleanup.append(status)
            require(not cleanup, 'Test Keychain cleanup failed')
    print('PASS: encrypted independent hosts, real Keychain restart, refused connection, duplicated correction, lost receipts and exact recovery')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', type=Path, required=True)
    arguments = parser.parse_args()
    require(arguments.host.is_absolute() and arguments.host.is_file(), 'Use an existing absolute secure-host binary')
    run(arguments.host)
