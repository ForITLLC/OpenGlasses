#!/bin/bash
# PREPARED ONLY: explicit top-bar-fix capture GO and lane ownership are required.
set -eu
case ${1:-} in
  -h | --help)
    printf '%s\n' \
      'Prepared only; requires explicit top-bar-fix capture GO and an owned simulator.' \
      'Usage: mark-capture-boot-guard.sh <original boot-slot label and arguments...>' \
      'Focused grant/lane route: CI_SIM_BOOT_SLOT=/absolute/path/to/this/script' \
      'Device matrix route: MATRIX_BOOT_SLOT=/absolute/path/to/this/script' \
      'Checks load1 < 40 and free Data space >= 30 GiB before and after the real slot.' \
      'Does not boot, retry, grant permission, or change global hooks.'
    exit 0 ;;
esac
exec python3 - "$@" <<'PY'
import os, subprocess, sys

REAL_SLOT = "/Users/Shared/ci-sim/ci-sim-boot-slot.sh"
DATA_VOLUME = "/System/Volumes/Data"
MIN_FREE = 30 * 1024 ** 3
REFUSED = 75

def capacity(stage):
    try:
        load = os.getloadavg()[0]
        volume = os.statvfs(DATA_VOLUME)
        free = volume.f_bavail * volume.f_frsize
    except OSError as error:
        print(f"mark-capture guard {stage}: capacity probe failed: {error}", file=sys.stderr, flush=True)
        return False
    passed = load < 40 and free >= MIN_FREE
    print(f"mark-capture guard {stage}: load1={load:.2f}, Data free={free / 1024 ** 3:.2f} GiB, "
          f"{'PASS' if passed else 'REFUSED'} (requires load1 < 40 and free >= 30 GiB)",
          file=sys.stderr, flush=True)
    return passed

if not capacity("before"):
    sys.exit(REFUSED)
try:
    # Merge and buffer both streams: ci-sim-grant validates the final raw grant line
    # in merged output, so no guard diagnostic may follow the authentic replay.
    delegated = subprocess.run([REAL_SLOT, *sys.argv[1:]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
except OSError as error:
    print(f"mark-capture guard: real boot slot unavailable: {error}", file=sys.stderr, flush=True)
    sys.exit(REFUSED)
after_ok = capacity("after")
code = delegated.returncode
if code < 0:
    code = 128 - code
if code == 0 and not after_ok:
    code = REFUSED
sys.stdout.buffer.write(delegated.stdout)
sys.stdout.buffer.flush()
sys.exit(code)
PY
