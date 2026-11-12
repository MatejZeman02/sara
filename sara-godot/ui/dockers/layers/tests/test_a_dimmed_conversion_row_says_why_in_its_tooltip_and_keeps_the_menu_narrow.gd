## A dimmed menu row's reason is its tooltip, so no reason
## widens a menu across the screen.
##
## The Layers docker's right-click menu of an adjustment layer was
## almost 1500 pixels wide, because the dimmed Convert to Attached Filter row
## carried its whole refusal in the column a shortcut stands in. What this
## suite holds is that the refusal is the row's tooltip, the column is empty,
## and the menu is no wider than the same menu on a paint layer.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const RECORD := {"brightness": 30.0, "contrast": 25.0}

var _docker: LayersDocker = null
var _registries: SaRegistries = null
var _adjust: SaLayer = null
var _paint: SaLayer = null


## A paint layer, an adjustment layer holding a filter over it, and a paint
## layer over that, so the adjustment is not at the top and cannot convert.
func before_each() -> void:
    _registries = Fixtures.make_registries()
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.easel.compositor.filter_chain.registry = _registries.filters
    _registries.filters.register(SaBrightnessContrastFilter.new(), &"sara-base-modules")
    _docker = LayersDockerScript.new()
    _docker.name = "LayersDocker"
    canvas.add_child(_docker)
    _docker.target_canvas = canvas
    _docker._ready()
    _docker.bind_registries(_registries.blend_modes, _registries.layer_types)
    _docker.actions.op_buttons.commands = _registries.commands
    _docker.actions.op_buttons.fit(100000.0)
    var doc := _document()
    var ops := SaLayerOps.new(doc)
    _paint = doc.get_node("Layer 1") as SaLayer
    doc.set_active_layer(_paint)
    _adjust = ops.add(SaBackdropLayer.TYPE_ID, _registries.layer_types)
    _adjust.name = "Desaturate"
    var key := SaFilterRegistry.key_for(&"sara-base-modules", SaBrightnessContrastFilter.new())
    assert_not_null(SaFilterOps.new(doc).attach(_adjust, key, RECORD), "The filter attaches to the adjustment layer")
    ops.add()


func after_each() -> void:
    _docker.target_canvas.free()
    _docker = null
    _registries = null
    _adjust = null
    _paint = null


func _document() -> SaDocument:
    return _docker.target_canvas.document


## The menu drawn for *layer* as the right click draws it.
func _menu_on(layer: SaLayer) -> SaChoicePopup:
    _document().set_active_layer(layer)
    _docker.actions.sync_from_active_layer()
    return _docker.actions.menu


func test_the_conversion_row_says_its_refusal_in_its_tooltip_and_not_in_its_hint() -> void:
    assert_true(_adjust.is_adjustment(), "The middle layer is an adjustment layer")
    var refusal := SaFilterConversion.new(_document()).record_refusal(_adjust)
    assert_true(refusal.contains("is not at the top"), "and it cannot convert, not being at the top: %s" % refusal)
    var menu := _menu_on(_adjust)
    var row := SaLayerActions.LAYER_TO_FILTER
    assert_true(row in menu.row_ids(), "The menu has the conversion row")
    assert_true(menu.is_disabled(row), "dimmed")
    assert_eq(menu.row_of(row).hint_text(), "", "with nothing in its hint column")
    assert_eq(menu.label_button(row).tooltip_text, refusal, "and the refusal as its tooltip")


## The width the menu's rows ask for, the widest row's. Read off the rows
## rather than off `wanted_size`, because the column's cached minimum waits for
## a frame the suite does not run and answered the same before the fix as after.
func _widest_row(menu: SaChoicePopup) -> float:
    var widest := 0.0
    for id: StringName in menu.row_ids():
        widest = maxf(widest, menu.row_of(id).get_combined_minimum_size().x)
    return widest


func test_the_menu_is_no_wider_than_the_same_menu_on_a_paint_layer() -> void:
    var on_paint := _widest_row(_menu_on(_paint))
    var on_adjust := _widest_row(_menu_on(_adjust))
    assert_true(on_paint > 0.0, "The paint layer's menu has rows with a width")
    assert_true(on_adjust <= on_paint, "The adjustment's menu is %d wide, the paint layer's %d" % [on_adjust, on_paint])


func test_a_conversion_that_can_run_has_no_tooltip_and_no_hint() -> void:
    _document().move_child(_adjust, _document().get_child_count() - 1)
    var menu := _menu_on(_adjust)
    var row := SaLayerActions.LAYER_TO_FILTER
    assert_false(menu.is_disabled(row), "At the top the conversion is live")
    assert_eq(menu.row_of(row).hint_text(), "", "with no hint")
    assert_eq(menu.label_button(row).tooltip_text, "", "and no tooltip, as a menu bar row with nothing to add")
