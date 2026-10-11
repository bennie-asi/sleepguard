#!/usr/bin/env python3
"""Exercise the production login controller using an in-memory service adapter.

Does not create an app bundle, register a login item, or access the system registry.
"""
import pathlib
import platform
import subprocess
import tempfile

project = pathlib.Path(__file__).resolve().parent.parent
source = project / 'macos/Sources/SleepGuard'

with tempfile.TemporaryDirectory(prefix='sleepguard-login-check-') as directory:
    executable = pathlib.Path(directory) / 'login-check'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-target', platform.machine() + '-apple-macosx13.0',
                    '-module-cache-path', str(project / 'work/swift-cache'), '-o', str(executable),
                    *map(str, [source / 'LoginItem.swift',
                               project / 'macos/Tests/LoginItemServiceFixture.swift',
                               project / 'macos/Tests/LoginItemChecks.swift',
                               project / 'macos/Tests/CheckSupport.swift'])], check=True)
    subprocess.run([str(executable)], check=True, timeout=20)
