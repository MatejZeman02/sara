## The active layer's opacity set by its name lands on the layer as one folded
## step, the opacity row's slider says that name, and a slider built with no
## name answers empty. A Preferences row's slider carries the setting's name and
## moves the setting while its page is shown.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The surface's easel and the layer's chunks need a RenderingDevice.
const REQUIRES_GPU := true

const SETTLE := &"settings/recorder_settle_seconds"

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _machine: ToolMachine = null
var _host: Node = null
var _values: SaAppDrive = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _registries = Fixtures.make_registries(_surface)
    _machine = ToolMachine.new()
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _host = Node.new()
    _host.name = "MidiLayerHost"
    EventBus.add_child(_host)
    var machine := _machine
    _values = SaAppDrive.new(func() -> ToolMachine: return machine)


func after_each() -> void:
    _values = null
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    _registries = null


func _document() -> SaDocument:
    return _surface.get_document()


## The ask: the opacity set by its name and read on the layer.
func test_the_opacity_set_by_its_name_is_the_layers() -> void:
    var layer := _document().active_layer
    assert_not_null(layer, "The document has an active layer")
    assert_true(_values.can_move(SaAppDrive.LAYER_OPACITY), "The opacity can be moved while a layer is active")
    var steps := _document().history.step_count()

    assert_true(_values.write(SaAppDrive.LAYER_OPACITY, 0.4), "The opacity is written by its name")
    assert_almost_eq(layer.opacity, 0.4, 1e-6, "The layer holds the opacity set")
    assert_almost_eq(_values.read(SaAppDrive.LAYER_OPACITY), 0.4, 1e-6, "The resolver reads it back by its name")
    assert_true(_values.write_ratio(SaAppDrive.LAYER_OPACITY, 0.75), "The opacity is set three quarters of the way")
    assert_almost_eq(layer.opacity, 0.75, 1e-6, "Three quarters is the layer's opacity")
    assert_eq(_document().history.step_count(), steps + 1, "A turn of a knob is one undo step, as a drag is")

    var above := SaLayerOps.new(_document()).add()
    _document().set_active_layer(above)
    assert_true(_values.write(SaAppDrive.LAYER_OPACITY, 0.2), "The name follows the active layer")
    assert_almost_eq(above.opacity, 0.2, 1e-6, "The layer made active takes it")
    assert_almost_eq(layer.opacity, 0.75, 1e-6, "The one below keeps its own")


## The slider a painter drags carries the name, and one built for nothing has none.
func test_the_opacity_row_names_its_slider_and_a_bare_slider_names_nothing() -> void:
    var row := SaLayerBlendOpacityRow.new()
    assert_eq(row.opacity_slider.value_name, SaAppDrive.LAYER_OPACITY, "The opacity row's slider names the layer's opacity")
    assert_eq(SaAppDrive.name_of(row.opacity_slider), SaAppDrive.LAYER_OPACITY, "The resolver reads the same name")
    row.free()

    var bare := FactorSlider.new()
    assert_eq(bare.value_name, &"", "A slider built with no name answers empty")
    assert_eq(SaAppDrive.name_of(bare), &"", "and the resolver reads nothing off it")
    bare.free()
    assert_eq(SaAppDrive.name_of(null), &"", "Nor off no control at all")


## With no layer to move, nothing is written.
func test_with_no_document_the_opacity_cannot_be_moved() -> void:
    var none := SaAppDrive.new(func() -> ToolMachine: return null)
    assert_false(none.can_move(SaAppDrive.LAYER_OPACITY), "No machine, no layer")
    assert_false(none.write(SaAppDrive.LAYER_OPACITY, 0.5), "and nothing written")
    assert_true(is_nan(none.range_of(SaAppDrive.LAYER_OPACITY).x), "and no range")


## A Preferences row's slider carries the setting's name, and moves the setting
## while its page is shown, and not once the page is gone.
func test_a_preferences_slider_moves_its_setting_while_its_page_is_shown() -> void:
    var was := SaSettings.recorder_settle_seconds
    var page := SaRecorderPage.new()
    _host.add_child(page)
    var slider := page.page.row(&"settle").control as Range
    assert_not_null(slider, "Timelapse has a settle slider")
    assert_eq(SaAppDrive.name_of(slider), SETTLE, "The row's slider names the setting")
    assert_true(_values.can_move(SETTLE), "The setting can be moved while its page is shown")

    var wanted := 12.5 if not is_equal_approx(was, 12.5) else 7.5
    assert_true(_values.write(SETTLE, wanted), "The setting is written by its name")
    assert_almost_eq(slider.value, wanted, 1e-6, "The page's slider stands at the value")
    assert_almost_eq(SaSettings.recorder_settle_seconds, wanted, 1e-6, "The setting holds it, as after a drag")
    assert_almost_eq(_values.read(SETTLE), wanted, 1e-6, "The resolver reads it back by its name")

    _host.remove_child(page)
    page.free()
    assert_false(_values.can_move(SETTLE), "With the page gone the setting cannot be moved now")
    SaSettings.recorder_settle_seconds = was
