#!/usr/bin/env python3
"""Bound a benchmark probe without changing its arguments or success contract."""
import os
import signal
import subprocess
import sys

def main():
    limit = int(sys.argv[1])
    if not 1 <= limit <= 3600 or len(sys.argv) < 3:
        return 2
    process = subprocess.Popen(sys.argv[2:], start_new_session=True)
    try:
        return process.wait(timeout=limit)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124
    except BaseException:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait()
        raise

if __name__ == "__main__":
    sys.exit(main())
