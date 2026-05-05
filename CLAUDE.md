# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this fork is

This is a fork of upstream Klipper (`Klipper3d/klipper`) carrying a **Windows-native port of Klippy (host)** and a tooling layer for running Klippy against a Rust-based MCU simulator. It does *not* fork the MCU firmware side — `src/` is upstream as-is.

The big-picture layering this fork participates in:

- **L3 — Klippy host** (this repo, `klippy/`): Python event loop + C helper. Now runs natively on Windows.
- **L2 — Web API gateway**: replaced by Rust `klipper-rs` at `C:/Users/marc4/rust/klipper-rs/` (Moonraker drop-in).
- **L1 — Web UI**: Mainsail, served by `klipper-rs`.
- **MCU**: usually `vulkan01` Rust simulator at `C:/Users/marc4/rust/vulkan01/` for native dev; real boards via `make`.

When debugging end-to-end issues, remember the boundary: real hardware uses serial/CAN; this dev setup uses **TCP** for both the MCU link and the G-code input.

## Common commands

### Klippy host (the active development surface)

```bash
./build.sh                 # set up .venv via uv, prebuild klippy/chelper/c_helper.so
./build.sh --clean         # nuke .venv/.uv/out + chelper artifacts and rebuild
./build.sh --firmware      # also run `make` (needs .config from menuconfig)
./start.sh                 # launch klippy against klipper-mcu-test.cfg
./start.sh path/to/printer.cfg
./test-gcode.sh ./stanless-steel-pin.gcode    # stream G-code to klippy's TCP input
```

`start.sh` listens for G-code on **`tcp://127.0.0.1:7126`** and expects an MCU listener on **127.0.0.1:7878** (overridable via `KLIPPY_GCODE_PORT` / `KLIPPY_MCU_PORT`). Default config is `klipper-mcu-test.cfg`, which `[include]`s `C:/Users/marc4/rust/vulkan01/config/klipper-mcu.cfg` and adds `[force_move]` + `[respond]` so test G-code can skip `G28` (the sim has no endstops).

### MCU firmware (upstream flow, unchanged)

```bash
make menuconfig            # pick MCU
make                       # produces out/klipper.bin / .hex / .uf2 etc.
make flash                 # board-specific
make clean
```

### Tests / lint (upstream flow)

```bash
./scripts/check_whitespace.sh
~/klippy-env/bin/python ./scripts/test_klippy.py -d dict/ ./test/klippy/*.test
```

`test_klippy.py` needs a data-dictionary tar from <https://github.com/Klipper3d/klipper/issues/1438>. To run a single test, point at the specific `.test` file: `… test_klippy.py -d dict/ test/klippy/move.test`.

### Trace switch

`KLIPPER_TRACE_IO=1` recompiles chelper with `-DKLIPPER_TRACE_IO` for verbose framing logs (set the env var, then delete `klippy/chelper/c_helper.so` to force a rebuild).

## Windows-specific architecture

The Windows port is concentrated in a small number of files; understand these before touching anything cross-platform:

- **`klippy/chelper/__init__.py`** — selects a real **MinGW-w64 ucrt64** gcc (NOT msys `/usr/bin/gcc`, whose `msys-2.0.dll` segfaults inside native CPython). Walks a candidate list, injects the toolchain `bin/` into `PATH` so `cc1` finds `libisl/libmpc/libmpfr`, then compiles `c_helper.so`. Override with `KLIPPY_GCC=...`.
- **`klippy/chelper/chelper_win.def`** — renames the wrapper `chelper_free` export back to `free`. On Windows we keep `--export-all-symbols` (without `-fwhole-program`, which strips libc symbols) and use this `.def` so `cffi.dlopen` can still resolve `free`.
- **`klippy/chelper/serialqueue.c`, `pollreactor.c`, `pyhelper.c`** — `WSAPoll` instead of `poll`; only `POLLIN/POLLOUT` are sent in (Windows rejects `POLLHUP` as input); a TCP-based emulated `socketpair` replaces `os.pipe` (WSAPoll can't poll OS pipes); links `-lws2_32`.
- **`klippy/util.py`** — `termios`/`fcntl`/`pty` are now lazy imports; `set_nonblock` has a Windows branch.
- **`klippy/reactor.py`** — uses `socket.socketpair` instead of `os.pipe` for the cross-thread wakeup.
- **`klippy/gcode.py`, `klippy/webhooks.py`** — accept `tcp://host:port` for input/API server (the original UNIX domain socket / PTY is POSIX-only). This is the contract `klipper-rs` consumes.
- **`klippy/serialhdl.py`** — `serial_for_url()` resolves `socket://host:port` so `[mcu] serial=...` can speak to a TCP MCU sim.
- **`klippy/extras/statistics.py`** — guards `os.getloadavg()` (Windows lacks it).
- **`src/linux/main.c`** — `mlockall` calls gated on `MCL_*` macros so the Linux-MCU build still cross-compiles cleanly from a non-glibc shell.

When making cross-platform changes to `klippy/`, the rule is: **POSIX-only modules (`termios`, `fcntl`, `pty`, `os.getloadavg`, `os.pipe` for cross-thread wakeup) must be lazy-imported or branched on `os.name == 'nt'`**, and any new socket I/O on Windows must go through TCP, not UNIX-domain or pipe FDs.

## Klippy webhooks contract (what L2 talks to)

`klippy/webhooks.py` exposes ETX-delimited (`\x03`) JSON-RPC over TCP when started with `-a tcp://host:port`. Key facts the Rust L2 relies on:

- Frame delimiter is the byte `\x03`, not newline.
- Every request must carry an `id`; the response carries the same `id`.
- Push notifications (no `id`) come from `register_remote_method` subscriptions; they are how `objects/subscribe` deltas are delivered.
- See `webhooks.py:273` (`process_received`), `:307` (`send`), `:340–504` (built-in endpoints), `:407–449` (remote-method push model) for the canonical implementation.

Do not change framing or these endpoints without coordinating with `klipper-rs`.

## Python environment

`./build.sh` provisions a hermetic environment via `uv`:

- `.uv/` — `uv` binary + downloaded CPython.
- `.venv/` — virtual env (`scripts/python.exe` on Windows, `bin/python` elsewhere).
- `.python-version` — pinned (default 3.10, overridable via `PYTHON_VERSION`).
- `scripts/setenv.python` / `setenv.python.ps1` — `source` these to put the venv on PATH.

Don't pip-install into the system Python; always work via `.venv` (`start.sh` and `test-gcode.sh` auto-detect it).

## Custom files vs. upstream

These files live at the repo root and are **specific to this fork** — they don't exist upstream:

```
build.sh, pack.sh, start.sh, test-gcode.sh        # dev workflow
install-project-python.sh / .ps1                  # uv-based Python provisioning
build-linux-klipper-dict.sh                       # produces out/klipper.dict for L2
klipper-mcu-test.cfg                              # vulkan01 + force_move + respond
stanless-steel-pin.gcode                          # canned test workload
DEVELOP.md, DEVELOP-v1.md, DEVELOP-to-rust.md     # design + Rust-rewrite analysis
scripts/setenv.python, setenv.python.ps1          # venv activators
scripts/install-project-python.{sh,ps1}           # mirror of root version
klippy/chelper/chelper_win.def                    # Windows export-table rename
```

When adding new dev-loop scripts, mirror the existing pattern (POSIX `sh`, `set -eu`, detect `.venv/Scripts/python.exe` vs `.venv/bin/python`, fall back to system `python3`).

## Coding conventions (upstream `docs/CONTRIBUTING.md`)

- Address root cause, not symptoms. No experimental PRs.
- Don't leave commented-out code, debug prints, or `// TODO ...` clutter.
- Comments explain *why*, not *what*.
- Every commit needs `Signed-off-by` (DCO).
- All regression tests in `test/klippy/` must pass.

For Windows port changes specifically: avoid Windows-only behaviour drift. If a code path needs to behave differently on Windows, branch on `os.name == 'nt'` (Python) or `_WIN32` / `__MINGW32__` (C); don't fork files. Keep upstream-mergeability in mind.

## Where to read first

- `DEVELOP.md` — current snapshot of architecture + build outputs (most accurate of the three DEVELOP files).
- `DEVELOP-v1.md` — earlier overview, includes recent-development focus areas (eddy-current probe, trigger_analog).
- `DEVELOP-to-rust.md` — Rust-rewrite feasibility analysis (informational, no active work in this repo).
- `docs/Code_Overview.md`, `docs/Protocol.md`, `docs/API_Server.md`, `docs/MCU_Commands.md` — upstream canonical docs.
