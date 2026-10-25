#!/usr/bin/env python3
"""Bound CI test runs and preserve native stacks when a runner stalls."""
import os
from pathlib import Path
import signal
import subprocess
import sys


def descendants(parent):
    lines = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid="], text=True).splitlines()
    pairs = [tuple(map(int, line.split())) for line in lines if len(line.split()) == 2]
    found = {parent}
    while True:
        expanded = found | {pid for pid, ppid in pairs if ppid in found}
        if expanded == found:
            return sorted(found)
        found = expanded


def main():
    command = sys.argv[1:] or ["./scripts/test.sh", "-Xswiftc", "-warnings-as-errors"]
    timeout = int(os.environ.get("FILEORBIT_CI_TEST_TIMEOUT", "240"))
    process = subprocess.Popen(command, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"::error::Tests exceeded {timeout}s; capturing descendant stacks before termination.", flush=True)
        destination = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "fileorbit-test-stacks"
        destination.mkdir(parents=True, exist_ok=True)
        for pid in descendants(process.pid):
            path = destination / f"sample-{pid}.txt"
            try:
                subprocess.run(["/usr/bin/sample", str(pid), "2", "-file", str(path)], timeout=12, check=False)
                if path.exists():
                    print(f"::group::Native stack {pid}", flush=True)
                    print("\n".join(path.read_text(errors="replace").splitlines()[:450]), flush=True)
                    print("::endgroup::", flush=True)
            except (OSError, subprocess.TimeoutExpired) as error:
                print(f"Could not sample {pid}: {error}", flush=True)
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return 124


if __name__ == "__main__":
    sys.exit(main())
