#!/usr/bin/env python3
"""Check the bundled monitor entry point using only a private config/store."""
import json
import pathlib
import plistlib
import subprocess
import tempfile

project = pathlib.Path(__file__).resolve().parent.parent
app = project / 'dist/SleepGuard.app'
agent = plistlib.loads((app / 'Contents/Library/LaunchAgents/io.sleepguard.app.agent.plist').read_bytes())
monitor = app / agent['BundleProgram']
assert monitor.is_file() and monitor.name != 'SleepGuard'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with tempfile.TemporaryDirectory(prefix='sleepguard-package-') as directory:
    root = pathlib.Path(directory)
    result = subprocess.run([str(monitor), 'ui', 'config', '--config', str(root / 'config.toml'),
                             '--state-dir', str(root / 'state')], capture_output=True, text=True,
                            check=True, timeout=10)
    assert json.loads(result.stdout)['config']['monitor']['interval']
    assert not (root / 'config.toml').exists()
print('Package checks passed (signed helper, private config, bundled Go entry point)')
