## Whether a process runs, asked of a process that is not this one's child.
##
## The door's known file and the run log both name the Sara that holds them by
## its process id, and both ask this whether that Sara still runs. Here rather
## than beside the known file, because `core` never names the harness, and the
## question is the platform's rather than the door's.
class_name SaProcess
extends RefCounted


## Whether a process of that id runs, asked in the way each platform answers
## for a process that is not this one's child. The engine's own
## `OS.is_process_running` answers for a child only: on Linux it waits on the
## id and says the process is not a child, as an engine error, and on Windows
## it looks the id up among the processes this one started and answers false
## for any other, read in `platform/windows/os_windows.cpp` of the engine's
## 4.7 build. Asked there, it would tell a second Sara nothing of a first.
##
## Windows is asked through its task list, whose one line for a live process
## carries the id in quotes whatever language the system speaks. That starts a
## process, so the run log asks only when its file names a Sara that has not
## closed it, which after a clean close it never does.
static func runs(pid: int) -> bool:
    match OS.get_name():
        "Windows":
            var output: Array = []
            OS.execute("tasklist", PackedStringArray(["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"]), output)
            return not output.is_empty() and str(output[0]).contains('"%d"' % pid)
        "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
            return DirAccess.dir_exists_absolute("/proc/%d" % pid)
        _:
            return OS.execute("kill", PackedStringArray(["-0", str(pid)])) == 0


## Whether *pid* names a process that runs and is not this one.
static func another_runs(pid: int) -> bool:
    return pid > 0 and pid != OS.get_process_id() and runs(pid)
