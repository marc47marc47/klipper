#!/usr/bin/env sh
# Start Klippy connected to a Linux-MCU style simulator over TCP.
#
# Default wiring:
#   Klippy G-code TCP input  : 127.0.0.1:7126
#   MCU  (xyz-gripper, etc.) : 127.0.0.1:7878
#
# Prerequisite: the MCU process must already be listening on $MCU_PORT.
# E.g. on the Windows side:
#     cd /c/Users/marc4/rust/vulkan01
#     cargo run --release -- --klipper-tcp 7878
#
# Usage:
#   ./start.sh                        # use default klipper-mcu.cfg
#   ./start.sh path/to/printer.cfg    # use a specific cfg
#   KLIPPY_GCODE_PORT=7200 ./start.sh # override TCP G-code port
#   KLIPPY_MCU_PORT=7900   ./start.sh # override MCU TCP port (cosmetic --
#                                       cfg's [mcu] serial=... is the truth)
#   KLIPPY_LOG=/tmp/klippy.log ./start.sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

CONFIG="${1:-$ROOT_DIR/klipper-mcu-test.cfg}"
LOG="${KLIPPY_LOG:-/tmp/klippy.log}"
GCODE_PORT="${KLIPPY_GCODE_PORT:-7126}"
MCU_PORT="${KLIPPY_MCU_PORT:-7878}"

if [ ! -f "$CONFIG" ]; then
    echo "[start] error: config not found: $CONFIG" >&2
    exit 1
fi

# Pick python from the project's .venv (created by install-project-python.sh
# / build.sh). Fall back to system python if missing.
if [ -x .venv/Scripts/python.exe ]; then
    PYTHON=.venv/Scripts/python.exe
elif [ -x .venv/bin/python ]; then
    PYTHON=.venv/bin/python
else
    echo "[start] warning: .venv not found - run ./build.sh first" >&2
    PYTHON=$(command -v python3 || command -v python || echo python)
fi

# Liveness probe of the MCU port (best-effort).
"$PYTHON" - "$MCU_PORT" <<'PY' || true
import socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.5)
try:
    s.connect(('127.0.0.1', port))
    s.close()
    print('[start] MCU listener is up on 127.0.0.1:%d' % port)
except OSError as e:
    print('[start] warning: nothing listening on 127.0.0.1:%d (%s)' % (port, e))
    print('[start]   start the MCU first, e.g. `xyz-gripper --klipper-tcp %d`' % port)
PY

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
: > "$LOG"

echo "[start] config:    $CONFIG"
echo "[start] python:    $PYTHON"
echo "[start] gcode tcp: 127.0.0.1:$GCODE_PORT"
echo "[start] mcu tcp:   127.0.0.1:$MCU_PORT (configured in [mcu] serial=)"
echo "[start] log:       $LOG"
echo "[start] launching klippy..."

exec "$PYTHON" klippy/klippy.py \
    -I "tcp://127.0.0.1:$GCODE_PORT" \
    -l "$LOG" \
    "$CONFIG"
