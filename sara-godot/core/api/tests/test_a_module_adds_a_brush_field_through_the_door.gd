## A module adds a brush field through the door, and the noise
## brush's own three register there the same way.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The requirement, one case per clause: the three shipped fields sit on the door's
## registry under the noise module's name, a second module's field reaches a
## stroke and the Texture row, that module names nothing of the noise module, and its unload takes
## its field with it. The stroke is read off the layer, so "reaches" is what
## the kernel painted rather than what a list says.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const WEAVE_PATH := "res://tests/fixtures/weave-field/modules/weave-field-fixture/module.gd"
const WeaveModuleScript = preload(WEAVE_PATH)

const RADIUS := 14.0
const INSIDE := RADIUS - 3.0
const SPOT := Vector2(60.0, 60.0)

var _registries: SaRegistries = null
var _noise: SaModule = null
var _weave: SaModule = null
var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null


func before_each() -> void:
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _noise = NoiseModuleScript.new()
    _noise.register(_registries.context.for_module(_noise.get_id()))
    _weave = WeaveModuleScript.new()
    _weave.register(_registries.context.for_module(_weave.get_id()))
    _surface = Fixtures.make_surface()
    _brush = StateNoiseBrushScript.new()
    _brush.settings = _noise.settings
    _brush.surface = _surface
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.opacity = 1.0
    _brush.settings.hardness = 1.0
    _brush.settings.strength = 0.5
    _brush.settings.strength_option.enabled = false
    _brush.settings.radius = RADIUS / 256.0


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null
    for module: SaModule in [_weave, _noise]:
        module.unregister(_registries.context)
        _registries.context.for_module(module.get_id()).remove_all_registrations()
    _registries = null


## The three shipped fields are on the door's registry, the noise module's,
## and the brush's registry reads its fields from there, the weave among them.
func test_the_shipped_fields_register_through_the_door() -> void:
    var door := _registries.brush_fields
    var ids: Array = door.fields_for(NoiseFieldsScript.ENGINE).map(
        func(each: SaBrushFieldRegistry.Field) -> String: return each.id
    )
    assert_eq(
        ids, ["grain", "bristle", "picture", "weave"], "The door holds the three shipped fields and the weave, in that order"
    )
    for field_id: String in ["grain", "bristle", "picture"]:
        var held := door.field(NoiseFieldsScript.ENGINE, field_id)
        assert_eq(door.owner_of(held), _noise.get_id(), "%s is registered by the noise module" % field_id)
    assert_eq(door.owner_of(door.field(NoiseFieldsScript.ENGINE, "weave")), _weave.get_id(), "and the weave by its own module")
    assert_eq(_noise.settings.fields.ids(), ids, "The noise brush reads its fields off the door")
    assert_false(
        _registries.context.register_brush_field(NoiseFieldsScript.shipped()[0]),
        "A second grain under the noise engine is refused"
    )


## The Texture row lists the weave though its module registered after the
## noise brush's row was made, and drops it when that module unloads.
func test_the_texture_row_follows_the_door() -> void:
    assert_eq(_texture_choices(), ["grain", "bristle", "picture", "weave"], "The Texture row lists the later module's field")
    _registries.context.for_module(_weave.get_id()).remove_all_registrations()
    assert_eq(_texture_choices(), ["grain", "bristle", "picture"], "and lets it go at that module's unload")


## A stroke with the weave chosen paints the weave: Grain's kernel at the
## module's own scale, which differs from Grain at the settings' scale and
## matches Grain once the settings are turned to the weave's.
func test_a_second_modules_field_reaches_a_stroke() -> void:
    _brush.settings.texture_field = "weave"
    var weave := _painted_with(7)
    assert_eq(_brush.field_binding.values[0], float(NoiseFieldsScript.SLOT_GRAIN), "The weave runs in Grain's slot")
    assert_eq(_brush.field_binding.values[5], WeaveModuleScript.SCALE, "with its own scale, a key the settings do not have")
    var painted := weave.count(true)
    assert_true(
        painted > 0 and painted < weave.size(),
        "The weave paints some texels and leaves holes, %d of %d" % [painted, weave.size()]
    )
    _brush.settings.texture_field = "grain"
    var grain := _painted_with(7)
    assert_true(grain != weave, "Grain at the settings' scale paints another field")
    _brush.settings.grain_scale = WeaveModuleScript.SCALE
    assert_eq(_painted_with(7), weave, "and Grain at the weave's scale paints the weave, texel for texel")


## The fixture module is written against the door alone: its text names no
## file of the noise module, the way a stranger's module could not.
func test_the_second_module_names_nothing_of_the_noise_module() -> void:
    var text := FileAccess.get_file_as_string(WEAVE_PATH)
    assert_false(text.is_empty(), "The fixture module is read")
    for needle: String in ["sara-noise-brush-engine", "noise_fields", "NoiseFields"]:
        assert_false(text.contains(needle), "and it names no %s" % needle)


## Unloading the module takes its field with it, and settings still naming
## the weave paint through the first field the noise brush has.
func test_unloading_the_module_drops_its_field() -> void:
    _registries.context.for_module(_weave.get_id()).remove_all_registrations()
    assert_null(_registries.brush_fields.field(NoiseFieldsScript.ENGINE, "weave"), "The weave is gone from the door")
    assert_eq(_noise.settings.fields.ids(), ["grain", "bristle", "picture"], "and from the brush's list")
    _brush.settings.texture_field = "weave"
    assert_eq(_noise.settings.fields.chosen(_brush.settings).id, "grain", "a preset naming it reads as the first field")


## The ids the noise brush's Texture row offers, read off its descriptor.
func _texture_choices() -> Array:
    var descriptor := _registries.tools.get_descriptor(NoiseModuleScript.TOOL_ID)
    for spec: SaOptionSpec in descriptor.options:
        if spec.key == NoiseFieldsScript.FIELD_KEY:
            return spec.choices.map(func(choice: Dictionary) -> Variant: return choice["id"])
    return []


## The texels a press at [constant SPOT] paints with *stroke_seed_value*, well
## inside the tip, on a fresh surface.
func _painted_with(stroke_seed_value: int) -> Array[bool]:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    _brush.surface = _surface
    _brush.stroke_seed = stroke_seed_value
    _brush.begin_stroke(SPOT, 1.0)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var out: Array[bool] = []
    var reach := int(INSIDE)
    for y in range(-reach, reach + 1):
        for x in range(-reach, reach + 1):
            if Vector2(x, y).length() > INSIDE:
                continue
            out.append(_alpha(layer, Vector2i(SPOT) + Vector2i(x, y), images) > 0.5)
    return out


func _alpha(layer: SaLayer, pixel: Vector2i, images: Dictionary) -> float:
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return 0.0
        if not images.has(here):
            @warning_ignore("static_called_on_instance")
            images[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (images[here] as Image).get_pixelv(pixel - here * side).a
    return 0.0
