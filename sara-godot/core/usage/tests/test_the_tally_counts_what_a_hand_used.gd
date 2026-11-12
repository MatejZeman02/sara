## The usage tally counts each of its ten kinds through the route a hand takes
## into it, and the file says what the tally says.
##
## The tally also counts the four a hand makes inside a docker, a colour, a Tool
## Options value, a preset and a layer, each pressed on the control that counts
## it, and the hold: a tool held on a key swaps in and back as no switch, and
## counts one use when it acted while held. A write behind the controls, the
## kind a scenario's setter and an undo make, counts none.
##
## The chord goes through `Input.parse_input_event` to a node that hands the
## root's unhandled input to a shortcut router, the way `Main` does. The button
## is a real press, pushed into the root over the embedded window that holds
## it, so the engine's own GUI pass finds the button and presses it. The menu row is pressed on its list, the
## docker is toggled by the call its chord and its row both reach, and the
## stroke is a press, three motions and a release on a main canvas, delivered
## the way the stroke ledger's suite delivers them.
##
## A test function cannot await a frame, so nothing here waits for the
## tally's deferred step into the tree, and a delivery the engine gives to an
## earlier suite's window is handed over by hand, once.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const TALLY_PATH := "res://core/usage/sa_usage_tally.gd"


## Hands the root's unhandled input to the router, which is `Main`'s one line.
class Forward:
    extends Node

    var router: ShortcutRouter = null

    func _unhandled_input(event: InputEvent) -> void:
        router.handle_viewport_input(event, get_viewport())


## One row that runs one command.
class UsageMenu:
    extends SaMenu

    func _add_items() -> void:
        add_commands([[1, &"test_usage_marquee"]])


## The dockers' layout store without a file behind it.
class StubStore:
    extends DockerLayoutStore

    func save(_by_painter: bool = false) -> void:
        pass

    func fork_for_painter_edit() -> String:
        return ""

    func reapply_deferred(_win: Window, _section: String) -> void:
        pass


var _folder: String = ""
var _was_embedding: bool = false
var _host: Node = null
var _detached: Node = null
var _main_canvas: Control = null
var _popup: SaChoicePopup = null
## What a case built outside the tree, freed after it.
var _built: Array[Object] = []


func before_each() -> void:
    _folder = SaDataRoot.path("test_usage_tally")
    _clear_folder()
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true


func after_each() -> void:
    SaUsageTally.stop()
    if _main_canvas != null:
        _main_canvas.tool_machine.registered_tools.clear()
        _main_canvas.tool_machine.active_tool = null
        _main_canvas.tool_machine.registry = null
        _main_canvas = null
    if _host != null:
        _host.free()
        _host = null
    if _detached != null:
        _detached.free()
        _detached = null
    if _popup != null:
        _popup.free()
        _popup = null
    for each: Object in _built:
        if is_instance_valid(each):
            each.free()
    _built.clear()
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _was_embedding
    _clear_folder()


## The unit's proof: one of each kind, read back from the tally and from the
## file it writes.
func test_each_kind_is_counted_through_its_route_and_read_back_from_the_file() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    var router := _router(machine)
    var tally := SaUsageTally.start(tree, _folder)
    assert_not_null(tally, "The tally switches on for a tree")

    # A switch no hand made, which the next event puts down to nothing.
    machine.set_active_tool(&"eraser")

    # The chord: B for the brush, which is a shortcut and a tool switch.
    _key(router, KEY_B)
    assert_eq(machine.active_tool_name, &"brush", "B reached the router and chose the brush")

    # The stroke, with the brush.
    _send(_button_event(Vector2(60, 60), true))
    for step in range(3):
        _send(_motion(Vector2(80 + step * 30, 70 + step * 10)))
    _send(_button_event(Vector2(140, 90), false))

    # The button, in a dialog of its own, whose own handler switches the tool
    # before the tally hears the press.
    _hand_moves_to(Vector2(300, 300))
    var dialog := _dialog_with_a_button(func() -> void: machine.set_active_tool(&"eraser"))
    _press(dialog, dialog.get_node("UsageBtn") as Button)
    assert_eq(machine.active_tool_name, &"eraser", "The press ran the button's own handler")

    # The menu row, whose command switches the tool.
    _hand_moves_to(Vector2(320, 40))
    var menu := _menu(func() -> bool: return _choose(machine, &"marquee"))
    assert_true(menu.popup.press_row(SaMenu.key(1)), "The row is pressed on its list")
    assert_eq(machine.active_tool_name, &"marquee", "and its command chose the marquee")

    # The docker, by the call its chord and its Window menu row both reach.
    var dockers := _dockers()
    var docker_window := dockers.registered_docker_node(&"UsageDocker")
    var was_visible := docker_window.visible
    dockers.toggle_docker_by_id(&"UsageDocker")
    var how := "hidden" if was_visible else "shown"

    var counts := tally.report()
    var dialog_path := String(tree.root.get_path_to(dialog))
    _assert_counts(counts, dialog_path, how, "The tally")

    var file_path := tally.path
    SaUsageTally.stop()
    assert_null(SaUsageTally.current, "Stopping switches it off")
    var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
    assert_true(written is Dictionary, "and it leaves its file behind, as JSON")
    if written is Dictionary:
        _assert_counts(written as Dictionary, dialog_path, how, "The file")
        assert_eq(file_path.get_base_dir(), _folder, "The file is in the folder the tally was handed")


## The travel of the stroke above, apart from the rest: the stretch from the
## press to the release is painting, and the hand's way to the press is not.
func test_the_travel_is_split_by_whether_a_stroke_is_down() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    machine.set_active_tool(&"brush")
    var tally := SaUsageTally.start(tree, _folder)
    _hand_moves_to(Vector2(20, 60))
    _send(_button_event(Vector2(60, 60), true))
    _send(_motion(Vector2(90, 100)))
    _send(_motion(Vector2(90, 160)))
    _send(_button_event(Vector2(90, 160), false))

    var scale := tree.root.get_final_transform().get_scale().x
    var travel: Dictionary = tally.report()["travel"]
    assert_almost_eq(float(travel["painting"]), 110.0 / scale, 0.2, "Painting is the fifty and sixty units the stroke drew")
    assert_true(float(travel["not_painting"]) >= 40.0 / scale - 0.2, "and the forty to the press are the hand's own way there")
    assert_eq(int(tally.report()["strokes"].get("brush", 0)), 1, "One stroke, of the brush")


## Nothing is counted and nothing is written without the flag or the step.
func test_a_run_without_the_flag_writes_nothing() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var usage := SaDataRoot.path(SaUsageTally.FOLDER)
    var before := _files_in(usage)
    SaUsageTally.start_if_asked(tree, PackedStringArray(["--capture=somewhere", "--no-banner"]))
    assert_null(SaUsageTally.current, "No flag, no tally")

    SaUsageTally.shortcut(&"tool_brush", _key_event(KEY_B, true))
    SaUsageTally.menu_row("FileMenu", "file_save")
    SaUsageTally.docker("LayersDocker", SaUsageTally.SHOWN)
    SaUsageTally.tool_input(_button_event(Vector2(10, 10), true), &"brush")
    SaUsageTally.note_key()
    SaUsageTally.hold(&"eyedropper", &"brush")
    SaUsageTally.color_set(SaUsageTally.HEX)
    SaUsageTally.option_set(&"opacity", SaUsageTally.BAR)
    SaUsageTally.preset_picked(SaUsageTally.PALETTE)
    SaUsageTally.layer_picked(SaUsageTally.ROW)
    assert_eq(_files_in(usage), before, "and every hook passes without a file anywhere")
    assert_eq(_files_in(_folder), 0, "in the data root's usage folder or any other")


## The file is written at every tenth count and a reset empties it.
func test_the_file_follows_every_tenth_count_and_a_reset() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var tally := SaUsageTally.start(tree, _folder)
    for i in range(9):
        SaUsageTally.docker("InfoDocker", SaUsageTally.SHOWN if i % 2 == 0 else SaUsageTally.HIDDEN)
    assert_false(FileAccess.file_exists(tally.path), "Nine counts write nothing yet")
    SaUsageTally.docker("InfoDocker", SaUsageTally.HIDDEN)
    var tenth: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tally.path))
    assert_eq(int(tenth["events"]), 10, "The tenth writes the file with all ten")
    assert_eq(int(tenth["dockers"]["InfoDocker"]["shown"]), 5, "five of them shows")

    tally.reset()
    var emptied: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tally.path))
    assert_eq(int(emptied["events"]), 0, "A reset writes the file again with nothing in it")
    assert_true((emptied["dockers"] as Dictionary).is_empty(), "and no docker left")


## The door's step switches the tally on, answers every kind, and resets.
func test_the_usage_step_switches_it_on_and_answers_every_kind() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var first := SaUsageTally.capture(tree, "")
    assert_not_null(SaUsageTally.current, "The step switches the tally on")
    assert_eq(SaUsageTally.KINDS.size(), 11, "Ten kinds and the travel")
    for kind: String in SaUsageTally.KINDS:
        assert_true(first.contains("SaCapture: usage %s " % kind), "and answers a line for %s" % kind)
    SaUsageTally.menu_row("ViewMenu", "view_fit")
    assert_true(SaUsageTally.capture(tree, "").contains('"view_fit":1'), "A row counted since is in the next answer")
    assert_false(SaUsageTally.capture(tree, "reset").contains("view_fit"), "and gone from the one after a reset")
    assert_true(SaUsageTally.capture(tree, "twice").contains("takes"), "Any other word is refused with what it takes")
    # The step's file went to the data root's own folder, which a suite has to
    # leave as it found it.
    var own := SaUsageTally.current.path
    SaUsageTally.stop()
    DirAccess.remove_absolute(own)
    if DirAccess.get_files_at(own.get_base_dir()).is_empty():
        DirAccess.remove_absolute(own.get_base_dir())


## A motion reaches the window handler and the tool hook, so neither may
## allocate: no dictionary, array, string or object is built on their path.
func test_the_motion_path_builds_nothing() -> void:
    var source := FileAccess.get_file_as_string(TALLY_PATH)
    for method: String in ["func _on_window_input(", "static func tool_input("]:
        var body := _body_of(source, method)
        assert_true(body.length() > 0, "%s is in the tally" % method)
        for banned: String in ["{", "[", ".new(", "append", "duplicate", "str(", "%", "String(", "_bump("]:
            assert_false(body.contains(banned), "%s builds no `%s`" % [method, banned])


## the hold: Alt held for the eyedropper and let go is no switch either way,
## nor is an Alt+Backspace fill, and a hold in which the eyedropper picked
## counts one use of it, held, however often it picked.
func test_a_held_tools_swap_counts_no_switch_and_its_picks_one_held_use() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    var router := _router(machine)
    machine.set_active_tool(&"brush")
    var tally := SaUsageTally.start(tree, _folder)

    _hold(router, machine, KEY_ALT, true)
    assert_eq(machine.active_tool_name, &"eyedropper", "Alt held puts the eyedropper in the hand")
    _hold(router, machine, KEY_ALT, false)
    assert_eq(machine.active_tool_name, &"brush", "and letting go hands the brush back")
    assert_true((tally.report()["tools"] as Dictionary).is_empty(), "Neither swap is a switch")

    _hold(router, machine, KEY_ALT, true)
    for pressed: bool in [true, false]:
        var backspace := _key_event(KEY_BACKSPACE, pressed)
        backspace.alt_pressed = true
        router.handle_viewport_input(backspace, tree.root)
    _hold(router, machine, KEY_ALT, false)
    assert_true((tally.report()["tools"] as Dictionary).is_empty(), "and an Alt+Backspace fill counts none")

    var was := [SaColors.foreground, SaColors.background, SaColors.recent.duplicate()]
    _hold(router, machine, KEY_ALT, true)
    for at: Vector2 in [Vector2(60, 60), Vector2(90, 80)]:
        _send(_button_event(at, true))
        _send(_button_event(at, false))
    _hold(router, machine, KEY_ALT, false)
    var tools: Dictionary = tally.report()["tools"]
    assert_eq(tools.keys(), ["eyedropper"], "A hold in which the eyedropper picked counts the eyedropper alone")
    assert_eq(int(tools["eyedropper"].get("held", 0)), 1, "one use, held, for the two picks")
    assert_eq(int(tally.report()["strokes"].get("eyedropper", 0)), 2, "and the two picks are its two strokes")
    SaColors.foreground = was[0]
    SaColors.background = was[1]
    SaColors.recent.assign(was[2])
    SaColors.save()


## The eyedropper made the permanent tool while Alt holds it stays in the hand
## when Alt is let go, so no swap says so, and the end of the hold is the switch.
## The key let go is the hand the tally last heard, which is a key as the I that
## a painter presses under Alt is.
func test_a_held_tool_made_the_permanent_one_counts_one_switch() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    var router := _router(machine)
    machine.set_active_tool(&"brush")
    var tally := SaUsageTally.start(tree, _folder)
    _hold(router, machine, KEY_ALT, true)
    machine.set_active_tool(&"eyedropper")
    _hold(router, machine, KEY_ALT, false)
    assert_eq(machine.active_tool_name, &"eyedropper", "The eyedropper stays in the hand")
    assert_eq(tally.report()["tools"], {"eyedropper": {"shortcut": 1}}, "and counts one switch, a key's")


## Each way a hand sets a colour counts once a gesture, by how, and a colour
## written onto the picker from outside counts none.
func test_a_colour_set_counts_once_a_gesture_by_how_and_a_write_counts_none() -> void:
    var tally := SaUsageTally.start(Engine.get_main_loop() as SceneTree, _folder)
    var picker := SaColorPicker.new()
    _built.append(picker)
    picker.shape.frame.size = Vector2(200, 200)
    _gesture(picker.shape, Vector2(100, 100), Vector2(110, 106))
    _gesture(picker.shape, Vector2(100, 8), Vector2(112, 9))
    picker.hex_input.text_submitted.emit("ff8000")
    picker.hex_input.text_submitted.emit("#00ff00")
    picker.hex_input.text_submitted.emit("not a colour")
    picker.set_recent([Color.RED])
    (picker.recent_flow.get_child(0) as Control).gui_input.emit(_button_event(Vector2(4, 4), true))
    var red: FactorSlider = picker.rgb_sliders.sliders[0]
    red._line_edit.visible = true
    red._line_edit.text = "128"
    red._stop_editing()

    var colors: Dictionary = tally.report()["colors"]
    assert_eq(colors, {"square": 1, "ring": 1, "hex": 2, "swatch": 1, "slider": 1}, "One of each gesture, two hex codes")
    picker.color = Color.BLUE
    picker.background = Color.GREEN
    picker.rgb_sliders.show_color(Color.YELLOW)
    picker.edit_background(true)
    assert_eq(tally.report()["colors"], colors, "A colour written from outside, a store's echo or a step's, counts none")


## A Tool Options value counts once for each press, by option and by the bar or
## the docker, however many times a drag writes it, and a value mirrored, synced
## or written behind the controls counts none.
func test_a_tool_options_value_counts_once_a_press_by_option_and_surface() -> void:
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    machine.set_active_tool(&"brush")
    var tally := SaUsageTally.start(Engine.get_main_loop() as SceneTree, _folder)
    var bar := _options(machine, true)
    var docker := _options(machine, false)
    var on_bar := bar.control(&"opacity") as FactorSlider
    var in_docker := docker.control(&"opacity") as FactorSlider
    assert_not_null(on_bar, "The bar has an Opacity slider")
    assert_not_null(in_docker, "and so does the docker")
    if on_bar == null or in_docker == null:
        return
    on_bar.size = Vector2(200, 20)

    _press_heard(tally)
    on_bar._begin_drag(20.0, false)
    for x: float in [60.0, 100.0, 140.0]:
        on_bar._drag_to(x, false)
    _press_heard(tally)
    on_bar._begin_drag(180.0, false)
    _press_heard(tally)
    in_docker._line_edit.visible = true
    in_docker._line_edit.text = "25"
    in_docker._stop_editing()

    var options: Dictionary = tally.report()["options"]
    assert_eq(options, {"opacity": {"bar": 2, "docker": 1}}, "Two presses on the bar and one typed in the docker")
    var brush := machine.get_tool(&"brush")
    docker.show_value(&"opacity", 0.3)
    bar.sync(brush, &"brush", 1080.0)
    bar.write(&"opacity", 0.4, brush, &"brush")
    assert_eq(tally.report()["options"], options, "A value mirrored, synced or written counts none")


## A preset pick counts by the picker it was pressed in, and a load called on
## the same picker, which is what the door's step and a suite call, counts none.
func test_a_preset_pick_counts_by_its_picker_and_a_load_counts_none() -> void:
    var tally := SaUsageTally.start(Engine.get_main_loop() as SceneTree, _folder)
    var grid := BrushPresetsDocker.new()
    var recent := HistoryDocker.new()
    var ring := PaletteSlotRing.new(func(_slot: int) -> void: pass)
    _built.append_array([grid, recent, ring])
    recent.path = _folder.path_join("recent_presets.cfg")
    recent.record("Inked Pen")

    grid.chooser.preset_chosen.emit("Inked Pen")
    (recent.rows.get_node("Row_Inked Pen") as Button).pressed.emit()
    ring.cells[0].pressed.emit()
    var presets: Dictionary = tally.report()["presets"]
    assert_eq(presets, {"brush_presets": 1, "recent_presets": 1, "palette": 1}, "One pick in each picker")
    grid.apply_preset("Inked Pen")
    recent.load_entry("Inked Pen")
    assert_eq(tally.report()["presets"], presets, "and a load that is not a press counts none")


## A layer pick counts a press on its row and a chord that steps the active
## layer, and the rows the docker picks again after an undo count none.
func test_a_layer_pick_counts_a_row_and_a_chord_and_an_undo_none() -> void:
    var tally := SaUsageTally.start(Engine.get_main_loop() as SceneTree, _folder)
    var easel := SaEasel.create_default(Vector2i(64, 64))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var canvas := SaCanvas.new()
    canvas.easel = easel
    var docker := LayersDocker.new()
    _built.append_array([docker, canvas, easel])
    SaLayerOps.new(easel.document).add()
    docker.target_canvas = canvas
    docker.sync_layer_list()

    docker.item_list.rows[1].gui_input.emit(_button_event(Vector2(20, 8), true))
    SaUsageTally.shortcut(&"layer_select_above", _key_event(KEY_BRACKETRIGHT, true))
    SaUsageTally.shortcut(&"layer_move_up", _key_event(KEY_PAGEUP, true))
    var layers: Dictionary = tally.report()["layers"]
    assert_eq(layers, {"row": 1, "chord": 1}, "One row pressed and one chord that steps, the chord that moves one aside")

    assert_true(easel.document.undo(), "The added layer is undone")
    docker.sync_layer_list()
    docker.item_list.picked.select(0)
    assert_eq(tally.report()["layers"], layers, "and the rows picked again after it count none")


# --- The routes -----------------------------------------------------------------


func _canvas_in_the_tree() -> Control:
    _host = Node.new()
    _host.name = "UsageHost"
    EventBus.add_child(_host)
    _main_canvas = MainCanvasScript.new()
    _host.add_child(_main_canvas)
    _main_canvas.bind_tools(Fixtures.make_tool_registry())
    return _main_canvas


func _router(machine: ToolMachine) -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    _host.add_child(router)
    var forward := Forward.new()
    forward.router = router
    _host.add_child(forward)
    return router


## A press and a release of *code* through the engine. A key an earlier suite's
## window took instead is handed to the router, once.
func _key(router: ShortcutRouter, code: Key) -> void:
    for pressed: bool in [true, false]:
        var event := _key_event(code, pressed)
        var before := _answered()
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        if pressed and _answered() == before:
            router.handle_viewport_input(event, (Engine.get_main_loop() as SceneTree).root)


func _answered() -> int:
    if SaUsageTally.current == null:
        return 0
    return SaUsageTally.current.report()["shortcuts"].size()


func _key_event(code: Key, pressed: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.pressed = pressed
    return event


## One edge of *code*, held across the steps after it. Through the engine, so
## `Input` knows the key is down when the tool machine asks, and by hand to the
## router when an earlier suite's window took it.
func _hold(router: ShortcutRouter, machine: ToolMachine, code: Key, pressed: bool) -> void:
    var event := _key_event(code, pressed)
    event.keycode = code
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    if machine._held_keys.has(code) != pressed:
        router.handle_viewport_input(event, (Engine.get_main_loop() as SceneTree).root)


## A press the root window hears, which is what the tally numbers presses by,
## handed over as the window's input signal hands it one.
func _press_heard(tally: SaUsageTally) -> void:
    tally._on_window_input(_button_event(Vector2(4, 4), true), (Engine.get_main_loop() as SceneTree).root)


## A press at *from*, a motion to *to* and a release there, on *shape*'s frame.
func _gesture(shape: SaPickerShape, from: Vector2, to: Vector2) -> void:
    shape._on_frame_gui_input(_button_event(from, true))
    var motion := InputEventMouseMotion.new()
    motion.position = to
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    shape._on_frame_gui_input(motion)
    shape._on_frame_gui_input(_button_event(to, false))


## The brush's controls on the bar, or in the docker, on a host of their own.
func _options(machine: ToolMachine, on_bar: bool) -> ToolOptionControls:
    var host := Control.new()
    _built.append(host)
    var controls := ToolOptionControls.new(host)
    controls.only_flagged_for_bar = on_bar
    controls.for_docker = not on_bar
    controls.build_for(machine.get_descriptor(&"brush"))
    controls.sync(machine.get_tool(&"brush"), &"brush", 1080.0)
    return controls


## A motion with no button down, which is the hand going somewhere, and a new
## event for the tally to tie what follows to.
func _hand_moves_to(at: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    Input.parse_input_event(event)
    Input.flush_buffered_events()


## An embedded window holding one button, whose handler is connected before it
## is in the tree, so the button's own handler runs before the tally's.
func _dialog_with_a_button(on_press: Callable) -> Window:
    var dialog := Window.new()
    dialog.name = "UsageDialog"
    dialog.position = Vector2i(200, 200)
    dialog.size = Vector2i(200, 120)
    var button := Button.new()
    button.name = "UsageBtn"
    button.text = "Erase"
    button.position = Vector2(20, 20)
    button.size = Vector2(120, 40)
    button.pressed.connect(on_press)
    dialog.add_child(button)
    _host.add_child(dialog)
    SaUI.apply_to_window(dialog)
    return dialog


## A left press and release on *button*, pushed into the root at the place the
## window shows it, after a motion over it. A button presses only while it is
## hovered, and only the root's pass over its embedded windows hovers one, so an
## event pushed straight into the window reaches the button and presses nothing.
func _press(window: Window, button: Button) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var at := Vector2(window.position) + window.get_final_transform() * button.get_global_rect().get_center()
    var over := InputEventMouseMotion.new()
    over.position = at
    over.global_position = at
    root.push_input(over)
    for pressed: bool in [true, false]:
        root.push_input(_button_event(at, pressed))


func _menu(run: Callable) -> UsageMenu:
    var registry := SaCommandRegistry.new()
    var row := SaCommandDescriptor.create(&"test_usage_marquee", "Marquee", run)
    row.action = &""
    registry.register(row, &"test")
    _popup = SaChoicePopup.new()
    _popup.name = "UsageMenu"
    var menu := UsageMenu.new(_popup)
    menu.bind_commands(registry)
    return menu


func _choose(machine: ToolMachine, tool_id: StringName) -> bool:
    machine.set_active_tool(tool_id)
    return true


func _dockers() -> MainDockers:
    _detached = Node.new()
    var registries := SaRegistries.new()
    var win := Window.new()
    win.name = "UsageDocker"
    _detached.add_child(win)
    registries.ui.register_docker(&"UsageDocker", "Usage", func() -> Window: return Window.new(), &"docker_usage")
    registries.ui.set_docker_node(&"UsageDocker", win)
    var dockers := MainDockers.new(registries.ui, StubStore.new())
    _detached.add_child(dockers)
    return dockers


## The stroke ledger suite's delivery: the press by hand to the canvas, a motion
## or a release by the engine, and by hand when an earlier suite's window held it.
func _send(event: InputEvent) -> void:
    var machine: ToolMachine = _main_canvas.tool_machine
    var seen_before := machine.motion_samples_seen
    var was_capturing: bool = _main_canvas._capturing_stroke
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var button := event as InputEventMouseButton
    if button != null and button.pressed:
        _main_canvas._on_canvas_gui_input(event)
    elif button != null and was_capturing and _main_canvas._capturing_stroke:
        _main_canvas._input(event)
    elif button == null and machine.motion_samples_seen == seen_before:
        _main_canvas._input(event)


func _button_event(at: Vector2, pressed: bool) -> InputEventMouseButton:
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


# --- Reading it back ------------------------------------------------------------


func _assert_counts(counts: Dictionary, dialog_path: String, how: String, who: String) -> void:
    var shortcuts: Dictionary = counts["shortcuts"].get("tool_brush", {})
    assert_eq(int(shortcuts.get("B", 0)), 1, "%s has the brush's shortcut once, on B" % who)
    var buttons: Dictionary = counts["buttons"].get(dialog_path, {})
    assert_eq(int(buttons.get('UsageBtn "Erase"', 0)), 1, "%s has the button once, under its dialog's path" % who)
    var rows: Dictionary = counts["menus"].get("UsageMenu", {})
    assert_eq(int(rows.get("test_usage_marquee", 0)), 1, "%s has the menu row once, by its command" % who)
    var docker: Dictionary = counts["dockers"].get("UsageDocker", {})
    assert_eq(int(docker.get(how, 0)), 1, "%s has the docker %s once" % [who, how])
    var tools: Dictionary = counts["tools"]
    assert_eq(int(tools.get("brush", {}).get("shortcut", 0)), 1, "%s puts the brush down to the shortcut" % who)
    assert_eq(int(tools.get("eraser", {}).get("UsageDialog", 0)), 1, "the eraser to the dialog whose button made it")
    assert_eq(int(tools.get("marquee", {}).get("menu", 0)), 1, "the marquee to the menu")
    assert_eq(int(tools.get("eraser", {}).get("other", 0)), 1, "and the switch no hand made to other")
    assert_eq(int(counts["strokes"].get("brush", 0)), 1, "%s has one stroke, of the brush" % who)
    assert_true(float(counts["travel"]["painting"]) > 0.0, "%s has the stroke's travel as painting" % who)


func _files_in(folder: String) -> int:
    return DirAccess.get_files_at(folder).size() if DirAccess.dir_exists_absolute(folder) else 0


func _clear_folder() -> void:
    if not DirAccess.dir_exists_absolute(_folder):
        return
    for file: String in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)


## The text of the method starting at *head*: its line and every indented or
## empty line after it, so a comment above the next function is not read as
## this one's.
static func _body_of(source: String, head: String) -> String:
    var start := source.find(head)
    if start < 0:
        return ""
    var lines := source.substr(start).split("\n")
    var kept := PackedStringArray([lines[0]])
    for i in range(1, lines.size()):
        var line: String = lines[i]
        if not line.begins_with("    ") and not line.strip_edges().is_empty():
            break
        kept.append(line)
    return "\n".join(kept)
