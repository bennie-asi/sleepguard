#!/usr/bin/env python3
"""Run production GuardModel login startup against private CLI fixtures.

The production model receives an in-memory login service adapter; all monitor
commands use a private mock. No system login items are registered or removed.
This checks startup decisions, not actual macOS registration or logout/reboot.
"""
import argparse
import contextlib
import json
import os
import pathlib
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import textwrap

project = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--backend', type=pathlib.Path,
                    default=pathlib.Path(os.environ.get('APP_OUTPUT', project / 'dist/SleepGuard.app'))
                    / 'Contents/Resources/sleepguard',
                    help='built Go CLI used only to obtain isolated config/status JSON')
args = parser.parse_args()
assert args.backend.is_file(), 'Build the Go CLI first, or pass --backend PATH'
source = project / 'macos/Sources/SleepGuard'
sparkle = pathlib.Path(subprocess.run([str(project / 'scripts/fetch-sparkle.sh')],
                                     capture_output=True, text=True, check=True).stdout.strip())

with tempfile.TemporaryDirectory(prefix='sleepguard-login-startup-') as directory, contextlib.ExitStack() as cleanup:
    root = pathlib.Path(directory)
    app = root / 'LoginStartupCheck.app'
    # AppKit can add even this fake-service app to LaunchServices. Unregister
    # its exact temporary path before deletion, including when a check fails.
    cleanup.callback(subprocess.run,
                     ['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                      '-u', str(app)], capture_output=True, timeout=10)
    executable = app / 'Contents/MacOS/LoginStartupCheck'
    executable.parent.mkdir(parents=True)
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    shutil.copytree(sparkle / 'Sparkle.framework', framework, symlinks=True)
    info = {'CFBundleIdentifier': 'io.sleepguard.tests.login-startup',
            'CFBundleName': 'SleepGuard Login Startup Check', 'CFBundleExecutable': executable.name,
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.0.1',
            'LSUIElement': True, 'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False,
            'SUFeedURL': 'http://127.0.0.1:1/disabled.xml'}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    sources = sorted(file for file in source.glob('*.swift') if file.name != 'SleepGuardApp.swift')
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-target', platform.machine() + '-apple-macosx13.0',
                    '-module-cache-path', str(project / 'work/swift-cache'),
                    '-F', str(app / 'Contents/Frameworks'), '-framework', 'Sparkle',
                    '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                    '-o', str(executable), *map(str, sources),
                    str(project / 'macos/Tests/LoginItemServiceFixture.swift'),
                    str(project / 'macos/Tests/LoginStartupChecks.swift')], check=True)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    fixture_state = root / 'fixture-state'
    fixture_state.mkdir()
    fixture_config = root / 'fixture-config.toml'

    def fixture(command):
        result = subprocess.run([str(args.backend.resolve()), 'ui', command, '--config', str(fixture_config),
                                 '--state-dir', str(fixture_state)], capture_output=True, text=True,
                                check=True, timeout=20)
        return json.loads(result.stdout)

    config = fixture('config')
    config['revision'] = 'private-login-startup-fixture'
    (root / 'config.json').write_text(json.dumps(config))
    status = fixture('status')
    status['watcher_running'] = False
    (root / 'status.json').write_text(json.dumps(status))
    mock = root / 'mock-backend.py'
    mock.write_text('#!' + sys.executable + '\n' + textwrap.dedent('''\
        import json, os, pathlib, sys
        root = pathlib.Path(__file__).parent
        state = pathlib.Path(os.environ['SLEEPGUARD_STATE_DIR'])
        config = pathlib.Path(os.environ['SLEEPGUARD_CONFIG'])
        assert state.is_relative_to(root) and config.is_relative_to(root)
        args = sys.argv[1:]
        assert args[args.index('--config') + 1] == str(config)
        assert args[args.index('--state-dir') + 1] == str(state)
        with (state / 'calls.jsonl').open('a') as calls:
            calls.write(json.dumps(args) + '\\n')
        operation = args[:2]
        if operation == ['ui', 'config']:
            print((root / 'config.json').read_text())
        elif operation == ['ui', 'status']:
            result = json.loads((root / 'status.json').read_text())
            result['watcher_running'] = (state / 'watcher').read_text() == 'running'
            result['config_path'], result['state_dir'] = str(config), str(state)
            print(json.dumps(result))
        elif operation == ['watch', '--exit-on-stdin-close']:
            (state / 'watcher').write_text('running')
            sys.stdin.buffer.read()
            (state / 'watcher').write_text('stopped')
            with (state / 'calls.jsonl').open('a') as calls:
                calls.write(json.dumps(['monitor-exited']) + '\\n')
        else:
            raise SystemExit('Unexpected isolated backend command: ' + repr(args))
        '''))
    mock.chmod(0o700)
    base_environment = os.environ | {'SLEEPGUARD_BACKEND': str(mock)}

    def check(mode):
        state = root / mode
        state.mkdir(exist_ok=True)
        environment = base_environment | {'SLEEPGUARD_STATE_DIR': str(state),
                                          'SLEEPGUARD_CONFIG': str(state / 'config.toml')}
        result = subprocess.run([str(executable), mode], capture_output=True, text=True,
                                env=environment, timeout=40)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        print(result.stdout.strip(), flush=True)

    for mode in ['manual', 'login-disabled', 'login-enabled', 'already-running', 'recovery-stopped',
                 'recovery-expired', 'recovery-corrupt', 'disable-preserves-monitor', 'quit-preserves-login',
                 'update-preparation-stopped', 'update-preparation-running']:
        check(mode)
print('Production login startup checks passed using a fake registry; system login items untouched.')
