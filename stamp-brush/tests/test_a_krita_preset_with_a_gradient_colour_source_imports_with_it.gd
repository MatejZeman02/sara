## A Krita preset with a gradient colour source imports with it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The committed fixture `fixtures/sara-gradient-source.kpp`, written by
## `kpp_fixtures.gd`, is a round brush on Krita's `gradient` value of
## `ColorSource/Type` with Mix on pressure through a curve well under the
## diagonal. Imported, it lands on the Gradient source with no tag, its ramp
## the default, the painter's colour to the background colour, which is
## Krita's own default gradient, and the report says so as it does for a
## gradient map.
##
## **Krita's reading, written out here rather than asked of Sara.** Krita picks
## `colorAt(mix)` off its gradient, its Mix the option's strength times the
## curve at the pen's pressure, so at no pressure the curve's foot and at full
## pressure its top, the gradient's start and its end, the painter's colour and
## the background. Under a plain source the importer turns the Mix curve over,
## since Krita's plain Mix is one for the painting colour, and a gradient source
## turned over would walk the ramp backwards. The suite reads the ends off the
## file's own curve and paints a dab at each.
##
## The cases that paint skip on a run with no rendering device, and the import
## itself never needs one.
extends "res://tests/test_framework.gd"

const KppFixtures = preload("res://modules/sara-base-modules/stamp-brush/tests/kpp_fixtures.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

const FIXTURE := "res://modules/sara-base-modules/stamp-brush/tests/fixtures/sara-gradient-source.kpp"
## The phrase a colour source Sara has no home for wears.
const TAG := "colour source"
## Krita's ids for the sources Sara still has no home for.
const OTHER_SOURCES: Array[String] = ["uniform_random", "total_random", "pattern", "lockedpattern"]

static var scratch_preset_dir: String = SaDataRoot.path("test_b7_gradient_source_presets")
static var scratch_dir: String = SaDataRoot.path("test_b7_gradient_source_kpp")

## The painter's pair, which a preset never carries and the module writes onto
## the brush. Red and blue at full, so the display colour and the layer's
## linear one are the same numbers at either end.
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)

## The low press the canvas cases paint, light enough that the file's curve
## reads close to its foot and a curve turned over close to its top.
const LOW := 0.1


func after_each() -> void:
    for folder: String in [scratch_preset_dir, scratch_dir]:
        if DirAccess.dir_exists_absolute(folder):
            var dir := DirAccess.open(folder)
            for file in dir.get_files():
                dir.remove(file)
            DirAccess.remove_absolute(folder)
    # The gradient map case writes its tip to the tips folder, as an import does.
    var tip := SaBrushTipMask.saved_dir().path_join(KppFixtures.GRADIENT_TIP_FILE)
    if FileAccess.file_exists(tip):
        DirAccess.remove_absolute(tip)


## The scenario imports the committed file and the suite reads the writer, so
## the two are held to each other key by key.
func test_the_committed_fixture_is_the_written_one() -> void:
    var written := SaKppReader.read_bytes(KppFixtures.gradient_source_kpp(), "sara-gradient-source.kpp")
    var committed := SaKppReader.read_file(FIXTURE)
    for key: String in ["name", "engine", "options", "tip", "format_version", "error"]:
        assert_eq(committed[key], written[key], "sara-gradient-source.kpp agrees on %s" % key)
    assert_eq(committed["error"], "", "and reads")
    var options: Dictionary = committed["options"]
    assert_eq(SaKppSensors.string_of(options, "ColorSource/Type"), "gradient", "Its source is Krita's gradient")
    assert_true(SaKppSensors.bool_of(options, "PressureMix"), "and its Mix is switched on")


## The import half: `GRADIENT` on the settings,
## an empty gradient, no `colour source` tag in the result or on the stored
## preset, and the report's sentence.
func test_the_fixture_imports_on_the_gradient_source_and_wears_no_tag() -> void:
    var store := _store()
    var result := _import(store)
    assert_eq(result["error"], "", "imported")
    var loaded := store.load_preset(KppFixtures.GRADIENT_SOURCE_NAME) as SaStampBrushSettings
    assert_not_null(loaded, "and stored as a stamp brush preset")
    if loaded == null:
        return
    assert_eq(loaded.color_source, SaColorDynamics.Source.GRADIENT, "on the Gradient source")
    assert_eq(loaded.gradient, [], "with an empty gradient, which reads as the default")
    assert_false(Array(result["not_carried"]).has(TAG), "The result names no lost source: %s" % [result["not_carried"]])
    assert_eq(result["not_carried"], [], "and nothing lost at all")
    for tag: String in store.tags_for(KppFixtures.GRADIENT_SOURCE_NAME):
        assert_false(tag.begins_with(SaKppImport.NOT_CARRIED_PREFIX), "and the preset wears no not-carried tag: %s" % tag)
    assert_eq(result["notes"], [SaKppImport.GRADIENT_FROM_THE_PAINTER], "The result carries the sentence")
    var line := SaKppImport.describe(result)
    assert_true(line.contains(SaKppImport.GRADIENT_FROM_THE_PAINTER), "and the console line says it: %s" % line)


## The Mix curve lands as the file wrote it, on pressure at the file's strength,
## where a plain source's would be turned over.
func test_the_mix_curve_lands_as_krita_wrote_it() -> void:
    var settings := _apply(KppFixtures.gradient_source_kpp())
    var mix := settings.mix_option
    var written := SaKppSensors.parse_curve(KppFixtures.GRADIENT_SOURCE_MIX_CURVE)
    assert_true(mix.enabled, "Mix is on")
    assert_almost_eq(mix.strength, 1.0, 1e-6, "at the file's strength")
    assert_true(mix.sensors.has(SaSensor.Id.PRESSURE), "on pressure")
    assert_eq(mix.common_curve, written, "through the curve as written, not turned over")

    var plain := _apply(KppFixtures.gradient_source_kpp("plain"))
    assert_eq(plain.color_source, SaColorDynamics.Source.PLAIN, "The same preset on a plain source")
    assert_almost_eq(plain.mix_option.common_curve[1].y, 1.0 - written[1].y, 1e-6, "still has its Mix turned over")


## The Done-when's first clause, the dab half, in arithmetic: a dab at no
## pressure and one at full land where Krita's reading puts them, the Mix the
## strength times the file's curve at its foot and at its top, the ramp's start
## and its end, and a light press stays at the start's side of the ramp.
func test_dabs_at_low_and_full_pressure_land_at_kritas_ends() -> void:
    var settings := _apply(KppFixtures.gradient_source_kpp())
    var written := SaKppSensors.parse_curve(KppFixtures.GRADIENT_SOURCE_MIX_CURVE)
    var dynamics := SaDynamics.new(settings)

    var none := dynamics.evaluate(_sample(0.0), 40.0)
    var light := dynamics.evaluate(_sample(LOW), 40.0)
    var full := dynamics.evaluate(_sample(1.0), 40.0)
    assert_almost_eq(none.mix, written[0].y, 1e-5, "No pressure reads Krita's Mix, the curve's foot")
    assert_almost_eq(full.mix, written[written.size() - 1].y, 1e-5, "and full pressure its top")
    assert_true(light.mix < written[1].y, "A light press reads under the curve's middle point, %.3f" % light.mix)

    _assert_color(_paint(settings, none), RED, 1e-5, "No pressure paints the ramp's start, the painter's colour")
    _assert_color(_paint(settings, full), BLUE, 1e-5, "and full pressure its end, the background")
    var near := _paint(settings, light)
    assert_true(_distance(near, RED) < _distance(near, BLUE), "and a light press lands nearer the start: %s" % near)


## Below full strength the stroke still walks the ramp as Krita's does, both
## reading the strength times the curve, so a Mix at a half with the pen fully
## down sits at the ramp's middle in both, where a plain source's turned-over
## Mix cannot follow Krita below full strength.
func test_a_mix_below_full_strength_reads_the_place_krita_reads() -> void:
    var settings := _apply(KppFixtures.gradient_source_kpp("gradient", "0.5"))
    var full := SaDynamics.new(settings).evaluate(_sample(1.0), 40.0)
    assert_almost_eq(full.mix, 0.5, 1e-5, "Half strength at full pressure is Krita's Mix of a half")
    var middle := SaColorDynamics.ramp_at(settings.gradient_ramp(), 0.5)
    _assert_color(_paint(settings, full), middle, 1e-5, "and paints the ramp there")


## The Done-when's second clause: a `total_random` preset keeps the tag, and
## so does each of Krita's other sources, on a plain source with no sentence.
func test_a_total_random_preset_keeps_the_tag() -> void:
    var store := _store()
    var result := _import_bytes(store, KppFixtures.gradient_source_kpp("total_random"), "sara-total-random.kpp")
    assert_true(Array(result["not_carried"]).has(TAG), "total_random is tagged: %s" % [result["not_carried"]])
    assert_eq(result["notes"], [], "with no sentence about a gradient")
    var tags := Array(store.tags_for(String(result["name"])))
    assert_true(tags.has(SaKppImport.NOT_CARRIED_PREFIX + TAG), "and the stored preset wears it: %s" % [tags])
    var loaded := store.load_preset(String(result["name"])) as SaStampBrushSettings
    if loaded != null:
        assert_eq(loaded.color_source, SaColorDynamics.Source.PLAIN, "It paints plain")
    for source: String in OTHER_SOURCES:
        var settings := SaStampBrushSettings.new()
        var applied := SaKppImport.apply(SaKppReader.read_bytes(KppFixtures.gradient_source_kpp(source), "x.kpp"), settings)
        assert_true(Array(applied["not_carried"]).has(TAG), "%s keeps the tag" % source)
        assert_eq(settings.color_source, SaColorDynamics.Source.PLAIN, "%s stays plain" % source)


## A gradient-map tip on a gradient source reads one ramp, so the report says
## where it came from once.
func test_a_gradient_map_tip_on_a_gradient_source_says_it_once() -> void:
    var preset := SaKppReader.read_bytes(KppFixtures.gradient_map_kpp(), "sara-gradient-map.kpp")
    preset["options"]["ColorSource/Type"] = {"type": "string", "value": "gradient"}
    var settings := SaStampBrushSettings.new()
    var applied := SaKppImport.apply(preset, settings)
    assert_eq(applied["notes"], [SaKppImport.GRADIENT_FROM_THE_PAINTER], "One sentence")
    assert_eq(settings.color_source, SaColorDynamics.Source.GRADIENT, "for the source")
    assert_eq(settings.tip_mode, SaStampBrushSettings.TipMode.GRADIENT_MAP, "and the tip both")


# --- On the canvas ------------------------------------------------------------


## The Done-when's first clause on the card: the imported preset stamps a dab at
## a light press and one at full pressure through the brush itself, and the
## first reads the ramp at its Mix by the painter's colour and the second the
## background, the ends Krita's reading puts them at.
func test_the_imported_preset_paints_the_ends_krita_paints() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no rendering device to paint the dabs on")
        return
    var full := _stamp(1.0)
    assert_almost_eq(float(full["mix"]), 1.0, 1e-3, "A full pressure dab reads a Mix of one")
    var top: Color = full["texel"]
    assert_true(top.a > 0.0, "and paints")
    if top.a > 0.0:
        _assert_color(_straight(top), BLUE, 1e-3, "the ramp's end, the background")

    var light := _stamp(LOW)
    assert_true(float(light["mix"]) < 0.2, "A light dab reads a Mix near the curve's foot, %.3f" % float(light["mix"]))
    var low: Color = light["texel"]
    assert_true(low.a > 0.0, "and paints")
    if low.a > 0.0:
        var got := _straight(low)
        _assert_color(got, light["want"], 2e-3, "what the ramp holds at its Mix of %.3f" % float(light["mix"]))
        assert_true(_distance(got, RED) < _distance(got, BLUE), "by the painter's colour: %s" % got)


## The committed fixture imported, through the store and with Krita's pressure
## curve read as linear, onto a brush over a fresh 256 square, stamping one dab
## at *pressure* at its middle, and the centre texel with what the ramp holds at
## the dab's Mix.
func _stamp(pressure: float) -> Dictionary:
    var store := _store()
    _import(store)
    var loaded := store.load_preset(KppFixtures.GRADIENT_SOURCE_NAME) as SaStampBrushSettings
    var out := {"mix": -1.0, "texel": Color(0, 0, 0, 0), "want": Color(0, 0, 0, 0)}
    if loaded == null:
        assert_true(false, "the preset loads")
        return out
    loaded.color = RED
    loaded.background_color = BLUE
    var surface := Fixtures.make_surface()
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings = loaded
    # What a stroke's start does, without the document's stroke it opens: the
    # evaluator reads no options until it is handed the settings.
    brush.dynamics.settings = loaded
    brush.dynamics.begin_stroke()
    brush.stroke_info.begin(Vector2(128.0, 128.0), 4242)

    brush._stamp_brush(Vector2(128.0, 128.0), pressure)

    out["mix"] = brush.last_dab.mix if brush.last_dab != null else -1.0
    var space: SaColorSpace = surface.get_document().color_space
    out["want"] = space.from_display(SaColorDynamics.ramp_at(loaded.gradient_ramp(), float(out["mix"]), space))
    var chunk: SaTexture = surface.get_document().stroke_layer.get_field(Vector2i(0, 0))
    if chunk != null:
        var data := GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0).to_float32_array()
        var at := (128 * 256 + 128) * 4
        out["texel"] = Color(data[at], data[at + 1], data[at + 2], data[at + 3])
    surface.get_document().free()
    surface.easel.free()
    return out


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


## A kritarc that is not there, so Krita's pressure curve is read as linear on
## every machine and the suite does not read a painter's own.
func _kritarc() -> String:
    return scratch_dir.path_join("no-kritarc")


func _import(store: SaPresetStore) -> Dictionary:
    var results := SaKppImport.import_path(FIXTURE, store, null, true, _kritarc())
    assert_eq(results.size(), 1, "one preset read")
    return results[0] if not results.is_empty() else {}


func _import_bytes(store: SaPresetStore, bytes: PackedByteArray, file_name: String) -> Dictionary:
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    var path := scratch_dir.path_join(file_name)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(bytes)
    file.close()
    var results := SaKppImport.import_path(path, store, null, true, _kritarc())
    assert_eq(results.size(), 1, "one preset read from %s" % file_name)
    return results[0] if not results.is_empty() else {}


## *bytes* applied onto a fresh stamp brush, the painter's pair on it.
func _apply(bytes: PackedByteArray) -> SaStampBrushSettings:
    var settings := SaStampBrushSettings.new()
    SaKppImport.apply(SaKppReader.read_bytes(bytes, "sara-gradient-source.kpp"), settings)
    settings.color = RED
    settings.background_color = BLUE
    return settings


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.pressure = pressure
    return info


## The colour *dab* paints, picked the way `state_brush.gd` picks it.
func _paint(settings: SaStampBrushSettings, dab: SaDabParams) -> Color:
    return SaColorDynamics.apply(
        settings.color, dab, settings.background_color, null, settings.color_source, settings.gradient_ramp
    )


static func _straight(texel: Color) -> Color:
    return Color(texel.r / texel.a, texel.g / texel.a, texel.b / texel.a, 1.0)


static func _distance(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _assert_color(got: Color, want: Color, tolerance: float, message: String) -> void:
    assert_almost_eq(got.r, want.r, tolerance, "%s, red" % message)
    assert_almost_eq(got.g, want.g, tolerance, "%s, green" % message)
    assert_almost_eq(got.b, want.b, tolerance, "%s, blue" % message)
