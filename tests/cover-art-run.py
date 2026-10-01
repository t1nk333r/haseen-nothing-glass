# Bound the whole probe process group, including a wedged Qt network/decode
# worker that keeps stdout open after its parent is terminated.
import os
import signal
import subprocess
import sys

probe = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=True)
try:
    output, _ = probe.communicate(timeout=60)
except subprocess.TimeoutExpired:
    os.killpg(probe.pid, signal.SIGKILL)
    try:
        output, _ = probe.communicate(timeout=5)
    except subprocess.TimeoutExpired as error:
        output = error.output or b""
        probe.stdout.close()
sys.stdout.buffer.write(output)
sys.exit(probe.returncode if probe.returncode is not None and probe.returncode >= 0 else 1)
