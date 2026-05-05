#!/usr/bin/env sh
# Build Klipper host (klippy + chelper) and optionally MCU firmware.
#
# Detects the host OS and architecture and produces artifacts for the
# current platform. Supports Linux, macOS, Windows (MinGW/MSYS2) on
# x64 and arm/arm64.
#
# Usage:
#   ./build.sh                # build host artifacts (chelper c_helper.so)
#   ./build.sh --firmware     # also build MCU firmware (requires .config)
#   ./build.sh --no-python    # skip Python venv setup
#   ./build.sh --clean        # remove .venv/.uv/out/c_helper.so first
#
# Env overrides:
#   PYTHON_VERSION  Python version installed by install-project-python.sh
#                   (default 3.10).
#   KLIPPER_GCC     Path to a specific gcc to use for chelper compile.
#                   Useful on Windows when picking ucrt64 vs mingw64.

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

WANT_FIRMWARE=0
WANT_PYTHON=1
WANT_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --firmware|-f)   WANT_FIRMWARE=1 ;;
        --no-python|-N)  WANT_PYTHON=0 ;;
        --clean|-c)      WANT_CLEAN=1 ;;
        --help|-h)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *)
            echo "build.sh: unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

# ---------- Detect host OS / arch ----------
case "$(uname -s 2>/dev/null || printf unknown)" in
    Linux*)               OS=linux ;;
    Darwin*)              OS=macos ;;
    MINGW*|MSYS*|CYGWIN*) OS=windows ;;
    *)                    OS=unknown ;;
esac

ARCH=$(uname -m 2>/dev/null || printf unknown)
case "$ARCH" in
    x86_64|amd64)         ARCH=x64 ;;
    aarch64|arm64)        ARCH=arm64 ;;
    armv7l|armv7|armv6l)  ARCH=arm ;;
    i?86)                 ARCH=x86 ;;
esac

echo "[build] platform: $OS/$ARCH"

# ---------- Optional clean ----------
if [ "$WANT_CLEAN" = "1" ]; then
    echo "[build] cleaning .venv/.uv/out and chelper artifacts"
    rm -rf .venv .uv out
    rm -f klippy/chelper/c_helper.so klippy/chelper/_temp_c_helper.so
fi

# ---------- Python venv ----------
if [ "$WANT_PYTHON" = "1" ]; then
    if [ ! -d .venv ]; then
        echo "[build] installing project Python via uv"
        sh ./install-project-python.sh
    else
        echo "[build] reusing existing .venv"
    fi
    # Pick python interpreter for this run.
    if [ -x .venv/Scripts/python.exe ]; then
        PYTHON=.venv/Scripts/python.exe
    elif [ -x .venv/bin/python ]; then
        PYTHON=.venv/bin/python
    else
        echo "[build] error: python interpreter not found in .venv" >&2
        exit 1
    fi
else
    PYTHON=$(command -v python3 || command -v python || echo python)
fi
echo "[build] python: $PYTHON"

# ---------- Pre-build chelper c_helper.so ----------
# klippy normally compiles c_helper.so on first launch. Pre-building
# catches toolchain issues now and gives pack.sh a complete artifact.
echo "[build] compiling klippy/chelper/c_helper.so for $OS/$ARCH"
"$PYTHON" - <<'PY'
import os, sys, logging
logging.basicConfig(level=logging.INFO, format='[chelper] %(message)s')
sys.path.insert(0, 'klippy')
import chelper
chelper.get_ffi()
size = os.path.getsize('klippy/chelper/c_helper.so')
print('[build] chelper: %d bytes' % size)
PY

# ---------- Optional MCU firmware ----------
if [ "$WANT_FIRMWARE" = "1" ]; then
    if [ ! -f .config ]; then
        echo "[build] error: --firmware requested but .config not found" >&2
        echo "[build]   run 'make menuconfig' first to choose an MCU target" >&2
        exit 1
    fi
    if ! command -v make >/dev/null 2>&1; then
        echo "[build] error: --firmware requested but make is not installed" >&2
        exit 1
    fi
    echo "[build] building MCU firmware via make"
    make
    echo "[build] MCU firmware built in out/"
fi

echo "[build] done: $OS/$ARCH"
