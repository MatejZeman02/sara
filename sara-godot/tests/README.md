# Tests

The suites are GDScript files named `test_*.gd`, run by `run_all.gd`. A suite is named for the behaviour it checks, and the ones for a package sit in that package's own `tests` folder. This folder holds the suites that cross packages, the shared `fixtures.gd`, recorded data under `data` and `fixtures`, the per-GPU picture records under `shots`, and `flakes.txt`.

## Running

```bash
cd sara-godot
SARA_TEST_OFFSCREEN=1 ./run_tests.sh              # every suite
SARA_TEST_OFFSCREEN=1 ./run_tests.sh transform    # the suites whose names hold the word
```

A clean run exits with 0. Read the exit code, not the summary line, because a run that leaked objects or lost a suite to a parse error must still fail. On Windows use `run_tests.ps1`.

Most suites need a Vulkan device, and Godot cannot create one under `--headless`. `SARA_TEST_OFFSCREEN=1` starts a nested headless `weston` compositor so the run opens no window on your desktop and several runs can share a machine. Without it the run maps a fullscreen window. `cage` or `sway --headless` would work as well as `weston`.

## Why the script has limits

`run_tests.sh` bounds a run in three ways, each set by an environment variable, so that a broken suite fails the run quickly instead of hanging or filling the machine.

- **Time.** Godot exits only when `run_all.gd` quits the tree, so a script that fails to parse or a suite that blocks on a window hangs it. A watchdog fails the run after `SARA_TEST_TIMEOUT` seconds, 1980 by default, three times a loaded full run, which takes about 650 seconds with other runs on the machine. The number errs long, because a false timeout is a worse bug than the hang. There is no per-suite timeout, since GDScript runs on the main thread and a blocked suite blocks the runner that would interrupt it.
- **Output.** A loop on one suite's script error can fill `/tmp`, which on a tmpfs is memory. `scripts/run_log_ceiling.py` stops the engine past `SARA_TEST_LOG_CEILING_MB` of output (256 by default, far above any run that ends on its own) or `SARA_TEST_REPEATED_ERRORS` repeats of one error at one place (10000), and keeps the first lines.
- **Memory.** `run_all.gd` reads the engine's resident memory after each suite and prints the peak and the ten suites that grew it most. Past `SARA_TEST_MEMORY_LIMIT_MB` (8400, about twice a full run's peak, 0 for none) the run fails naming the suite that crossed it.

`SARA_SKIP_GITLINK_CHECK=1` turns off the check that no submodule points behind what the commit records, for a checkout pinned back on purpose.
