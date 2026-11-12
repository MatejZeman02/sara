## PageUp and PageDown, Krita's, step the active layer, and Alt with a bracket,
## Photoshop's, does not make the brush a tenth smaller, because the bracket rule
## declines a chord an action holds. Two commands
## step the active layer through the rows the Layers docker lists.
##
## Pressed the way a keyboard sends a chord and answered by the router the main
## window hands every unhandled key to. The docker is built over the same
## document and never added to the tree, for the reason
## `ui/dockers/layers/tests/test_layer_group_collapse.gd` gives. The scenario of
## the same name strikes the keys over the booted app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The layers live on a document, which needs a RenderingDevice.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _canvas: SaCanvas = null
var _docker: LayersDocker = null
var _saved_events: Dictionary = {}


## The application's commands are registered beside the skeleton's before the
## map is saved, because a profile makes any action it names that does not
## exist yet, as the Deselect chord suite beside this one does.
func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.tool_machine_provider = func() -> ToolMachine: return _machine
    _router.bind_commands(_registries.commands)
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    _router.free()
    _router = null
    _registries = null
    if _docker != null:
        _docker.free()
        _docker = null
        _canvas.free()
        _canvas = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## Background, Layer 1, a group of Under and Top, and Outsider over it, bottom
## first, with Outsider active and a docker listing them. Returns the group.
func _stack() -> SaLayer:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var under := ops.add()
    under.name = "Under"
    var top := ops.add()
    top.name = "Top"
    var outsider := ops.add()
    outsider.name = "Outsider"
    var group := ops.group_layers([under, top])
    group.name = "Group"
    doc.set_active_layer(outsider)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _docker = LayersDocker.new()
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()
    return group


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


## The names the docker's rows read, top first.
func _rows() -> Array:
    var out: Array = []
    for i: int in _docker.item_list.row_count():
        var layer: SaLayer = _docker.item_list.layer_at(i)
        out.append(str(layer.name) if layer != null else "")
    return out


func _active() -> String:
    return str(_surface.easel.document.active_layer.name)


func _radius() -> float:
    return float(_machine.get_tool(&"brush").get("settings").radius)


func test_each_profile_puts_the_steps_on_its_own_chords() -> void:
    var wanted := {
        SaShortcutStore.DEFAULT_PROFILE: ["PageUp", "PageDown"],
        "Krita": ["PageUp", "PageDown"],
        "Photoshop": ["Alt+]", "Alt+["],
    }
    for profile: String in wanted:
        SaShortcutStore.apply_profile(profile)
        var chords: Array = wanted[profile]
        assert_eq(SaShortcutStore.chords_for(&"layer_select_above"), [chords[0]] as Array[String], "%s: above" % profile)
        assert_eq(SaShortcutStore.chords_for(&"layer_select_below"), [chords[1]] as Array[String], "%s: below" % profile)
        for chord: String in chords:
            var others := SaShortcutStore.holders(chord)
            others.erase("layer_select_above")
            others.erase("layer_select_below")
            assert_eq(others, [] as Array[String], "%s gives %s to nothing else" % [profile, chord])


## PageDown walks the docker's rows top to bottom, into the group and out of
## it, and stays on the bottom row. PageUp walks back and stays on the top one.
## No step is a history step and none marks the document changed.
func test_the_steps_walk_the_rows_and_stop_at_the_ends_with_no_history_step() -> void:
    _stack()
    var doc: SaDocument = _surface.easel.document
    var rows := _rows()
    assert_eq(rows, ["Outsider", "Group", "Top", "Under", "Layer 1", "Background"], "The docker lists the stack")
    var version: int = doc.undo_redo.get_version()
    var modified := doc.modified

    var walked: Array = [_active()]
    for i: int in rows.size():
        assert_true(_router.handle(_press("PageDown")), "PageDown is taken on row %d" % i)
        walked.append(_active())
    assert_eq(walked, rows + ["Background"], "PageDown walks every row down and stops at the bottom")

    walked = [_active()]
    for i: int in rows.size():
        assert_true(_router.handle(_press("PageUp")), "PageUp is taken on row %d" % i)
        walked.append(_active())
    var upward := rows.duplicate()
    upward.reverse()
    assert_eq(walked, upward + ["Outsider"], "PageUp walks them back up and stops at the top")

    assert_eq(doc.undo_redo.get_version(), version, "with no history step")
    assert_eq(doc.modified, modified, "and the document no more changed than it was")
    assert_eq(_docker.item_list.picked.selected_idx, 0, "and the docker lights the row the key reached")


## A step that lands inside a shut group opens it, so the active layer always
## has a row the docker lights.
func test_a_step_into_a_shut_group_opens_it() -> void:
    var group := _stack()
    _docker._on_group_toggled(_rows().find("Group"))
    assert_false(_rows().has("Top"), "The group is shut")

    _router.handle(_press("PageDown"))
    assert_eq(_active(), "Group", "PageDown reaches the group's row")
    _router.handle(_press("PageDown"))
    assert_eq(_active(), "Top", "and the next one its top member")
    assert_false(_docker._closed_groups.has(group), "which opens the group")
    assert_eq(_docker.item_list.picked.selected_idx, _rows().find("Top"), "and the docker lights its row")


## Under Photoshop Alt and a bracket select the layer
## above and below and leave the brush's size, and a bracket that arrives as
## Ctrl+Alt, how a compositor may report AltGr, still sizes it.
func test_under_photoshop_alt_and_a_bracket_steps_and_altgr_still_sizes() -> void:
    _stack()
    SaShortcutStore.apply_profile("Photoshop")
    _router.handle(_press("Alt+["))
    assert_eq(_active(), "Group", "Alt+[ selects the layer below")
    var radius := _radius()

    assert_true(_router.handle(_press("Alt+]")), "Alt+] is taken")
    assert_eq(_active(), "Outsider", "by the layer above")
    assert_eq(_radius(), radius, "and the brush keeps its size")

    assert_true(_router.handle(_press("Ctrl+Alt+]")), "Ctrl+Alt+] is taken")
    assert_almost_eq(_radius(), radius + SaShortcutKeys.brush_size_step(radius, 1), 1e-6, "by the brush, a tenth larger")
    assert_eq(_active(), "Outsider", "with the active layer left where it was")


## Where no action holds Alt and a bracket, Sara Default's map, the bracket rule
## answers it as before, the AltGr keyboard `brush-size-brackets-2.json`
## stands for.
func test_under_sara_default_alt_and_a_bracket_still_sizes() -> void:
    _stack()
    var radius := _radius()

    assert_true(_router.handle(_press("Alt+]")), "Alt+] is taken")
    assert_almost_eq(_radius(), radius + SaShortcutKeys.brush_size_step(radius, 1), 1e-6, "by the brush, a tenth larger")
    assert_eq(_active(), "Outsider", "and the active layer stays")


## One bracket in a shape `brush-size-brackets-2.json` hands the app, the
## fields a keyboard leaves unset left at nought.
func _bracket(keycode: Key, physical: Key, label: Key, alt: bool) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = physical
    event.key_label = label
    event.alt_pressed = alt
    event.pressed = true
    return event


## The decline counts the bracket's own size action out. Sara Default holds
## the bracket by position, which a bracket sent as a keycode alone does not
## match exactly, and it answered nothing while the decline counted Larger
## brush as a holder, which `brush-size-brackets-2.json` caught.
func test_each_shape_of_a_bracket_still_sizes_the_brush() -> void:
    var shapes := {
        "position alone": _bracket(KEY_NONE, KEY_BRACKETRIGHT, KEY_NONE, false),
        "keycode alone": _bracket(KEY_BRACKETRIGHT, KEY_NONE, KEY_NONE, false),
        "label with Alt": _bracket(KEY_NONE, KEY_NONE, KEY_BRACKETRIGHT, true),
        "left keycode alone": _bracket(KEY_BRACKETLEFT, KEY_NONE, KEY_NONE, false),
    }
    for shape: String in shapes:
        var wanted := -1 if shape.begins_with("left") else 1
        assert_eq(SaShortcutKeys.brush_size_direction(shapes[shape]), wanted, "A bracket as its %s sizes the brush" % shape)
