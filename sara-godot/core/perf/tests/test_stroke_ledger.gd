## The stroke ledger: the CPU half of stroke latency, from the window's input
## signal to the dab's dispatch and on to the frame's post draw.
##
## Two halves, because a test function cannot await a frame
## and a stroke injected in one lands in
## a single process frame. The shape of the load, 25 frames with dabs and four
## motions in one frame, is a scripted sequence that hands each hook its frame
## index. The latency is a real press, three motions and a release through
## `Input.parse_input_event` on a main canvas with the brush, so the figure comes
## from the hooks the app itself calls and not from the test calling the ledger.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const LEDGER_PATH := "res://core/perf/sa_stroke_ledger.gd"

var _host: Node = null
var _main_canvas: Control = null


func before_each() -> void:
    SaStrokeLedger.reset()
    SaCursorPolicy.forget_pointer_device()


func after_each() -> void:
    SaPointerDevice.suite_pointer = null
    if _main_canvas != null:
        _main_canvas.tool_machine.registered_tools.clear()
        _main_canvas.tool_machine.active_tool = null
        _main_canvas.tool_machine.registry = null
        _main_canvas = null
    if _host != null:
        _host.free()
        _host = null
    SaStrokeLedger.reset()


## The press frame and the 24 move frames a 24-step scenario stroke expands to,
## each with its dab, then a burst of four motions in one frame with no dab, the
## way `motion_burst` lands after a release.
func test_a_scripted_stroke_counts_its_frames_and_its_burst() -> void:
    SaStrokeLedger.event_arrived(false, 100)
    SaStrokeLedger.dab_dispatched(1, 100)
    SaStrokeLedger.composite_issued(100)
    SaStrokeLedger.redraw_queued(100)
    SaStrokeLedger.frame_drawn(100)
    for step in range(24):
        var frame := 101 + step
        SaStrokeLedger.event_arrived(true, frame)
        SaStrokeLedger.dab_dispatched(2, frame)
        SaStrokeLedger.composite_issued(frame)
        SaStrokeLedger.redraw_queued(frame)
        SaStrokeLedger.frame_drawn(frame)
    SaStrokeLedger.event_arrived(false, 125)
    SaStrokeLedger.frame_drawn(125)
    for point in range(4):
        SaStrokeLedger.event_arrived(true, 126)
    SaStrokeLedger.frame_drawn(126)

    var block := SaStrokeLedger.block()
    assert_eq(block["frames_with_dabs"], 25, "The press frame and the 24 move frames, never the release frame")
    assert_eq(block["motions_per_frame_max"], 4, "Four motions in one frame is the burst")
    assert_eq(block["dabs"], 25, "One dab a frame")
    assert_eq(block["dabs_per_frame_max"], 1, "and never two in one")
    assert_eq(block["targets"], 49, "One chunk under the press and two under each move")
    assert_eq(block["events"], 30, "A press, 24 moves, a release and the burst of four")
    assert_eq(block["motions"], 28, "The moves and the burst, not the two button events")
    assert_eq(block["frames_drawn"], 27, "Every drawn frame is counted, dab or none")
    for key: String in ["input_to_dispatch", "input_to_composite", "input_to_redraw", "input_to_post_draw"]:
        var fold: Dictionary = block[key]
        assert_eq(fold["n"], 25, "%s folds once for each frame that had a dab" % key)
        _assert_ordered(fold, key)
    assert_eq(block["dab_frame_interval"]["n"], 24, "25 dab frames in a row are 24 intervals")
    _assert_ordered(block["dab_frame_interval"], "dab_frame_interval")


## A frame with events and no dab owes nothing to the composite after it, and a
## second post draw of one frame folds the dab's frame once.
func test_only_a_frame_with_a_dab_folds_the_frame_figures() -> void:
    SaStrokeLedger.event_arrived(true, 7)
    SaStrokeLedger.composite_issued(7)
    SaStrokeLedger.redraw_queued(7)
    SaStrokeLedger.frame_drawn(7)
    var idle := SaStrokeLedger.block()
    assert_eq(idle["input_to_composite"]["n"], 0, "No dab, so the composite was not this stroke's")
    assert_eq(idle["input_to_post_draw"]["n"], 0, "and neither was the frame")

    SaStrokeLedger.event_arrived(true, 8)
    SaStrokeLedger.dab_dispatched(1, 8)
    SaStrokeLedger.composite_issued(8)
    SaStrokeLedger.redraw_queued(8)
    SaStrokeLedger.redraw_queued(8)
    SaStrokeLedger.frame_drawn(8)
    SaStrokeLedger.frame_drawn(8)
    var block := SaStrokeLedger.block()
    assert_eq(block["input_to_redraw"]["n"], 1, "A second redraw of one composite is not a second frame")
    assert_eq(block["input_to_post_draw"]["n"], 1, "and a forced second draw is not one either")
    assert_eq(block["frames_drawn"], 3, "though every draw is counted")
    assert_eq(block["dab_frame_interval"]["n"], 0, "One dab frame has no neighbour to be measured from")

    SaStrokeLedger.event_arrived(true, 20)
    SaStrokeLedger.dab_dispatched(1, 20)
    SaStrokeLedger.composite_issued(20)
    SaStrokeLedger.frame_drawn(20)
    assert_eq(
        SaStrokeLedger.block()["dab_frame_interval"]["n"], 0, "and a dab twelve frames later is another stroke, not a slow frame"
    )


## The capture harness dabs in SaCapture's `_process`, after the easel's, so the
## composite of a harness dab is the next frame's and the next step's event
## arrives before that frame's post draw. The stamp has to survive both.
func test_a_harness_dab_reads_one_frame_long_and_is_not_lost() -> void:
    SaStrokeLedger.event_arrived(true, 40)
    SaStrokeLedger.dab_dispatched(1, 40)
    SaStrokeLedger.frame_drawn(40)
    assert_eq(SaStrokeLedger.block()["input_to_post_draw"]["n"], 0, "Frame 40 drew before anything composed the dab")

    SaStrokeLedger.composite_issued(41)
    SaStrokeLedger.redraw_queued(41)
    SaStrokeLedger.event_arrived(true, 41)
    SaStrokeLedger.dab_dispatched(1, 41)
    SaStrokeLedger.frame_drawn(41)
    var block := SaStrokeLedger.block()
    assert_eq(block["input_to_composite"]["n"], 1, "The dab of frame 40 is composed in frame 41")
    assert_eq(block["input_to_post_draw"]["n"], 1, "and drawn there, under the next step's event")
    assert_eq(block["frames_with_dabs"], 2, "Both frames had a dab")

    SaStrokeLedger.composite_issued(42)
    SaStrokeLedger.frame_drawn(42)
    assert_eq(SaStrokeLedger.block()["input_to_post_draw"]["n"], 2, "and the second dab was still owed its frame")


## An airbrush tick dabs with no event behind it. It is a dab, and it has no
## latency to fold: the last arrival would be the start of the hold.
func test_a_dab_no_event_caused_is_counted_and_folds_nothing() -> void:
    SaStrokeLedger.event_arrived(false, 3)
    SaStrokeLedger.dab_dispatched(1, 3)
    SaStrokeLedger.dab_dispatched(1, 9)
    var block := SaStrokeLedger.block()
    assert_eq(block["dabs"], 2, "Both dabs are counted")
    assert_eq(block["frames_with_dabs"], 2, "in two frames")
    assert_eq(block["input_to_dispatch"]["n"], 1, "and only the one an event caused has a latency")


## The brush sends a frame's dabs at `process_frame`, which
## the engine may number as the next process frame although no composite has
## shown them yet. They are still their arrivals' dabs. A dab after that
## composite is not, and neither is one two indices on.
func test_a_dab_sent_at_the_next_index_before_its_composite_is_its_arrivals() -> void:
    SaStrokeLedger.event_arrived(true, 70)
    OS.delay_usec(3000)
    SaStrokeLedger.event_arrived(true, 71)
    SaStrokeLedger.event_arrived(true, 71)
    SaStrokeLedger.dab_dispatched(1, 72)
    SaStrokeLedger.dab_dispatched(1, 72)
    assert_eq(SaStrokeLedger.block()["input_to_dispatch"]["n"], 2, "Both dabs of the frame's send have an arrival behind them")
    SaStrokeLedger.composite_issued(72)
    var composed: Dictionary = SaStrokeLedger.block()["input_to_composite"]
    assert_eq(composed["n"], 1, "and the composite that shows them is timed")
    assert_true(composed["max"] < 3000, "from the first arrival of their frame, not a hover's before it, %d us" % composed["max"])
    SaStrokeLedger.dab_dispatched(1, 72)
    assert_eq(SaStrokeLedger.block()["input_to_dispatch"]["n"], 2, "A dab after that composite is no arrival's")
    SaStrokeLedger.event_arrived(true, 80)
    SaStrokeLedger.dab_dispatched(1, 82)
    assert_eq(SaStrokeLedger.block()["input_to_dispatch"]["n"], 2, "nor is one two indices after its arrival")


func test_reset_clears_everything() -> void:
    SaStrokeLedger.event_arrived(true, 1)
    SaStrokeLedger.dab_dispatched(3, 1)
    SaStrokeLedger.composite_issued(1)
    SaStrokeLedger.redraw_queued(1)
    SaStrokeLedger.frame_drawn(1)
    SaStrokeLedger.reset()
    var block := SaStrokeLedger.block()
    for key: String in block:
        if block[key] is Dictionary:
            for field: String in block[key]:
                # The budget is not a figure of a measured thing, it is one
                # refresh of the display the window is on, so a reset leaves it
                # where the start-up block put it rather than noughting it.
                if field == "budget":
                    assert_eq(block[key][field], SaStrokeLedger.budget_usec, "the budget survives a reset")
                    continue
                assert_eq(block[key][field], 0, "%s.%s is zero after a reset" % [key, field])
        else:
            assert_eq(block[key], 0, "%s is zero after a reset" % key)
    SaStrokeLedger.composite_issued(2)
    SaStrokeLedger.frame_drawn(2)
    assert_eq(SaStrokeLedger.block()["input_to_composite"]["n"], 0, "and no stamp from before the reset is still owed")


## The real hooks. The events go through `Input.parse_input_event`, so the
## arrival is stamped by the window's input signal the way a pen's is, and the
## dab is whatever the stamp brush dispatches through `dispatch_batch`.
func test_a_driven_stroke_stamps_every_dab_from_its_arrival() -> void:
    var main_canvas := _canvas_in_the_tree()
    main_canvas.tool_machine.set_active_tool(&"brush")
    var seen_before: int = main_canvas.tool_machine.motion_samples_seen

    _send(main_canvas, _button(_on_document(main_canvas, Vector2(60, 60)), true))
    for step in range(3):
        _send(main_canvas, _motion(_on_document(main_canvas, Vector2(80 + step * 30, 70 + step * 10))))
    _send(main_canvas, _button(_on_document(main_canvas, Vector2(140, 90)), false))

    var block := SaStrokeLedger.block()
    var fold: Dictionary = block["input_to_dispatch"]
    assert_true(block["dabs"] > 0, "A press and three motions with the brush dispatch at least one dab")
    assert_eq(fold["n"], block["dabs"], "Every dab of a driven stroke has an arrival behind it")
    assert_true(fold["min"] > 0, "A dab cannot be dispatched in the microsecond its event arrived")
    _assert_ordered(fold, "input_to_dispatch")
    assert_true(block["targets"] >= block["dabs"], "A dab touches at least one chunk")
    assert_eq(block["events"], 5, "The window's signal stamped the press, the three motions and the release")
    assert_eq(block["motions"], 3, "of which three were motions")
    assert_eq(
        main_canvas.tool_machine.motion_samples_seen - seen_before,
        3,
        "and the tool machine's own motion count still moves by one a motion"
    )


## `_ready()` is called by hand in three places of one gate run, and a second
## connect of one callable is an engine error.
func test_a_second_ready_leaves_one_connection() -> void:
    var was_connected := RenderingServer.frame_post_draw.is_connected(SaStrokeLedger.frame_drawn)
    var first := MainCanvasScript.new()
    first._ready()
    var second := MainCanvasScript.new()
    second._ready()
    var count := 0
    for connection: Dictionary in RenderingServer.frame_post_draw.get_connections():
        if connection["callable"] == Callable(SaStrokeLedger, "frame_drawn"):
            count += 1
    assert_eq(count, 1, "One connection to the post draw, however many canvases readied")
    first.free()
    second.free()
    if not was_connected:
        RenderingServer.frame_post_draw.disconnect(SaStrokeLedger.frame_drawn)


## The scratchpad is a canvas too, and its strokes are not the painter's
## document. It dabs through the same `dispatch_batch`, which is counted, and it
## never connects the post draw.
func test_an_embedded_canvas_does_not_connect_the_post_draw() -> void:
    var was_connected := RenderingServer.frame_post_draw.is_connected(SaStrokeLedger.frame_drawn)
    if was_connected:
        RenderingServer.frame_post_draw.disconnect(SaStrokeLedger.frame_drawn)
    var pad := MainCanvasScript.new()
    pad.embedded = true
    pad._ready()
    assert_false(
        RenderingServer.frame_post_draw.is_connected(SaStrokeLedger.frame_drawn), "Only the main surface owns the frame's clock"
    )
    pad.free()
    if was_connected:
        RenderingServer.frame_post_draw.connect(SaStrokeLedger.frame_drawn)


## Four integers a figure, never a list of samples: a 2000-dab stroke must not
## make the ledger grow. And nothing here reads the canvas or waits for a frame.
func test_the_ledger_keeps_no_list_and_reads_nothing_back() -> void:
    var source := FileAccess.get_file_as_string(LEDGER_PATH)
    assert_true(source.length() > 0, "The ledger's source is readable")
    for banned: String in ["Array", "append", "texture_get_data", "buffer_get_data", "await", "sync(", "submit("]:
        assert_false(source.contains(banned), "The ledger holds no `%s`" % banned)


func _assert_ordered(fold: Dictionary, key: String) -> void:
    assert_true(fold["min"] >= 0, "%s never runs backwards" % key)
    assert_true(fold["min"] <= fold["mean"], "%s min is at most its mean" % key)
    assert_true(fold["mean"] <= fold["max"], "%s mean is at most its max" % key)


## In the tree, because the window's input signal is connected in `_enter_tree`
## and a detached canvas has no window. On an autoload, because the root is busy
## readying the runner and refuses a child.
func _canvas_in_the_tree() -> Control:
    _host = Node.new()
    _host.name = "M5Host"
    EventBus.add_child(_host)
    _main_canvas = MainCanvasScript.new()
    _host.add_child(_main_canvas)
    _main_canvas.bind_tools(Fixtures.make_tool_registry())
    return _main_canvas


## Every event reaches the window's signal through the engine, which is the half
## under test. The press reaches the canvas's own handler by hand, because an
## injected press is routed by a hit test over a window this suite does not lay
## out. A motion or a release is the engine's to deliver, to `MainCanvas._input`
## once the press has started the stroke capture, and it does when this suite
## runs alone. In a full run an earlier suite's window can hold the input, so an
## event the tool machine did not see is handed over, once and never twice.
func _send(main_canvas: Control, event: InputEvent) -> void:
    var machine: ToolMachine = main_canvas.tool_machine
    var seen_before := machine.motion_samples_seen
    var was_capturing: bool = main_canvas._capturing_stroke
    _point_at(main_canvas, (event as InputEventMouse).position)
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var button := event as InputEventMouseButton
    if button != null and button.pressed:
        main_canvas._on_canvas_gui_input(event)
    elif button != null and was_capturing and main_canvas._capturing_stroke:
        main_canvas._input(event)
    elif button == null and machine.motion_samples_seen == seen_before:
        main_canvas._input(event)


## *document_point* where the window shows it. The view centres the document in
## a canvas the window's size, so a fixed window point lands on the document
## under Linux's 1920 by 1080 and above it on a slower machine's 1280 by 1024
## under Windows, where the stroke painted nothing.
func _on_document(main_canvas: Control, document_point: Vector2) -> Vector2:
    return main_canvas.canvas.get_global_transform_with_canvas() * document_point


## Puts the pointer the brush reads at *at*, since the brush takes a mouse's
## point from `SaPointerDevice.pointer_in` rather than from the event. Under
## Wayland the display server's pointer is the last event's, so a parsed event
## moves it. Under X11 and Windows it is where the hand left the real one, so
## the run on Windows laid its stroke there, off the document, and no dab at
## all. An earlier version warped the pointer to each event, which held on its
## nested X server and not on the Windows desktop of 2026-10-01, where the same
## two lines failed again, nor under an X server whose window manager put the
## window somewhere other than where Godot read it. The
## suite's own place answers for the display server on every desktop, so
## nothing here depends on where the real one is.
func _point_at(main_canvas: Control, at: Vector2) -> void:
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(main_canvas.get_window())
    SaPointerDevice.suite_pointer = to_desktop * at


func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
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


## The stall a window reports is the longest wait for one of its own drawn
## frames, the first counted from the reset. The engine's process monitor holds
## the worst frame of the last whole second, so four windows of the tools
## scenario read one shot's 329 ms.
func test_the_frame_gap_is_the_windows_own_and_counts_from_the_reset() -> void:
    SaStrokeLedger.reset()
    OS.delay_usec(20000)
    SaStrokeLedger.frame_drawn(10)
    var first: int = SaStrokeLedger.block()["frame_gap_usec_max"]
    assert_true(first >= 20000, "Work before the first frame is a wait for it, read %d" % first)
    SaStrokeLedger.reset()
    SaStrokeLedger.frame_drawn(11)
    OS.delay_usec(30000)
    SaStrokeLedger.frame_drawn(12)
    var gap: int = SaStrokeLedger.block()["frame_gap_usec_max"]
    assert_true(gap >= 30000, "The 30 ms between two frames is the longest, read %d" % gap)
    assert_true(gap < 1000000, "and the reset forgot the wait of the window before, read %d" % gap)
