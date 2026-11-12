## Ctrl+Shift+E merges the visible layers, and the brush
## editor, which held that chord, moves to F5.
##
## The brush editor held Ctrl+Shift+E before it moved to F5. Krita ships both chords:
## Ctrl+Shift+E merges what is visible and F5 opens Edit Brush Settings.
##
## Every press is a key as a keyboard sends it, through the router the main
## window hands every unhandled key to, over the application's whole map, so
## a second command on either chord would take the press first. The brush
## editor's handler opens the window a frame later, which a suite cannot wait
## for, so the press is read as the command running, with a probe
## where the handler was. A scenario presses F5 on the running app and reads
## `SaBrushEditorWindow` in the dump.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The proof is the pixels the merge leaves, which needs a RenderingDevice.
const REQUIRES_GPU := true

const GROUND := Color(0.8, 0.3, 0.1, 1.0)
const HALF := Color(0.1, 0.7, 0.3, 0.5)
const MULTIPLIED := Color(0.5, 0.9, 0.6, 1.0)
const HIDDEN := Color(0.0, 0.0, 1.0, 1.0)
## Where the three visible layers all draw, where only the ground does, and
## where the multiply layer stands alone over the ground.
const POINTS: Array[Vector2i] = [Vector2i(20, 20), Vector2i(200, 200), Vector2i(150, 30)]

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _heard: Array[String] = []
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    SaAppCommands.register_all(_registries, func(_docker_id: StringName) -> void: pass)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _heard.clear()
    SaProblems.pending_refusals = PackedStringArray()
    EventBus.corner_notice.connect(_hear)
    EventBus.paint_refused.connect(_hear)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    EventBus.paint_refused.disconnect(_hear)
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


func _hear(line: String) -> void:
    _heard.append(line)


## A key as a keyboard sends it: the character's code, its position and its
## label all set, with Ctrl and Shift as asked.
func _press(keycode: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.key_label = keycode
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    event.pressed = true
    return event


## A layer above the active one with *color* over *rect* of the first chunk.
func _painted(color: Color, rect: Rect2i) -> SaLayer:
    var doc: SaDocument = _surface.easel.document
    var layer := SaLayerOps.new(doc).add()
    doc.selection.select_rect(rect)
    doc.fill_layer(color, layer)
    doc.selection.deselect()
    return layer


## The four layers: the surface's own two, its ground filled over the whole
## chunk and its paint layer half opaque over a corner, a Multiply layer, and a
## hidden blue one on top that would cover all of it were it shown.
func _four() -> Array[SaLayer]:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var stack := ops.layers()
    assert_eq(stack.size(), 2, "The surface opens on a ground and one layer")
    var ground := stack[0]
    doc.fill_layer(GROUND, ground)
    var half := stack[1]
    doc.selection.select_rect(Rect2i(0, 0, 64, 64))
    doc.fill_layer(HALF, half)
    doc.selection.deselect()
    var multiplied := _painted(MULTIPLIED, Rect2i(0, 0, 192, 64))
    ops.set_blend_mode(multiplied, &"multiply")
    var hidden := _painted(HIDDEN, Rect2i(0, 0, 256, 256))
    ops.set_visible(hidden, false)
    return [ground, half, multiplied, hidden]


## The canvas's own composite at each of `POINTS`.
func _output() -> Array[Color]:
    Bench.composite(_surface.easel)
    var found: Array[Color] = []
    for at in POINTS:
        found.append(Bench.texel(_surface.easel.output, at))
    return found


## *layer*'s own paint at each of `POINTS`.
func _paint(layer: SaLayer) -> Array[Color]:
    var found: Array[Color] = []
    var field: SaTexture = layer.get_or_create_field(Vector2i.ZERO)
    for at in POINTS:
        found.append(Bench.texel(field, at))
    return found


func _same(was: Array[Color], now: Array[Color], what: String) -> void:
    for i in was.size():
        var a: Color = was[i]
        var b: Color = now[i]
        var moved := maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))
        assert_true(moved < 0.01, "%s, point %s: %s against %s" % [what, POINTS[i], a, b])


## Four layers, one hidden and one multiplying: Ctrl+Shift+E leaves two, the
## hidden one as it was and one merged layer whose paint is what the canvas
## showed, and one Ctrl+Z gives the four back.
func test_ctrl_shift_e_merges_the_visible_layers_and_one_undo_gives_them_back() -> void:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var four := _four()
    var hidden: SaLayer = four[3]
    var hidden_paint := _paint(hidden)
    var shown := _output()
    var steps := doc.history.step_count()

    assert_true(_router.handle(_press(KEY_E, true, true)), "The router takes Ctrl+Shift+E")

    var left := ops.layers()
    assert_eq(left.size(), 2, "Two layers are left")
    assert_true(left.has(hidden), "and the hidden one is one of them")
    assert_false(hidden.visible, "still hidden")
    _same(hidden_paint, _paint(hidden), "with its paint untouched")
    var merged: SaLayer = left[0]
    assert_eq(left.find(hidden), 1, "standing above the merged layer, as it stood above the three")
    assert_eq(str(merged.name), str(four[2].name), "The merged layer takes the topmost visible layer's name")
    assert_eq(merged.blend_mode, SaLayer.BLEND_MODE.NORMAL, "and shows its paint plainly")
    assert_almost_eq(merged.opacity, 1.0, 0.0001, "at full opacity")
    _same(shown, _paint(merged), "The merged layer's paint is the composite")
    _same(shown, _output(), "and the canvas did not move")
    assert_eq(doc.history.step_count(), steps + 1, "in one history step")
    assert_true(_heard.is_empty(), "A merge that runs says nothing: %s" % ", ".join(_heard))

    # What the router's Ctrl+Z runs, `_handle_history`'s `document.undo()`,
    # called as it calls it: the router reaches the document through a canvas,
    # which a surface built for a suite does not have.
    assert_true(doc.undo(), "One Ctrl+Z takes a step back")

    assert_eq(ops.layers(), four, "One undo gives the four back in their order")
    assert_eq(four[2].blend_mode, &"multiply", "the multiply layer still multiplying")
    _same(shown, _output(), "and the canvas is what it was")


## Merge Visible stands in the Layer menu with the chord in its hint, and no
## other command answers Ctrl+Shift+E.
func test_merge_visible_holds_ctrl_shift_e_alone() -> void:
    var commands := _registries.commands
    var command := commands.get_descriptor(&"layer_merge_visible")
    assert_not_null(command, "Merge Visible is registered")
    if command == null:
        return
    assert_eq(command.menu_label(), "Merge Visible", "named as the menu draws it")
    assert_eq(command.category, &"layer", "among the layer commands")
    assert_eq(commands.chord_text(&"layer_merge_visible"), "Ctrl+Shift+E", "on Ctrl+Shift+E")
    var others: Array[String] = []
    for command_id: StringName in commands.list_ids():
        if command_id != &"layer_merge_visible" and "Ctrl+Shift+E" in commands.chord_text(command_id).split(", ", false):
            others.append(String(command_id))
    assert_true(others.is_empty(), "and nothing else does: %s" % ", ".join(others))
    var rows: Array = []
    for row: Variant in SaLayerMenuRows.ROWS:
        if row is Array and row[0] == &"layer_merge_visible":
            rows.append(row)
    assert_eq(rows.size(), 1, "The Layer menu draws one row for it")


## A visible locked layer refuses the whole merge and the corner names it.
func test_a_locked_visible_layer_refuses_the_merge_and_is_named() -> void:
    var doc: SaDocument = _surface.easel.document
    var ops := SaLayerOps.new(doc)
    var four := _four()
    four[1].is_locked = true
    var steps := doc.history.step_count()

    _router.handle(_press(KEY_E, true, true))

    assert_eq(ops.layers(), four, "Every layer stays")
    assert_eq(doc.history.step_count(), steps, "and the history did not move")
    var said := SaProblems.pending_refusals
    assert_eq(said.size(), 1, "One line in the corner")
    if not said.is_empty():
        assert_true(said[0].contains(str(four[1].name)), "naming the locked layer: %s" % said[0])
        assert_true(said[0].contains("locked"), "and the lock: %s" % said[0])


## F5 runs the brush editor's command, Ctrl+Shift+E no longer does, and the
## command carries F5 alone.
func test_f5_opens_the_brush_editor_and_ctrl_shift_e_no_longer_does() -> void:
    var commands := _registries.commands
    assert_eq(commands.chord_text(&"edit_brush"), "F5", "Edit Brush answers F5, Krita's own key for it")
    var ran := [0]
    var command := commands.get_descriptor(&"edit_brush")
    command.handler = func() -> bool:
        ran[0] += 1
        return true

    assert_true(_router.handle(_press(KEY_F5)), "The router takes F5")
    assert_eq(ran[0], 1, "and F5 runs the brush editor's command")

    _router.handle(_press(KEY_E, true, true))
    assert_eq(ran[0], 1, "Ctrl+Shift+E no longer runs it")
