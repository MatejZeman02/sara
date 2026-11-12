## A stops field of the Exposure docker takes a typed number past its drag's
## reach.
##
## Each of the three rows is dragged to both ends and reads the reach it had
## before, 4 for View, 10 for Paint and 8 for Layer, and then a number is typed
## past it, the way a painter types one, and the field and the number's home
## both hold it as typed: the display exposure setting, the colour pair's
## stops and the Exposure filter's record. A half precision document's Paint
## field refuses a number past what half holds, says why, and leaves the pair
## alone.
extends "res://tests/test_framework.gd"

## The Layer row's preview and Apply run a kernel over a chunk.
const REQUIRES_GPU := true

const ExposureDocker = preload("res://modules/sara-base-modules/exposure/exposure_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const OWNER := &"sara-base-modules"
const SIZE := Vector2i(256, 256)

var _docker_host: Control = null
var _docker: ExposureDocker = null
var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null

var _view_before: float = 0.0
var _view_on_before: bool = false
var _foreground_before: Color = Color.BLACK
var _way_before: String = "bake"


func before_each() -> void:
    _view_before = SaSettings.display_exposure_stops
    _view_on_before = SaSettings.display_exposure_enabled
    _foreground_before = SaColors.foreground
    _way_before = SaSettings.filter_way
    SaSettings.display_exposure_stops = 0.0
    SaSettings.display_exposure_enabled = false
    SaColors.foreground = Color(0.5, 0.25, 0.0)
    _docker_host = Control.new()
    _docker = ExposureDocker.new()
    _docker_host.add_child(_docker)
    _docker._ready()


func after_each() -> void:
    if _docker_host != null:
        _docker_host.free()
        _docker_host = null
        _docker = null
    if _easel != null:
        _easel.free()
        _easel = null
    _doc = null
    _layer = null
    SaSettings.display_exposure_stops = _view_before
    SaSettings.display_exposure_enabled = _view_on_before
    SaSettings.filter_way = _way_before
    SaColors.foreground = _foreground_before


func test_the_view_row_drags_to_four_and_takes_twelve_typed() -> void:
    var slider := _docker.view_slider
    slider._set_from_drag(1.0)
    assert_almost_eq(slider.value, 4.0, 1e-6, "A drag to the right end reaches four stops, as before")
    slider._set_from_drag(0.0)
    assert_almost_eq(slider.value, -4.0, 1e-6, "and to the left end minus four")
    _type(slider, "12")
    assert_almost_eq(slider.value, 12.0, 1e-6, "Twelve typed is twelve in the field")
    assert_almost_eq(SaSettings.display_exposure_stops, 12.0, 1e-6, "and in the setting, which no longer cuts it to four")
    _type(slider, "-12")
    assert_almost_eq(SaSettings.display_exposure_stops, -12.0, 1e-6, "Minus twelve typed is held as well")


func test_the_paint_row_drags_to_ten_and_takes_forty_typed_on_a_float_document() -> void:
    _painting(SaColorSpace.linear_srgb(), SaFilterRegistry.new())
    var slider := _docker.paint_slider
    slider._set_from_drag(1.0)
    assert_almost_eq(slider.value, 10.0, 1e-6, "A drag to the right end reaches ten stops, as before")
    _type(slider, "40")
    assert_almost_eq(slider.value, 40.0, 1e-6, "Forty typed is forty in the field")
    assert_almost_eq(SaColors.exposure_stops, 40.0, 1e-6, "and the colour pair's stops, past the old 32")
    assert_false(_docker.paint_refusal.visible, "with nothing refused")


func test_the_layer_row_drags_to_eight_and_takes_minus_twelve_typed() -> void:
    SaSettings.filter_way = "attach"
    _painting(SaColorSpace.linear_srgb(), _exposure_registry())
    var slider := _docker.layer_row.slider
    slider._set_from_drag(1.0)
    assert_almost_eq(slider.value, 8.0, 1e-6, "A drag to the right end reaches eight stops, as before")
    slider._set_from_drag(0.0)
    assert_almost_eq(slider.value, -8.0, 1e-6, "and to the left end minus eight")
    _type(slider, "-12")
    assert_almost_eq(slider.value, -12.0, 1e-6, "Minus twelve typed is minus twelve in the field")
    assert_true(_docker.layer_row.apply(), "Apply attaches")
    assert_eq(_layer.filters.size(), 1, "The layer holds one record")
    var held := float(_layer.filters[0].parameters.get("stops", 0.0))
    assert_almost_eq(held, -12.0, 1e-6, "and the record holds minus twelve as typed")


func test_a_half_document_refuses_paint_past_what_half_holds_and_says_why() -> void:
    var half := SaColorSpace.linear_srgb()
    half.depth = SaColorSpace.Depth.F16
    _painting(half, SaFilterRegistry.new())
    var slider := _docker.paint_slider
    _type(slider, "12")
    assert_almost_eq(SaColors.exposure_stops, 12.0, 1e-6, "Twelve stops, a peak of 4096, a half document holds")
    var before := SaColors.foreground
    _type(slider, "20")
    assert_almost_eq(slider.value, 12.0, 1e-6, "Twenty typed is refused, and the field reads the stops the pair has")
    assert_almost_eq(SaColors.exposure_stops, 12.0, 1e-6, "The pair's stops are unchanged")
    assert_eq(SaColors.foreground, before, "and so is the foreground")
    assert_true(_docker.paint_refusal.visible, "The line under the field shows")
    var said := _docker.paint_refusal.text
    assert_true(said.contains("20.00"), "and names the number refused: %s" % said)
    assert_true(said.contains("15.99"), "and the most a half document holds: %s" % said)
    _type(slider, "3")
    assert_false(_docker.paint_refusal.visible, "A number the document holds takes the line away")


## Types *text* into *slider*'s number field and presses Enter. The field is
## shown by hand rather than by `start_editing`, which grabs the focus, and a
## docker in no tree has none to give: what Enter runs is the same.
func _type(slider: FactorSlider, text: String) -> void:
    slider._line_edit.visible = true
    slider._line_edit.text = text
    slider._on_line_edit_submitted(text)


## A document in *space* with one paint layer, under a canvas the docker is
## pointed at with *filters* as its registry.
func _painting(space: SaColorSpace, filters: SaFilterRegistry) -> void:
    _easel = SaEasel.create_default(SIZE, null, space)
    var registries := Fixtures.make_registries()
    _easel.compositor.set_registry(registries.blend_modes)
    _easel.compositor.filter_chain.registry = filters
    _doc = _easel.document
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(Color(0.25, 0.5, 0.1, 1.0))
    _docker.target_surface = SaSurface.create(&"probe", _easel, Fixtures.FakeView.new())
    _docker.filter_registry = filters
    _docker.layer_types = registries.layer_types
    _docker.follow()


func _exposure_registry() -> SaFilterRegistry:
    var filters := SaFilterRegistry.new()
    filters.register(SaExposureFilter.new(), OWNER)
    return filters
