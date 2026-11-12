## A running Sara's reading of the lock, one reading at a time. A holder
## whose lock names another live Sara lost a race and stops listening, and a
## watcher whose lock names nobody alive takes it. Two real Saras taking it
## over are
## `scripts/test_the_sara_still_on_the_screen_takes_the_single_instance_lock_over_when_the_holder_closes.py`.
extends "res://tests/test_framework.gd"

static var lock: String = ProjectSettings.globalize_path(SaDataRoot.path("probe_running.json"))

## A process that runs and is not this one, the system's first on Linux.
const ANOTHER := 1


func after_each() -> void:
    DirAccess.remove_absolute(lock)


func _write(fields: Dictionary) -> void:
    var file := FileAccess.open(lock, FileAccess.WRITE)
    file.store_string(JSON.stringify(fields))
    file.close()


func _pid() -> int:
    return int(SaSingleInstance.read_lock(lock).get("pid", 0))


func test_a_holder_that_lost_the_race_goes_back_to_watching() -> void:
    if not SaProcess.runs(ANOTHER):
        skip("no process %d to stand for the other Sara" % ANOTHER)
        return
    var listener := SaSingleInstance.Listener.new(lock, true)
    assert_true(listener.listening(), "it holds the lock")
    assert_eq(_pid(), OS.get_process_id(), "which names it")
    listener.watch()
    assert_true(listener.listening(), "its own lock keeps it holding")
    _write({"pid": ANOTHER, "port": 9, "token": "theirs"})
    listener.watch()
    assert_false(listener.listening(), "a lock another live Sara wrote over sends it back to watching")
    assert_eq(_pid(), ANOTHER, "and it leaves that lock as it is")
    listener.free()


func test_a_watcher_takes_the_lock_once_its_holder_is_gone() -> void:
    if not SaProcess.runs(ANOTHER):
        skip("no process %d to stand for the other Sara" % ANOTHER)
        return
    _write({"pid": ANOTHER, "port": 9, "token": "theirs"})
    var listener := SaSingleInstance.Listener.new(lock, false)
    assert_false(listener.listening(), "beside a live holder it only watches")
    listener.watch()
    assert_false(listener.listening(), "and goes on watching while the holder runs")
    _write({"pid": 2147483000, "port": 9, "token": "theirs"})
    listener.watch()
    assert_true(listener.listening(), "a lock naming a process that ended is taken")
    var held := SaSingleInstance.read_lock(lock)
    assert_eq(int(held.get("pid", 0)), OS.get_process_id(), "the lock names it now")
    assert_true(str(held.get("token", "")) != "theirs", "with a token of its own")
    listener.free()


func test_a_holder_whose_lock_went_writes_it_again() -> void:
    var listener := SaSingleInstance.Listener.new(lock, true)
    DirAccess.remove_absolute(lock)
    listener.watch()
    assert_true(listener.listening(), "it still listens")
    assert_eq(_pid(), OS.get_process_id(), "and the lock is back")
    listener.free()
