## The preset named Eraser erases under the Brush tool.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A door `brush` step with the preset
## Eraser under the Brush tool laid a black block where a figure was to be
## erased. The shipped Eraser and Soft Eraser carry `blend_mode` Erase, and
## every way of picking a preset, a cell of the Brush Presets docker, the door's
## `brush` step and a pen button bound to a brush slot, comes to
## `ToolOptionsPresets.load_preset` and from there to `SaPresetStore.apply_preset`.
##
## Built the way the app builds it: the modules registered through the door, a
## machine bound to their registry on a live canvas, the real bar over the
## shipped recipes, the Brush Presets docker in the tree, and the compositor
## handed the built-in blend modes so an erase lands under the erase rule at the
## commit. Every stroke is a press, motions at full pressure and a release
## handed to the tool in the machine's hand.
extends "res://tests/test_framework.gd"

## Paints and reads the layer back.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StampModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")
const BaseModuleScript = preload("res://modules/sara-base-modules/base/module.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const CANVAS := Vector2i(256, 256)
## The shipped recipes the suite puts in the store, the two that erase and one
## that paints.
const SHIPPED: Array[String] = ["Eraser", "Soft Eraser", "Paint"]

static var scratch_dir: String = SaDataRoot.path("test_eraser_under_the_brush")

var _host: Node = null
var _canvas: SaCanvas = null
var _surface: SaSurface = null
var _registries: SaRegistries = null
var _modules: Array[SaModule] = []
var _machine: ToolMachine = null
var _bar: ToolOptionsBar = null
var _docker: BrushPresetsDocker = null
var _keep_was: bool = false

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _clear(scratch_dir)
    _keep_was = SaSettings.keep_blend_mode
    _host = Node.new()
    _host.name = "U72EraserHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = CANVAS
    _host.add_child(_canvas)
    _canvas.size = Vector2(CANVAS)
    _front = Fixtures.FrontDocuments.over(_canvas)
    _surface = SaSurface.create(&"main", _canvas.easel, Fixtures.FakeView.new())
    _registries = Fixtures.make_registries(_surface)
    _canvas.easel.compositor.set_registry(_registries.blend_modes)
    _modules.clear()
    for script: GDScript in [StampModuleScript, BaseModuleScript]:
        var module: SaModule = script.new()
        module.register(_registries.context.for_module(module.get_id()))
        _modules.append(module)
    _machine = ToolMachine.new()
    _machine.name = "ToolMachine"
    _canvas.add_child(_machine)
    _machine.bind(_surface, _registries.tools)
    _machine.set_active_tool(&"brush")
    _bar = ToolOptionsBar.new()
    _bar.name = "ToolOptionsBar"
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar.preset_store.dir = scratch_dir
    for entry: Dictionary in SaShippedPresets.entries():
        if SHIPPED.has(String(entry["name"])):
            var built := SaShippedPresets.build(StateBrushScript.BrushSettingsScript, entry)
            _bar.preset_store.save_preset(String(entry["name"]), built)
    for wanted: String in SHIPPED:
        assert_true(_bar.preset_store.has_preset(wanted), "The shipped %s is in the store" % wanted)
    _bar._ready()
    _docker = BrushPresetsDocker.new()
    _host.add_child(_docker)


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    SaSettings.keep_blend_mode = _keep_was
    for module: SaModule in _modules:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _modules.clear()
    if _machine != null:
        _machine.registered_tools.clear()
        _machine.active_tool = null
        _machine.registry = null
    if _surface != null:
        _surface.tool_machine = null
    if _host != null:
        EventBus.remove_child(_host)
        _host.free()
    _host = null
    _canvas = null
    _surface = null
    _machine = null
    _bar = null
    _docker = null
    _registries = null
    _clear(scratch_dir)


## Empties the suite's own folder and nothing else, so a store that failed to
## parse, whose path reads as the project's root, takes nothing with it.
func _clear(path: String) -> void:
    if not path.ends_with("test_eraser_under_the_brush") or not DirAccess.dir_exists_absolute(path):
        return
    for file_name: String in DirAccess.get_files_at(path):
        DirAccess.remove_absolute(path.path_join(file_name))
    DirAccess.remove_absolute(path)


## "A suite fills a layer, picks the Eraser preset under the Brush tool through
## the presets docker, draws a stroke with real presses, and reads the stroke's
## pixels with less alpha than before and no black."
func test_the_eraser_picked_in_the_docker_erases_under_the_brush() -> void:
    var layer := _filled_layer()
    _docker.chooser.preset_chosen.emit("Eraser")
    _assert_erases("Eraser", "picked in the docker", layer)


## "The same for Soft Eraser."
func test_the_soft_eraser_picked_in_the_docker_erases_under_the_brush() -> void:
    var layer := _filled_layer()
    _docker.chooser.preset_chosen.emit("Soft Eraser")
    _assert_erases("Soft Eraser", "picked in the docker", layer)


## "And through the door's `brush` step", both erasers, once with Keep Blend
## Mode off and once with it on, the switch a painter could have left on.
func test_both_erasers_given_by_the_doors_brush_step_erase_under_the_brush() -> void:
    for keep: bool in [false, true]:
        _bar.keep_blend_chk.button_pressed = keep
        assert_eq(_bar.preset_store.keep_blend_mode, keep, "The Keep toggle sets Keep Blend Mode %s" % keep)
        for wanted: String in ["Eraser", "Soft Eraser"]:
            # The brush paints Normal before each load, as it did on Day 20,
            # so a load that kept the mode in hand would keep a mode that paints.
            (_machine.get_tool(&"brush") as StateBrushScript).settings.blend_mode = SaLayer.BLEND_MODE.NORMAL
            var layer := _filled_layer()
            var answer := SaCaptureLayers.brush(_canvas.get_tree(), {"preset": wanted})
            assert_true(answer.contains("preset '%s'" % wanted), "The step loads %s: %s" % [wanted, answer])
            assert_true(answer.contains("blend erase"), "and its answer says the brush erases: %s" % answer)
            _assert_erases(wanted, "given by the brush step, Keep Blend Mode %s" % keep, layer)
            SaLayerOps.new(_surface.get_document()).remove(layer)


## "A suite picks Eraser, then a painting preset, and reads the next stroke
## laying paint again", through the docker and through the door, with Keep
## Blend Mode off and on. Under Keep the running app's Paint after the Eraser
## answered `blend erase` and erased, until a painting preset gave back the mode
## the Eraser took.
func test_a_painting_preset_after_the_eraser_lays_paint_again() -> void:
    for keep: bool in [false, true]:
        _bar.keep_blend_chk.button_pressed = keep
        (_machine.get_tool(&"brush") as StateBrushScript).settings.blend_mode = SaLayer.BLEND_MODE.NORMAL
        _eraser_then_paint()


## Under Keep Blend Mode the painter's own Erase stays across a painting preset,
## because nothing took it from another mode.
func test_an_erase_chosen_by_hand_stays_across_a_painting_preset_under_keep() -> void:
    _bar.keep_blend_chk.button_pressed = true
    var brush := _machine.get_tool(&"brush") as StateBrushScript
    brush.settings.blend_mode = SaLayer.BLEND_MODE.ERASE
    _docker.chooser.preset_chosen.emit("Paint")
    assert_eq(brush.settings.blend_mode, SaLayer.BLEND_MODE.ERASE, "Keep Blend Mode keeps the Erase chosen by hand")


## Eraser, Paint, Eraser and Paint again on one layer, the first two through the
## docker and the last two through the door's `brush` step.
func _eraser_then_paint() -> void:
    var layer := _filled_layer()
    _docker.chooser.preset_chosen.emit("Eraser")
    _assert_erases("Eraser", "picked in the docker", layer)
    _docker.chooser.preset_chosen.emit("Paint")
    _assert_paints("Paint picked in the docker", layer, 64)

    SaCaptureLayers.brush(_canvas.get_tree(), {"preset": "Eraser"})
    _assert_erases("Eraser", "given by the brush step", layer, 160)
    var answer := SaCaptureLayers.brush(_canvas.get_tree(), {"preset": "Paint"})
    assert_true(answer.contains("blend normal"), "The step's answer says Paint paints: %s" % answer)
    _assert_paints("Paint given by the brush step", layer, 200)


## A layer of opaque red, the active one, for a stroke to cross.
func _filled_layer() -> SaLayer:
    var layer := SaLayerOps.new(_surface.get_document()).add()
    layer.fill(Color.RED)
    return layer


## The brush is in hand and erases: a stroke along row *y* in black, the colour
## of Day 20's block, leaves less alpha there than the fill had and no black,
## and leaves the row it did not cross.
func _assert_erases(preset: String, how: String, layer: SaLayer, y: int = CANVAS.y >> 1) -> void:
    assert_eq(_machine.active_tool_name, &"brush", "%s %s leaves the Brush in hand" % [preset, how])
    var brush := _machine.active_tool as StateBrushScript
    assert_eq(brush.settings.blend_mode, SaLayer.BLEND_MODE.ERASE, "%s %s sets Erase on the brush" % [preset, how])
    brush.settings.color = Color.BLACK
    var at := Vector2i(CANVAS.x >> 1, y)
    var before := _texel(layer, at)
    _stroke(Vector2(40.0, y), Vector2(CANVAS.x - 40.0, y))
    var after := _texel(layer, at)
    assert_true(after.a < before.a - 0.3, "%s %s takes paint away: alpha %.3f after %.3f" % [preset, how, after.a, before.a])
    var black := after.a > 0.02 and maxf(maxf(after.r, after.g), after.b) < 0.1
    assert_false(black, "and lays no black: %s" % after)
    assert_almost_eq(_texel(layer, Vector2i(at.x, 8)).a, 1.0, 1e-3, "and leaves what it did not cross")


## The brush in hand paints: a stroke along row *y* in blue turns the red fill
## blue and keeps it opaque. The colour is written on the brush, because the
## bus that carries the painter's colour to it is the app's and not this suite's.
func _assert_paints(how: String, layer: SaLayer, y: int) -> void:
    var brush := _machine.active_tool as StateBrushScript
    assert_true(brush.settings.blend_mode != SaLayer.BLEND_MODE.ERASE, "%s takes Erase off the brush" % how)
    brush.settings.color = Color.BLUE
    var at := Vector2i(CANVAS.x >> 1, y)
    _stroke(Vector2(40.0, y), Vector2(CANVAS.x - 40.0, y))
    var after := _texel(layer, at)
    assert_true(after.r < 0.5 and after.b > 0.5 and after.a > 0.9, "%s lays the blue in hand: %s" % [how, after])


## A press at *from*, motions to *to* at full pressure and the release, handed
## to the tool in the machine's hand.
func _stroke(from: Vector2, to: Vector2, steps: int = 40) -> void:
    var tool := _machine.active_tool
    var view := _surface.view as Fixtures.FakeView
    view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = from
    tool.handle_input(press)
    for i in range(1, steps + 1):
        view.mouse_position = from.lerp(to, float(i) / float(steps))
        var motion := InputEventMouseMotion.new()
        motion.button_mask = MOUSE_BUTTON_MASK_LEFT
        motion.position = view.mouse_position
        motion.pressure = 1.0
        tool.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    tool.handle_input(release)


## The texel of *layer* at document pixel *at*, read off its chunk, and clear
## where no chunk is.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var edge := chunk.pixel_size()
        var local := at - grid_pos * edge
        if local.x < 0 or local.y < 0 or local.x >= edge or local.y >= edge:
            continue
        var texture := chunk.albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image_format := Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF
        return Image.create_from_data(edge, edge, false, image_format, bytes).get_pixel(local.x, local.y)
    return Color(0, 0, 0, 0)
