## An Exposure docker holds the view's, the paint's and the layer's exposure.
##
## Three rows, each moved here the way a hand moves it and read
## where the number lives: the View row in `SaSettings.display_exposure_stops`,
## the Paint row in the foreground's stops and on the bar's Exposure, and the
## Layer row in the layer's values, untouched while a drag previews and scaled
## after Apply, as one undo step. The Display page's slider is moved too, and
## the View row read following it.
##
## Built the way the app builds it: the real options bar over a machine bound to
## the stamp and base modules' registry for the Paint row, and for the Layer row
## a canvas over an easel whose filter registry holds the Exposure filter under
## the base module's id, the key the app registers it under.
extends "res://tests/test_framework.gd"

## The machine builds every tool, and the Layer row's preview and Apply run a
## kernel over a chunk.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const ExposureDocker = preload("res://modules/sara-base-modules/exposure/exposure_docker.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")

## The base module's id, which the Exposure filter is registered under.
const OWNER := &"sara-base-modules"
const SIZE := Vector2i(256, 256)
const PROBE := Vector2i(100, 100)
const TOLERANCE := 1.0e-3

## The paint and the same at +2 stops, in a linear document so the numbers
## read back are the light.
const PAINT := Color(0.25, 0.5, -0.1, 1.0)
const PLUS_TWO := Color(1.0, 2.0, -0.4, 1.0)

static var scratch_dir: String = SaDataRoot.path("test_e4_presets")

var _docker_host: Control = null
var _docker: ExposureDocker = null
var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null

## The Paint row's bench: a surface, the modules' registries, a machine and
## the bar over it.
var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null

## What the suite moves, put back after.
var _view_before: float = 0.0
var _view_on_before: bool = false
var _foreground_before: Color = Color.BLACK
var _way_before: String = "bake"
var _every_before: bool = false


func before_each() -> void:
    _view_before = SaSettings.display_exposure_stops
    _view_on_before = SaSettings.display_exposure_enabled
    _foreground_before = SaColors.foreground
    _way_before = SaSettings.filter_way
    _every_before = SaSettings.filter_affect_all
    SaSettings.display_exposure_stops = 0.0
    SaSettings.display_exposure_enabled = false
    SaSettings.filter_way = "bake"
    SaSettings.filter_affect_all = false
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
    _free_the_bar()
    SaSettings.display_exposure_stops = _view_before
    SaSettings.display_exposure_enabled = _view_on_before
    SaSettings.filter_way = _way_before
    SaSettings.filter_affect_all = _every_before
    SaColors.foreground = _foreground_before


## The View row writes the stops the Display page writes, and puts the
## exposure on off nought and off at nought, the page's own rule.
func test_the_view_row_writes_the_display_exposure() -> void:
    _move(_docker.view_slider, 1.5)
    assert_almost_eq(SaSettings.display_exposure_stops, 1.5, 1e-6, "The View row wrote the display exposure")
    assert_true(SaSettings.display_exposure_enabled, "and put it on")
    assert_true(_docker.view_switch.button_pressed, "with its switch following")
    _move(_docker.view_slider, 0.0)
    assert_false(SaSettings.display_exposure_enabled, "Back at nought it is off again")
    _docker.view_switch.button_pressed = true
    assert_true(SaSettings.display_exposure_enabled, "and the switch alone puts it on")


## Second: the Display page's slider moved, and the View row
## reads it. The page's slider is dragged as its own suite drags it, the value
## and the signal a hand's drag fires, since a page built here is in no tree.
func test_the_display_pages_slider_moves_the_view_row() -> void:
    var page := SaDisplayPage.new()
    _drag(page._exposure_slider, -2.0)
    assert_almost_eq(SaSettings.display_exposure_stops, -2.0, 1e-6, "The page's drag wrote the stops")
    assert_almost_eq(_docker.view_slider.value, -2.0, 1e-6, "and the View row follows it")
    assert_true(_docker.view_switch.button_pressed, "with its switch on as the page's is")
    _drag(page._exposure_slider, 0.75)
    assert_almost_eq(_docker.view_slider.value, 0.75, 1e-6, "A second drag on the page moves it again")
    page.free()


## The Paint row is the paint's number: a move here is the foreground's stops, the
## bar's Exposure and the colour docker's row, and a move elsewhere comes back.
func test_the_paint_row_moves_the_foregrounds_stops_and_the_bar() -> void:
    _build_the_bar()
    var colour := ColorDocker.new()
    _docker_host.add_child(colour)
    colour._ready()
    var colours_row := colour.find_child("PaintExposureSlider", true, false) as FactorSlider
    assert_not_null(colours_row, "The colour docker has its stops slider")
    _move(_docker.paint_slider, 2.0)
    assert_almost_eq(SaColors.exposure_stops, 2.0, 1e-6, "The Paint row moved the foreground's stops")
    _near(SaColors.foreground, Color(2.0, 1.0, 0.0), "The foreground is (0.5, 0.25, 0) at two stops")
    assert_almost_eq(float(_bar.control_value(&"exposure")), 2.0, 1e-6, "and the bar's Exposure reads two")
    assert_almost_eq(colours_row.value, 2.0, 1e-6, "and so does the colour docker's row")
    SaColors.exposure_stops = 0.5
    assert_almost_eq(_docker.paint_slider.value, 0.5, 1e-6, "A move of the store elsewhere comes back to the row")


## The Layer row on Bake: a drag shows the layer at +2 stops on the canvas and
## writes nothing, and Apply writes it, one undo step, and Undo takes it back.
func test_a_drag_previews_and_apply_bakes_the_layer_as_one_step() -> void:
    _painting(_exposure_registry())
    assert_eq(_docker.layer_row.describe()["filter"], "%s.exposure" % OWNER, "The row found the filter by its id")
    _move(_docker.layer_row.slider, 2.0)
    _near(_shown(), PLUS_TWO, "The drag shows the layer at +2 stops")
    _near(_stored(), PAINT, "while the layer is as painted")
    assert_false(_docker.layer_row.apply_button.disabled, "and Apply is live")
    var steps := _doc.undo_redo.get_history_count()
    _docker.layer_row.apply_button.pressed.emit()
    _near(_stored(), PLUS_TWO, "Apply wrote +2 stops into the layer")
    _near(_shown(), PLUS_TWO, "which the canvas shows with no preview standing")
    assert_null(_easel.compositor.point_preview.for_document(_doc), "The preview is off the canvas")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "Apply is one undo step")
    assert_almost_eq(_docker.layer_row.slider.value, 0.0, 1e-6, "and the slider is back at nought")
    _doc.undo()
    _near(_stored(), PAINT, "Undo puts the paint back")


## The Layer row on Attach: Apply hangs one record on the layer and writes no
## pixel, and the composite reads it.
func test_apply_on_attach_hangs_the_record_and_leaves_the_paint() -> void:
    SaSettings.filter_way = "attach"
    _painting(_exposure_registry())
    assert_eq(_docker.layer_row.way_toggle.value, &"attach", "The toggle follows the remembered way")
    _move(_docker.layer_row.slider, 2.0)
    var steps := _doc.undo_redo.get_history_count()
    assert_true(_docker.layer_row.apply(), "Apply attaches")
    assert_eq(_layer.filters.size(), 1, "The layer holds one record")
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "as one undo step")
    _near(_stored(), PAINT, "Its pixels are as painted")
    _near(_shown(), PLUS_TWO, "and the composite reads +2 stops")


## Affect all and the way are the dialog's preferences: a tick and a pick here
## write them, and a write elsewhere moves them here.
func test_affect_all_and_the_way_are_the_dialogs_preferences() -> void:
    _painting(_exposure_registry())
    var row := _docker.layer_row
    row.affect_all.button_pressed = true
    assert_true(SaSettings.filter_affect_all, "A tick writes Affect all")
    row.way_toggle.picked.emit(&"layer")
    assert_eq(SaSettings.filter_way, "layer", "and a pick the way")
    SaSettings.filter_affect_all = false
    assert_false(row.affect_all.button_pressed, "A write elsewhere unticks it")
    SaSettings.filter_way = "attach"
    assert_eq(row.way_toggle.value, &"attach", "and moves the thumb")


## A drag left standing comes off the canvas when the painter goes to another
## layer, and nothing is written.
func test_a_preview_comes_off_when_the_active_layer_changes() -> void:
    _painting(_exposure_registry())
    _move(_docker.layer_row.slider, 2.0)
    assert_not_null(_easel.compositor.point_preview.for_document(_doc), "The drag previews")
    _doc.set_active_layer(_doc.get_node("Background") as SaLayer)
    _docker.follow()
    assert_null(_easel.compositor.point_preview.for_document(_doc), "Another layer takes the preview off")
    assert_almost_eq(_docker.layer_row.slider.value, 0.0, 1e-6, "and the slider back to nought")
    _near(_stored(), PAINT, "with the paint as it was")


## Without the Exposure filter, the skeleton with no modules, the row says so in
## place of its controls.
func test_without_the_filter_the_row_says_so() -> void:
    _painting(SaFilterRegistry.new())
    var described := _docker.layer_row.describe()
    assert_eq(described["filter"], "", "No filter was found")
    assert_false(String(described["note"]).is_empty(), "and the row says why: %s" % described["note"])
    assert_false(_docker.layer_row.apply(), "Apply writes nothing")


## A linear document whose one paint layer holds `PAINT`, under a canvas the
## docker is pointed at with *filters* as its registry.
func _painting(filters: SaFilterRegistry) -> void:
    _easel = SaEasel.create_default(SIZE, null, SaColorSpace.linear_srgb())
    var registries := Fixtures.make_registries()
    _easel.compositor.set_registry(registries.blend_modes)
    _easel.compositor.filter_chain.registry = filters
    _doc = _easel.document
    (_doc.get_node("Background") as SaLayer).visible = false
    _layer = _doc.get_node("Layer 1") as SaLayer
    _doc.set_active_layer(_layer)
    _layer.get_or_create_chunk(Vector2i.ZERO).clear(PAINT)
    _docker.target_surface = SaSurface.create(&"e4-layer", _easel, Fixtures.FakeView.new())
    _docker.filter_registry = filters
    _docker.layer_types = registries.layer_types
    _docker.follow()


## A registry holding the Exposure filter under the base module's id.
func _exposure_registry() -> SaFilterRegistry:
    var filters := SaFilterRegistry.new()
    filters.register(SaExposureFilter.new(), OWNER)
    return filters


## Moves *slider* the way the harness's `control` step and a drag do: the value
## and the signal a hand's move fires.
func _move(slider: FactorSlider, value: float) -> void:
    assert_true(SaControlWalker.move(slider, value), "%s moves to %s" % [slider.name, value])


## The Display page's Stops slider dragged to *value*.
static func _drag(slider: HSlider, value: float) -> void:
    slider.set_value_no_signal(value)
    slider.value_changed.emit(value)


## The composite at the probe, every chunk drawn again.
func _shown() -> Color:
    _doc.invalidate_chunks([Vector2i.ZERO])
    Bench.composite(_easel)
    return Bench.texel(_easel.output, PROBE)


## The layer's own texel at the probe.
func _stored() -> Color:
    return Bench.texel(_layer.chunks[Vector2i.ZERO].albedo(), PROBE)


func _near(found: Color, wanted: Color, what: String) -> void:
    var apart := maxf(maxf(absf(found.r - wanted.r), absf(found.g - wanted.g)), absf(found.b - wanted.b))
    assert_true(apart <= TOLERANCE, "%s: %s against %s" % [what, found, wanted])


## The bar in the tree over a machine bound to the stamp and base modules, the
## way the paint-exposure suite builds it, over a scratch preset folder.
func _build_the_bar() -> void:
    var easel := SaEasel.create_default(SIZE, null, SaColorSpace.srgb())
    _surface = SaSurface.create(&"e4", easel, Fixtures.FakeView.new())
    _registries = Fixtures.make_registries(_surface)
    for script: GDScript in [StampModuleScript, BaseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar._ready()
    assert_not_null(_bar.control_for(&"exposure"), "The bar has an Exposure slider")


func _free_the_bar() -> void:
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    if _surface != null:
        Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    if DirAccess.dir_exists_absolute(scratch_dir):
        for file_name in DirAccess.get_files_at(scratch_dir):
            DirAccess.remove_absolute(scratch_dir.path_join(file_name))
        DirAccess.remove_absolute(scratch_dir)
