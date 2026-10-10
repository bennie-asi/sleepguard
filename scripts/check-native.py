#!/usr/bin/env python3
"""Acceptance using only project-owned disposable processes and a private store."""
import json
import pathlib
import subprocess
import tempfile
import time

project = pathlib.Path(__file__).resolve().parent.parent
app = project / 'dist/SleepGuard.app'
cli = str(app / 'Contents/Resources/sleepguard')
subprocess.run([str(app / 'Contents/MacOS/SleepGuard'), '--check-keychain'], check=True)
with tempfile.TemporaryDirectory(prefix='sleepguard-native-') as directory:
    root = pathlib.Path(directory)
    fixture_path = str(root / 'assertion-fixture')
    subprocess.run(['clang', '-framework', 'IOKit', '-framework', 'CoreFoundation',
                    str(project / 'macos/Tests/AssertionFixture.c'), '-o', fixture_path], check=True)
    flags = ['--config', str(root / 'config.toml'), '--state-dir', str(root / 'state')]
    for force in [False, True]:
        fixture = subprocess.Popen([fixture_path])
        try:
            time.sleep(.3)
            status = json.loads(subprocess.check_output([cli, 'ui', 'status', *flags]))
            candidate = next(c for c in status['assessment']['candidates']
                             if c.get('target', {}).get('pid') == fixture.pid)
            request = {'key': candidate['key'], 'target': candidate['target'], 'force': force}
            changed = json.loads(json.dumps(request))
            changed['target']['started_ms'] += 1
            rejected = subprocess.run([cli, 'ui', 'manual-action', *flags],
                                      input=json.dumps(changed), text=True, capture_output=True)
            assert rejected.returncode != 0 and fixture.poll() is None
            result = json.loads(subprocess.check_output([cli, 'ui', 'manual-action', *flags],
                                                       input=json.dumps(request).encode()))
            fixture.wait(timeout=5)
            assert result['exited'] and fixture.returncode == (-9 if force else -15)
            print('Manual action verified:', 'SIGKILL' if force else 'SIGTERM',
                  '(only a disposable assertion fixture)')
        finally:
            if fixture.poll() is None:
                fixture.terminate()
                fixture.wait(timeout=5)
    events = json.loads(subprocess.check_output([cli, 'history', '--limit', '20', *flags]))
    assert sum(e['kind'].startswith('manual_') for e in events) == 4
    print('History verified: both requests and exit results recorded')
