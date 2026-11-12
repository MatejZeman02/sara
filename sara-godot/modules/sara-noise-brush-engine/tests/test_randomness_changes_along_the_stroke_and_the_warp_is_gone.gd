## Randomness changes along the stroke and the warp is gone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## No dab is a unit of paint that can
## show, read three ways. A long stroke is painted through the tool's own
## public calls with Hardness rolled along the stroke, and the band each chord
## point is laid at is recorded by a brush that answers the state's own
## [method band_for] and remembers the answer, so what the suite reads is what
## the kernel was handed. A preset stored before, rolled per dab and warped, is
## written as such a file looks and loaded through the store. And the page and
## the settings are read for the Warp row. The seed tests of the earlier randomness
## suite are kept here, since the seed is what an along the
## stroke roll is drawn from.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoiseModuleScript = preload("res://modules/sara-noise-brush-engine/module.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

## A canvas long enough for a stroke of thirty features, and the tip's radius
## on it, in pixels: a feature is four diameters, thirty-two pixels.
const CANVAS := Vector2i(1152, 128)
const RADIUS := 4.0
## Where the long stroke starts, how far each pen sample moves and how many.
const FROM := Vector2(40.0, 64.0)
const SAMPLE_STEP := 6.0
const SAMPLES := 175

## The Hardness row and how far its roll reaches below it, so the band runs
## over the row times the amount.
const HARDNESS := 0.9
const AMOUNT := 0.6


## The noise brush, remembering the band of every point it lays.
class RecordingBrush:
    extends "res://modules/sara-noise-brush-engine/state_noise_brush.gd"

    var bands: Array[float] = []

    func band_for(dab: SaDabParams) -> float:
        var band: float = super(dab)
        bands.append(band)
        return band


var _surface: SaSurface = null
var _brush: RecordingBrush = null
var _dir: String = SaDataRoot.path("test_s4_rolled_per_dab")


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)
    _brush = RecordingBrush.new()
    _brush.surface = _surface
    _brush.stroke_seed = 11
    _brush.settings.color = Color(0.2, 0.4, 0.8, 1.0)
    _brush.settings.hardness = HARDNESS
    _brush.settings.radius = RADIUS / float(mini(CANVAS.x, CANVAS.y))
    DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
    _brush = null
    Fixtures.teardown(_surface)
    _surface = null
    if not DirAccess.dir_exists_absolute(_dir):
        return
    for file_name: String in DirAccess.get_files_at(_dir):
        DirAccess.remove_absolute(_dir.path_join(file_name))
    DirAccess.remove_absolute(_dir)


## Hardness rolled along the stroke: over a stroke of about thirty features
## the band crosses at least half the roll's range, and from one chord point to
## the next it never moves by more than a twentieth of it, the smooth change of
## design 5 rather than a number drawn afresh at every point.
func test_a_hardness_rolled_along_the_stroke_changes_slowly_along_it() -> void:
    _brush.settings.hardness_option.bind_random(AMOUNT, SaSensor.Id.FUZZY_ALONG_STROKE, "hardness")
    var range_of := HARDNESS * AMOUNT
    for seed_value: int in [11, 12]:
        _brush.stroke_seed = seed_value
        _brush.bands.clear()
        _paint_long_stroke()
        var bands := _brush.bands
        var label := "Stroke %d" % seed_value
        var expected := int(SAMPLES * SAMPLE_STEP / (0.5 * RADIUS))
        assert_true(bands.size() >= expected, "%s laid a point every quarter diameter, %d of them" % [label, bands.size()])
        var swing: float = bands.max() - bands.min()
        assert_true(
            swing >= 0.5 * range_of,
            "%s: the band moves over %.3f of the roll's %.3f, at least half of it" % [label, swing, range_of]
        )
        assert_true(bands.min() >= 1.0 - HARDNESS - 0.0001, "%s: and never past the row, %.3f" % [label, bands.min()])
        var jump := 0.0
        for index in range(1, bands.size()):
            jump = maxf(jump, absf(bands[index] - bands[index - 1]))
        assert_true(
            jump <= range_of / 20.0,
            "%s: no two neighbouring points differ by more than a twentieth of it, %.4f at most" % [label, jump]
        )


## The roll is drawn from the stroke's seed: the same seed rolls the same band
## at every point, and another seed another.
func test_one_seed_rolls_one_way_and_another_seed_another() -> void:
    _brush.settings.hardness_option.bind_random(AMOUNT, SaSensor.Id.FUZZY_ALONG_STROKE, "hardness")
    _paint_long_stroke()
    var first := _brush.bands.duplicate()
    _fresh_surface()
    _brush.bands.clear()
    _paint_long_stroke()
    assert_eq(_brush.bands, first, "The same seed rolls the same band at every point")
    _fresh_surface()
    _brush.stroke_seed = 12
    _brush.bands.clear()
    _paint_long_stroke()
    assert_true(_brush.bands != first, "and another seed rolls another")


## A preset stored before the change, its Hardness rolled per dab and its Warp set,
## loads through the store with the roll along the stroke at the amount it had
## and nothing of the warp, and a Size rolled per stroke stays per stroke.
func test_a_preset_rolled_per_dab_with_a_warp_loads_rolled_along_and_unwarped() -> void:
    var stored := NoiseBrushSettingsScript.new()
    stored.hardness_option.bind_random(0.7, SaSensor.Id.FUZZY_PER_DAB, "hardness")
    stored.size_option.bind_random(0.4, SaSensor.Id.FUZZY_PER_STROKE, "size")
    _write_before_s4(stored, _dir.path_join("Old Chalk.tres"))
    var store := SaPresetStore.new()
    store.dir = _dir
    var loaded := store.load_preset("Old Chalk")
    assert_not_null(loaded, "The store loads the preset")
    assert_eq(loaded.get("format_version"), NoiseBrushSettingsScript.FORMAT_VERSION, "at the format of now")
    var hardness := loaded.get("hardness_option") as SaCurveOption
    assert_null(hardness.sensor_for(SaSensor.Id.FUZZY_PER_DAB), "Its Hardness rolls nothing per dab")
    assert_eq(hardness.random_clock(), SaSensor.Id.FUZZY_ALONG_STROKE, "but along the stroke")
    assert_almost_eq(hardness.random_amount(), 0.7, 0.0001, "as far below the row as it rolled")
    assert_eq(hardness.sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE).resource_name, "hardness", "by the option's name")
    var size := loaded.get("size_option") as SaCurveOption
    assert_eq(size.random_clock(), SaSensor.Id.FUZZY_PER_STROKE, "A roll per stroke stays per stroke")
    assert_false("warp" in loaded, "The warp is not a setting any more")
    assert_false("warp_option" in loaded, "and nor is its curve option")
    assert_false(loaded.call("options").has("warp"), "and the brush's options name no warp")
    assert_false(loaded.call("migrate"), "and a preset carried once is not carried twice")


## A roll stored per dab with no name of its own, as a curve editor's tick
## leaves one, takes its option's name, so two such rolls do not move together.
func test_a_roll_with_no_name_takes_its_options() -> void:
    var settings := NoiseBrushSettingsScript.new()
    for key: String in ["opacity", "strength"]:
        var option: SaCurveOption = settings.options()[key]
        option.set_sensor(SaSensor.create(SaSensor.Id.FUZZY_PER_DAB, true))
    assert_true(settings.carry_rolls_along(), "The rolls move")
    for key: String in ["opacity", "strength"]:
        var roll := (settings.options()[key] as SaCurveOption).sensor_for(SaSensor.Id.FUZZY_ALONG_STROKE)
        assert_eq(roll.resource_name, key, "%s's roll is drawn by its name" % key)
    assert_false(settings.carry_rolls_along(), "and a second carry finds none")


## The General page has no Warp row and no randomise row for it, Randomness
## still comes after Strength with none of its own, and every randomise row
## offers Along the stroke and Per stroke, opening on the first.
func test_the_page_has_no_warp_and_rolls_along_the_stroke() -> void:
    var keys: Array[String] = []
    for spec: SaOptionSpec in NoiseModuleScript.options():
        if spec.page == NoiseModuleScript.PAGE:
            keys.append(String(spec.key))
    assert_false(keys.has("warp"), "No Warp row")
    assert_false(keys.has("warp_random"), "and no randomise row for one")
    var tip := keys.find("tip_generator")
    var under: Array[String] = ["noise_tip_edge", "tip_angle", "tip_image_path", "tip_load"]
    assert_eq(keys.slice(tip + 1, tip + 5), under, "Tip's own four rows sit under it, Edge Hardness first and Angle next")
    assert_eq(keys[tip + 5], "texture_field", "and Texture is the row after them")
    var randomness := keys.find("randomness")
    assert_true(randomness > keys.find("strength"), "Randomness comes after Strength")
    assert_eq(keys[randomness + 1], "blend_mode", "and has no randomise row of its own")
    var settings := NoiseBrushSettingsScript.new()
    assert_false("warp" in settings, "The settings carry no warp")
    assert_false(settings.options().has("warp"), "and no curve option for one")
    var control := SaRandomiseControl.new(Callable(), "hardness", "Hardness")
    var clock := control.find_child("HardnessRandomClock", true, false) as SaChoiceButton
    assert_eq(clock.choice_labels(), ["Along the stroke", "Per stroke"] as Array[String], "The clocks are along and per stroke")
    assert_eq(clock.selected_value(), SaRandomiseControl.ALONG, "and a row opens on along the stroke")
    control.free()


## Broken Chalk keeps its broken edge from its grain and names no warp. Its
## seed rolls each
## stroke through two texture channels of the scumble picture, which it ships.
func test_broken_chalk_breaks_by_its_grain_and_rolls_its_seed() -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        var settings: Dictionary = entry.get("settings", {})
        assert_false(settings.has("warp"), "%s sets no warp" % entry["name"])
        if entry["name"] != "Broken Chalk":
            continue
        assert_eq(settings.get("randomness"), 1.0, "Broken Chalk rolls a seed each stroke, as a painter set it")
        assert_eq(settings.get("texture_channels"), 2, "through the two channels of the painter's grain")
        assert_false(String(entry["about"]).contains("dab"), "and its about line names no dab")


## Randomness at nought holds the seed: two strokes the tool was handed no seed
## for paint the same texels. Above nought each stroke rolls its own seed.
func test_a_held_seed_paints_one_stroke_twice_and_a_rerolled_one_does_not() -> void:
    _brush.settings.radius = 20.0 / float(mini(CANVAS.x, CANVAS.y))
    _brush.settings.strength = 0.5
    _brush.settings.randomness = 0.0
    _brush.settings.held_seed = 42
    var first := _short_stroke()
    var first_seed: int = _brush.field_seed
    var again := _short_stroke()
    assert_eq(first_seed, 42, "A held stroke is laid with the preset's seed")
    assert_eq(_brush.field_seed, first_seed, "and so is the next")
    assert_true(first.count(true) > 50, "The stroke painted, %d texels" % first.count(true))
    assert_eq(first, again, "and painted the same texels twice")

    _brush.settings.randomness = 1.0
    var rolled := _short_stroke()
    var rolled_seed: int = _brush.field_seed
    var other := _short_stroke()
    assert_true(rolled_seed != _brush.field_seed, "Rerolled strokes draw two seeds, %d and %d" % [rolled_seed, _brush.field_seed])
    assert_true(rolled != other, "and paint two strokes")


## A seed the tool is handed wins over both, which is what keeps a preset's
## thumbnail the same picture on every launch.
func test_a_handed_seed_wins_over_randomness() -> void:
    _brush.settings.randomness = 1.0
    _brush.stroke_seed = 9
    assert_eq(_brush.seed_for_stroke(), 9, "A handed seed is the stroke's")
    _brush.settings.randomness = 0.0
    assert_eq(_brush.seed_for_stroke(), 9, "held or not")


## A stroke from left to right at full pressure through the tool's public
## calls, about thirty features long.
func _paint_long_stroke() -> void:
    _brush.begin_stroke(FROM, 1.0)
    for i in range(1, SAMPLES + 1):
        _brush.add_sample(FROM + Vector2(SAMPLE_STEP * i, 0.0), 1.0)
    _brush.end_stroke()


## The texels of a short stroke laid with no handed seed, on a fresh surface,
## whether each took paint, row by row.
func _short_stroke() -> Array[bool]:
    _fresh_surface()
    _brush.stroke_seed = 0
    _brush.begin_stroke(FROM, 1.0)
    for i in range(1, 6):
        _brush.add_sample(FROM + Vector2(8.0 * i, 0.0), 1.0)
    _brush.end_stroke()
    var layer := _surface.easel.document.active_layer
    var images := {}
    var out: Array[bool] = []
    for y in range(-32, 33):
        for x in range(-32, 96):
            out.append(_alpha(layer, Vector2i(FROM) + Vector2i(x, y), images) > 0.5)
    return out


func _fresh_surface() -> void:
    Fixtures.teardown(_surface)
    _surface = Fixtures.make_surface(CANVAS)
    _brush.surface = _surface


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


## Writes *settings* as a preset stored before the change looks, at *path*: the earlier
## format, a Warp of 0.8, and a Warp curve option rolled per dab, which
## is the hardness option's own block, since a reference is all the line holds.
func _write_before_s4(settings: Resource, path: String) -> void:
    assert_eq(ResourceSaver.save(settings, path), OK, "the preset saves")
    var text := FileAccess.get_file_as_string(path)
    var lines := text.split("\n")
    var kept := PackedStringArray()
    for line: String in lines:
        if line.begins_with("format_version = "):
            kept.append("format_version = 2")
            continue
        kept.append(line)
        if line.begins_with("hardness_option = "):
            kept.append("warp = 0.8")
            kept.append(line.replace("hardness_option", "warp_option"))
    assert_true(kept.has("format_version = 2"), "the file names its format")
    assert_true(kept.has("warp = 0.8"), "and carries a warp")
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(kept))
    file = null
