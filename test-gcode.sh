#!/usr/bin/env sh
# Stream a G-code file to klippy's TCP G-code input and capture the response.
#
# Usage:
#   ./test-gcode.sh                                 # default file + port
#   ./test-gcode.sh ./stanless-steel-pin.gcode      # specific file
#   KLIPPY_HOST=10.0.0.5 ./test-gcode.sh
#   KLIPPY_GCODE_PORT=7200 ./test-gcode.sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

GCODE_FILE="${1:-./stanless-steel-pin.gcode}"
HOST="${KLIPPY_HOST:-127.0.0.1}"
PORT="${KLIPPY_GCODE_PORT:-7126}"
DRAIN_SECS="${KLIPPY_DRAIN_SECS:-60}"

if [ ! -f "$GCODE_FILE" ]; then
    echo "[test] error: G-code file not found: $GCODE_FILE" >&2
    exit 1
fi

if [ -x .venv/Scripts/python.exe ]; then
    PYTHON=.venv/Scripts/python.exe
elif [ -x .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    PYTHON=$(command -v python3 || command -v python)
fi

echo "[test] file:  $GCODE_FILE"
echo "[test] target: $HOST:$PORT"

exec "$PYTHON" - "$HOST" "$PORT" "$GCODE_FILE" "$DRAIN_SECS" <<'PY'
import socket, sys, time

host  = sys.argv[1]
port  = int(sys.argv[2])
path  = sys.argv[3]
drain = float(sys.argv[4])

with open(path, 'r', encoding='utf-8') as f:
    raw_lines = f.readlines()

# Strip ';' comments and blank lines so we don't spam the parser.
def clean(line):
    return line.split(';', 1)[0].strip()

cmds = [c for c in (clean(l) for l in raw_lines) if c]
if not cmds:
    print('[test] no executable G-code lines after stripping comments')
    sys.exit(1)

print('[test] sending %d command(s)' % len(cmds))

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5.0)
try:
    s.connect((host, port))
except OSError as e:
    print('[test] error: cannot connect to %s:%d -- %s' % (host, port, e))
    print('[test]   is klippy running? start it with ./start.sh')
    sys.exit(1)

payload = ('\n'.join(cmds) + '\n').encode()
s.sendall(payload)

# Drain responses until we have one ok per submitted command, or
# DRAIN_SECS elapses with no new traffic.
expected_oks = sum(1 for c in cmds if not c.startswith(('//', '#')))

deadline = time.time() + drain
buf = b''
last_data = time.time()
s.settimeout(0.3)
while time.time() < deadline:
    try:
        chunk = s.recv(8192)
    except socket.timeout:
        # Got every ack and nothing new arrived recently -> done.
        if buf.count(b'ok') >= expected_oks and time.time() - last_data > 0.5:
            break
        # Still missing acks: only bail if the link has been idle a long time.
        if time.time() - last_data > 5.0:
            break
        continue
    if not chunk:
        break
    buf += chunk
    last_data = time.time()

s.close()

text = buf.decode(errors='replace')
print('--- klippy response (%d bytes) ---' % len(buf))
print(text if text else '(no response)')
print('--- summary ---')
ok_count   = text.count('\nok') + (1 if text.startswith('ok') else 0)
err_count  = text.lower().count('!! ')
print('ok-lines: %d  expected: %d' % (ok_count, expected_oks))
print('error-lines: %d' % err_count)
PY
