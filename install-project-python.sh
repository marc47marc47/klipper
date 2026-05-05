#!/usr/bin/env sh
set -eu

PYTHON_VERSION="${PYTHON_VERSION:-3.10}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR="$SCRIPT_DIR"
UV_DIR="$ROOT_DIR/.uv"
UV_BIN_DIR="$UV_DIR/bin"
PYTHON_INSTALL_DIR="$UV_DIR/python"
VENV_DIR="$ROOT_DIR/.venv"
UV="$UV_BIN_DIR/uv"

case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*)
        UV="$UV_BIN_DIR/uv.exe"
        ;;
esac

mkdir -p "$UV_BIN_DIR" "$PYTHON_INSTALL_DIR"

if [ ! -x "$UV" ]; then
    if command -v uv >/dev/null 2>&1; then
        cp "$(command -v uv)" "$UV"
        chmod +x "$UV" 2>/dev/null || true
    else
        if command -v curl >/dev/null 2>&1; then
            curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$UV_BIN_DIR" sh
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://astral.sh/uv/install.sh | UV_INSTALL_DIR="$UV_BIN_DIR" sh
        else
            echo "error: curl or wget is required to install uv" >&2
            exit 1
        fi
    fi
fi

if [ ! -x "$UV" ]; then
    echo "error: uv was not installed at $UV" >&2
    exit 1
fi

printf '%s\n' "$PYTHON_VERSION" > "$ROOT_DIR/.python-version"

echo "Installing Python $PYTHON_VERSION into $PYTHON_INSTALL_DIR"
echo "Using uv: $UV"

VIRTUAL_ENV= UV_PYTHON_INSTALL_DIR="$PYTHON_INSTALL_DIR" \
    "$UV" python install "$PYTHON_VERSION" \
    --install-dir "$PYTHON_INSTALL_DIR" \
    --no-bin

VIRTUAL_ENV= UV_PYTHON_INSTALL_DIR="$PYTHON_INSTALL_DIR" \
    "$UV" python find "$PYTHON_VERSION"

if [ ! -e "$VENV_DIR" ]; then
    VIRTUAL_ENV= UV_PYTHON_INSTALL_DIR="$PYTHON_INSTALL_DIR" \
        "$UV" venv --python "$PYTHON_VERSION" "$VENV_DIR"
else
    echo "Virtual environment already exists: $VENV_DIR"
fi

VIRTUAL_ENV= UV_PYTHON_INSTALL_DIR="$PYTHON_INSTALL_DIR" \
    "$UV" run --python "$PYTHON_VERSION" python --version

echo
echo "Environment ready."
echo "Enable it in the current shell with:"
echo "  . scripts/setenv.python"
