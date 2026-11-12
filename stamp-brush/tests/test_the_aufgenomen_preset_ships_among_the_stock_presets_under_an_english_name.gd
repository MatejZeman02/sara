## The `aufgenomen` preset ships among the stock presets as Torn Gouache.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A fresh profile is offered the stock presets and finds Torn Gouache among
## them, with the tags of the drawn bundle's other textures. Then one stroke is
## painted with it and one with `fixtures/earlier-presets/Torn Gouache.tres`, a byte for
## byte copy of the original `aufgenomen` file, each loaded through a store of
## its own, and the two layers are read back and found equal texel for texel.
## The stroke ramps its pressure, so the original's opacity curve is read along
## all of it, and both take one seed, so the turn at random each dab is the same turn.
extends "res://tests/test_framework.gd"

const SaShippedPresetsScript = preload("res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## The name the preset ships under.
const NAME: String = "Torn Gouache"

## The original Torn Gouache with `aufgenomen` merged into it, copied into the
## suite's fixtures, so the run never reads or writes a painter's own folder.
const REFERENCE_FILE: String = "res://modules/sara-base-modules/stamp-brush/tests/fixtures/earlier-presets/Torn Gouache.tres"

## A fresh profile's store and the one the original file is loaded from, never
## the real `user://brush_presets`, for the reason `test_brush_presets.gd`
## gives.
static var fresh_dir: String = SaDataRoot.path("test_fresh_profile")
static var reference_dir: String = SaDataRoot.path("test_authors_file")

const FROM: Vector2 = Vector2(40.0, 140.0)
const TO: Vector2 = Vector2(470.0, 110.0)
const STEP: float = 3.0
const SEED: int = 567

var _correction := PackedFloat32Array()
var _max_pressure: float = 1.0


func before_each() -> void:
    _correction = SaTablet.correction
    _max_pressure = SaSettings.tablet_max_pressure
    SaTablet.correction = PackedFloat32Array()
    SaSettings.tablet_max_pressure = 1.0
    _clear(fresh_dir)
    _clear(reference_dir)


func after_each() -> void:
    SaTablet.correction = _correction
    SaSettings.tablet_max_pressure = _max_pressure
    _clear(fresh_dir)
    _clear(reference_dir)


func test_a_fresh_profile_is_offered_it_under_its_english_name() -> void:
    var store := _fresh_profile()
    assert_true(store.has_preset(NAME), "A fresh profile holds %s" % NAME)
    assert_false(store.has_preset("aufgenomen"), "and no preset under the original name")
    assert_eq(store.tags_for(NAME), PackedStringArray(["paint"]), "with the one tag of an opaque fill")
    assert_eq(
        String(store.meta_for(NAME, SaPresetMeta.BUNDLE_META, "")),
        "Sara Advanced Paint",
        "in Sara Advanced Paint, which took that bundle over"
    )


func test_a_stroke_of_it_is_the_stroke_of_the_reference_file_texel_for_texel() -> void:
    var shipped := _fresh_profile().load_preset(NAME) as SaStampBrushSettings
    var authors := _reference_store().load_preset(NAME) as SaStampBrushSettings
    assert_not_null(shipped, "The shipped preset loads")
    assert_not_null(authors, "and so does the original file")
    if shipped == null or authors == null:
        return
    var ours := _paint(shipped)
    var theirs := _paint(authors)
    assert_true(ours.size() > 0, "The stroke laid paint in %d chunks" % ours.size())
    assert_eq(ours.keys(), theirs.keys(), "in the same chunks as the original's")
    var unequal := 0
    var painted := 0
    for grid: Vector2i in ours:
        var a: PackedByteArray = ours[grid]
        var b: PackedByteArray = theirs.get(grid, PackedByteArray())
        if a != b:
            unequal += 1
        for offset in range(12, a.size(), 16):
            if a.decode_float(offset) > 0.0:
                painted += 1
    assert_eq(unequal, 0, "and every chunk holds the original's texels exactly")
    assert_true(painted > 2000, "over %d painted texels" % painted)


## A store in an empty folder, offered the stock presets as a first run is.
func _fresh_profile() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = fresh_dir
    store.install_shipped(SaStampBrushSettings.new(), SaShippedPresetsScript)
    return store


## A store holding the original file and nothing else.
func _reference_store() -> SaPresetStore:
    DirAccess.make_dir_recursive_absolute(reference_dir)
    var bytes := FileAccess.get_file_as_bytes(REFERENCE_FILE)
    var file := FileAccess.open(reference_dir.path_join(NAME + ".tres"), FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    var store := SaPresetStore.new()
    store.dir = reference_dir
    return store


## One stroke with *settings* on a fresh document, its layer's albedo by chunk.
func _paint(settings: SaStampBrushSettings) -> Dictionary:
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    brush.settings = settings
    brush.stroke_seed = SEED
    var was := SaColors.foreground
    SaColors.foreground = Color(0.55, 0.18, 0.1, 1.0)
    surface.view.mouse_position = FROM
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = FROM
    brush.handle_input(press)
    var length := FROM.distance_to(TO)
    var along := 0.0
    while along < length:
        along = minf(length, along + STEP)
        var at := FROM.lerp(TO, along / length)
        surface.view.mouse_position = at
        var motion := InputEventMouseMotion.new()
        motion.position = at
        motion.pressure = along / length
        brush.handle_input(motion)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)
    SaColors.foreground = was
    var chunks := {}
    var layer: SaLayer = surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var texture: SaTexture = (layer.chunks[grid] as SaChunk).field(SaFieldSpec.ALBEDO)
        if texture != null:
            chunks[grid] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    Fixtures.teardown(surface, machine)
    return chunks


func _clear(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for file_name: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file_name))
    DirAccess.remove_absolute(folder)
