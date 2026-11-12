## Crashes the process on purpose, so the report a crash leaves can be read
## without waiting for a real one. `SARA_CRASH_ON_PURPOSE=boot` is the switch,
## and what checks it is in [packaging/README.md](../../../packaging/README.md).
##
## Read once, the shape the compiler's `KernelBreak` set, and unlike that one
## live in a release export as well. A release template carries no crash
## handler, and the check can only say so if the crash still happens there:
## gated on a debug build, the release binary sat out the whole timeout and the
## check failed for the wrong reason. A painter reaches the switch only by
## setting an environment variable nobody told them about.
class_name SaCrashProbe
extends RefCounted

## Where the environment asked for a crash, or empty.
static var asked: String = OS.get_environment("SARA_CRASH_ON_PURPOSE")


## Called first thing in `Main._ready`, above the headless return, so a
## binary started with `--headless` reaches it with no display and no GPU.
static func at_boot() -> void:
    if asked != "boot":
        return
    OS.crash("SARA_CRASH_ON_PURPOSE=boot asked Sara to crash at boot, and this is that crash.")
