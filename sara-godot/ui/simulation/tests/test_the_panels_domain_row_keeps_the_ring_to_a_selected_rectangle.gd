## The simulation panel's domain row. Its Selection button keeps
## the ring a simulation grows to the rectangle the selection lies in, and its
## Canvas button lets it grow anywhere on the canvas again, and the row says
## which holds.
##
## The canvas is three chunks square with Spread on the middle chunk, so the
## first ring is the eight round it on the canvas and three in the middle
## column.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const FRAME := 1.0 / 60.0
const MIDDLE := Vector2i(1, 1)

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _host: Node = null
var _docker: ToolOptionsDocker = null
var _follower: SaSimulationPanel = null


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _surface = Fixtures.make_surface(Vector2i(3, 3) * SaChunk.SIZE)
    _registries = Fixtures.make_registries(_surface)
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    _host = Node.new()
    _docker = ToolOptionsDocker.new()
    _host.add_child(_docker)
    _follower = SaSimulationPanel.new(_registries, _docker)
    _host.add_child(_follower)


func after_each() -> void:
    _host.free()
    _surface.get_document().free()
    _surface.easel.free()
    _surface = null
    _registries = null
    SaProblems.pending_refusals = PackedStringArray()


func _frame() -> void:
    _follower._process(FRAME)


func _press(button_name: String) -> void:
    var button := _docker.find_child(button_name, true, false) as Button
    assert_not_null(button, "The panel holds %s" % button_name)
    if button != null:
        button.pressed.emit()


func _row() -> Dictionary:
    return _follower.report().get("panel", {})


## A paint layer of its own, active, holding the middle chunk, with Spread on.
func _simulated() -> SaLayer:
    var document := _surface.get_document()
    var layer := SaLayerOps.new(document).add(&"")
    document.set_active_layer(layer)
    layer.get_or_create_chunk(MIDDLE)
    SaSimulation.put_on(layer, _registries.simulation_rules.find(&"spread"))
    return layer


func _held(layer: SaLayer) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    out.assign(layer.chunks.keys())
    out.sort()
    return out


func test_selection_keeps_the_ring_to_the_selected_column_and_canvas_lets_it_grow_everywhere() -> void:
    var layer := _simulated()
    var record := SaSimulation.record_of(layer)
    _frame()
    assert_eq(_row().get("domain"), "Area: the whole canvas", "The row says the canvas holds by default")
    assert_false(_row().get("selection_enabled"), "and offers no Selection while nothing is selected")

    var column := Rect2i(Vector2i(SaChunk.SIZE, 0), Vector2i(SaChunk.SIZE, 3 * SaChunk.SIZE))
    _surface.get_document().selection.select_rect(column)
    _frame()
    assert_true(_row().get("selection_enabled"), "A selection offers Selection")
    _press("SimulationGrowInSelection")
    assert_eq(record.domain, column, "which sets the domain to the rectangle the selection lies in")
    _frame()
    assert_eq(_row().get("domain"), "Area: 256 × 768 px at 256, 0", "and the row says so")
    assert_eq(_follower.report().get("domain"), [256, 0, 256, 768], "as the state dump does")

    _press("SimulationStep")
    var want: Array[Vector2i] = [Vector2i(1, 0), MIDDLE, Vector2i(1, 2)]
    assert_eq(_held(layer), want, "The first ring keeps to the selected column")

    _press("SimulationGrowOnCanvas")
    assert_false(record.domain.has_area(), "Canvas lets it grow anywhere again")
    _press("SimulationReset")
    _press("SimulationStep")
    assert_eq(_held(layer).size(), 9, "and the first ring after a reset is the eight round it")
    _frame()
    assert_eq(_row().get("domain"), "Area: the whole canvas", "and the row says the canvas again")


func test_selection_with_nothing_selected_is_refused_and_leaves_the_domain() -> void:
    var layer := _simulated()
    var document := _surface.get_document()
    assert_false(SaSimulation.grow_inside_selection(document, layer), "Nothing selected, Selection is refused")
    assert_false(SaSimulation.record_of(layer).domain.has_area(), "and the domain stays the canvas")
    assert_eq(SaProblems.pending_refusals.size(), 1, "with a line saying why")
