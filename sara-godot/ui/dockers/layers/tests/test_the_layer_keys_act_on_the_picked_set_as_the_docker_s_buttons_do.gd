## The Layer menu's chords act on the Layers docker's picked rows as the docker's
## own buttons do.
##
## Without that, Ctrl+J, Ctrl+G, Ctrl+E, Shift+Delete,
## Ctrl+Shift+L and Ctrl+Alt+A would act on the active layer alone, and Ctrl+E would merge
## it into the layer under the set, one the painter never picked. Each case here
## builds the stack Layer 1, A, B and C afresh, picks C and then A with a
## Ctrl press on its row, runs the docker's button, and does the same again from
## a fresh stack with the chord pressed as a keyboard sends it, answered by the
## router the main window hands every key to. The two stacks must read the same.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _router: ShortcutRouter = null
var _canvas: SaCanvas = null
var _layers: LayersDocker = null
var _doc: SaDocument = null
var _saved_events: Dictionary = {}
var _layer_1_before: int = 0
var _layer_1_at: int = -1


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    _drop()
    for action: StringName in InputMap.get_actions():
        if not _saved_events.has(action):
            InputMap.erase_action(action)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## A fresh document holding Layer 1 as made under A, B and C, each filled, with
## the docker, the commands and the router over it, and C then A picked, or
## the rows *picks* names, the first plainly and the rest with Ctrl held.
func _fresh(picks: Array = ["C", "A"]) -> void:
    _drop()
    _surface = Fixtures.make_surface(Vector2i(128, 128))
    _registries = Fixtures.make_registries(_surface)
    _router = ShortcutRouter.new()
    _router.bind_commands(_registries.commands)
    _doc = _surface.easel.document
    var colours := [Color(0.8, 0.1, 0.1, 1.0), Color(0.1, 0.8, 0.1, 1.0), Color(0.1, 0.1, 0.8, 1.0)]
    SaLayerOps.new(_doc).rename(_doc.active_layer, "Layer 1")
    for i in 3:
        var layer := SaLayerOps.new(_doc).add()
        SaLayerOps.new(_doc).rename(layer, ["A", "B", "C"][i])
        _doc.fill_layer(colours[i], layer)
    _canvas = SaCanvas.new()
    _canvas.easel = _surface.easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()
    _doc.set_active_layer(_named("Layer 1"))
    _layer_1_before = _named("Layer 1").chunks.size()
    _layer_1_at = SaLayerOps.new(_doc).layers().find(_named("Layer 1"))
    for i in picks.size():
        _pick(_named(picks[i]), i > 0)


func _drop() -> void:
    if _layers != null:
        _layers.free()
        _layers = null
    if _canvas != null:
        _canvas.free()
        _canvas = null
    if _router != null:
        _router.free()
        _router = null
    _registries = null
    _doc = null
    if _surface != null:
        Fixtures.teardown(_surface)
        _surface = null


func _list() -> SaLayerList:
    return _layers.item_list


func _named(wanted: String) -> SaLayer:
    for layer in SaLayerOps.new(_doc).layers():
        if layer.name == wanted:
            return layer
    return null


## A press on *layer*'s row, Ctrl held or not, as the pointer sends it.
func _pick(layer: SaLayer, ctrl: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            _list()._on_row_gui_input(event, i)
            return


## The press a keyboard sends for *chord*, handed to the router.
func _press(chord: String) -> bool:
    var parsed := SaShortcutStore.parse_chord(chord)
    var event := InputEventKey.new()
    event.keycode = parsed.keycode
    event.physical_keycode = parsed.keycode
    event.key_label = parsed.keycode
    event.ctrl_pressed = parsed.ctrl_pressed
    event.shift_pressed = parsed.shift_pressed
    event.alt_pressed = parsed.alt_pressed
    event.pressed = true
    return _router.handle(event)


## The stack bottom first, each layer as its name, the group it stands in, its
## kind, its three flags and whether it holds paint.
func _stack() -> Array:
    var out: Array = []
    for layer in SaLayerOps.new(_doc).layers():
        var parent := SaLayerStack.parent_of(layer)
        (
            out
            . append(
                [
                    layer.name,
                    String(parent.name) if parent != null else "",
                    layer.is_group,
                    layer.is_locked,
                    layer.alpha_locked,
                    layer.clip_to_below,
                    layer.chunks.size(),
                ]
            )
        )
    return out


## The stack *button* gives on C and A, then the one *chord* gives on the same
## pick of a fresh stack. Answers both, the key's first, with the steps it wrote.
func _both(button: Callable, chord: String, picks: Array = ["C", "A"]) -> Dictionary:
    _fresh(picks)
    button.call()
    var by_button := _stack()
    _fresh(picks)
    assert_eq(_doc.picked.acted_on(_doc).size(), picks.size(), "the pick reaches the document as %s" % [picks])
    var steps := _doc.history.step_count() if _doc.history != null else 0
    assert_true(_press(chord), "the router takes %s" % chord)
    var wrote := (_doc.history.step_count() if _doc.history != null else 0) - steps
    return {"key": _stack(), "button": by_button, "steps": wrote}


func _same(chord: String, got: Dictionary) -> void:
    assert_eq(got["key"], got["button"], "%s leaves the stack the button leaves" % chord)


func test_ctrl_j_duplicates_every_picked_row() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.DUPLICATE), "Ctrl+J")
    _same("Ctrl+J", got)
    assert_not_null(_named("C Copy"), "Ctrl+J copies C")
    assert_not_null(_named("A Copy"), "and A")


func test_ctrl_g_groups_the_picked_rows() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.GROUP), "Ctrl+G")
    _same("Ctrl+G", got)
    var group := SaLayerStack.parent_of(_named("C"))
    assert_true(group != null and group.is_group, "C stands in a group")
    assert_eq(SaLayerStack.parent_of(_named("A")), group, "and A in the same one")


## C and A do not touch, so the button refuses them, and so does the key now,
## where it merged A into Layer 1.
func test_ctrl_e_on_c_and_a_leaves_layer_1_untouched() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.MERGE_DOWN), "Ctrl+E")
    _same("Ctrl+E", got)
    _layer_1_untouched()
    assert_not_null(_named("A"), "A is still a layer of its own")
    assert_eq(got["steps"], 0, "and nothing was written")


## A pick of C, B and A merges into A as the button does.
func test_ctrl_e_on_c_b_and_a_merges_them_into_a() -> void:
    var button := func() -> void: _layers.actions.press_item(SaLayerActions.Item.MERGE_DOWN)
    var got := _both(button, "Ctrl+E", ["C", "B", "A"])
    _same("Ctrl+E", got)
    _layer_1_untouched()
    assert_not_null(_named("A"), "A holds the merge")
    assert_null(_named("B"), "B went into it")
    assert_null(_named("C"), "and C")
    assert_eq(got["steps"], 1, "as one step")


func _layer_1_untouched() -> void:
    var stack := SaLayerOps.new(_doc).layers()
    var layer_1 := _named("Layer 1")
    assert_not_null(layer_1, "Layer 1 is still there")
    if layer_1 != null:
        assert_eq(stack.find(layer_1), _layer_1_at, "where it stood")
        assert_eq(layer_1.chunks.size(), _layer_1_before, "holding what it held, so nothing was merged into it")


func test_shift_delete_deletes_the_set_as_one_step() -> void:
    var got := _both(func() -> void: _layers.actions.delete_picked(), "Shift+Delete")
    _same("Shift+Delete", got)
    assert_null(_named("C"), "C is gone")
    assert_null(_named("A"), "and A")
    assert_not_null(_named("B"), "and B, which was not picked, stays")
    assert_eq(got["steps"], 1, "as one step")


func test_ctrl_shift_l_locks_every_picked_row_as_one_step() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.LOCK_PAINT), "Ctrl+Shift+L")
    _same("Ctrl+Shift+L", got)
    assert_true(_named("C").is_locked and _named("A").is_locked, "C and A are locked")
    assert_false(_named("B").is_locked, "and B is not")
    assert_eq(got["steps"], 1, "as one step")
    assert_true(_doc.undo(), "Ctrl+Z has the step")
    assert_false(_named("C").is_locked or _named("A").is_locked, "and takes both locks off")


func test_ctrl_alt_a_locks_the_alpha_of_every_picked_row_as_one_step() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.LOCK_ALPHA), "Ctrl+Alt+A")
    _same("Ctrl+Alt+A", got)
    assert_true(_named("C").alpha_locked and _named("A").alpha_locked, "C and A have the alpha locked")
    assert_eq(got["steps"], 1, "as one step")


func test_ctrl_shift_g_clips_every_picked_row_as_one_step() -> void:
    var got := _both(func() -> void: _layers.actions.press_item(SaLayerActions.Item.CLIP), "Ctrl+Shift+G")
    _same("Ctrl+Shift+G", got)
    assert_true(_named("C").clip_to_below and _named("A").clip_to_below, "C and A are clipped")
    assert_eq(got["steps"], 1, "as one step")
    assert_true(_doc.undo(), "Ctrl+Z has the step")
    assert_false(_named("C").clip_to_below or _named("A").clip_to_below, "and takes both clips off")


## With no docker to pick anything, each key acts on the active layer alone,
## as it always did.
func test_with_no_docker_a_key_acts_on_the_active_layer() -> void:
    _fresh()
    _layers.free()
    _layers = null
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    assert_eq(doc.picked.acted_on(doc), [doc.active_layer] as Array[SaLayer], "the set is the active layer")
    var before := SaLayerOps.new(doc).layers().size()
    assert_true(registries.commands.execute(&"layer_duplicate"), "Duplicate runs")
    assert_eq(SaLayerOps.new(doc).layers().size(), before + 1, "and copies the one layer")
    Fixtures.teardown(surface)
