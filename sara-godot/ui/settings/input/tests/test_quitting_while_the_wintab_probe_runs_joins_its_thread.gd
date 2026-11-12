## Quitting while the WinTab look runs joins its thread.
##
## The look runs a PowerShell helper on a thread from every launch on WinTab,
## and only its answer, a frame later, joins that thread. A Sara that
## quit first would leave the thread running and the engine said so at exit. Linux has
## no PowerShell, so the look is started here with a stand-in for the helper.
extends "res://tests/test_framework.gd"


func after_each() -> void:
    SaTabletDriver.stop_looking()
    SaTabletDriver.ask = Callable()
    SaTabletDriver._falls_back("")


## Waits two engine frames, so an answer the thread queued has run.
func _two_frames() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var start := Engine.get_process_frames()
    for i in 6:
        if Engine.get_process_frames() >= start + 2:
            return
        await tree.process_frame


func test_a_quit_while_the_helper_is_still_out_joins_the_thread() -> void:
    SaTabletDriver.ask = func(_path: String) -> String:
        OS.delay_msec(1000)
        return "failed"
    SaTabletDriver.look_at("wintab32.dll")
    var thread: Thread = SaTabletDriver._looking
    assert_not_null(thread, "the look started a thread")
    assert_true(thread.is_started(), "the thread runs while the stand-in sleeps")
    SaTabletDriver.stop_looking()
    assert_false(thread.is_started(), "the quit joined the thread")
    assert_null(SaTabletDriver._looking, "no thread is held after the quit")
    await _two_frames()
    assert_null(SaTabletDriver._looking, "the queued answer took no thread")
    assert_eq(SaTabletDriver.wintab_found, "", "the answer of a look let go is dropped")


func test_an_answer_that_came_first_leaves_the_quit_nothing_to_join() -> void:
    SaTabletDriver.ask = func(_path: String) -> String: return "open"
    SaTabletDriver.look_at("wintab32.dll")
    var thread: Thread = SaTabletDriver._looking
    assert_not_null(thread, "the look started a thread")
    var tree := Engine.get_main_loop() as SceneTree
    for i in 120:
        if SaTabletDriver._looking == null:
            break
        await tree.process_frame
    assert_null(SaTabletDriver._looking, "the answer joined the thread")
    assert_false(thread.is_started(), "the answer's join ended the thread")
    assert_eq(SaTabletDriver.wintab_found, "open", "the answer was kept")
    SaTabletDriver.stop_looking()
    assert_null(SaTabletDriver._looking, "the quit after the answer changed nothing")
    assert_eq(SaTabletDriver.wintab_found, "open", "the quit after the answer kept it")


func test_a_quit_with_no_look_started_does_nothing() -> void:
    assert_null(SaTabletDriver._looking, "no look runs before the case")
    SaTabletDriver.stop_looking()
    assert_null(SaTabletDriver._looking, "the quit started nothing")
    assert_eq(SaTabletDriver.wintab_found, "", "the quit wrote no answer")
