## The Layers docker builds a deep stack's rows a part a frame and ends on what
## one sync in one frame drew.
##
## A large test document's 756 rows were built in the one frame its open ended in,
## over a second of it. Now a list in the tree builds as many new rows a frame
## as a twentieth of a second holds and owes the rest. A stack of 756 rows is
## built here twice on one canvas: whole, by a keeper whose list stands outside
## the tree, as every sync was built before, and in parts, by one whose list
## stands in it. Once the parts are done the two lists hold the same rows in
## the same order at the same indents, the same picks, the same active row and
## the same folds. A change of the stack between two parts leaves the rows of
## the stack as it then stands. The frames are [method SaLayerListKeeper.next_part],
## called straight, because a suite that awaits drops every assertion after the
## await.
extends "res://tests/test_framework.gd"

## The rows draw their pictures with compute dispatches.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The rows a large test document draws, and the groups they stand in.
const ROWS := 756
const GROUP_EVERY := 28

## More parts than any machine needs, so a build that never ends fails here
## rather than looping.
const MOST_PARTS := 400

var _easel: SaEasel
var _doc: SaDocument
var _canvas: SaCanvas
var _host: Control
var _whole_list: SaLayerList
var _whole: SaLayerListKeeper
var _parted_list: SaLayerList
var _parted: SaLayerListKeeper
var _folded: SaLayer


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(64, 64))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    _doc = _easel.document
    _stack()
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "BuildHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _whole = null
    _parted = null
    for list: SaLayerList in [_whole_list, _parted_list]:
        if list != null:
            if list.get_parent() != null:
                list.get_parent().remove_child(list)
            list.free()
    _whole_list = null
    _parted_list = null
    _host.free()
    _canvas.free()
    _easel.free()


## Groups of [constant GROUP_EVERY] layers, one more group's worth shut
## inside a folded group, and loose layers on top until the rows a sync draws
## are [constant ROWS]. The layers are put into the document as a file's load
## puts them, members below their group, because adding 756 through
## [SaLayerOps] one by one costs a step and a refresh each, seconds that grow
## with the stack.
func _stack() -> void:
    var made := 1
    for g in 25:
        var group := _layer("G%d" % g, true, null)
        for i in GROUP_EVERY:
            _doc.add_child(_layer("L%d" % made, false, group))
            made += 1
        _doc.add_child(group)
    _folded = _layer("Shut", true, null)
    for i in GROUP_EVERY:
        _doc.add_child(_layer("In%d" % i, false, _folded))
    _folded.folded = true
    _doc.add_child(_folded)
    var top := 0
    while _shown() < ROWS and top < ROWS:
        _doc.add_child(_layer("Top%d" % top, false, null))
        top += 1
    assert_eq(_shown(), ROWS, "The stack shows its rows")


func _layer(layer_name: String, is_group: bool, group: SaLayer) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    layer.is_group = is_group
    layer.group = group
    layer.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    return layer


## The layers whose rows a sync draws: every one but those in the shut group.
func _shown() -> int:
    var count := 0
    for child in _doc.get_children():
        var layer := child as SaLayer
        if layer == null or layer == _doc.stroke_layer:
            continue
        if layer == _folded or not SaLayerStack.is_inside(layer, _folded):
            count += 1
    return count


## The name of the loose layer *below* rows under the top of the stack.
func _top(below: int) -> String:
    var layers := _doc.get_children().filter(func(child: Node) -> bool: return child is SaLayer and child != _doc.stroke_layer)
    return str(layers[layers.size() - 1 - below].name)


func _keeper(in_tree: bool) -> SaLayerListKeeper:
    var list := SaLayerList.new()
    if in_tree:
        _host.add_child(list)
        _parted_list = list
    else:
        _whole_list = list
    var keeper := SaLayerListKeeper.new(list, _canvas)
    keeper.listen()
    return keeper


## What the painter sees in a list: each row's layer, indent and fold mark,
## the picked rows, the active row and the picked filter.
static func _seen(list: SaLayerList) -> Dictionary:
    var rows: Array = []
    for i in list.row_count():
        var row: SaRowFrame = list.rows[i]
        rows.append([list.layer_at(i), row.indent_depth, row.collapsed])
    return {
        "rows": rows,
        "picked": list.picked.selected_indices(),
        "active": list.picked.selected_idx,
        "record": list.picked.selected_record,
    }


## Runs the frames the build owes, and answers how many it took.
func _finish(keeper: SaLayerListKeeper) -> int:
    var parts := 0
    while keeper._build.owing and parts < MOST_PARTS:
        keeper.next_part()
        parts += 1
    return parts


func _picked_set() -> Array[SaLayer]:
    var out: Array[SaLayer] = []
    for name: String in ["L3", "L400", _top(1)]:
        out.append(_doc.get_node(name) as SaLayer)
    return out


func test_the_parts_end_on_what_one_sync_draws() -> void:
    _doc.set_active_layer(_doc.get_node("L400") as SaLayer)
    _whole = _keeper(false)
    assert_eq(_whole_list.row_count(), ROWS, "The stack draws a large test document's rows")
    _whole_list.select_layers(_picked_set(), _doc.active_layer)
    _parted = _keeper(true)
    assert_true(_parted._build.owing, "A list in the tree owes the rest of a deep stack to the frames after")
    assert_true(_parted_list.row_count() < ROWS, "The first frame built a part of the rows")
    var first := _parted_list.row_count()
    var top_rows := (_seen(_whole_list)["rows"] as Array).slice(0, first)
    assert_eq(_seen(_parted_list)["rows"], top_rows, "The part built is the top of the stack, in its order")
    var parts := _finish(_parted)
    assert_false(_parted._build.owing, "The build ends, in %d parts" % parts)
    assert_true(parts > 1, "The rest took more than one frame")
    assert_eq(_seen(_parted_list), _seen(_whole_list), "The rows, picks, active row and folds are what one sync drew")
    var shut := func(row: SaRowFrame) -> bool: return row.layer == _folded and row.collapsed
    assert_true(_parted_list.rows.any(shut), "The shut group's row is drawn shut")


func test_a_list_outside_the_tree_is_built_whole() -> void:
    _whole = _keeper(false)
    assert_false(_whole._build.owing, "A list with no frames owes nothing")
    assert_eq(_whole_list.row_count(), ROWS, "Every row is built in the one sync")


func test_a_change_of_the_stack_mid_build_builds_the_stack_as_it_then_stands() -> void:
    _parted = _keeper(true)
    assert_true(_parted._build.owing, "The build is under way")
    var ops := SaLayerOps.new(_doc)
    ops.add().name = "Added"
    var gone := _doc.get_node("L5") as SaLayer
    ops.remove(gone)
    var moved := _doc.get_node(_top(0)) as SaLayer
    ops.place(moved, null, 1)
    _folded.folded = false
    _doc.document_changed.emit()
    _finish(_parted)
    assert_false(_parted._build.owing, "The build ends")
    _whole = _keeper(false)
    assert_eq(_seen(_parted_list)["rows"], _seen(_whole_list)["rows"], "The rows are the stack as it stands after the change")
    assert_eq(_parted_list.picked.selected_idx, _whole_list.picked.selected_idx, "The active row is the stack's active layer")
    assert_false(_seen(_parted_list)["rows"].any(func(row: Array) -> bool: return row[0] == gone), "The deleted layer has no row")


func test_a_press_mid_build_acts_on_the_row_the_painter_sees() -> void:
    _parted = _keeper(true)
    # The third row, since a part builds at least [constant
    # SaLayerListBuild.FEWEST] rows, which is three.
    var shown := _parted_list.layer_at(SaLayerListBuild.FEWEST - 1)
    assert_not_null(shown, "The first part drew the row pressed")
    _parted.select_row(SaLayerListBuild.FEWEST - 1)
    assert_eq(_doc.active_layer, shown, "The press made the row's own layer active")
    _finish(_parted)
    var lit := _parted_list.layer_at(_parted_list.picked.selected_idx)
    assert_eq(lit, shown, "The pressed row is still the lit one once the rows are built")
