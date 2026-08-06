# Contributing

Follow the step-by-step setup, development, runtime test, Test Lab, and packaging
workflow in [DEVELOPMENT.md](DEVELOPMENT.md). Run `./scripts/validate.sh` before
opening a pull request. Runtime changes must be tested in X4 9.00 with UI
Extensions and HUD 9.00+ and must not copy or replace Egosoft or dependency
source files. Prefix runtime diagnostics with `[X4GC]`.

On Windows, use `scripts\launch-x4-dev.bat` for runtime testing so loose files
and `[X4GC]` diagnostics are enabled consistently. Linux developers should use
the equivalent arguments documented in [DEVELOPMENT.md](DEVELOPMENT.md).

Use `./scripts/package.sh 0.20` to create a Nexus-ready ZIP. Please include the
output of `scripts/filter-gunnery-log.sh`, ship/bridge/turret details, game
version, and active mod list in bug reports.
