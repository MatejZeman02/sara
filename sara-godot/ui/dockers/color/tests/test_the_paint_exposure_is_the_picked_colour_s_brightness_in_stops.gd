## The paint exposure is the picked colour's brightness in stops.
##
## The foreground is a base colour whose peak is at most one, times two to a
## number of stops. A pick brighter than white splits into the two, the stops
## slider on the bar and the one in the colour docker read the stops, the
## docker's wheel edits the base and keeps them, and the brush paints the
## foreground as it is, with no multiplier of its own.
##
## Built the way the app builds it: the stamp, the base and the noise modules
## registered through the door, a machine bound to their registry, the real
## options bar and the real colour docker over the `SaColors` store, and the
## eyedropper's own press on a layer holding the colour. The document is sRGB,
## whose picks are stored as they are, so the numbers read back are the numbers
## put in.
extends "res://tests/test_framework.gd"

## The machine builds every tool and the eyedropper reads a chunk, which needs a
## RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")

const KEY := &"exposure"

## Wide enough for a row of dabs a chunk apart, whatever side a chunk has.
const CANVAS := Vector2i(1024, 1024)

## The colour: red at sixteen, four stops over one, with a blue
## below zero that nothing may clamp.
const HDR := Color(16.0, 0.0, -0.5)

## Where the eyedropper presses, inside the chunk the colour is put into.
const PICK_AT := Vector2(20.0, 20.0)

static var scratch_dir: String = SaDataRoot.path("test_e3_presets")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
var _docker_host: Control = null
var _docker: ColorDocker = null
## The painter's foreground before the suite moved it, put back after.
var _foreground_before: Color = Color.BLACK


func before_each() -> void:
    _foreground_before = SaColors.foreground
    _clear(scratch_dir)
    var easel := SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    _surface = SaSurface.create(&"e3", easel, Fixtures.FakeView.new())
    _registries = Fixtures.make_registries(_surface)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript, NoiseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _machine._ready()
    _machine.bind(_surface, _registries.tools)


func after_each() -> void:
    if _docker_host != null:
        _docker_host.free()
        _docker_host = null
        _docker = null
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
        _host = null
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _machine = null
    _surface = null
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    _registries = null
    _clear(scratch_dir)
    SaColors.foreground = _foreground_before


## The first case: a pick of (16, 0, -0.5) is four stops on the bar's
## slider and on the docker's, and a dab of it is (16, 0, -0.5) in the layer.
func test_an_hdr_pick_reads_four_stops_on_both_sliders_and_paints_as_picked() -> void:
    _build_the_bar()
    _build_the_docker()
    _pick(HDR)
    assert_almost_eq(SaColors.exposure_stops, 4.0, 1e-6, "The pick is four stops")
    assert_true(SaColors.foreground_base.is_equal_approx(Color(1.0, 0.0, -0.5 / 16.0)), "over a base whose peak is one")
    assert_true(SaColors.foreground.is_equal_approx(HDR), "and the foreground is the colour picked")
    assert_almost_eq(float(_bar.control_value(KEY)), 4.0, 1e-6, "The bar's Exposure reads four stops")
    assert_almost_eq(_picker().exposure_row.slider.value, 4.0, 1e-6, "and so does the colour docker's")
    var dab := _dab(&"brush", 0)
    _assert_colour(dab, HDR, 1e-3, "A dab of it")


## The second case: plain red is nought stops, and the docker's slider at one
## makes the foreground (2, 0, 0), which the next dab paints.
func test_a_plain_red_reads_nought_stops_and_the_dockers_slider_doubles_it() -> void:
    _build_the_bar()
    _build_the_docker()
    _pick(Color(1.0, 0.0, 0.0))
    assert_almost_eq(SaColors.exposure_stops, 0.0, 1e-6, "Red at one is nought stops")
    assert_almost_eq(float(_bar.control_value(KEY)), 0.0, 1e-6, "on the bar")
    assert_almost_eq(_picker().exposure_row.slider.value, 0.0, 1e-6, "and on the docker")
    _picker().exposure_row.slider._commit(1.0)
    assert_almost_eq(SaColors.exposure_stops, 1.0, 1e-6, "The docker's slider moved the stops")
    _assert_colour(SaColors.foreground, Color(2.0, 0.0, 0.0), 1e-6, "The foreground")
    assert_almost_eq(float(_bar.control_value(KEY)), 1.0, 1e-6, "and the bar follows")
    _assert_colour(_dab(&"brush", 1), Color(2.0, 0.0, 0.0), 1e-3, "A dab of it")


## The third case: (0.5, 0.25, 0) at two stops paints (2, 1, 0), and a turn of
## the hue on the docker's wheel moves the base and leaves the stops at two.
func test_a_hue_turn_on_the_wheel_keeps_the_stops() -> void:
    _build_the_bar()
    _build_the_docker()
    SaColors.foreground = Color(0.5, 0.25, 0.0)
    assert_almost_eq(SaColors.exposure_stops, 0.0, 1e-6, "A colour under one is nought stops")
    _picker().exposure_row.slider._commit(2.0)
    _assert_colour(SaColors.foreground, Color(2.0, 1.0, 0.0), 1e-6, "Two stops over (0.5, 0.25, 0)")
    _assert_colour(_dab(&"brush", 2), Color(2.0, 1.0, 0.0), 1e-3, "A dab of it")
    var shape := _picker().shape
    shape.set_kind(SaPickerShape.Kind.WHEEL)
    shape._drag_ring(Vector2(0.0, 50.0))
    var base := SaColors.foreground_base
    assert_false(base.is_equal_approx(Color(0.5, 0.25, 0.0)), "The wheel turned the hue, to %s" % base)
    assert_almost_eq(SaColors.exposure_stops, 2.0, 1e-6, "and the stops stay at two")
    assert_almost_eq(_picker().exposure_row.slider.value, 2.0, 1e-6, "on the docker")
    assert_almost_eq(float(_bar.control_value(KEY)), 2.0, 1e-6, "and on the bar")
    _assert_colour(SaColors.foreground, SaColorStore.exposed(base, 2.0), 1e-6, "The foreground is the new base at two stops")


## The fourth case: the noise brush paints the same foreground, since neither
## engine multiplies it.
func test_the_noise_brush_paints_the_same_foreground() -> void:
    _pick(HDR)
    _assert_colour(_dab(&"brush", 0), HDR, 1e-3, "The stamp's dab")
    _assert_colour(_dab(NoiseModuleScript.TOOL_ID, 1), HDR, 1e-3, "The noise brush's dab")


## A preset written before the exposure existed carries an exposure, which loads without it:
## the stops and the foreground stay as the painter left them.
func test_an_old_presets_exposure_is_read_without_it() -> void:
    SaColors.foreground = Color(0.5, 0.25, 0.0)
    SaColors.exposure_stops = 1.0
    var live: Resource = _machine.get_tool(&"brush").get("settings")
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    var stored := store.save_preset("Old", live)
    assert_eq(stored, "Old", "A preset is saved")
    var path := scratch_dir.path_join(stored + SaPresetStore.EXTENSION)
    var text := FileAccess.get_file_as_string(path)
    assert_true(text.contains("[resource]\n"), "with a resource section to put the old number in")
    var old := FileAccess.open(path, FileAccess.WRITE)
    old.store_string(text.replace("[resource]\n", "[resource]\nexposure = 2.5\n"))
    old.close()
    assert_true(store.apply_preset("Old", live), "The old preset loads")
    assert_almost_eq(SaColors.exposure_stops, 1.0, 1e-6, "and leaves the stops alone")
    _assert_colour(SaColors.foreground, Color(1.0, 0.5, 0.0), 1e-6, "and the foreground")
    assert_false("exposure" in live, "The brush has no exposure of its own to take it")


## The bar in the tree, the way the bar suites build it, over a scratch preset
## folder so the painter's own presets are never read.
func _build_the_bar() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    _bar._ready()
    assert_not_null(_bar.control_for(KEY), "The bar has an Exposure slider")


## The colour docker over the store, the way the picker's own suite builds it.
func _build_the_docker() -> void:
    _docker_host = Control.new()
    _docker = ColorDocker.new()
    _docker.name = "ColorDocker"
    _docker_host.add_child(_docker)
    _docker._ready()
    assert_not_null(_picker().exposure_row, "The docker has a stops slider")


## The docker's picker, typed, since the docker holds it as a `Control`.
func _picker() -> SaColorPicker:
    return _docker.color_picker as SaColorPicker


## Puts *color* into the first chunk of the active layer and presses and lets
## go the eyedropper there, reading the layer, which is the pick's whole door.
func _pick(color: Color) -> void:
    var field := _surface.easel.document.active_layer.get_or_create_field(Vector2i.ZERO)
    GlobalShaderCompiler.get_rd().texture_clear(field.rid, Color(color.r, color.g, color.b, 1.0), 0, 1, 0, 1)
    _machine.set_active_tool(&"eyedropper")
    var eyedropper: Object = _machine.active_tool
    eyedropper.set("sample_from", StateEyedropperScript.SampleFrom.LAYER)
    _surface.view.mouse_position = PICK_AT
    _click()


## A hard dab at full opacity of the tool *id*, in the *index*th chunk of the
## second row, which nothing else touches, and the layer's texel under it.
func _dab(id: StringName, index: int) -> Color:
    var side := _side()
    var at := Vector2(side * (index + 0.5), side * 1.5)
    assert_true(Rect2(Vector2.ZERO, Vector2(CANVAS)).has_point(at), "The dab at %s is on the canvas" % at)
    _machine.set_active_tool(id)
    var settings: Object = _machine.active_tool.get("settings")
    settings.set("opacity", 1.0)
    settings.set("radius", 0.03)
    _make_hard(settings)
    _surface.view.mouse_position = at
    _click()
    return _texel(at)


## Full strength under the centre, as the bar suites make it: a hard tip, full
## flow on the stamp, no texture cut on the noise engine and no pressure.
func _make_hard(settings: Object) -> void:
    var hardness: Variant = settings.get("hardness")
    if hardness is Object:
        (hardness as Object).set("value", 1.0)
    else:
        settings.set("hardness", 1.0)
    if "flow" in settings:
        var flow: Variant = settings.get("flow")
        if flow is Object:
            (flow as Object).set("value", 1.0)
        else:
            settings.set("flow", 1.0)
    if "strength" in settings:
        settings.set("strength", 0.0)
    if "opacity_by_pressure" in settings:
        settings.set("opacity_by_pressure", false)


## One press and release through the machine where the view's pointer is.
func _click() -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _machine.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    _machine.handle_input(release)


## A chunk's side in pixels, asked of a chunk rather than assumed.
func _side() -> int:
    var layer := _surface.easel.document.active_layer
    layer.get_or_create_field(Vector2i.ZERO)
    return (layer.chunks[Vector2i.ZERO] as SaChunk).pixel_size()


## The active layer's texel at *at*, in document pixels.
func _texel(at: Vector2) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := _side()
    var pixel := Vector2i(at.floor())
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixelv(pixel - grid * side)


func _assert_colour(got: Color, want: Color, tolerance: float, what: String) -> void:
    var near := absf(got.r - want.r) <= tolerance and absf(got.g - want.g) <= tolerance and absf(got.b - want.b) <= tolerance
    assert_true(near, "%s is %s, read %s" % [what, want, got])


func _clear(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file_name in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)
