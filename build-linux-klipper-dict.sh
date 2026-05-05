#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KLIPPER_DIR=${KLIPPER_DIR:-$SCRIPT_DIR}
DEST_DICT=${DEST_DICT:-/mnt/c/Users/marc4/rust/vulkan01/assets/klipper-dict.bin}

cd "$KLIPPER_DIR"

if ! command -v gcc >/dev/null 2>&1; then
    echo "error: gcc not found; run this script in WSL/Linux with build tools installed" >&2
    exit 1
fi
if ! command -v make >/dev/null 2>&1; then
    echo "error: make not found; run this script in WSL/Linux with build tools installed" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found; run this script in WSL/Linux with python3 installed" >&2
    exit 1
fi

python3 - <<'PY'
from pathlib import Path

config_path = Path(".config")
settings = {
    "CONFIG_MACH_LINUX": "y",
    "CONFIG_MACH_SIMU": None,
    "CONFIG_BOARD_DIRECTORY": '"linux"',
    "CONFIG_CLOCK_FREQ": "50000000",
    "CONFIG_LINUX_SELECT": "y",
}

lines = config_path.read_text().splitlines() if config_path.exists() else []
seen = set()
out = []

for line in lines:
    key = None
    if line.startswith("CONFIG_") and "=" in line:
        key = line.split("=", 1)[0]
    elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
        key = line[len("# "):].split(" ", 1)[0]

    if key in settings:
        value = settings[key]
        out.append(f"# {key} is not set" if value is None else f"{key}={value}")
        seen.add(key)
    else:
        out.append(line)

for key, value in settings.items():
    if key not in seen:
        out.append(f"# {key} is not set" if value is None else f"{key}={value}")

config_path.write_text("\n".join(out) + "\n")
PY

make olddefconfig
make clean
make

python3 - <<'PY'
import pathlib
import zlib

src = pathlib.Path("out/klipper.dict")
dst = pathlib.Path("out/data_dictionary.bin")
data = src.read_bytes()
dst.write_bytes(zlib.compress(data, 9))
print(f"wrote {dst} ({dst.stat().st_size} bytes, {len(data)} bytes decompressed)")
PY

mkdir -p "$(dirname -- "$DEST_DICT")"
cp out/data_dictionary.bin "$DEST_DICT"
echo "copied out/data_dictionary.bin -> $DEST_DICT"
