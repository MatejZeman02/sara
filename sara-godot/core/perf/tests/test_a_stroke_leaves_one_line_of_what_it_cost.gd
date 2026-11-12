## A stroke leaves one line in the log of what it cost.
##
## A painter painted a small brush on Windows for the third sitting running
## and it lagged, and the log held stall lines that said a frame was long and
## not what it was long with. The stroke ledger now keeps the stroke under way
## from the left button's press to the first frame drawn after its release, and
## prints one `Sara stroke:` line: every frame's time, the longest frame split
## into its input and its drawing, the motions and the dabs, the compute lists
## and input to dispatch. These drive the ledger's hooks with frame indices the
## way its own suite does, a test function being unable to wait for a frame,
## and one stroke through the main canvas so the press is the app's own hook.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const FRAME_TIMES_PATH := "res://core/perf/sa_frame_times.gd"

var _host: Node = null
var _main_canvas: Control = null


func before_each() -> void:
    SaStrokeLedger.reset()


func after_each() -> void:
    if _main_canvas != null:
        _main_canvas.tool_machine.registered_tools.clear()
        _main_canvas.tool_machine.active_tool = null
        _main_canvas.tool_machine.registry = null
        _main_canvas = null
    if _host != null:
        _host.free()
        _host = null
    SaStrokeLedger.reset()


## Nineteen frames on time and one freeze: the maximum is the freeze, and the
## 95th percentile is the nineteenth frame, which the mean of the twenty hides.
func test_the_95th_percentile_of_twenty_frames_is_the_nineteenth() -> void:
    var times := SaFrameTimes.new()
    for _i in range(19):
        times.fold(10000)
    times.fold(500000)
    var block := times.block()
    assert_eq(block["count"], 20, "Twenty frames folded")
    assert_eq(block["max"], 500000, "The freeze is the longest")
    assert_eq(block["slow"], 1, "and the one over the budget")
    assert_true(block["p95"] >= 10000, "The 95th percentile holds the nineteenth frame, read %d" % block["p95"])
    assert_true(block["p95"] <= 10450, "to a bucket's 4.4 %%, read %d" % block["p95"])
    assert_eq(times.percentile_usec(1.0), 500000, "The hundredth percentile is the longest, not a bucket's edge past it")
    assert_eq(SaFrameTimes.new().block()["p95"], 0, "No frame folded reads nought")


## Every time from a microsecond to a minute lands in a bucket whose upper
## edge is at or above it, so "95 % took at most this" is true as written.
func test_a_buckets_edge_is_never_below_a_time_it_holds() -> void:
    var usec := 1
    while usec < 60000000:
        var edge := SaFrameTimes.upper_edge(SaFrameTimes.bucket_of(usec))
        if usec < 16777216:
            assert_true(edge >= usec, "%d microseconds is under its bucket's edge %d" % [usec, edge])
            assert_true(edge <= ceili(usec * 1.0444) + 1, "and the edge is a sixteenth of an octave above it at most")
        usec = ceili(usec * 1.37) + 1


## The distribution is a fixed number of integers: ten thousand frames grow
## nothing, which is the ledger's own rule held by its own suite.
func test_the_frame_times_never_grow() -> void:
    var times := SaFrameTimes.new()
    var buckets := times._buckets.size()
    for i in range(10000):
        times.fold(1000 + i * 37)
    assert_eq(times._buckets.size(), buckets, "Ten thousand frames leave the bucket count where it was")
    var source := FileAccess.get_file_as_string(FRAME_TIMES_PATH)
    for banned: String in ["append", "push_back", "insert(", "await", "texture_get_data", "buffer_get_data"]:
        assert_false(source.contains(banned), "The frame times hold no `%s`" % banned)


## A press, four frames of motions and dabs, a release, and the frame that
## shows the release: one stroke of five frames, with its figures whole.
func test_a_stroke_runs_from_the_press_to_the_frame_after_its_release() -> void:
    SaStrokeLedger.frame_drawn(9)
    SaStrokeLedger.event_arrived(false, 10)
    SaStrokeLedger.left_button(_button(true), 10)
    SaStrokeLedger.dab_dispatched(1, 10)
    SaStrokeLedger.frame_drawn(10)
    for frame in range(11, 15):
        for _report in range(3):
            SaStrokeLedger.event_arrived(true, frame)
            SaStrokeLedger.dab_dispatched(2, frame)
            SaStrokeLedger.dab_dispatched(2, frame)
        SaStrokeLedger.frame_drawn(frame)
    assert_true(SaStrokeLedger.last_stroke.is_empty(), "No stroke has ended before the release")
    SaStrokeLedger.event_arrived(false, 15)
    SaStrokeLedger.left_button(_button(false), 15)
    SaStrokeLedger.dab_dispatched(1, 15)
    assert_true(SaStrokeLedger.last_stroke.is_empty(), "The release's own dab is still the stroke's")
    SaStrokeLedger.frame_drawn(15)

    var stroke := SaStrokeLedger.last_stroke
    assert_false(stroke.is_empty(), "The frame that shows the release ends the stroke")
    assert_eq(stroke["frames"]["count"], 6, "The press's frame, four of motions and the release's")
    assert_eq(stroke["motions"], 12, "Three motions in each of four frames")
    assert_eq(stroke["motions_per_frame_max"], 3, "and three at most in one")
    assert_eq(stroke["dabs"], 26, "The press's dab, six a frame and the release's")
    assert_eq(stroke["dabs_per_frame_max"], 6, "and six at most in one")
    assert_eq(stroke["input_to_dispatch"]["n"], 26, "Every dab here had an event of its frame behind it")
    SaStrokeLedger.frame_drawn(16)
    assert_eq(SaStrokeLedger.last_stroke["frames"]["count"], 6, "A frame after the stroke is not the stroke's")


## The frame that froze names what it held: its input against its drawing, its
## motions, its dabs and the lists the card was sent.
func test_the_longest_frame_is_split_into_its_input_and_its_drawing() -> void:
    SaStrokeLedger.frame_drawn(19)
    SaStrokeLedger.event_arrived(false, 20)
    SaStrokeLedger.left_button(_button(true), 20)
    SaStrokeLedger.frame_drawn(20)
    SaStrokeLedger.event_arrived(true, 21)
    OS.delay_usec(30000)
    SaStrokeLedger.dab_dispatched(1, 21)
    SaCompute.lists += 2
    SaStrokeLedger.frame_drawn(21)
    SaStrokeLedger.event_arrived(true, 22)
    SaStrokeLedger.dab_dispatched(1, 22)
    SaStrokeLedger.frame_drawn(22)
    SaStrokeLedger.left_button(_button(false), 23)
    SaStrokeLedger.frame_drawn(23)

    var stroke := SaStrokeLedger.last_stroke
    var longest: Dictionary = stroke["longest"]
    assert_true(stroke["frames"]["max"] >= 30000, "The frame that took 30 ms of input is the longest")
    assert_true(longest["input"] >= 30000, "and its input holds the 30 ms, read %d" % longest["input"])
    assert_true(longest["draw"] < longest["input"], "rather than its drawing")
    assert_eq(longest["motions"], 1, "It held one motion")
    assert_eq(longest["dabs"], 1, "one dab")
    assert_true(longest["lists"] >= 2, "and the lists sent in it")
    assert_true(stroke["frames"]["slow"] >= 1, "One frame of the stroke missed the budget")
    assert_true(stroke["input_usec"] >= 30000, "The stroke's input adds up its frames'")
    assert_true(SaStrokeLedger.block()["frame_usec"]["max"] >= 30000, "and the window folds the same frame")
    assert_true(SaStrokeLedger.block()["input_usec_max"] >= 30000, "with its input")


## The line reads every figure the record's table has a column for, in words a
## painter's log can be read by, with the prose rules of a shown string.
func test_the_line_says_every_figure() -> void:
    SaStrokeLedger.frame_drawn(29)
    SaStrokeLedger.left_button(_button(true), 30)
    SaStrokeLedger.event_arrived(true, 30)
    SaStrokeLedger.dab_dispatched(1, 30)
    SaStrokeLedger.frame_drawn(30)
    SaStrokeLedger.left_button(_button(false), 31)
    SaStrokeLedger.frame_drawn(31)
    var line := SaStrokeLedger.line_of(SaStrokeLedger.last_stroke)
    assert_true(line.begins_with("Sara stroke: "), "The line opens beside the stall lines' `Sara stall:`")
    for said: String in [
        " frames, the longest ",
        "(input ",
        ", drawing ",
        "the 95th percentile ",
        " over 16.7 ms.",
        " in all.",
        " motions, at most ",
        " dabs at ",
        " ms of input each",
        " dispatches in ",
        " compute lists, at most ",
        "Input to dispatch ",
    ]:
        assert_true(line.contains(said), "The line says '%s': %s" % [said, line])
    assert_false(line.contains(";"), "No semicolon in a line a painter reads")
    assert_false(line.contains("—"), "and no em dash")


## A left press that lays no dab, on a docker or a menu, ends with no line and
## leaves figures that say so. A press while a stroke is open ends that one.
func test_a_press_with_no_dab_ends_quietly_and_a_second_press_ends_the_first() -> void:
    SaStrokeLedger.left_button(_button(true), 40)
    SaStrokeLedger.frame_drawn(40)
    SaStrokeLedger.left_button(_button(false), 41)
    SaStrokeLedger.frame_drawn(41)
    assert_eq(SaStrokeLedger.last_stroke["dabs"], 0, "A press that laid nothing ends with no dab")

    SaStrokeLedger.left_button(_button(true), 50)
    SaStrokeLedger.event_arrived(true, 50)
    SaStrokeLedger.dab_dispatched(1, 50)
    SaStrokeLedger.frame_drawn(50)
    SaStrokeLedger.left_button(_button(true), 51)
    assert_eq(SaStrokeLedger.last_stroke["dabs"], 1, "A press with no release before it ends the stroke it found")
    SaStrokeLedger.left_button(_button(false), 52)
    SaStrokeLedger.frame_drawn(52)
    assert_eq(SaStrokeLedger.last_stroke["dabs"], 0, "and starts its own")


## Any other button and any other event leave the stroke alone, and a reset
## drops a stroke under way with the window's figures.
func test_only_the_left_button_opens_a_stroke_and_a_reset_drops_one() -> void:
    var right := _button(true)
    right.button_index = MOUSE_BUTTON_RIGHT
    SaStrokeLedger.left_button(right, 60)
    SaStrokeLedger.left_button(null, 60)
    SaStrokeLedger.event_arrived(true, 60)
    SaStrokeLedger.dab_dispatched(1, 60)
    SaStrokeLedger.frame_drawn(60)
    assert_true(SaStrokeLedger.last_stroke.is_empty(), "No left press, no stroke")

    SaStrokeLedger.left_button(_button(true), 61)
    SaStrokeLedger.reset()
    SaStrokeLedger.left_button(_button(false), 62)
    SaStrokeLedger.frame_drawn(62)
    assert_true(SaStrokeLedger.last_stroke.is_empty(), "A reset took the stroke under way with it")


## The press, three motions and the release through `Input.parse_input_event`
## on a main canvas with the brush, so the stroke opens and closes at the
## window's own input signal. The frame that shows it is handed in by hand.
func test_a_driven_stroke_is_one_stroke_with_its_dabs() -> void:
    var main_canvas := _canvas_in_the_tree()
    main_canvas.tool_machine.set_active_tool(&"brush")
    _send(main_canvas, _button_at(Vector2(60, 60), true))
    for step in range(3):
        _send(main_canvas, _motion(Vector2(80 + step * 30, 70 + step * 10)))
    _send(main_canvas, _button_at(Vector2(140, 90), false))
    SaStrokeLedger.frame_drawn()

    var stroke := SaStrokeLedger.last_stroke
    assert_false(stroke.is_empty(), "The canvas's own hook opened and closed the stroke")
    assert_eq(stroke["motions"], 3, "Its three motions")
    assert_true(stroke["dabs"] > 0, "and the dabs the brush laid along them, read %d" % stroke["dabs"])
    assert_eq(stroke["dabs"], SaStrokeLedger.block()["dabs"], "every dab of the window, since the stroke was all it held")
    assert_true(stroke["dispatches"] >= 1, "sent to the card")
    assert_true(stroke["lists"] >= 1, "in at least one compute list")


func _button(pressed: bool) -> InputEventMouseButton:
    return _button_at(Vector2.ZERO, pressed)


func _button_at(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.position = at
    event.global_position = at
    return event


func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.position = at
    event.global_position = at
    event.pressure = 1.0
    return event


## In the tree on an autoload, as the ledger's own suite builds it, because
## the window's input signal is connected in `_enter_tree`.
func _canvas_in_the_tree() -> Control:
    _host = Node.new()
    _host.name = "D15StrokeLineHost"
    EventBus.add_child(_host)
    _main_canvas = MainCanvasScript.new()
    _host.add_child(_main_canvas)
    _main_canvas.bind_tools(Fixtures.make_tool_registry())
    return _main_canvas


## The ledger's own suite's delivery, for the reason it gives there: an event
## the tool machine did not see in a full run is handed over once.
func _send(main_canvas: Control, event: InputEvent) -> void:
    var machine: ToolMachine = main_canvas.tool_machine
    var seen_before := machine.motion_samples_seen
    var was_capturing: bool = main_canvas._capturing_stroke
    var viewport := main_canvas.get_viewport()
    var at := (event as InputEventMouse).position
    if not viewport.get_mouse_position().is_equal_approx(at):
        viewport.warp_mouse(at)
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var button := event as InputEventMouseButton
    if button != null and button.pressed:
        main_canvas._on_canvas_gui_input(event)
    elif button != null and was_capturing and main_canvas._capturing_stroke:
        main_canvas._input(event)
    elif button == null and machine.motion_samples_seen == seen_before:
        main_canvas._input(event)
