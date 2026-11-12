## The place a tool paints at, a summoned docker opens at and a dragged docker
## follows comes from the cursor policy, so a pen the display server does not
## report is where they all answer from.
##
## On a Windows tablet a pen painted at one
## point, a summoned docker opened in the same place wherever the pen was, and
## a docker dragged with the pen did not move. Under Windows Ink the pen moves
## the window's events and not the pointer the display server reports, and
## every one of the three asked the display server. The ring was right all
## along, because it asked `SaCursorPolicy`.
##
## A pen is fed to the policy the way `CursorOverlay._input` feeds it, with a
## tilt so the policy knows it for a pen, at places the display server has
## never heard of.
##
## A mouse is put where each case says through
## [member SaPointerDevice.suite_pointer], so what is read is the policy's
## carrying of that place. A part that compares the policy with Godot's own
## reading of the live pointer runs only where the suite could put the live
## pointer there, and says so on the suite's line where it could not. On the
## Windows desktop of 2026-10-01 the two reads came out thousands apart near
## x -1.85e9 and failed three cases.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The folders whose readers must ask the policy, and the one file that may ask
## the display server on their behalf.
const POLICED_ROOTS: Array[String] = ["render", "ui/main", "ui/dockers"]
const THE_POLICY: String = "render/cursor/sa_pointer_device.gd"
const THE_CALL: String = "DisplayServer.mouse_get_position"

const PEN_ONE := Vector2(311.0, 207.0)
const PEN_TWO := Vector2(642.5, 118.25)
## Where the suite puts the mouse, and where it tries to put the live pointer.
## Apart, so a reader that ignored the first could not pass on the second.
const MOUSE := Vector2(523.0, 287.0)
const LIVE := Vector2(380.0, 230.0)
const LIVE_SKIP := (
    "the live pointer did not go where the suite put it, so a mouse was not compared with Godot's reading of it,"
    + " and the pointer probe line says where it went"
)

var _host: Node = null
var _previous_embed: bool = true


func before_each() -> void:
    _previous_embed = SaSettings.embed_subwindows
    SaCursorPolicy.forget_pointer_device()
    DockerDragHandle.capture_pointer = null
    _host = Node.new()
    _host.name = "PointerFromThePolicyTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    SaCursorPolicy.forget_pointer_device()
    SaSettings.embed_subwindows = _previous_embed
    if _host != null:
        _host.free()
        _host = null


func _window() -> Window:
    var window := Window.new()
    window.borderless = true
    window.size = Vector2i(1280, 720)
    window.gui_embed_subwindows = true
    _host.add_child(window)
    window.show()
    return window


## Puts the suite's mouse at *at* in *window*.
func _mouse_at(window: Window, at: Vector2) -> void:
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(window)
    SaPointerDevice.suite_pointer = to_desktop * at


## Puts the live pointer at *at* in *window* as far as the desktop lets a suite:
## a parsed motion moves the pointer Godot reports under Wayland, and a warp
## moves it under X11. True when Godot then reads it there. False, with the
## part skipped and the reason on the suite's line, when it does not, since two
## reads of a place nobody put the pointer at agree only by luck.
func _live_pointer_at(window: Window, at: Vector2) -> bool:
    SaPointerDevice.suite_pointer = null
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    Input.parse_input_event(motion)
    Input.flush_buffered_events()
    if not window.get_mouse_position().is_equal_approx(at):
        window.warp_mouse(at)
    if window.get_mouse_position().is_equal_approx(at):
        return true
    skip(LIVE_SKIP)
    return false


func _pen_at(window: Window, at: Vector2) -> void:
    var motion := InputEventMouseMotion.new()
    motion.tilt = Vector2(0.2, -0.1)
    motion.position = at
    SaCursorPolicy.note_pointer_device(motion, window)


func test_no_reader_asks_the_display_server_but_the_policy() -> void:
    var offenders: Array[String] = []
    for root: String in POLICED_ROOTS:
        var found: Array[String] = []
        _walk(ProjectSettings.globalize_path("res://").path_join(root), root + "/", found)
        for path: String in found:
            if path != THE_POLICY and _code(_read(ProjectSettings.globalize_path("res://").path_join(path))).contains(THE_CALL):
                offenders.append(path)
    assert_true(offenders.is_empty(), "Asks the display server instead of the policy: %s" % ", ".join(offenders))


func test_the_canvas_view_answers_from_the_pen() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    window.add_child(canvas)
    canvas.scale = Vector2(2.0, 2.0)
    canvas.position = Vector2(100.0, 40.0)
    var view := SaCanvasView.for_canvas(canvas)

    if _live_pointer_at(window, LIVE):
        assert_eq(view.get_document_mouse_position(), canvas.get_local_mouse_position(), "A mouse is Godot's answer")
    _mouse_at(window, MOUSE)
    assert_true(
        view.get_document_mouse_position().is_equal_approx(Vector2(211.5, 123.5)),
        "A mouse the suite put down is read through the canvas, less the pan, halved"
    )
    for pen: Vector2 in [PEN_ONE, PEN_TWO]:
        _pen_at(window, pen)
        var expected := canvas.get_global_transform_with_canvas().affine_inverse() * pen
        assert_true(view.get_document_mouse_position().is_equal_approx(expected), "The document place is the pen's at %s" % pen)
    assert_true(
        view.get_document_mouse_position().is_equal_approx(Vector2(271.25, 39.125)), "which is the pen less the pan, halved"
    )


func test_the_summon_answers_from_the_pen() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    var summon := DockerSummon.new(null)
    window.add_child(summon)

    SaSettings.embed_subwindows = true
    if _live_pointer_at(window, LIVE):
        assert_eq(summon.pointer(), window.get_mouse_position(), "A mouse over embedded dockers is Godot's answer")
    _mouse_at(window, MOUSE)
    assert_true(summon.pointer().is_equal_approx(MOUSE), "A mouse the suite put down is the summon's place")
    _pen_at(window, PEN_ONE)
    assert_eq(summon.pointer(), PEN_ONE, "and the pen's is the pen's own place")

    # Letting the dockers out lets this window out of the root as well, onto
    # the desktop at its own place, so the pen's place is taken again there. The
    # one kept before was read through the root's place, and a root window that
    # is not at the desktop's corner, as under an X server, moved the first read
    # by the root's place and not by the pen's travel.
    SaSettings.embed_subwindows = false
    _pen_at(window, PEN_ONE)
    var first := summon.pointer()
    _pen_at(window, PEN_TWO)
    var second := summon.pointer()
    assert_true((second - first).is_equal_approx(PEN_TWO - PEN_ONE), "On the desktop the place moves with the pen")
    var desktop := Vector2(_outer(window).position) + window.get_screen_transform() * PEN_TWO
    assert_true(second.is_equal_approx(desktop), "and is where the pen is on the desktop")


func test_the_drag_handle_answers_from_the_pen_in_the_docker() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var window := _window()
    var docker := Window.new()
    docker.size = Vector2i(300, 200)
    docker.position = Vector2i(400, 150)
    window.add_child(docker)
    docker.show()
    assert_true(docker.is_embedded(), "The docker is drawn inside its window, the embedded case")

    if _live_pointer_at(window, LIVE):
        assert_eq(DockerDragHandle.pointer_in_parent_space_of(docker), window.get_mouse_position(), "A mouse is Godot's answer")
    _mouse_at(window, MOUSE)
    assert_true(
        DockerDragHandle.pointer_in_parent_space_of(docker).is_equal_approx(MOUSE),
        "A mouse the suite put down is read in the docker's window"
    )
    _pen_at(docker, Vector2(20.0, 10.0))
    var pressed := DockerDragHandle.pointer_in_parent_space_of(docker)
    assert_true(pressed.is_equal_approx(Vector2(420.0, 160.0)), "The pen in the docker, in its window's space")

    # The drag moves the docker, and the pen's place must not move with it until
    # the pen itself does, or every step would add the last one to itself.
    docker.position += Vector2i(35, 25)
    var held := DockerDragHandle.pointer_in_parent_space_of(docker)
    assert_true(held.is_equal_approx(pressed), "A docker moved under a still pen leaves the pen where it was")
    _pen_at(docker, Vector2(20.0, 10.0))
    assert_true(
        DockerDragHandle.pointer_in_parent_space_of(docker).is_equal_approx(Vector2(455.0, 185.0)),
        "and the pen's next motion is read against where the docker is now"
    )


func test_the_pens_tip_coming_down_is_where_the_stroke_begins() -> void:
    var window := _window()
    _pen_at(window, PEN_ONE)
    var tip := InputEventMouseButton.new()
    tip.button_index = MOUSE_BUTTON_LEFT
    tip.pressed = true
    tip.position = PEN_TWO
    SaCursorPolicy.note_pointer_device(tip, window)
    assert_true(SaCursorPolicy.pointer_is_tablet, "A button says nothing of the device")
    assert_eq(SaCursorPolicy.pointer_in(window), PEN_TWO, "The press is read where it landed, not at the last hover")


func test_a_space_the_pen_cannot_be_carried_into_keeps_godots_answer() -> void:
    var loose := Control.new()
    _pen_at(null, PEN_ONE)
    assert_true(SaCursorPolicy.pointer_is_tablet, "A pen with no window is still a pen")
    assert_eq(SaCursorPolicy.pointer_in(loose), Vector2.ZERO, "A control in no tree has no pointer")
    loose.free()


## Not a check but a line on the log, "pointer probe", of what the live
## pointer reads before and after a warp to the middle of the root window, with
## that window's place, size and focus, so a desktop where a suite cannot put
## the pointer names why.
##
## Read it this way. A warp the driver refused for want of a focused window
## reads "not focused" and the same place after as before, which Godot's
## Windows driver does: its `warp_mouse` returns at once without one. A root
## window placed far out shows in its own place. A read of nothing shows as a
## place far out that changes between two reads with no hand on the mouse, and
## the two words after it are that read's y and x in hex, so a value that is
## really an address left in memory reads as one.
func test_the_live_pointer_goes_to_the_log() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var root := (Engine.get_main_loop() as SceneTree).root
    var target := root.get_visible_rect().get_center()
    var before := DisplayServer.mouse_get_position()
    var again := DisplayServer.mouse_get_position()
    root.warp_mouse(target)
    var after := DisplayServer.mouse_get_position()
    var seen := [
        DisplayServer.get_name(),
        root.position,
        root.size,
        "focused" if root.has_focus() else "not focused",
        before,
        again,
        before.y & 0xFFFFFFFF,
        before.x & 0xFFFFFFFF,
        target,
        after,
        root.get_mouse_position(),
    ]
    var line := (
        "pointer probe: %s, the root window at %s size %s %s. The display server read %s and then %s,"
        + " words 0x%08x 0x%08x. After a warp to %s it read %s, and the root viewport read %s."
    )
    print(line % seen)


## Every `.gd` under *dir_path*, relative to the project.
func _walk(dir_path: String, prefix: String, out: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var entry := dir.get_next()
    while not entry.is_empty():
        if dir.current_is_dir():
            if entry != "tests":
                _walk(dir_path.path_join(entry), prefix + entry + "/", out)
        elif entry.get_extension() == "gd":
            out.append(prefix + entry)
        entry = dir.get_next()


## The file with its comment lines removed, so a comment naming the call is not
## a call.
func _code(text: String) -> String:
    var kept: Array[String] = []
    for line in text.split("\n"):
        if not line.strip_edges().begins_with("#"):
            kept.append(line)
    return "\n".join(kept)


func _read(absolute: String) -> String:
    var file := FileAccess.open(absolute, FileAccess.READ)
    return file.get_as_text() if file != null else ""


## The window of its own *window* is drawn in, whose desktop place its screen
## transform leaves out.
func _outer(window: Window) -> Window:
    var outer := window
    while outer.is_embedded():
        outer = outer.get_parent().get_viewport() as Window
    return outer
