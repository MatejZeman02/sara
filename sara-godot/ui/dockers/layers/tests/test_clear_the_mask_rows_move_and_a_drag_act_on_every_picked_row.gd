## Clear Layer, the mask rows, Move Up and Move Down and a drag act on every
## picked row, each as one undo step.
##
## On a picked set these would otherwise act on the active row alone, so Move
## would pull the set apart and a drag would carry only the row under the pointer. The running app's half, with
## real presses, a real drag and a real Ctrl+Z, is
## `scenarios/clear-the-mask-rows-move-and-a-drag-act-on-every-picked-row.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _layers: LayersDocker
var _a: SaLayer
var _b: SaLayer
var _c: SaLayer


func before_each() -> void:
    _easel = Bench.easel(Vector2i(128, 128))
    _doc = _easel.document
    _a = _doc.active_layer
    _a.name = "A"
    _b = SaLayerOps.new(_doc).add()
    _b.name = "B"
    _c = SaLayerOps.new(_doc).add()
    _c.name = "C"
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _layers = LayersDocker.new()
    _layers.target_canvas = _canvas
    _layers.list_keeper.listen()
    _layers.sync_layer_list()


func after_each() -> void:
    _layers.free()
    _canvas.free()
    _easel.free()
    _a = null
    _b = null
    _c = null


func _list() -> SaLayerList:
    return _layers.item_list


func _row_of(layer: SaLayer) -> int:
    for i in _list().rows.size():
        if _list().layer_at(i) == layer:
            return i
    return -1


## A press on *layer*'s row, plain or with Ctrl, as the painter picks.
func _pick(layer: SaLayer, ctrl: bool = false) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = true
    event.ctrl_pressed = ctrl
    _list()._on_row_gui_input(event, _row_of(layer))


func _names() -> PackedStringArray:
    var names := PackedStringArray()
    for layer in SaLayerOps.new(_doc).layers():
        names.append(str(layer.name))
    return names


func _paint(layer: SaLayer) -> void:
    _doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), layer)


## C and B painted, A painted too so the row nobody picked can be read.
func _fill_stack() -> void:
    _paint(_a)
    _paint(_b)
    _paint(_c)


## The note's first case: C and B picked on a filled stack, Clear Layer, both
## empty, and one Ctrl+Z refills both.
func test_two_picked_rows_clear_as_one_step() -> void:
    _fill_stack()
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.clear_layer()

    assert_true(_c.chunks.is_empty() and _b.chunks.is_empty(), "both picked rows are empty")
    assert_false(_a.chunks.is_empty(), "and the row nobody picked keeps its paint")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Clear Layers", "named for the set")
    assert_true(_doc.undo(), "the step is undone")
    assert_false(_c.chunks.is_empty() or _b.chunks.is_empty(), "one Ctrl+Z refills both")
    assert_true(_doc.redo(), "and redone")
    assert_true(_c.chunks.is_empty() and _b.chunks.is_empty(), "which empties both again")


## The Layer menu's Clear Layer is the `layer_clear` command, which Backspace
## runs too, and it empties the picked set as the docker's row does: the
## running app's scenario found it clearing the active layer alone.
func test_the_clear_command_empties_the_picked_set_as_one_step() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var doc: SaDocument = surface.easel.document
    var low := doc.active_layer
    var high := SaLayerOps.new(doc).add()
    doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), low)
    doc.fill_layer(Color(0.8, 0.2, 0.1, 1.0), high)
    doc.picked.pick([high, low])
    var steps := doc.history.step_count()

    assert_true(registries.commands.execute(&"layer_clear"), "the command runs")

    assert_true(high.chunks.is_empty() and low.chunks.is_empty(), "both picked layers are empty")
    assert_eq(doc.history.step_count(), steps + 1, "as one step")
    assert_true(doc.undo(), "the step is undone")
    assert_false(high.chunks.is_empty() or low.chunks.is_empty(), "one Ctrl+Z refills both")
    registries = null
    Fixtures.teardown(surface)


## A set of one clears as it always did, its step keeping its name.
func test_one_picked_row_clears_as_it_always_did() -> void:
    _fill_stack()
    _pick(_b)
    _layers.actions.clear_layer()
    assert_true(_b.chunks.is_empty(), "the row is empty")
    assert_false(_c.chunks.is_empty(), "and its neighbour is not")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Clear Layer", "one Clear Layer step")


## Add Mask on C and B gives both a mask, and one Ctrl+Z takes both away.
func test_two_picked_rows_add_a_mask_as_one_step() -> void:
    _fill_stack()
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.run_mask_command(SaMaskOps.ADD)

    assert_true(_c.mask != null and _b.mask != null, "both picked rows have a mask")
    assert_null(_a.mask, "and the row nobody picked has none")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_c.mask == null and _b.mask == null, "one Ctrl+Z takes both masks off")


## Delete Mask on C and B, both masked, takes both off, and one Ctrl+Z puts
## both back.
func test_two_picked_rows_delete_their_masks_as_one_step() -> void:
    _fill_stack()
    SaMaskOps.new(_doc).add(_c)
    SaMaskOps.new(_doc).add(_b)
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.run_mask_command(SaMaskOps.DELETE)

    assert_true(_c.mask == null and _b.mask == null, "both masks are gone")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_c.mask != null and _b.mask != null, "one Ctrl+Z puts both back")


## Disable Mask on a mixed set lands every mask on the state the active row's
## tick promised, as one step.
func test_disable_mask_follows_the_active_row() -> void:
    SaMaskOps.new(_doc).add(_c)
    SaMaskOps.new(_doc).add(_b)
    SaMaskOps.new(_doc).set_enabled(_c, false)
    _pick(_c)
    _pick(_b, true)
    var steps := _doc.history.step_count()

    _layers.actions.run_mask_command(SaMaskOps.DISABLE)

    assert_false(_c.mask.enabled or _b.mask.enabled, "both masks are off, as B's tick said")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_true(_b.mask.enabled and not _c.mask.enabled, "and each is back as it was")


## The note's second case: B and A picked, Move Up, the two still side by side
## one place higher, and one Ctrl+Z puts them back.
func test_two_picked_rows_move_up_as_one_block() -> void:
    _pick(_b)
    _pick(_a, true)
    var steps := _doc.history.step_count()

    _layers.actions.move_layer(1)

    assert_eq(_names(), PackedStringArray(["Background", "C", "A", "B"]), "B and A one place higher, side by side")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "one Ctrl+Z puts them back")
    assert_true(_doc.redo(), "and redone")
    assert_eq(_names(), PackedStringArray(["Background", "C", "A", "B"]), "which moves them up again")


## Move Down on C, B and A, the three as one block one place lower, under
## Background.
func test_three_picked_rows_move_down_as_one_block() -> void:
    _pick(_c)
    _pick(_b, true)
    _pick(_a, true)

    _layers.actions.move_layer(-1)

    assert_eq(_names(), PackedStringArray(["A", "B", "C", "Background"]), "the three one place lower, in their order")
    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "one Ctrl+Z puts them back")


## A set whose front row is at the top does not move, rather than closing up.
func test_a_set_at_the_top_stays_put() -> void:
    _pick(_c)
    _pick(_a, true)
    var steps := _doc.history.step_count()
    _layers.actions.move_layer(1)
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "nothing moved")
    assert_eq(_doc.history.step_count(), steps, "and no step was written")


## Ctrl+PageUp's command reads the picked set the docker handed the document,
## and moves it as Move Up does.
func test_the_move_up_chord_moves_the_set() -> void:
    _pick(_b)
    _pick(_a, true)
    SaLayerSetStep.new(_doc).move(_doc.picked.acted_on(_doc), 1)
    assert_eq(_names(), PackedStringArray(["Background", "C", "A", "B"]), "the set moved as one block")


## The note's third case: B and A picked, a press on A, a drag onto
## Background's lower half, and B and A together under Background in their
## order, as one step.
func test_a_drag_carries_every_picked_row() -> void:
    _pick(_b)
    _pick(_a, true)
    var steps := _doc.history.step_count()
    var background := _doc.get_node("Background") as SaLayer

    _pick(_a)
    assert_eq(_list().selected_layers().size(), 2, "the press on a picked row keeps the set for the drag")
    _list().dragging = true
    _list().drag_over(_row_of(background), SaLayerList.Drop.BELOW)
    _list().drop()

    assert_eq(_names(), PackedStringArray(["A", "B", "Background", "C"]), "B and A together under Background, in their order")
    assert_eq(_doc.history.step_count(), steps + 1, "as one step")
    assert_eq(_list().selected_layers().size(), 2, "and both are still picked")
    assert_true(_doc.undo(), "the step is undone")
    assert_eq(_names(), PackedStringArray(["Background", "A", "B", "C"]), "one Ctrl+Z puts both back")


## A plain click on a picked row that drags nothing leaves that row picked
## alone.
func test_a_click_without_a_drag_still_picks_one_row() -> void:
    _pick(_b)
    _pick(_a, true)
    _pick(_b)
    _list().drop()
    assert_eq(_list().selected_layers(), [_b] as Array[SaLayer], "the clicked row alone is picked at the release")
    assert_eq(_doc.active_layer, _b, "and it is the active layer")


## A drag of the set onto a group's middle puts every picked row in the group.
func test_a_drag_into_a_group_takes_the_set_in() -> void:
    var group := SaLayerOps.new(_doc).group_layers([_c])
    _layers.sync_layer_list()
    _pick(_b)
    _pick(_a, true)
    _pick(_a)
    _list().dragging = true
    _list().drag_over(_row_of(group), SaLayerList.Drop.INTO)
    _list().drop()
    assert_eq(SaLayerStack.parent_of(_a), group, "A went into the group")
    assert_eq(SaLayerStack.parent_of(_b), group, "and so did B")
    assert_true(_b.get_index() > _a.get_index(), "in their order")
