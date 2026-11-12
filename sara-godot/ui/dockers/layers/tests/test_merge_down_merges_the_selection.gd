## Merge Down merges every picked row.
##
## A painter clicks Layer 3, shift-clicks Layer 1 so all three rows are
## highlighted, and presses Merge Down. Merging only Layer 3 into Layer 2 would
## leave the other highlight standing, so the docker's Merge Down reads the pick
## and not the active layer alone, and the pick goes into its
## lowest layer as one step, the uppers composited bottom to top.
##
## A docker is a `Window` and adding one to the tree in a headless test hangs,
## so nothing here enters the tree, as in `test_layer_multiselect.gd`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const MERGE := &"layer_merge_down"

var _easel: SaEasel
var _doc: SaDocument
var _docker: LayersDocker
var _layer_1: SaLayer
var _layer_2: SaLayer
var _layer_3: SaLayer


## Background, Layer 1, Layer 2 and Layer 3, each over the whole first chunk:
## Layer 1 mid grey, Layer 2 mid grey multiplying, and Layer 3 white at half
## opacity. On screen that is 0.5, then 0.25, then 0.625. Merged from the top
## down instead, Layer 3 goes into Layer 2 at Normal, 0.75, and that into
## Layer 1 by Layer 2's Multiply, 0.375, which is how a wrong order shows.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(256, 256))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    var ops := SaLayerOps.new(_doc)
    _layer_1 = _doc.active_layer
    _doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), _layer_1)
    _layer_2 = ops.add()
    _doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0), _layer_2)
    ops.set_blend_mode(_layer_2, SaLayer.BLEND_MODE.MULTIPLY)
    _layer_3 = ops.add()
    _doc.fill_layer(Color(1.0, 1.0, 1.0, 1.0), _layer_3)
    ops.set_opacity(_layer_3, 0.5)
    var canvas := SaCanvas.new()
    canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.target_canvas = canvas
    _docker.sync_layer_list()


func after_each() -> void:
    var canvas := _docker.target_canvas
    _docker.free()
    canvas.free()
    _easel.free()
    _docker = null
    _doc = null


func _row_of(layer: SaLayer) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == layer:
            return i
    return -1


## A plain click on *first*, then a Shift click on *last*, the run between them
## picked and *first* left active, as the list's own press leaves them.
func _shift_pick(first: SaLayer, last: SaLayer) -> void:
    _doc.set_active_layer(first)
    _docker.item_list.picked.press(_row_of(first), false, false)
    _docker.item_list.picked.press(_row_of(last), false, true)
    _docker.actions.sync_buttons()


func _names() -> Array[String]:
    var out: Array[String] = []
    for layer in SaLayerOps.new(_doc).layers():
        out.append(str(layer.name))
    return out


func _texel(layer: SaLayer) -> float:
    var image := SaExport.get_texture_image_float(layer.get_field(Vector2i.ZERO))
    return image.get_pixel(17, 17).r


## The Undo docker's rows, which are the history's action names.
func _merge_rows() -> int:
    var count := 0
    for index in _doc.undo_redo.get_history_count():
        if _doc.undo_redo.get_action_name(index) == "Merge Down":
            count += 1
    return count


func _merge_button() -> Button:
    return _docker.actions.op_buttons.button(MERGE)


## The refusals said while *work* runs, kept apart from the ones the suites
## before this one left.
func _refusals_during(work: Callable) -> PackedStringArray:
    var kept := SaProblems.pending_refusals
    var announcing := SaProblems.announce
    SaProblems.pending_refusals = PackedStringArray()
    SaProblems.announce = false
    work.call()
    var said := SaProblems.pending_refusals
    SaProblems.pending_refusals = kept
    SaProblems.announce = announcing
    return said


## The case that matters: Layer 3 clicked, Layer 1 shift-clicked, Merge Down
## pressed. One layer is left holding what the three showed, the Undo docker
## has one Merge Down row, and Ctrl+Z brings back all three.
func test_three_shift_picked_rows_merge_into_one_layer_as_one_step() -> void:
    _shift_pick(_layer_3, _layer_1)
    assert_eq(_docker.item_list.selected_layers().size(), 3, "Three rows are highlighted")
    assert_eq(_doc.active_layer, _layer_3, "and Layer 3, clicked first, stays active")
    assert_false(_merge_button().disabled, "Merge Down is live over the three")
    var steps := _doc.undo_redo.get_history_count()

    _merge_button().pressed.emit()

    assert_eq(_names(), ["Background", "Layer 1"], "One layer is left of the three, the lowest")
    assert_eq(_doc.active_layer, _layer_1, "and it is the active one")
    assert_almost_eq(_texel(_layer_1), 0.625, 1e-3, "holding what the three showed, composited bottom to top")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one step")
    assert_eq(_merge_rows(), 1, "and the Undo docker has one Merge Down row")
    _docker.sync_layer_list()
    assert_eq(_docker.item_list.selected_layers(), [_layer_1] as Array[SaLayer], "The pick is the merged row alone")

    assert_true(_doc.undo(), "Ctrl+Z")
    assert_eq(_names(), ["Background", "Layer 1", "Layer 2", "Layer 3"], "brings all three back, in their order")
    assert_almost_eq(_texel(_layer_1), 0.5, 1e-4, "Layer 1 with its own grey")
    assert_almost_eq(_texel(_layer_2), 0.5, 1e-4, "Layer 2 with its own")
    assert_eq(_layer_2.blend_mode, SaLayer.BLEND_MODE.MULTIPLY, "still multiplying")
    assert_almost_eq(_texel(_layer_3), 1.0, 1e-4, "and Layer 3 with its white")
    assert_almost_eq(_layer_3.opacity, 0.5, 1e-6, "at half opacity")

    assert_true(_doc.redo(), "Ctrl+Shift+Z")
    assert_eq(_names(), ["Background", "Layer 1"], "merges the three again")
    assert_almost_eq(_texel(_layer_1), 0.625, 1e-3, "into the same picture")


## Ctrl-click two rows with one between them: the button is dimmed, and the
## press, made through the action since a dimmed button takes none, says why
## nothing happened and leaves the stack and its history alone.
func test_a_pick_with_a_gap_says_why_nothing_happened() -> void:
    _doc.set_active_layer(_layer_3)
    _docker.item_list.picked.press(_row_of(_layer_3), false, false)
    _docker.item_list.picked.press(_row_of(_layer_1), true, false)
    _docker.actions.sync_buttons()
    assert_eq(_docker.item_list.selected_layers().size(), 2, "Two rows are picked, Layer 2 between them is not")
    assert_true(_merge_button().disabled, "Merge Down is dimmed over a gap")
    var steps := _doc.undo_redo.get_history_count()

    var said := _refusals_during(_docker.actions.merge_down)

    assert_eq(said.size(), 1, "The press says one thing")
    assert_true(
        said.size() == 1 and said[0].contains("Merge needs layers that sit next to each other"),
        "and it is why nothing happened: %s" % ", ".join(said)
    )
    assert_eq(_names(), ["Background", "Layer 1", "Layer 2", "Layer 3"], "Every layer is still there")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and the history has no new step")
    assert_almost_eq(_texel(_layer_1), 0.5, 1e-4, "nor Layer 1 new paint")


## One picked row merges into the one under it, as Merge Down always did.
func test_one_picked_row_merges_down_as_before() -> void:
    _doc.set_active_layer(_layer_3)
    _docker.item_list.picked.press(_row_of(_layer_3), false, false)
    _docker.actions.sync_buttons()
    assert_false(_merge_button().disabled, "Merge Down is live on one row with paint under it")

    _merge_button().pressed.emit()

    assert_eq(_names(), ["Background", "Layer 1", "Layer 2"], "Layer 3 alone went into Layer 2")
    assert_eq(_doc.active_layer, _layer_2, "and Layer 2 is active")
    assert_almost_eq(_texel(_layer_2), 0.75, 1e-3, "holding the white over its grey at half opacity")
    assert_almost_eq(_texel(_layer_1), 0.5, 1e-4, "and Layer 1 is untouched")
    assert_eq(_merge_rows(), 1, "as one Merge Down row")
    assert_true(_doc.undo(), "and one undo")
    assert_eq(_names(), ["Background", "Layer 1", "Layer 2", "Layer 3"], "brings Layer 3 back")


## A run picked from the bottom layer up. The bottom layer alone has nothing
## under it to merge into, so the active layer's own test dims the button,
## and the folded More menu row with it, which then refused its press. Both
## ask the pick, and both merge it.
func test_a_run_from_the_bottom_layer_merges_from_the_button_and_the_folded_row() -> void:
    var background := SaLayerOps.new(_doc).layers()[0]
    _shift_pick(background, _layer_1)
    assert_false(SaLayerOps.new(_doc).can_merge_down(background), "The bottom layer alone has nothing to merge into")
    assert_false(_merge_button().disabled, "and the button is live over the two")

    _docker.actions.op_buttons.fit(0.0)
    _docker.actions.sync_from_active_layer()
    assert_true(_docker.actions.menu.row_ids().has(MERGE), "On a docker too narrow for it the row is in the More menu")
    assert_false(_docker.actions.menu.is_disabled(MERGE), "and it is live as the button was")
    assert_true(_docker.actions.menu.press_row(MERGE), "and takes the press")

    assert_eq(_names(), ["Background", "Layer 2", "Layer 3"], "Layer 1 went into the background")
    assert_almost_eq(_texel(background), 0.5, 1e-4, "which shows the same grey")
    assert_eq(_merge_rows(), 1, "as one Merge Down row")


## The pick over two parents is a gap as well, and a group in the pick is
## refused with the sentence Merge Down gives a group, each before anything
## moves. Picked by hand, since a Shift range always runs over siblings.
func test_a_pick_over_a_group_s_edge_and_a_picked_group_are_refused() -> void:
    var ops := SaLayerOps.new(_doc)
    var group := ops.group_layers([_layer_2])
    var steps := _doc.undo_redo.get_history_count()
    assert_eq(_names(), ["Background", "Layer 1", "Layer 2", "Group 1", "Layer 3"], "Layer 2 is in a group")

    var across: Array[SaLayer] = [_layer_2, _layer_3]
    var across_says := SaLayerOps.MergePick.new(_doc, across).refusal()
    assert_false(ops.can_merge_down(_layer_3, across), "A member and the layer over its group do not merge")
    assert_true(across_says.contains("next to each other"), "and say why: %s" % across_says)
    var over_group: Array[SaLayer] = [group, _layer_3]
    var group_says := SaLayerOps.MergePick.new(_doc, over_group).refusal()
    assert_false(ops.can_merge_down(_layer_3, over_group), "A group and the layer over it do not merge")
    assert_true(group_says.contains("is a group"), "and say why: %s" % group_says)

    var said := _refusals_during(func() -> void: ops.merge_down(_layer_3, over_group))
    assert_eq(said.size(), 1, "The press says one thing")
    assert_eq(_names(), ["Background", "Layer 1", "Layer 2", "Group 1", "Layer 3"], "and nothing moved")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "with no step")
