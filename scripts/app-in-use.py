#!/usr/bin/env python3
"""Refuse to replace a bundle while its executable or bundled monitor is alive."""
import pathlib
import subprocess
import sys


def running_processes(bundle):
    prefix = str(pathlib.Path(bundle).resolve()) + '/'
    result = subprocess.run(['/bin/ps', '-ww', '-axo', 'pid=,comm='],
                            check=True, capture_output=True, text=True)
    matches = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[1].startswith('/') and str(pathlib.Path(parts[1]).resolve()).startswith(prefix):
            matches.append((int(parts[0]), parts[1]))
    return matches


if __name__ == '__main__':
    processes = running_processes(sys.argv[1])
    if processes:
        print('Cannot replace a running SleepGuard bundle:', file=sys.stderr)
        for pid, executable in processes:
            print(f'  PID {pid}: {executable}', file=sys.stderr)
        print('Quit SleepGuard and stop its monitor, or build to another APP_OUTPUT path.', file=sys.stderr)
        sys.exit(1)
