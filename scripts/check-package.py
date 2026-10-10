#!/usr/bin/env python3
"""Check the bundled monitor entry point using only a private config/store."""
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile

project = pathlib.Path(__file__).resolve().parent.parent
app = pathlib.Path(os.environ.get('APP_OUTPUT', project / 'dist/SleepGuard.app'))
bundle = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = os.environ.get('VERSION', (project / 'VERSION').read_text().strip())
assert bundle['CFBundleShortVersionString'] == version
assert bundle['SUPublicEDKey']
assert bundle['SUFeedURL'].endswith(('appcast-arm64.xml', 'appcast-x86_64.xml'))
assert (app / 'Contents/Frameworks/Sparkle.framework').is_dir()
agent = plistlib.loads((app / 'Contents/Library/LaunchAgents/io.sleepguard.app.agent.plist').read_bytes())
monitor = app / agent['BundleProgram']
assert monitor.is_file() and monitor.name != 'SleepGuard'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
backend = app / 'Contents/Resources/sleepguard'
version_info = json.loads(subprocess.run([str(backend), 'version', '--json'], capture_output=True,
                                         text=True, check=True, timeout=10).stdout)
assert version_info == {'version': version, 'build': bundle['CFBundleVersion']}
with tempfile.TemporaryDirectory(prefix='sleepguard-package-') as directory:
    root = pathlib.Path(directory)
    result = subprocess.run([str(monitor), 'ui', 'config', '--config', str(root / 'config.toml'),
                             '--state-dir', str(root / 'state')], capture_output=True, text=True,
                            check=True, timeout=10)
    assert json.loads(result.stdout)['config']['monitor']['interval']
    assert not (root / 'config.toml').exists()
print('Package checks passed (signed helper, private config, bundled Go entry point)')
