#!/usr/bin/env python3
"""Real Sparkle installation with production controller and isolated native fixtures.

The coordinator prints a fixture path for native launch. It never opens or kills
the user's app and never uses their Keychain/configuration/background service.
"""
import functools
import argparse
import http.server
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time

project = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--case', choices=['clean_running', 'replaced_running', 'clean_stopped', 'bad_signature'])
options = parser.parse_args()
root = pathlib.Path(tempfile.mkdtemp(prefix='sleepguard-update-integration-', dir=project / 'work'))
framework = project / 'work/sparkle-2.10.0/Sparkle.framework'
cache = project / 'work/swift-cache'


def command(*args):
    subprocess.run(list(map(str, args)), check=True, stdout=subprocess.DEVNULL)


def events(case):
    path = case / 'events.jsonl'
    if not path.exists():
        return []
    result = []
    for line in path.read_text().splitlines():
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return result


def wait_for(check, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = check()
        if result:
            return result
        time.sleep(.1)
    raise TimeoutError('Native update fixture timed out')


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
port = server.server_address[1]
command('xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-module-cache-path', cache,
        project / 'macos/Tests/UpdateFixtureSigner.swift', '-o', root / 'signer')
signer = subprocess.Popen([str(root / 'signer')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
public_key = signer.stdout.readline().strip()
assert public_key


def sign(path):
    signer.stdin.write(str(path) + '\n')
    signer.stdin.flush()
    result = signer.stdout.readline().strip()
    assert result
    return result


command('xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-module-cache-path', cache,
        '-F', framework.parent, '-framework', 'Sparkle', '-Xlinker', '-rpath',
        '-Xlinker', '@executable_path/../Frameworks',
        project / 'macos/Sources/SleepGuard/UpdateController.swift',
        project / 'macos/Sources/SleepGuard/UpdateRecovery.swift',
        project / 'macos/Sources/SleepGuard/UpdateRelaunch.swift',
        project / 'macos/Sources/SleepGuard/UpdateFailure.swift',
        project / 'macos/Sources/SleepGuard/BackendCommand.swift',
        project / 'macos/Tests/CheckSupport.swift',
        project / 'macos/Tests/UpdateIntegrationApp.swift', '-o', root / 'fixture')
command('clang', project / 'macos/Tests/MonitorFixture.c', '-o', root / 'monitor-fixture')


def bundle(path, case, version, build, running):
    executable = path / 'Contents/MacOS/SleepGuardFixture'
    executable.parent.mkdir(parents=True)
    shutil.copy2(root / 'fixture', executable)
    command('ditto', framework, path / 'Contents/Frameworks/Sparkle.framework')
    info = {'CFBundleIdentifier': 'io.sleepguard.updatecheck.' + case.name,
            'CFBundleName': 'SleepGuard Update Fixture', 'CFBundleExecutable': 'SleepGuardFixture',
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': build,
            'CFBundleShortVersionString': version, 'NSPrincipalClass': 'NSApplication',
            'LSMinimumSystemVersion': '13.0', 'SUEnableAutomaticChecks': False,
            'SUAutomaticallyUpdate': False, 'SUPublicEDKey': public_key,
            'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
            'SUFeedURL': f'http://127.0.0.1:{port}/{case.name}/appcast.xml',
            'SleepGuardTestStateRoot': str(case), 'SleepGuardTestMonitorInitiallyRunning': running}
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    command('codesign', '--force', '--sign', '-', path)
    command('codesign', '--verify', '--deep', '--strict', path)


cases = [('clean_running', True, False, False), ('replaced_running', True, True, False),
         ('clean_stopped', False, False, False), ('bad_signature', True, False, True)]
if options.case:
    cases = [case for case in cases if case[0] == options.case]
plan = []
for name, running, replaced, corrupt in cases:
    case = root / name
    case.mkdir()
    shutil.copy2(root / 'monitor-fixture', case / 'monitor-fixture')
    old = case / 'Installed/SleepGuardFixture.app'
    new = case / 'Release/SleepGuardFixture.app'
    bundle(old, case, '0.4.1', '4001', running)
    bundle(new, case, '0.4.2', '4002', running)
    archive = case / 'SleepGuardFixture-0.4.2.zip'
    command('ditto', '-c', '-k', '--keepParent', new, archive)
    signature = sign(archive)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
           '<channel><title>SleepGuard update fixture</title><item><title>0.4.2</title>'
           '<sparkle:version>4002</sparkle:version><sparkle:shortVersionString>0.4.2</sparkle:shortVersionString>'
           f'<enclosure url="http://127.0.0.1:{port}/{name}/{archive.name}" length="{archive.stat().st_size}" '
           f'type="application/octet-stream" sparkle:edSignature="{signature}"/>'
           '</item></channel></rss>\n').encode()
    feed = case / 'appcast.xml'
    feed.write_bytes(xml)
    feed_signature = sign(feed)
    with feed.open('ab') as output:
        output.write(f'<!-- sparkle-signatures:\nedSignature: {feed_signature}\nlength: {len(xml)}\n-->\n'.encode())
    if corrupt:
        with archive.open('r+b') as output:
            output.seek(100)
            byte = output.read(1)
            output.seek(100)
            output.write(bytes([byte[0] ^ 1]))
    plan.append({'name': name, 'app': str(old), 'running': running, 'replaced': replaced, 'corrupt': corrupt})
(root / 'plan.json').write_text(json.dumps(plan, indent=2))
print('INTEGRATION_ROOT=' + str(root), flush=True)

report = []
try:
    for spec in plan:
        case = root / spec['name']
        installed = pathlib.Path(spec['app'])
        print('LAUNCH_FIXTURE=' + str(installed), flush=True)
        ready = wait_for(lambda: next((e for e in events(case) if e['event'] == 'ready'), None), seconds=600)
        assert ready['build'] == '4001' and ready['executable_current']
        assert ready['monitor_running'] == spec['running']
        if spec['replaced']:
            replacement = case / 'replacement.app'
            command('ditto', installed, replacement)
            removed = case / 'unlinked.app'
            installed.rename(removed)
            replacement.rename(installed)
            shutil.rmtree(removed)
        (case / 'request-update').touch()
        if spec['corrupt']:
            failure = wait_for(lambda: next((e for e in events(case) if e['event'] == 'update_error'), None))
            assert failure['status'] == '验证更新失败', failure
            assert not any(e['event'] == 'prepared' for e in events(case))
            os.kill(ready['pid'], 0)
            result = {'case': spec['name'], 'rejected_before_quit': True, 'old_pid': ready['pid']}
        else:
            def updated():
                failures = [e for e in events(case) if e['event'] in ('update_error', 'fixture_error')]
                if failures:
                    raise RuntimeError(json.dumps(failures))
                return next((e for e in events(case) if e['event'] == 'ready' and e['build'] == '4002'), None)
            current = wait_for(updated)
            trace = events(case)
            assert current['pid'] != ready['pid'] and current['executable_current']
            assert current['monitor_running'] == spec['running']
            assert any(e['event'] == 'terminated' and e['pid'] == ready['pid'] and e['prepared'] for e in trace)
            assert any(e['event'] == 'state_restored' and e['build'] == '4002' and e['was_running'] == spec['running'] for e in trace)
            if spec['replaced']:
                assert any(e['event'] == 'prepared' and e['continuing'] for e in trace)
                assert len({e['pid'] for e in trace if e['event'] == 'ready' and e['build'] == '4001'}) == 2
            info = plistlib.loads((installed / 'Contents/Info.plist').read_bytes())
            assert info['CFBundleVersion'] == '4002'
            command('codesign', '--verify', '--deep', '--strict', installed)
            result = {'case': spec['name'], 'old_pid': ready['pid'], 'new_pid': current['pid'],
                      'build': current['build'], 'monitor_running': current['monitor_running'],
                      'automatic_restart_continuation': spec['replaced']}
        (case / 'finish').touch()
        wait_for(lambda: any(e['event'] == 'terminated' for e in events(case) if e['build'] == ('4001' if spec['corrupt'] else '4002')))
        report.append(result)
        (root / 'report.json').write_text(json.dumps(report, indent=2))
        print('PASSED=' + json.dumps(result), flush=True)
    (root / 'report.json').write_text(json.dumps(report, indent=2))
    print('UPDATE_INTEGRATION_PASSED=' + str(root / 'report.json'), flush=True)
finally:
    for spec in plan:
        (root / spec['name'] / 'finish').touch()
    server.shutdown()
    signer.stdin.close()
    signer.wait(timeout=5)
