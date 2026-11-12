## The frame cap comes off while the hand moves and goes back on when it stops.
##
## The presentation half of the ring's lag. Mailbox and the two-image swapchain
## are settings, and what a run can say about those is that they took, which the
## scenario's `pacer` dump does. The fallback where mailbox is refused is a rule,
## and is held here. What has logic in it is the countdown: the cap
## has to come off on the first motion, stay off through a stroke, and come back
## a fifth of a second after the hand stops, and it has to come back to whatever
## the profile had rather than to a number written here.
##
## `scenarios/present-without-the-queue.json` drives the real app, where the
## dump reads `mailbox`, a swapchain of 2, and `max_fps` at the display's refresh
## rate under motion on a capture's fresh profile, 0 once Uncapped is chosen, and
## 100 at rest. **Neither this suite nor that scenario is the judge of the lag.**
## `scripts/ring_lag.py` is, on a real desktop.
extends "res://tests/test_framework.gd"


## A pacer that was never added to the tree, so no `_process` runs under the
## assertions and the countdown is stepped by hand. `_ready` is called
## explicitly, because that is where the resting values are read. The frame
## rate while painting is pinned to Uncapped, which is what "the cap comes off"
## means in every case here. It is a choice rather than the
## default, so a fresh profile would cap at the display's refresh rate instead.
func _pacer(resting_fps: int = 100, resting_low: bool = false) -> SaFramePacer:
    var previous_fps := Engine.max_fps
    var previous_low := OS.low_processor_usage_mode
    var previous_rate := SaSettings.painting_frame_rate
    SaSettings.painting_frame_rate = SaSettingsPerformance.UNCAPPED
    Engine.max_fps = resting_fps
    OS.low_processor_usage_mode = resting_low
    var pacer := SaFramePacer.new()
    pacer._ready()
    # Kept on the node rather than in a member, because every case here builds
    # its own pacer and `_drop` is what puts the engine back either way.
    pacer.set_meta("previous_fps", previous_fps)
    pacer.set_meta("previous_low", previous_low)
    pacer.set_meta("previous_rate", previous_rate)
    return pacer


func _drop(pacer: SaFramePacer) -> void:
    Engine.max_fps = int(pacer.get_meta("previous_fps"))
    OS.low_processor_usage_mode = bool(pacer.get_meta("previous_low"))
    SaSettings.painting_frame_rate = String(pacer.get_meta("previous_rate"))
    pacer.free()


func test_the_resting_values_are_read_rather_than_assumed() -> void:
    var pacer := _pacer(72, true)
    assert_eq(pacer.resting_max_fps, 72, "The cap the profile had is the one to put back")
    assert_true(pacer.resting_low_processor, "and so is the low-processor mode")
    _drop(pacer)


func test_the_first_motion_takes_the_cap_off() -> void:
    var pacer := _pacer(100, false)
    assert_false(pacer.is_moving(), "A pacer starts at rest")

    pacer.note_motion()
    assert_true(pacer.is_moving(), "One motion event is the hand moving")
    assert_eq(Engine.max_fps, 0, "and the cap comes off")
    _drop(pacer)


func test_the_cap_comes_back_a_fifth_of_a_second_after_the_hand_stops() -> void:
    var pacer := _pacer(100, false)
    pacer.note_motion()

    for _i in SaFramePacer.IDLE_FRAMES - 1:
        pacer._process(0.016)
        assert_eq(Engine.max_fps, 0, "Still moving, so the cap is still off")
    pacer._process(0.016)

    assert_false(pacer.is_moving(), "Twelve frames with no motion is a hand that has stopped")
    assert_eq(Engine.max_fps, 100, "and the cap is back")
    _drop(pacer)


## The pause at the top of a stroke while the hand changes direction must not
## drop the cap back on and lose a frame to it.
func test_a_motion_part_way_through_the_countdown_restarts_it() -> void:
    var pacer := _pacer(100, false)
    pacer.note_motion()
    for _i in SaFramePacer.IDLE_FRAMES - 2:
        pacer._process(0.016)
    assert_true(pacer.is_moving(), "Two frames short of resting")

    pacer.note_motion()
    for _i in SaFramePacer.IDLE_FRAMES - 1:
        pacer._process(0.016)
    assert_true(pacer.is_moving(), "and the count started again rather than carrying on")
    assert_eq(Engine.max_fps, 0, "so the cap never came back")
    _drop(pacer)


## A pacer freed while the hand was moving would otherwise leave the engine
## uncapped for the rest of the session.
func test_leaving_the_tree_puts_the_cap_back() -> void:
    var pacer := _pacer(100, false)
    pacer.note_motion()
    assert_eq(Engine.max_fps, 0, "Uncapped while moving")

    pacer.rest()
    assert_eq(Engine.max_fps, 100, "and capped again the moment it rests")
    _drop(pacer)


func test_a_host_gets_one_pacer_however_often_it_is_asked() -> void:
    var host := Node.new()
    host.name = "A2PacerHost"

    var first := SaFramePacer.attach_to(host)
    var second := SaFramePacer.attach_to(host)
    assert_eq(first, second, "The second call finds the first pacer rather than adding another")
    assert_eq(host.get_child_count(), 1, "so the host has one")
    assert_null(SaFramePacer.attach_to(null), "and a host that is not there gets none")

    host.free()


## The project setting, read when the swapchain is made and therefore the one
## half of the setting a test can only read.
func test_the_swapchain_asks_for_two_images() -> void:
    assert_eq(SaFramePacer.swapchain_image_count(), 2, "Two rather than the engine's three")


## Where mailbox is refused, no vsync under XWayland and enabled elsewhere. `ring_lag.py` read the ring 60 ms
## behind the pointer under
## XWayland's FIFO and 1 ms with no vsync, and a compositor flips whole frames
## so nothing tears there. A bare X11 session may have no compositor to stop a
## tear, and Windows is to be measured on Windows.
func test_the_fallback_drops_the_vsync_only_under_a_compositor() -> void:
    assert_eq(SaFramePacer.fallback_mode("X11", true), DisplayServer.VSYNC_DISABLED, "XWayland: the compositor has its own vsync")
    assert_eq(SaFramePacer.fallback_mode("X11", false), DisplayServer.VSYNC_ENABLED, "bare X11 may have no compositor")
    assert_eq(SaFramePacer.fallback_mode("Windows", false), DisplayServer.VSYNC_ENABLED, "Windows until it is measured")
    assert_eq(SaFramePacer.fallback_mode("Wayland", true), DisplayServer.VSYNC_ENABLED, "Wayland has never refused mailbox")


## The driver's answer is read once it has drawn with it, and what is put in
## then. A refusal read on the line that asked was never seen: the window
## reports the mode asked for until the next frame rebuilds its swapchain.
func test_the_fallback_goes_in_once_the_driver_has_answered() -> void:
    var enabled := DisplayServer.VSYNC_ENABLED
    var mailbox := DisplayServer.VSYNC_MAILBOX
    assert_eq(SaFramePacer.settled_mode(enabled, enabled, "X11", true), DisplayServer.VSYNC_DISABLED, "XWayland refused mailbox")
    assert_eq(SaFramePacer.settled_mode(enabled, mailbox, "X11", true), -1, "mailbox granted is left")
    assert_eq(SaFramePacer.settled_mode(enabled, enabled, "Windows", false), -1, "enabled is already the fallback")
    assert_eq(
        SaFramePacer.settled_mode(DisplayServer.VSYNC_DISABLED, enabled, "X11", true), -1, "a mode the project chose is left"
    )

    var pacer := _pacer(100, false)
    pacer._process(0.016)
    assert_false(pacer.vsync_settled, "No frame was drawn, so nothing is read yet")
    _drop(pacer)


## The project asks for the engine's default, so the pacer asks for mailbox,
## and an `override.cfg` that asked for another mode would be left alone.
func test_the_project_leaves_the_mode_to_the_pacer() -> void:
    assert_eq(SaFramePacer.project_vsync_mode(), DisplayServer.VSYNC_ENABLED, "project.godot sets no vsync mode")
    var dump := SaFramePacer.capture_state(Engine.get_main_loop() as SceneTree)
    assert_true(dump.contains('"project_vsync_mode":"enabled"'), "and the dump says what the project asked for")
    assert_true(dump.contains('"vsync_settled":'), "and whether the driver's answer has been read")


## A dump holding `3` says nothing, and which of the four the driver settled on
## is the whole point of the block.
func test_every_vsync_mode_has_a_word() -> void:
    assert_eq(SaFramePacer.vsync_name(DisplayServer.VSYNC_DISABLED), "disabled")
    assert_eq(SaFramePacer.vsync_name(DisplayServer.VSYNC_ENABLED), "enabled")
    assert_eq(SaFramePacer.vsync_name(DisplayServer.VSYNC_ADAPTIVE), "adaptive")
    assert_eq(SaFramePacer.vsync_name(DisplayServer.VSYNC_MAILBOX), "mailbox")
    assert_eq(SaFramePacer.vsync_name(-1), "none, headless", "and a mode nothing answers says so")
