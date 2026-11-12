## A first shelf of noise presets ships.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The shelf is installed the way the module installs it, into a scratch
## store rather than the profile's, then each preset is loaded back off disk
## and paints a stroke through the tool's own public calls on a real surface.
## Read back from the file rather than from the recipe, because what a painter
## gets is what the store wrote.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseFieldsScript = preload("res://modules/sara-noise-brush-engine/noise_fields.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")

## Never the profile's own `user://brush_presets`, for `test_brush_presets.gd`'s
## reason.
static var scratch_dir: String = SaDataRoot.path("test_s4_noise_shelf")

## How many presets ship: the ten first shelf, Wood Grain, Wet Into Wet, and
## the five of the Look page's style.
const SHELF: int = 15

## The stroke each preset paints, across the middle of a 256 canvas.
const FROM := Vector2(40.0, 128.0)
const TO := Vector2(216.0, 128.0)

var _surface: SaSurface = null


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    if _surface != null:
        Fixtures.teardown(_surface)
        _surface = null
    ScratchFolder.clear(scratch_dir)


func test_the_module_registers_the_shelf_under_its_engines_role() -> void:
    _surface = Fixtures.make_surface()
    var registries := Fixtures.make_registries(_surface)
    NoiseModuleScript.new().register(registries.context)
    var engine: StringName = registries.tools.get_descriptor(NoiseModuleScript.TOOL_ID).preset_engine
    assert_eq(
        NoiseModuleScript.PRESETS_ROLE, StringName("shipped_presets_%s" % engine), "The role is named for the brush's engine"
    )
    assert_eq(registries.roles.script_for(NoiseModuleScript.PRESETS_ROLE), NoisePresetsScript, "and holds the shelf")
    assert_eq(registries.roles.owner_of(&"shipped_presets"), &"", "and the stamp's role is left alone")
    var bar := FileAccess.get_file_as_string("res://ui/presets/tool_options_presets.gd")
    assert_true(
        bar.contains('"shipped_presets_%s" % preset_engine()'), "The presets bar asks the role of the active tool's engine"
    )


func test_the_install_writes_ten_presets_of_the_noise_engine() -> void:
    var store := _store()
    assert_eq(_install(store), SHELF, "The install writes the whole shelf")
    var names := store.list_names()
    assert_eq(names.size(), SHELF, "and the folder holds fifteen presets")
    for preset_name: String in names:
        assert_eq(store.engine_for(preset_name), &"noise", "%s is a noise preset" % preset_name)
        assert_false(store.about_for(preset_name).is_empty(), "%s says what it is for" % preset_name)
        assert_eq(
            store.meta_for(preset_name, SaPresetMeta.BUNDLE_META, ""),
            NoisePresetsScript.BUNDLE,
            "%s is of the noise bundle" % preset_name
        )
        assert_eq(
            store.meta_for(preset_name, SaPresetMeta.LICENCE_META, ""),
            "GPL-3.0-or-later",
            "%s carries the bundle's licence" % preset_name
        )


func test_the_shelf_is_offered_once() -> void:
    var store := _store()
    _install(store)
    var deleted: String = NoisePresetsScript.entries()[0]["name"]
    store.delete_preset(deleted)
    assert_eq(_install(_store()), 0, "A second start writes nothing")
    assert_false(_store().has_preset(deleted), "and a preset the painter deleted stays deleted")


## The plan's list: one per field, a thick impasto, a dry brush, one with
## chroma variation and one with the lift-up bound.
func test_the_shelf_covers_what_the_plan_asked_for() -> void:
    var store := _store()
    _install(store)
    var fields := {}
    var impasto := false
    var dry := false
    var chroma := false
    var lift := false
    for preset_name: String in store.list_names():
        var settings: Resource = store.load_preset(preset_name)
        fields[settings.texture_field] = true
        impasto = impasto or settings.thickness >= 1.5
        # Paint only the peaks even under a full press: the cut at a full
        # press is the row times the curve's end.
        var curve: PackedVector2Array = settings.strength_option.common_curve
        dry = dry or settings.strength * curve[curve.size() - 1].y >= 0.5
        chroma = chroma or settings.chroma_variation > 0.0
        var opacity_lift: SaSensor = settings.opacity_option.sensor_for(SaSensor.Id.LIFT_UP)
        var saturation_lift: SaSensor = settings.saturation_option.sensor_for(SaSensor.Id.LIFT_UP)
        lift = (
            lift
            or (
                settings.opacity_option.enabled
                and opacity_lift != null
                and opacity_lift.active
                and saturation_lift != null
                and saturation_lift.active
            )
        )
    for field_id: String in [NoiseFieldsScript.GRAIN, NoiseFieldsScript.BRISTLE, NoiseFieldsScript.PICTURE]:
        assert_true(fields.has(field_id), "A preset paints through the %s field" % field_id)
    assert_true(impasto, "One lays thick impasto")
    assert_true(dry, "One is a dry brush that a full press never fills in")
    assert_true(chroma, "One varies its colour with the texture")
    assert_true(lift, "One has the lift-up bound on Opacity and Saturation")


func test_the_picture_preset_names_a_shipped_pattern() -> void:
    var patterns := SaPatternStore.new()
    for entry: Dictionary in NoisePresetsScript.entries():
        var values: Dictionary = entry["settings"]
        if values.get("texture_field", "") == NoiseFieldsScript.PICTURE:
            assert_true(patterns.has(values["picture_name"]), "%s paints through a pattern Sara ships" % entry["name"])


func test_every_preset_paints_a_stroke() -> void:
    var store := _store()
    _install(store)
    for preset_name: String in store.list_names():
        var painted := _paint(store.load_preset(preset_name))
        assert_true(painted > 100, "%s painted a stroke, %d texels" % [preset_name, painted])


## A fresh surface, one stroke of *settings* across it at a pressure that
## rises and falls, and how many texels of the stroke's row band took paint.
func _paint(settings: Resource) -> int:
    if _surface != null:
        Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface()
    var brush := StateNoiseBrushScript.new()
    brush.surface = _surface
    brush.stroke_seed = 7
    settings.color = Color(0.7, 0.3, 0.2, 1.0)
    brush.settings = settings
    brush.begin_stroke(FROM, 0.2)
    for step in range(1, 61):
        var t := step / 60.0
        brush.add_sample(FROM.lerp(TO, t), 0.2 + 0.8 * sin(PI * t))
    brush.end_stroke()
    return _inked()


## Texels with any paint on the active layer, over every chunk the stroke
## made.
func _inked() -> int:
    var layer := _surface.easel.document.active_layer
    var count := 0
    for grid: Vector2i in layer.chunks:
        @warning_ignore("static_called_on_instance")
        var image := SaExport.get_texture_image_float(layer.get_field(grid))
        for y in range(0, image.get_height(), 2):
            for x in range(0, image.get_width(), 2):
                if image.get_pixel(x, y).a > 0.01:
                    count += 1
    return count


## The install the presets bar runs while the noise brush is active: the
## brush's own settings as the template and the script the module registered.
func _install(store: SaPresetStore) -> int:
    return store.install_shipped(NoiseBrushSettingsScript.new(), NoisePresetsScript)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store
