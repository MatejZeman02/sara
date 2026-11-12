## Android keeps one instance of an app by itself and Sara asks it for no
## network, so a listener told it runs there never listens, never watches and
## writes no lock, where every listen would print two engine errors.
extends "res://tests/test_framework.gd"

static var lock: String = ProjectSettings.globalize_path(SaDataRoot.path("android_probe_running.json"))


func after_each() -> void:
    DirAccess.remove_absolute(lock)


func test_a_listener_on_android_takes_no_lock_however_often_it_watches() -> void:
    DirAccess.remove_absolute(lock)
    var listener := SaSingleInstance.Listener.new(lock, true, "Android")
    assert_false(listener.listening(), "asked to hold, it does not listen")
    for reading in 3:
        listener.watch()
    assert_false(listener.listening(), "three watches later it still does not")
    assert_false(FileAccess.file_exists(lock), "and no lock was written")
    listener.free()


func test_a_listener_on_android_leaves_another_s_lock_alone() -> void:
    var file := FileAccess.open(lock, FileAccess.WRITE)
    file.store_string(JSON.stringify({"pid": 2147483000, "port": 9, "token": "theirs"}))
    file.close()
    var listener := SaSingleInstance.Listener.new(lock, false, "Android")
    for reading in 3:
        listener.watch()
    assert_false(listener.listening(), "a lock naming a process that ended is not taken")
    assert_eq(str(SaSingleInstance.read_lock(lock).get("token", "")), "theirs", "and stays as it was")
    listener.free()


func test_the_same_listener_on_a_desktop_holds_the_lock() -> void:
    var listener := SaSingleInstance.Listener.new(lock, true, "Linux")
    assert_true(listener.listening(), "a desktop keeps its lock")
    assert_eq(int(SaSingleInstance.read_lock(lock).get("pid", 0)), OS.get_process_id(), "which names it")
    listener.free()
