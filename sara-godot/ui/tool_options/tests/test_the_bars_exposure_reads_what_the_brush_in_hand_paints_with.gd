## The bar's Exposure never reads a number the brush in hand does not paint
## with.
##
## The stamp declares Exposure and the noise engine declares it under the same
## key, so with a noise preset picked the one slider follows the engine in hand
## rather than editing the stamp's number while the noise dab ignores it.
##
## **One number.** The Exposure is the paint exposure in
## stops, the foreground's own in `SaColors`, which both engines' settings read
## and write as `paint_exposure`, and the dab paints the foreground with no
## multiplier of its own. So the slider reads the store's stops whichever
## engine is in hand, a preset never moves them, and a move of the slider is
## the foreground's.
##
## Built the way the app builds it: the three modules registered through the
## door, a machine bound to their registry, the real bar over a store its first
## refresh fills with every engine's shipped presets, and the preset group's
## own load, which is what a click on a cell does.
extends "res://tests/test_framework.gd"

## The machine builds every tool, which needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")

const KEY := &"exposure"

## Where the dabs land, well inside the first chunk.
const AT := Vector2(100.0, 100.0)

## A number of stops no shipped preset could set, put on the store before a
## pick, so a slider that read anything but the store would be caught.
const STRAY := 3.0

static var scratch_dir: String = SaDataRoot.path("test_d56_presets")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _host: Node = null
var _bar: ToolOptionsBar = null
## The painter's foreground before the suite moved it, put back after.
var _base_before: Color = Color.BLACK
var _stops_before: float = 0.0


func before_each() -> void:
    _base_before = SaColors.foreground_base
    _stops_before = SaColors.exposure_stops
    _clear(scratch_dir)
    _surface = Fixtures.make_surface()
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
    _surface.view.mouse_position = AT


func after_each() -> void:
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
    SaColors.foreground_base = _base_before
    SaColors.exposure_stops = _stops_before


## The bar in the tree over a store holding the stamp's and the noise
## engine's shipped presets, each shelf installed onto its own engine's settings
## from the role its module registered, the way the preset group's refresh does
## in the app. Here by hand, because the refresh asks main's registries for the
## role and a suite has no main.
func _bar_over_the_stock_presets() -> void:
    _host = Node.new()
    EventBus.add_child(_host)
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    for id: StringName in [&"brush", NoiseModuleScript.TOOL_ID]:
        var descriptor := _registries.tools.get_descriptor(id)
        for role: StringName in [&"shipped_presets", StringName("shipped_presets_%s" % descriptor.preset_engine)]:
            var recipes := _registries.roles.script_for(role)
            if recipes != null:
                _bar.preset_store.install_shipped(descriptor.shared_settings, recipes)
    _bar._ready()


## The stops the next dab of the tool in hand is painted at: the store's, which
## the foreground the dab paints already carries.
func _painted_with() -> float:
    return SaColors.exposure_stops


## The ask: with each stock preset picked, the bar's Exposure is hidden or reads
## the stops the next dab is painted at. The store holds STRAY before each pick
## and still holds it after, since a preset carries no exposure.
func test_every_stock_preset_reads_the_exposure_its_dab_paints_with() -> void:
    _bar_over_the_stock_presets()
    var names := _bar.preset_store.list_names()
    var engines := {}
    for preset_name: String in names:
        engines[_bar.preset_store.engine_for(preset_name)] = true
    assert_true(
        engines.has(&"noise") and engines.size() >= 2, "The store holds both engines' stock presets: %s" % [engines.keys()]
    )
    var control := _bar.control_for(KEY) as FactorSlider
    assert_not_null(control, "The bar has an Exposure slider")
    for preset_name: String in names:
        SaColors.exposure_stops = STRAY
        assert_true(_bar.preset_box.load_preset(preset_name), "%s loads" % preset_name)
        var hand := _machine.active_tool_name
        assert_eq(_bar.owner_of(KEY), hand, "%s: the slider belongs to %s, the tool in hand" % [preset_name, hand])
        # Hidden or shown alike, since a row the painter turns on shows the
        # number its control already holds.
        assert_almost_eq(control.value, _painted_with(), 1e-6, "%s: the slider reads what the dab is painted with" % preset_name)
        assert_almost_eq(_bar.read_option(KEY), _painted_with(), 1e-6, "%s: and so does the bar's read of it" % preset_name)
        assert_almost_eq(_painted_with(), STRAY, 1e-6, "%s: which the preset left alone" % preset_name)


## The note's own case on a bar where the row is shown: a noise preset picked
## reads the store's stops, and a move of the slider is the store's, which the
## stamp reads too.
func test_a_noise_preset_reads_and_writes_its_own_exposure() -> void:
    _bar_over_the_stock_presets()
    SaColors.exposure_stops = 0.0
    var noise_preset := ""
    for preset_name: String in _bar.preset_store.list_names():
        if _bar.preset_store.engine_for(preset_name) == &"noise":
            noise_preset = preset_name
            break
    assert_true(_bar.preset_box.load_preset(noise_preset), "A noise preset, %s, loads" % noise_preset)
    assert_eq(_machine.active_tool_name, NoiseModuleScript.TOOL_ID, "and the noise engine is in hand")
    assert_almost_eq(_bar.control_value(KEY), 0.0, 1e-6, "The slider reads the store's nought stops")
    assert_true(_bar.write_option(KEY, 2.0), "A move of the slider writes")
    assert_almost_eq(_painted_with(), 2.0, 1e-6, "into the store")
    var stamp: Object = _machine.get_tool(&"brush").get("settings")
    assert_almost_eq(float(stamp.get(&"paint_exposure")), 2.0, 1e-6, "which the stamp reads as well")


## White picked paints white, on either engine, at the nought stops a pick of
## white reads. A hard dab at full opacity, so the centre texel is the colour
## and not the falloff.
func test_a_fresh_profiles_brush_paints_a_white_dab_white() -> void:
    SaColors.foreground = Color.WHITE
    for id: StringName in [&"brush", NoiseModuleScript.TOOL_ID]:
        _machine.set_active_tool(id)
        var settings: Object = _machine.active_tool.get("settings")
        assert_almost_eq(_painted_with(), 0.0, 1e-6, "%s paints white at nought stops" % id)
        settings.set("color", Color.WHITE)
        settings.set("opacity", 1.0)
        settings.set("radius", 0.1)
        _make_hard(settings)
        _stroke()
        var texel := _texel(AT)
        assert_almost_eq(texel.r, 1.0, 0.01, "%s paints white's red at one, read %.4f" % [id, texel.r])
        assert_almost_eq(texel.g, 1.0, 0.01, "%s and its green" % id)
        assert_almost_eq(texel.b, 1.0, 0.01, "%s and its blue" % id)


## The noise dab honours the number, the half that makes its slider worth
## showing: white at one stop is two, which the foreground carries to the dab
## past one, since nothing clamps.
func test_the_noise_engine_paints_with_its_exposure() -> void:
    _machine.set_active_tool(NoiseModuleScript.TOOL_ID)
    var settings: Object = _machine.active_tool.get("settings")
    SaColors.foreground = Color.WHITE
    settings.set("opacity", 1.0)
    settings.set("radius", 0.1)
    settings.set(&"paint_exposure", 1.0)
    _make_hard(settings)
    _stroke()
    var texel := _texel(AT)
    assert_almost_eq(texel.r, 2.0, 0.02, "White at one stop paints two, read %.4f" % texel.r)
    assert_almost_eq(texel.a, 1.0, 0.01, "and the coverage stays one")


## Full strength under the centre: a hard tip, full flow on the stamp, and no
## texture cut on the noise engine, whose pressure would otherwise lift its cut.
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


## One press and release through the machine at AT.
func _stroke() -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    _machine.handle_input(press)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    _machine.handle_input(release)


## The active layer's texel at *at*, in document pixels.
func _texel(at: Vector2) -> Color:
    var layer := _surface.easel.document.active_layer
    var side := 0
    for grid: Vector2i in layer.chunks:
        side = (layer.chunks[grid] as SaChunk).pixel_size()
        break
    if side == 0:
        return Color.TRANSPARENT
    var pixel := Vector2i(at.floor())
    var grid := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
    if not layer.chunks.has(grid):
        return Color.TRANSPARENT
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(layer.get_field(grid))
    return image.get_pixelv(pixel - grid * side)


func _clear(path: String) -> void:
    if not DirAccess.dir_exists_absolute(path):
        return
    for file_name in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)
