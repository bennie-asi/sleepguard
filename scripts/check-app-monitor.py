#!/usr/bin/env python3
"""Exercise AppMonitor without registering an app, login item, or launchd job.

Only private fixture processes are started or killed. Pass --check-btm for an
optional before/after BTM comparison in an interactive user session.
"""
import argparse
import json
import os
import pathlib
import platform
import re
import signal
import subprocess
import sys
import tempfile
import textwrap
import time

project = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check-btm', action='store_true', help='compare system BTM identifiers before and after checks')
args = parser.parse_args()


def background_ids():
    result = subprocess.run(['/usr/bin/sfltool', 'dumpbtm'], capture_output=True,
                            text=True, check=True, timeout=45)
    identifiers = set(re.findall(r'^\s*Identifier:\s*(.+)$', result.stdout, re.MULTILINE))
    if not identifiers:
        raise RuntimeError('BTM readback returned no identifiers; cannot verify isolation')
    return identifiers


def wait_for(predicate, message, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(message)


def events(state):
    file = state / 'events.jsonl'
    if not file.exists():
        return []
    # Each event is one short append; tolerate the final line while it is being written.
    return [json.loads(line) for line in file.read_text().splitlines() if line.endswith('}')]


def process_command(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'stat=', '-o', 'command='],
                            capture_output=True, text=True, timeout=5)
    line = result.stdout.strip()
    if result.returncode or not line or line.split()[0].startswith('Z'):
        return None
    return line


before = background_ids() if args.check_btm else None
if before is not None:
    print(f'BTM baseline read: {len(before)} identifiers.', flush=True)
try:
    with tempfile.TemporaryDirectory(prefix='sleepguard-app-monitor-') as directory:
        root = pathlib.Path(directory)
        executable = root / 'app-monitor-check'
        source = project / 'macos/Sources/SleepGuard'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                        '-target', platform.machine() + '-apple-macosx13.0',
                        '-module-cache-path', str(project / 'work/swift-cache'),
                        '-o', str(executable), str(source / 'AppMonitor.swift'),
                        str(source / 'MonitorLog.swift'),
                        str(project / 'macos/Tests/CheckSupport.swift'),
                        str(project / 'macos/Tests/AppMonitorChecks.swift')], check=True)
        worker = root / 'stdin-worker.py'
        worker.write_text('#!' + sys.executable + '\n' + textwrap.dedent('''\
            import json, os, pathlib, sys
            args = sys.argv[1:]
            assert args[:2] == ['watch', '--exit-on-stdin-close'], args
            assert len(args) == 6 and args[2] == '--config' and args[4] == '--state-dir', args
            state = pathlib.Path(args[5])
            assert state.parent == pathlib.Path(__file__).parent
            assert args[3] == str(state / 'config.toml')
            def record(event):
                entry = {'event': event, 'pid': os.getpid(), 'ppid': os.getppid()}
                with (state / 'events.jsonl').open('a') as output:
                    output.write(json.dumps(entry) + '\\n')
                    output.flush()
                    os.fsync(output.fileno())
            attempts = state / 'attempts'
            attempt = int(attempts.read_text()) + 1 if attempts.exists() else 1
            attempts.write_text(str(attempt))
            record('start')
            if attempt == 1 and state.name in ('retry-stop', 'retry-resume', 'normal-exit'):
                record('exit')
                raise SystemExit(0 if state.name == 'normal-exit' else 7)
            assert sys.stdin.buffer.read() == b''
            record('eof')
            if state.name == 'lifecycle':
                sys.stdout.write('stdout-final\\n' * 10000)
                sys.stdout.flush()
                sys.stderr.write('stderr-final\\n' * 10000)
                sys.stderr.flush()
            record('exit')
            '''))
        worker.chmod(0o700)
        states = [root / mode for mode in ('lifecycle', 'orphan-parent', 'retry-stop', 'retry-resume', 'normal-exit')]
        parent = None
        try:
            lifecycle, orphan = states[:2]
            result = subprocess.run([str(executable), 'lifecycle', str(worker), str(lifecycle)],
                                    capture_output=True, text=True, timeout=35)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            records = events(lifecycle)
            starts = [event for event in records if event['event'] == 'start']
            assert len(starts) == 2 and len({event['pid'] for event in starts}) == 2, records
            log = (lifecycle / 'agent.log').read_text()
            assert log.count('stdout-final\n') == 20000 and log.count('stderr-final\n') == 20000, 'lost final worker output'
            for start in starts:
                assert [event['event'] for event in records if event['pid'] == start['pid']] == ['start', 'eof', 'exit'], records
                wait_for(lambda pid=start['pid']: process_command(pid) is None,
                         'fixture survived stop')
            print(result.stdout.strip(), flush=True)

            for state in states[2:]:
                result = subprocess.run([str(executable), state.name, str(worker), str(state)],
                                        capture_output=True, text=True, timeout=15)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
                records = events(state)
                starts = [event for event in records if event['event'] == 'start']
                assert len(starts) == (2 if state.name == 'retry-resume' else 1), records
                for start in starts:
                    wait_for(lambda pid=start['pid']: process_command(pid) is None,
                             'retry fixture survived owner cleanup')
                print(result.stdout.strip(), flush=True)

            parent = subprocess.Popen([str(executable), 'orphan-parent', str(worker), str(orphan)],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            wait_for(lambda: (orphan / 'parent-ready').exists() or parent.poll() is not None,
                     'orphan test parent was not ready')
            if parent.poll() is not None:
                output, errors = parent.communicate()
                raise RuntimeError(output + errors)
            start = next(event for event in events(orphan) if event['event'] == 'start')
            assert start['ppid'] == parent.pid, start
            child_pid = start['pid']
            assert process_command(child_pid) is not None
            parent.kill()  # Exact Popen child owned by this test, never the user's app.
            parent.communicate(timeout=5)
            assert parent.returncode == -signal.SIGKILL
            wait_for(lambda: any(event['event'] == 'eof' for event in events(orphan)),
                     'worker did not receive EOF after parent death')
            wait_for(lambda: process_command(child_pid) is None,
                     'orphan fixture remained alive after EOF')
            assert [event['event'] for event in events(orphan)] == ['start', 'eof', 'exit']
            print('Parent SIGKILL check passed: stdin EOF released the child without a child signal.', flush=True)
        finally:
            if parent is not None and parent.poll() is None:
                parent.kill()
                parent.communicate(timeout=5)
            # Failure cleanup is limited to positively identified private workers.
            for state in states:
                for pid in {event['pid'] for event in events(state) if event['event'] == 'start'}:
                    command = process_command(pid)
                    if command and str(worker) in command and str(state) in command:
                        os.kill(pid, signal.SIGKILL)
                        wait_for(lambda pid=pid: process_command(pid) is None,
                                 'failed to clean up private worker')
finally:
    if before is not None:
        after = background_ids()
        added = after - before
        if added:
            raise AssertionError('BTM identifiers were added during the checks: ' + repr(sorted(added)))
        print(f'BTM comparison passed: {len(after)} identifiers after checks, 0 added.', flush=True)
print('AppMonitor checks passed; private processes and temporary files removed.')
