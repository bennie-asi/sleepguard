#!/usr/bin/env python3
"""Exercise the build guard with only a disposable executable."""
import pathlib
import runpy
import subprocess
import tempfile
import time

project = pathlib.Path(__file__).resolve().parent.parent
find = runpy.run_path(str(project / 'scripts/app-in-use.py'))['running_processes']
with tempfile.TemporaryDirectory(prefix='sleepguard-build-guard-') as folder:
    root = pathlib.Path(folder)
    bundle = root / 'Fixture.app'
    executable = bundle / 'Contents/MacOS/fixture'
    executable.parent.mkdir(parents=True)
    subprocess.run(['clang', str(project / 'macos/Tests/MonitorFixture.c'), '-o', str(executable)], check=True)
    assert not find(bundle)
    child = subprocess.Popen([str(executable), '60'])
    try:
        time.sleep(.1)
        assert any(pid == child.pid for pid, _ in find(bundle))
        assert not find(root / 'Other.app')
        executable.unlink()
        assert any(pid == child.pid for pid, _ in find(bundle)), 'Unlinked executable must still be protected'
    finally:
        child.terminate()
        child.wait(timeout=5)
    assert not find(bundle)
print('Build guard passed: live, unrelated, unlinked and exited processes')
