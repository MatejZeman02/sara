## An adjustment layer is one row in the Layers docker, and the filters attached
## to it are listed under it. A Levels layer does not carry an `ƒ Levels` row
## under it as well: the layer acts as the effect, and new effects attach to it.
##
## The layer's first record is the layer: its row stands for it, a click on the
## row opens its settings on a double click on its picture,
## and it is not listed under the row. The records
## attached after it are listed under the row as a plain layer's are, the one
## that runs last nearest the row. The click is driven by a press delivered to
## the row the way a hand's is, and the window is the filter editor under a host
## the way the suites of the dialogs hold one. The running app's half is
## `scenarios/an-adjustment-layer-is-one-row-and-filters-attached-to-it-are-listed.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER := &"sara-base-modules"
const LEVELS_VALUES := {
    "in_black": 0.3, "gamma": 1.6, "in_white": 0.85, "out_black": 0.05, "out_white": 0.95, "channel": "master"
}
const CURVES_VALUES := {"curves": {"master": [[0.0, 0.0], [0.375, 0.75], [1.0, 1.0]], "blue": [[0.0, 0.25], [1.0, 0.75]]}}
## Where a press lands on a row, inside it and clear of its buttons.
const PRESS_AT := Vector2(60, 8)
## Where the file goes for the save and reopen.
static var scratch_path: String = SaDataRoot.path("n3_adjustment_row.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _background: SaLayer = null
var _registries: SaRegistries = null
var _registry: SaFilterRegistry = null
var _levels: StringName = &""
var _curves: StringName = &""
var _canvas: SaCanvas = null
var _docker: LayersDocker = null
var _window: SaFilterEditWindow = null
var _host: Node = null
var _was_embedding := false
## The rows the document's own layers make before an adjustment layer is added.
var _layers_listed := 0


## Embedding is forced the way `test_escape_closes_a_dialog.gd` forces it:
## without it `add_child` maps a real OS window and the run blocks until the
## watchdog.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _background = _doc.get_node("Background") as SaLayer
    _registries = Fixtures.make_registries()
    _registry = _easel.compositor.filter_chain.registry
    _registry.register(SaLevelsFilter.new(), OWNER)
    _registry.register(SaCurvesFilter.new(), OWNER)
    _levels = SaFilterRegistry.key_for(OWNER, SaLevelsFilter.new())
    _curves = SaFilterRegistry.key_for(OWNER, SaCurvesFilter.new())
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _docker = LayersDocker.new()
    _docker.filter_registry = _registry
    _docker.target_canvas = _canvas
    _docker.sync_layer_list()
    _layers_listed = _docker.item_list.row_count()
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _host = Node.new()
    _host.name = "N3AdjustmentRowHost"
    EventBus.add_child(_host)
    _host.add_child(_window)
    _host.add_child(_docker)


## The host is freed rather than queued: the capture and `find_in` look a window
## up by its name, and one waiting for the end of the frame would still answer
## to the next test's.
func after_each() -> void:
    _host.free()
    _host = null
    _window = null
    _docker = null
    _canvas.free()
    _easel.free()
    _canvas = null
    _easel = null
    _doc = null
    _background = null
    _registries = null
    _registry = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding
    if FileAccess.file_exists(scratch_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_path))


## The docker's list, typed.
func _list() -> SaLayerList:
    return _docker.item_list


## A Levels adjustment layer above the active layer, as the kind browser makes
## it, listed.
func _levels_layer() -> SaLayer:
    var layer := SaFilterConversion.new(_doc).add_holding(_levels, LEVELS_VALUES, _registries.layer_types, "Levels")
    assert_true(layer != null and layer.is_adjustment(), "A Levels adjustment layer is added")
    _docker.sync_layer_list()
    return layer


## The records the docker lists under *node*, top to bottom.
func _listed_under(node: SaLayer) -> Array[SaAttachedFilter]:
    var found: Array[SaAttachedFilter] = []
    for i: int in _docker.item_list.row_count():
        var view := _list().filter_at(i)
        if view != null and view.node == node:
            found.append(view.record)
    return found


## The row *layer* is drawn on, or -1.
func _row_of(layer: SaLayer) -> int:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.layer_at(i) == layer:
            return i
    return -1


## How many rows the list holds that are a filter's.
func _filter_rows() -> int:
    var count := 0
    for i: int in _docker.item_list.row_count():
        if _list().filter_at(i) != null:
            count += 1
    return count


## A left press on the row *idx*, as the row receives one.
func _press(idx: int, ctrl: bool = false) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = PRESS_AT
    press.global_position = PRESS_AT
    press.ctrl_pressed = ctrl
    _docker.item_list.rows[idx].gui_input.emit(press)


func test_a_filter_layer_is_one_row() -> void:
    var layer := _levels_layer()
    assert_eq(layer.filters.size(), 1, "The layer holds its one record")
    assert_eq(_docker.item_list.row_count(), _layers_listed + 1, "and the list holds one row more than before, the layer's")
    assert_eq(_filter_rows(), 0, "neither of them the record again")
    assert_eq(_listed_under(layer), [] as Array[SaAttachedFilter], "Nothing is listed under the adjustment layer's row")
    assert_eq(_docker.item_list.layer_at(0), layer, "and the layer's row is its own")
    assert_eq(_docker.item_list.rows[0].label, "Levels", "titled by the layer's name")
    assert_eq(SaBackdropLayer.own_filter(layer), layer.filters[0], "The first record is the layer's own")
    assert_eq(SaBackdropLayer.own_filter(_background), null, "A plain layer has none")


func test_a_record_attached_after_it_is_listed_under_the_row() -> void:
    var layer := _levels_layer()
    var curves := SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    assert_eq(_listed_under(layer), [curves] as Array[SaAttachedFilter], "Curves is listed under the Levels layer")
    assert_eq(_docker.item_list.row_count(), _layers_listed + 2, "as a row of its own")
    assert_eq(_docker.item_list.record_at(_row_of(layer) + 1), curves, "directly under the layer's row")
    var again := SaFilterOps.new(_doc).attach(layer, _levels, LEVELS_VALUES)
    _docker.sync_layer_list()
    assert_eq(
        _listed_under(layer),
        [again, curves] as Array[SaAttachedFilter],
        "A third is listed above it, the one that runs last first"
    )
    var titles: Array[String] = []
    for i: int in _docker.item_list.row_count():
        var view := _list().filter_at(i)
        if view != null:
            titles.append(view.filter_title)
    assert_eq(titles, ["Levels 2", "Curves"] as Array[String], "and a second Levels is numbered past the layer's own")


func test_undo_removes_the_attached_record_and_the_layer_stays_one_row() -> void:
    var layer := _levels_layer()
    var own := layer.filters[0]
    SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    assert_eq(_docker.item_list.row_count(), _layers_listed + 2, "The layer and Curves are listed")
    assert_true(_doc.undo(), "Undo")
    _docker.sync_layer_list()
    assert_eq(layer.filters, [own] as Array[SaAttachedFilter], "takes Curves off and leaves the layer its own record")
    assert_eq(_docker.item_list.row_count(), _layers_listed + 1, "and the layer is still one row")
    assert_eq(_filter_rows(), 0, "with nothing under it")


## A single click picks the layer and opens nothing, whose
## suite reads a double click on the picture opening the layer's own record.
func test_a_click_on_the_row_picks_the_layer_and_opens_no_settings() -> void:
    var layer := _levels_layer()
    assert_false(_window.visible, "No settings are open before the click")
    _press(_row_of(layer))
    assert_false(_window.visible, "A click on the adjustment layer's row opens no filter editor")
    assert_eq(_doc.active_layer, layer, "and the layer is the active one")
    assert_eq(_docker.item_list.picked.selected_record, null, "with no filter row picked")


func test_a_click_on_other_rows_opens_nothing() -> void:
    var layer := _levels_layer()
    _press(_row_of(_background))
    assert_false(_window.visible, "A click on a plain layer's row opens no window")
    var curves := SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    _press(_row_of(layer), true)
    assert_false(_window.visible, "nor does a ctrl click, which adds to the set")
    assert_eq(_docker.item_list.selected_layers().size(), 2, "the two layers being picked")
    _press(_row_of(layer) + 1)
    assert_false(_window.visible, "A press on an attached record's row picks it and leaves the window shut")
    assert_eq(_docker.item_list.picked.selected_record, curves, "Curves being the pick")


func test_taking_the_first_record_off_makes_the_next_the_layers_own() -> void:
    var layer := _levels_layer()
    var levels := layer.filters[0]
    var ops := SaFilterOps.new(_doc)
    var curves := ops.attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    _docker.item_list.picked.pick_filter(curves)
    assert_true(ops.detach(layer, levels), "The first record comes off, as a script or Tool Options takes it")
    _docker.sync_layer_list()
    assert_eq(SaBackdropLayer.own_filter(layer), curves, "Curves is the layer's own now")
    assert_eq(_listed_under(layer), [] as Array[SaAttachedFilter], "and has no row under it")
    assert_eq(_docker.item_list.row_count(), _layers_listed + 1, "so the layer is one row")
    assert_eq(_docker.item_list.picked.selected_record, null, "and a pick on it is let go, there being no row to hold it")
    _press(_row_of(layer))
    assert_false(_window.visible, "A click on the row opens no settings, a double click on its picture does")
    assert_true(_doc.undo(), "Undo")
    _docker.sync_layer_list()
    assert_eq(SaBackdropLayer.own_filter(layer), levels, "puts Levels back as the layer's own")
    assert_eq(_listed_under(layer), [curves] as Array[SaAttachedFilter], "and Curves under the row")


func test_deleting_the_row_deletes_the_layer() -> void:
    var layer := _levels_layer()
    SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    _docker.item_list.picked.select(_row_of(layer))
    _docker.actions.delete_picked()
    _docker.sync_layer_list()
    assert_true(not is_instance_valid(layer) or layer.get_parent() != _doc, "The layer, with its records, is gone")
    assert_eq(_filter_rows(), 0, "and no record row is left over")
    assert_true(_doc.undo(), "Undo")
    _docker.sync_layer_list()
    assert_eq(
        _listed_under(layer), [layer.filters[1]] as Array[SaAttachedFilter], "brings the layer back with Curves under its row"
    )


func test_converting_the_layer_back_lists_its_records_where_they_land() -> void:
    var layer := _levels_layer()
    var levels := layer.filters[0]
    var curves := SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    assert_true(_docker.actions.convert_layer_to_filter(), "Convert to Attached Filter turns the layer back into records")
    _docker.sync_layer_list()
    assert_eq(_docker.item_list.row_count(), _layers_listed + 2, "The layer's row is gone and its two records are rows")
    assert_eq(
        _listed_under(null), [curves, levels] as Array[SaAttachedFilter], "listed on the root, the one that runs last first"
    )
    assert_true(_doc.undo(), "Undo")
    _docker.sync_layer_list()
    assert_eq(_listed_under(layer), [curves] as Array[SaAttachedFilter], "puts the layer back with Curves under its row")


func test_a_drag_among_the_attached_records_leaves_the_layers_own_first() -> void:
    var layer := _levels_layer()
    var own := layer.filters[0]
    var ops := SaFilterOps.new(_doc)
    var second := ops.attach(layer, _curves, CURVES_VALUES)
    var third := ops.attach(layer, _levels, LEVELS_VALUES)
    _docker.sync_layer_list()
    var rows: SaLayerList = _docker.item_list
    rows.begin_drag(rows.rows.find(_row_view(second)))
    rows.drag_over(rows.rows.find(_row_view(third)), SaLayerList.Drop.ABOVE)
    rows.drop()
    assert_eq(
        layer.filters,
        [own, third, second] as Array[SaAttachedFilter],
        "Curves dropped above the newest runs last, after the layer's own"
    )
    rows.begin_drag(rows.rows.find(_row_view(second)))
    rows.drag_over(rows.rows.find(_row_view(third)), SaLayerList.Drop.BELOW)
    rows.drop()
    assert_eq(
        layer.filters,
        [own, second, third] as Array[SaAttachedFilter],
        "and dropped below it runs before it, never before the layer's own"
    )


func test_save_and_reopen_lists_the_same() -> void:
    var layer := _levels_layer()
    SaFilterOps.new(_doc).attach(layer, _curves, CURVES_VALUES)
    _docker.sync_layer_list()
    var before := _shape()
    assert_eq(SaExport.save_sad(_doc, scratch_path, 0), OK, "Saved")
    var loaded := SaExport.load_sad(_doc, ProjectSettings.globalize_path(scratch_path))
    assert_eq(loaded, OK, "and reopened")
    # The kind is bound back to the layers by Main on a load, which is not here.
    _registries.layer_types.rebind(_doc.get_children().filter(func(child: Node) -> bool: return child is SaLayer))
    _docker.sync_layer_list()
    assert_eq(_shape(), before, "The list is the same: %s" % [before])


## The list as a column of words: a layer's name, a record's title.
func _shape() -> Array[String]:
    var shape: Array[String] = []
    for i: int in _docker.item_list.row_count():
        var view := _list().filter_at(i)
        if view != null:
            shape.append("  %s" % view.filter_title)
        else:
            shape.append(String(_docker.item_list.layer_at(i).name))
    return shape


func _row_view(record: SaAttachedFilter) -> SaFilterRowView:
    for i: int in _docker.item_list.row_count():
        if _docker.item_list.record_at(i) == record:
            return _list().filter_at(i)
    return null
