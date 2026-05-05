#!/usr/bin/env sh
# Package Klipper host + (optional) MCU firmware into a distributable
# archive for the current OS/arch.
#
# Output: dist/klipper-<os>-<arch>-<version>.{tar.gz,zip}
#
# Usage:
#   ./pack.sh                # build host + pack
#   ./pack.sh --firmware     # also bundle MCU firmware (requires .config)
#   ./pack.sh --skip-build   # skip running build.sh first
#   ./pack.sh --zip          # force zip archive (default tar.gz on unix,
#                              zip on windows)
#   ./pack.sh --tar          # force tar.gz
#
# Result archive layout:
#   klipper-<os>-<arch>-<version>/
#       klippy/                  (host code, with prebuilt c_helper.so)
#       src/                     (MCU sources, for rebuild)
#       config/                  (sample printer.cfg files)
#       scripts/                 (helpers, except install-* moved to root)
#       docs/                    (if present)
#       Makefile
#       install-project-python.sh
#       install-project-python.ps1
#       build.sh
#       COPYING, README.md       (if present)
#       out/                     (firmware artifacts, only with --firmware)
#       VERSION                  (git describe + build platform)

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"

WANT_FIRMWARE=0
WANT_BUILD=1
ARCHIVE_FMT=auto
for arg in "$@"; do
    case "$arg" in
        --firmware|-f)    WANT_FIRMWARE=1 ;;
        --skip-build|-S)  WANT_BUILD=0 ;;
        --zip)            ARCHIVE_FMT=zip ;;
        --tar)            ARCHIVE_FMT=tar ;;
        --help|-h)
            sed -n '2,28p' "$0"
            exit 0
            ;;
        *)
            echo "pack.sh: unknown argument: $arg" >&2
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

if [ "$ARCHIVE_FMT" = "auto" ]; then
    case "$OS" in
        windows) ARCHIVE_FMT=zip ;;
        *)       ARCHIVE_FMT=tar ;;
    esac
fi

VERSION=$(git -C "$ROOT_DIR" describe --always --tags --dirty 2>/dev/null \
          || cat "$ROOT_DIR/klippy/.version" 2>/dev/null \
          || printf unknown)

echo "[pack] platform: $OS/$ARCH"
echo "[pack] version:  $VERSION"
echo "[pack] format:   $ARCHIVE_FMT"

# ---------- Build first ----------
if [ "$WANT_BUILD" = "1" ]; then
    BUILD_ARGS=
    [ "$WANT_FIRMWARE" = "1" ] && BUILD_ARGS=--firmware
    sh "$ROOT_DIR/build.sh" $BUILD_ARGS
fi

# ---------- Stage ----------
PKG_NAME="klipper-${OS}-${ARCH}-${VERSION}"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/$PKG_NAME"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

echo "[pack] staging into $STAGE_DIR"

copy_if_present() {
    src=$1
    if [ -e "$src" ]; then
        cp -R "$src" "$STAGE_DIR/"
    fi
}

# Required: host code + native helper
cp -R klippy "$STAGE_DIR/"
# Strip __pycache__ and stray .pyc to keep package small.
find "$STAGE_DIR/klippy" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$STAGE_DIR/klippy" -type f -name '*.pyc' -delete 2>/dev/null || true
# Drop the temp build artifact if present.
rm -f "$STAGE_DIR/klippy/chelper/_temp_c_helper.so"
if [ ! -e "$STAGE_DIR/klippy/chelper/c_helper.so" ]; then
    echo "[pack] warning: klippy/chelper/c_helper.so missing -- run build.sh first" >&2
fi

# Required: MCU sources + build system, install/build scripts, config
copy_if_present src
copy_if_present scripts
copy_if_present config
copy_if_present docs
copy_if_present Makefile
copy_if_present install-project-python.sh
copy_if_present install-project-python.ps1
copy_if_present build.sh
copy_if_present COPYING
copy_if_present README.md

# Optional: bundle firmware artifacts
if [ "$WANT_FIRMWARE" = "1" ]; then
    if [ -d out ]; then
        mkdir -p "$STAGE_DIR/out"
        for f in klipper.elf klipper.bin klipper.elf.hex klipper.uf2 \
                 klipper.dict autoconf.h; do
            [ -f "out/$f" ] && cp "out/$f" "$STAGE_DIR/out/"
        done
    else
        echo "[pack] warning: --firmware requested but out/ does not exist" >&2
    fi
fi

# Manifest
cat > "$STAGE_DIR/VERSION" <<EOF
klipper $VERSION
platform: $OS/$ARCH
built: $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)
EOF

# ---------- Archive ----------
case "$ARCHIVE_FMT" in
    zip)
        ARCHIVE="$DIST_DIR/${PKG_NAME}.zip"
        rm -f "$ARCHIVE"
        if command -v zip >/dev/null 2>&1; then
            (cd "$DIST_DIR" && zip -qr "${PKG_NAME}.zip" "$PKG_NAME")
        elif command -v 7z >/dev/null 2>&1; then
            (cd "$DIST_DIR" && 7z a -tzip -bd "${PKG_NAME}.zip" "$PKG_NAME" >/dev/null)
        elif command -v powershell >/dev/null 2>&1; then
            powershell -NoProfile -Command "Compress-Archive -Force -Path '$STAGE_DIR' -DestinationPath '$ARCHIVE'"
        else
            echo "[pack] error: need zip, 7z, or powershell to build a .zip" >&2
            exit 1
        fi
        ;;
    tar)
        ARCHIVE="$DIST_DIR/${PKG_NAME}.tar.gz"
        rm -f "$ARCHIVE"
        (cd "$DIST_DIR" && tar -czf "${PKG_NAME}.tar.gz" "$PKG_NAME")
        ;;
esac

# Optionally keep stage dir for inspection; remove to save space.
rm -rf "$STAGE_DIR"

echo "[pack] wrote $ARCHIVE"
ls -la "$ARCHIVE"
