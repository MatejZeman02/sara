## Krita's Reselect on Ctrl+Shift+D had no command, because a
## deselect kept nothing to bring back, and F2, Krita's Rename Current Layer,
## did nothing over the canvas, because only the Layers docker's list read it
## and only while the docker held the keyboard.
##
## Pressed the way a keyboard sends a chord and answered by the router the main
## window hands every unhandled key to. The docker is never added to the tree,
## for the reason `ui/dockers/layers/tests/test_layer_rename_dialog.gd` gives,
## so F2 is held in two halves here: the press reaching the command, and the
## docker's answer to it. The scenario of the same name presses F2 over the
## booted app's canvas and reads the window it opened.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## The selection lives on a document, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _saved_events: Dictionary = {}


## The application's commands are registered beside the skeleton's before the
## map is saved, for the reason the suite beside this one gives. Two chunks
## wide, so a selection can reach across a seam.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 256))
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    _router.free()
    _router = null
    _registries = null
    Fixtures.teardown(_surface)
    _surface = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The press a keyboard sends: the character, its position and its label all
## set, rather than the one field a chord's text parses to.
func _press(chord: String) -> InputEventKey:
    var parsed := SaShortcutStore.parse_chord(chord)
    var event := InputEventKey.new()
    event.keycode = parsed.keycode
    event.physical_keycode = parsed.keycode
    event.key_label = parsed.keycode
    event.ctrl_pressed = parsed.ctrl_pressed
    event.shift_pressed = parsed.shift_pressed
    event.alt_pressed = parsed.alt_pressed
    event.pressed = true
    return event


## With a selection up, Ctrl+Shift+A drops it, and one Ctrl+Shift+D
## brings back the same chunks over the same box, so a feathered edge comes back
## as soft as it went and nothing is drawn again.
func test_ctrl_shift_d_brings_back_what_a_deselect_dropped() -> void:
    var selection: SaSelection = _surface.easel.document.selection
    selection.select_rect(Rect2i(16, 16, 300, 40))
    var chunks_before: Dictionary = selection.chunks.duplicate()
    var bounds_before := selection.bounds
    assert_eq(chunks_before.size(), 2, "The selection reaches two chunks")

    assert_true(_router.handle(_press("Ctrl+Shift+A")), "Ctrl+Shift+A is taken")
    assert_false(selection.active, "and drops the selection")
    assert_true(selection.chunks.is_empty(), "with its chunks")

    assert_true(_router.handle(_press("Ctrl+Shift+D")), "Ctrl+Shift+D is taken")
    assert_true(selection.active, "and the selection is back in the one step")
    assert_eq(selection.bounds, bounds_before, "over the box it had")
    assert_eq(selection.chunks.size(), chunks_before.size(), "with as many chunks")
    for grid_pos: Vector2i in chunks_before:
        assert_true(selection.chunks.get(grid_pos) == chunks_before[grid_pos], "the very chunk at %s" % grid_pos)


## A click with the marquee that drags nothing deselects, and a second such
## click must not lose what the first one kept.
func test_a_deselect_with_nothing_selected_keeps_the_last_one() -> void:
    var selection: SaSelection = _surface.easel.document.selection
    selection.select_rect(Rect2i(8, 8, 32, 32))
    var bounds_before := selection.bounds
    selection.deselect()
    selection.deselect()

    assert_true(_router.handle(_press("Ctrl+Shift+D")), "Ctrl+Shift+D is taken")
    assert_eq(selection.bounds, bounds_before, "and brings back the selection the first deselect dropped")


## A selection made since the deselect stands, and a reselect would throw it
## away, so the chord falls through. The next deselect keeps that one instead,
## which is what the chord brings back after it.
func test_a_selection_made_since_stands_and_is_the_next_one_kept() -> void:
    var selection: SaSelection = _surface.easel.document.selection
    selection.select_rect(Rect2i(8, 8, 32, 32))
    _router.handle(_press("Ctrl+Shift+A"))
    selection.select_rect(Rect2i(100, 100, 20, 20))
    var second := selection.bounds

    assert_false(_router.handle(_press("Ctrl+Shift+D")), "Ctrl+Shift+D falls through over a standing selection")
    assert_eq(selection.bounds, second, "which is left as it was")

    _router.handle(_press("Ctrl+Shift+A"))
    assert_true(_router.handle(_press("Ctrl+Shift+D")), "After the next deselect it is taken")
    assert_eq(selection.bounds, second, "and brings back the second selection, not the first")
    assert_false(_router.handle(_press("Ctrl+Shift+D")), "and a second press has nothing left to bring back")


## Nothing dropped is nothing to bring back: the chord falls through and the
## Select menu's row is dimmed until a deselect keeps something.
func test_the_row_is_lit_only_while_something_is_kept() -> void:
    var selection: SaSelection = _surface.easel.document.selection
    var reselect := _registries.commands.get_descriptor(&"select_reselect")
    assert_not_null(reselect, "Reselect is a command")
    if reselect == null:
        return
    assert_false(reselect.is_enabled(), "dimmed on a new document")
    assert_false(_router.handle(_press("Ctrl+Shift+D")), "whose chord falls through")

    selection.select_rect(Rect2i(8, 8, 32, 32))
    assert_false(reselect.is_enabled(), "still dimmed while the selection stands")
    selection.deselect()
    assert_true(reselect.is_enabled(), "and lit once a deselect kept it")
    assert_eq(reselect.menu_label(), "Reselect", "under the word Krita's and Photoshop's menus use")


## A crop moves the picture under the kept chunks, so a reselect after it would
## land over the wrong pixels. The crop lets the kept selection go with the
## standing one.
func test_a_crop_lets_the_kept_selection_go() -> void:
    var doc: SaDocument = _surface.easel.document
    doc.selection.select_rect(Rect2i(8, 8, 32, 32))
    doc.selection.deselect()
    assert_true(doc.selection.can_reselect(), "A deselect kept the first selection")

    doc.selection.select_rect(Rect2i(40, 40, 64, 64))
    assert_true(_registries.commands.execute(&"image_crop_to_selection"), "Crop to Selection runs")
    assert_eq(doc.canvas_size, Vector2i(64, 64), "and crops to the second selection")

    assert_false(doc.selection.can_reselect(), "with nothing left to bring back")
    assert_false(_router.handle(_press("Ctrl+Shift+D")), "so Ctrl+Shift+D falls through")


## F2 over the canvas once changed nothing. The press reaches the
## rename command now. With no docker in the tree it has nothing to open, and
## declines rather than eating the key.
func test_f2_over_the_canvas_reaches_the_rename() -> void:
    _router.handle(_press("F2"))
    assert_eq(_registries.commands.last_command, &"layer_rename", "F2 runs the rename command")
    assert_eq(_registries.commands.chord_text(&"layer_rename"), "F2", "on F2 alone")


## The docker's half: F2 opens Rename Layer on the active layer with the
## keyboard in the name, the window the Layer menu's Rename... opens.
func test_the_docker_answers_f2_with_the_rename_window() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    canvas.add_child(docker)
    docker.target_canvas = canvas
    docker._ready()
    var sky := SaLayerOps.new(canvas.document).add()
    sky.name = "Sky"
    canvas.document.set_active_layer(sky)
    docker.sync_layer_list()

    assert_true(docker.answer_rename_key(), "A docker without the keyboard takes F2")
    var dialog := docker.find_child("LayerRenameDialog", true, false) as SaLayerRenameDialog
    assert_not_null(dialog, "and opens Rename Layer")
    if dialog != null:
        assert_eq(dialog._layer, sky, "on the active layer")
        var name_field := dialog.find_child("NameEdit", true, false) as LineEdit
        assert_eq(name_field.text, "Sky", "with its name in the name field")
        assert_eq(dialog.first_focus, name_field, "and the keyboard in it")
    assert_eq(docker.item_list.renaming_row(), -1, "and no row opened its own name")
    canvas.free()


## The Layer menu's Rename... row is the command now, so it draws F2 beside it
## and reads the command's words.
func test_the_layer_menu_row_reads_the_command() -> void:
    var rows := SaLayerMenuRows.new(_surface.easel.document, _registries.commands, null)
    var found := false
    for row: Variant in rows.rows(false):
        if row is SaLayerMenuRows.Row and (row as SaLayerMenuRows.Row).id == SaLayerMenuRows.RENAME:
            found = true
            assert_eq((row as SaLayerMenuRows.Row).chord, "F2", "Rename... draws F2")
            assert_eq((row as SaLayerMenuRows.Row).words, "Rename...", "beside its word")
    assert_true(found, "The Layer menu has its Rename... row")
