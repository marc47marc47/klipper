Welcome to the Klipper project!

[![Klipper](docs/img/klipper-logo-small.png)](https://www.klipper3d.org/)

https://www.klipper3d.org/

The Klipper firmware controls 3d-Printers. It combines the power of a
general purpose computer with one or more micro-controllers. See the
[features document](https://www.klipper3d.org/Features.html) for more
information on why you should use the Klipper software.

Start by [installing Klipper software](https://www.klipper3d.org/Installation.html).

Klipper software is Free Software. See the [license](COPYING) or read
the [documentation](https://www.klipper3d.org/Overview.html). We
depend on the generous support from our
[sponsors](https://www.klipper3d.org/Sponsors.html).

---

## About this fork

This fork carries a **Windows-native port of Klippy (host)** plus a small dev
tooling layer for running Klippy against a Rust-based MCU simulator. The MCU
firmware side (`src/`) is upstream as-is.

Big-picture layering this fork participates in:

- **L3 — Klippy host** (this repo, `klippy/`): now runs natively on Windows;
  exposes ETX JSON-RPC over TCP and accepts G-code over TCP.
- **L2 — Web API gateway**: [`klipper-rs`](https://github.com/marc47marc47/klipper-rs)
  (Rust, Moonraker drop-in).
- **L1 — Web UI**: Mainsail, served by `klipper-rs`.
- **MCU**: usually the `vulkan01` Rust simulator for native dev; real boards
  via `make` (unchanged from upstream).

Quick start (Windows / MSYS2 shell):

```sh
./build.sh                              # provision .venv via uv, build chelper
./start.sh                              # launch klippy against klipper-mcu-test.cfg
./test-gcode.sh ./stanless-steel-pin.gcode    # stream a test workload
```

Read [`CLAUDE.md`](CLAUDE.md) for the architecture & contributor guide,
[`DEVELOP.md`](DEVELOP.md) for the codebase walkthrough, and
[`DEVELOP-to-rust.md`](DEVELOP-to-rust.md) for the Rust-rewrite feasibility
analysis.
