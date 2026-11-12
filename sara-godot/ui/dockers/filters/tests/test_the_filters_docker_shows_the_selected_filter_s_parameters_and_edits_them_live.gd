## The Filters docker shows the picked filter's parameters and
## edits them live.
##
## The docker holds "the parameters of the selected filter layer" beside
## the list. Held here: a press on an adjustment layer's row shows that layer's
## own record in the docker, a picked attached record's row shows it in the
## docker and in Tool Options at once, a slider moved in either stands at the
## same value in the other and one undo puts both back, the part says so in a
## sentence when nothing is picked, a scenario's `control` step finds the
## docker's slider, and the docker builds no page while it is shut.
##
## The running app is `scenarios/the-filters-docker-shows-the-selected-filter-s-parameters-and-edits-them-live.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Walker = preload("res://harness/controls/sa_control_walker.gd")
const FilterParameters = preload("res://ui/dockers/filters/filter_parameters.gd")

## The panels redraw the canvas through the compositor.
const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const LEVELS_VALUES := {
    "in_black": 0.3, "gamma": 1.6, "in_white": 0.85, "out_black": 0.05, "out_white": 0.95, "channel": "master"
}
## Where a press lands on a row, inside it and clear of its buttons.
const PRESS_AT := Vector2(60, 8)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _registries: SaRegistries = null
var _registry: SaFilterRegistry = null
var _blur := StringName()
var _levels := StringName()
var _canvas: SaCanvas = null
var _layers: LayersDocker = null
var _options: ToolOptionsDocker = null
var _filters: FiltersDocker = null
var _window: SaFilterEditWindow = null
var _host: Node = null
var _was_embedding := false


## Embedding is forced the way the other Filters docker suites force it, so the dockers under the
## host map no OS window.
func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _was_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _easel = Bench.easel(Vector2i(256, 256))
    _doc = _easel.document
    _registries = Fixtures.make_registries()
    _registry = _easel.compositor.filter_chain.registry
    _registry.register(SaGaussianBlurFilter.new(), OWNER)
    _registry.register(SaLevelsFilter.new(), OWNER)
    _blur = SaFilterRegistry.key_for(OWNER, SaGaussianBlurFilter.new())
    _levels = SaFilterRegistry.key_for(OWNER, SaLevelsFilter.new())
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    _host = Node.new()
    _host.name = "R2ParametersHost"
    EventBus.add_child(_host)
    _options = ToolOptionsDocker.new()
    _host.add_child(_options)
    _filters = FiltersDocker.new()
    _filters.parameters.target_canvas = _canvas
    _filters.parameters.registry = _registry
    _host.add_child(_filters)
    _filters.show()
    _window = SaFilterEditWindow.new()
    _window.watch(_registry)
    _host.add_child(_window)
    _layers = LayersDocker.new()
    _layers.filter_registry = _registry
    _layers.target_canvas = _canvas
    _layers.tool_options = _options
    _host.add_child(_layers)
    _layers.sync_layer_list()


## The host is freed rather than queued, because `find_in` looks the docker up
## by its name and one waiting for the end of the frame would answer the next
## test's.
func after_each() -> void:
    _host.free()
    _host = null
    _layers = null
    _options = null
    _filters = null
    _window = null
    _canvas.free()
    _easel.free()
    _canvas = null
    _easel = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _was_embedding


func _part() -> FilterParameters:
    return _filters.parameters


func _docker_panel() -> SaFilterPanel:
    var panel := _part().panel
    return panel if panel != null and is_instance_valid(panel) else null


func _options_panel() -> SaFilterPanel:
    return _options._filter_panel as SaFilterPanel


## The row *layer* is drawn on, or -1.
func _row_of(layer: SaLayer) -> int:
    for i: int in _layers.item_list.row_count():
        if _layers.item_list.layer_at(i) == layer:
            return i
    return -1


## The row *record* is listed on, or -1.
func _row_of_record(record: SaAttachedFilter) -> int:
    for i: int in _layers.item_list.row_count():
        var view := (_layers.item_list as SaLayerList).filter_at(i)
        if view != null and view.record == record:
            return i
    return -1


## A left press on the row *idx*, as the row receives one.
func _press(idx: int) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = PRESS_AT
    press.global_position = PRESS_AT
    _layers.item_list.rows[idx].gui_input.emit(press)


## A Gaussian blur at *radius* attached to the active layer and its row pressed.
func _picked_blur(radius: float) -> SaAttachedFilter:
    var record := SaFilterOps.new(_doc).attach(_doc.active_layer, _blur, {"radius": radius})
    _layers.sync_layer_list()
    var row := _row_of_record(record)
    assert_true(row >= 0, "The blur is listed under its layer")
    _press(row)
    return record


## The Radius slider of *panel*.
static func _radius_of(panel: SaFilterPanel) -> FactorSlider:
    return panel.dialog.row(&"radius").control as FactorSlider if panel != null else null


## Moves *panel*'s Radius the way a hand does and lets the deferred write land.
func _move(panel: SaFilterPanel, radius: float) -> void:
    var slider := _radius_of(panel)
    slider.set_value_no_signal(radius)
    slider.value_changed.emit(slider.value)
    panel.dialog.flush_rerun()


func test_an_adjustment_layers_row_shows_its_own_record_in_the_docker() -> void:
    var layer := SaFilterConversion.new(_doc).add_holding(_levels, LEVELS_VALUES, _registries.layer_types, "Levels")
    assert_true(layer != null and layer.is_adjustment(), "A Levels adjustment layer is added")
    _layers.sync_layer_list()
    _press(_row_of(_doc.get_node("Background") as SaLayer))
    _press(_row_of(layer))
    assert_eq(_doc.active_layer, layer, "A press on its row makes it the active layer")
    var panel := _docker_panel()
    assert_not_null(panel, "and the docker holds a panel")
    if panel == null:
        return
    assert_eq(panel.record, layer.filters[0], "on the layer's own record")
    var said: Dictionary = _filters.describe()["parameters"]
    assert_eq(said["showing"]["filter"], String(_levels), "which is Levels")
    assert_eq(said["showing"]["parameters"]["gamma"], 1.6, "at the layer's own values")
    assert_eq(said["sentence"], "", "with no sentence beside it")


func test_a_picked_rows_record_is_in_both_panels() -> void:
    var record := _picked_blur(4.0)
    assert_eq(_layers.item_list.picked.selected_record, record, "The blur's row is the pick")
    assert_not_null(_options_panel(), "Tool Options shows a panel")
    assert_not_null(_docker_panel(), "and so does the docker")
    if _options_panel() == null or _docker_panel() == null:
        return
    assert_eq(_options_panel().record, record, "Tool Options is on the blur")
    assert_eq(_docker_panel().record, record, "and the docker on the same record")
    assert_false(_docker_panel() == _options_panel(), "each with a panel of its own")
    assert_eq(_radius_of(_docker_panel()).value, 4.0, "The docker's Radius reads 4")


func test_a_move_in_the_docker_is_one_step_and_the_tool_options_follow() -> void:
    var record := _picked_blur(4.0)
    assert_true(_docker_panel() != null and _options_panel() != null, "Both panels are up")
    if _docker_panel() == null or _options_panel() == null:
        return
    var steps := _doc.undo_redo.get_history_count()
    _move(_docker_panel(), 9.0)
    _move(_docker_panel(), 12.0)
    assert_eq(record.parameters["radius"], 12.0, "The record holds the docker's Radius")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "and the two moves are one step")
    assert_eq(_radius_of(_options_panel()).value, 12.0, "Tool Options' Radius stands at 12 too")
    assert_true(_doc.undo(), "Undo")
    assert_eq(record.parameters["radius"], 4.0, "One undo puts the record back")
    assert_eq(_radius_of(_docker_panel()).value, 4.0, "and the docker's Radius")
    assert_eq(_radius_of(_options_panel()).value, 4.0, "and Tool Options' Radius")


func test_a_move_in_tool_options_moves_the_docker() -> void:
    var record := _picked_blur(4.0)
    assert_true(_docker_panel() != null and _options_panel() != null, "Both panels are up")
    if _docker_panel() == null or _options_panel() == null:
        return
    _move(_options_panel(), 20.0)
    assert_eq(record.parameters["radius"], 20.0, "Tool Options writes the record")
    assert_eq(_radius_of(_docker_panel()).value, 20.0, "and the docker's Radius stands at 20")
    _move(_docker_panel(), 6.0)
    assert_eq(_radius_of(_options_panel()).value, 6.0, "and back the other way")


func test_with_nothing_picked_the_part_says_so() -> void:
    var said: Dictionary = _filters.describe()["parameters"]
    assert_eq(said["sentence"], FilterParameters.NOTHING_PICKED, "Nothing picked, the part says so")
    assert_eq(said["showing"], {}, "and holds no panel")
    _picked_blur(4.0)
    assert_eq(_filters.describe()["parameters"]["sentence"], "", "A pick takes the sentence away")
    _press(_row_of(_doc.active_layer))
    said = _filters.describe()["parameters"]
    assert_eq(said["sentence"], FilterParameters.NOTHING_PICKED, "and a press on a paint layer's row brings it back")
    assert_eq(said["showing"], {}, "with the panel gone")


func test_the_control_step_finds_the_dockers_radius() -> void:
    _picked_blur(4.0)
    var found := Walker.find((Engine.get_main_loop() as SceneTree).root, "Radius")
    assert_not_null(found, "A `control` step finds a made control called Radius")
    if found == null:
        return
    assert_true(_filters.is_ancestor_of(found), "in the Filters docker")
    assert_true(Walker.move(found, 15.0), "and moves it")
    _docker_panel().dialog.flush_rerun()
    assert_eq(_options_panel().record.parameters["radius"], 15.0, "which writes the record")
    assert_eq(_radius_of(_options_panel()).value, 15.0, "under Tool Options' Radius")


func test_a_shut_docker_builds_no_panel_and_shows_the_pick_when_opened() -> void:
    _filters.hide()
    var record := _picked_blur(4.0)
    assert_null(_docker_panel(), "A shut docker builds no panel")
    _filters.show()
    assert_not_null(_docker_panel(), "and opened, it shows the pick")
    if _docker_panel() != null:
        assert_eq(_docker_panel().record, record, "on the blur")


## The docker's default is 160 wide, and the blur's Radius asked 171 for its
## widest text before its slider took a floor. Levels' own page is 362 wide and
## scrolls sideways in the part.
func test_the_part_fits_the_docker_width() -> void:
    var room := float(SaUI.px(FiltersDocker.DEFAULT_SIZE.x))
    _picked_blur(4.0)
    var wide := _filters._column.get_combined_minimum_size().x
    assert_true(wide <= room, "The docker with the blur's panel asks %s, inside its default %s" % [wide, room])
    var layer := SaFilterConversion.new(_doc).add_holding(_levels, LEVELS_VALUES, _registries.layer_types, "Levels")
    _layers.sync_layer_list()
    _press(_row_of(layer))
    assert_eq(_docker_panel().record if _docker_panel() != null else null, layer.filters[0], "Levels is shown")
    wide = _filters._column.get_combined_minimum_size().x
    assert_true(wide <= room, "and with Levels' wider page it asks %s, still inside %s" % [wide, room])
