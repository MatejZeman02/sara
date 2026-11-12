## The Look page's rows leave every preset that shipped before them as it was,
## and the five presets of the flat tip style built from them lay what the Look rows
## make reachable: a body painted over most of its core, strands
## that differ in width, and an outline that repeats no unit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The before is a file per preset.** `fixtures/before` holds each of the ten
## presets that shipped before the rows came, built from its recipe and saved
## at format four by the code of then. Read back by today's script, every
## setting the file holds is the one today's recipe builds, so the ten paint as
## they did, and once migrated the file is the preset written at format five
## whole, the Look page's rows at their rests.
##
## **The five are measured on one stroke each**, the level stroke the three
## rows' suites paint, at [constant PRESSURE], as each preset ships less its
## radius taper, at [constant RADIUS] and [constant SEED], in a mid brown. The
## core's share is read as the core row's suite reads it, the strands' widths as
## the strands row's does, as runs across the body, of paint or of the darker tone where
## a preset fills its body and shows its field as tone, and the outline as
## the edge row's does, over [constant OUTLINE] pixels of the body, with each row's
## bound.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")
const NoisePresetsScript = preload("res://modules/sara-noise-brush-engine/presets/noise_presets.gd")

const BEFORE := "res://modules/sara-noise-brush-engine/presets/tests/fixtures/before"
## The rows the Look page added, which a file of format four never holds.
const LOOK: Array[String] = [
    "fill", "texture_tone", "strand_width", "strand_softness", "strand_taper", "rim_firmness", "build_up"
]
const FLAT_TIP_STYLE: Array[String] = ["Firm Fill", "Smeary Flat", "Sea Sponge", "Ribbon Pen", "Graphite Pencil"]
## The settings a recipe has changed on purpose since the files were saved,
## which the comparison leaves out: Bristle Flat lays a thin relief, so a
## return over its stroke can stand higher.
const CHANGED_SINCE := {"Bristle Flat": ["thickness"]}

const PRESSURE := 0.8
const CANVAS := Vector2i(1024, 256)
const RADIUS := 30.0
const FROM := Vector2(60.0, 128.0)
const TO := Vector2(964.0, 128.0)
const SPACING := 4.0
const SAMPLE_MS := 8.0
const SEED := 7
const COLOUR := Color(0.55, 0.32, 0.18, 1.0)
## How many radii from each end the body is read from, and the alpha a texel
## holds to count as painted, the three suites' own.
const END_MARGIN := 2.0
const PAINTED := 0.5
## The share of the half-width its core spans, and the share of that core a
## stroke at 0.8 paints more than.
const CORE := 0.6
const MOST := 0.75
## The share of the half-width its strands are read across, and its least
## spread of their widths as a share of their mean and least share of them off
## a tenth of it.
const STRANDS := 0.8
const WIDTH_SPREAD := 0.45
const WIDTHS_OFF := 0.5
## The length of outline and the autocorrelation it stays under at every lag
## from one grain scale to one tip width.
const OUTLINE := 600
const REPEAT := 0.25
## The Rim Firmness from which the edge takes no nick, so the outline is the
## tip's own less a slow wander and the bound above, which reads a smooth line
## as one unit repeated, is not asked of it. Firm Fill and Ribbon Pen stand
## over it, since a nick cuts a round blob's firm rim in by a third of its
## radius, and Firm Fill's rim is held to no notch by
## `test_firm_fill_lays_no_dark_specks_and_no_grey_in_its_grain.gd`.
const FIRM := 0.5

var _surface: SaSurface = null
var _brush: StateNoiseBrushScript = null
var _albedo: Dictionary = {}


func before_each() -> void:
    _surface = Fixtures.make_surface(CANVAS)


func after_each() -> void:
    _brush = null
    _albedo.clear()
    Fixtures.teardown(_surface)
    _surface = null


## Every setting a preset saved before the rows holds is the one its recipe
## builds today, and its Look rows load at their rests.
func test_every_preset_saved_before_the_look_rows_holds_what_its_recipe_builds_now() -> void:
    var files := DirAccess.get_files_at(BEFORE)
    var checked := 0
    for entry: Dictionary in NoisePresetsScript.entries():
        var file := String(entry["name"]).to_lower().replace(" ", "_") + ".tres"
        if FLAT_TIP_STYLE.has(entry["name"]):
            assert_false(files.has(file), "%s is new, so no file of before holds it" % entry["name"])
            continue
        var old := _load_before(file)
        var now := NoisePresetsScript.build(NoiseBrushSettingsScript, entry)
        assert_eq(old.format_version, 4, "%s was saved at format four" % entry["name"])
        var differs := _differences(old, now, "", ["format_version"] + CHANGED_SINCE.get(entry["name"], []))
        assert_true(differs.is_empty(), "%s holds every setting it held before, differing in %s" % [entry["name"], differs])
        var fresh := NoiseBrushSettingsScript.new()
        for row: String in LOOK:
            assert_eq(old.get(row), fresh.get(row), "%s loads %s at its rest" % [entry["name"], row])
        checked += 1
    assert_eq(checked, 10, "Every one of the ten presets of before is read")


## A preset saved at format four, migrated as the store migrates it, is the one
## written at format five, its Look rows at their rests.
func test_a_preset_of_format_four_migrates_to_the_one_written_at_format_five() -> void:
    for entry: Dictionary in NoisePresetsScript.entries():
        if FLAT_TIP_STYLE.has(entry["name"]):
            continue
        var old := _load_before(String(entry["name"]).to_lower().replace(" ", "_") + ".tres")
        assert_true(old.migrate(), "%s of format four is carried" % entry["name"])
        assert_eq(
            old.format_version, NoiseBrushSettingsScript.FORMAT_VERSION, "to format %d" % NoiseBrushSettingsScript.FORMAT_VERSION
        )
        var path := SaDataRoot.path("test_now.tres")
        assert_eq(
            ResourceSaver.save(NoisePresetsScript.build(NoiseBrushSettingsScript, entry), path),
            OK,
            "%s saves at format five" % entry["name"]
        )
        var now := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NoiseBrushSettingsScript
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
        assert_false(now.migrate(), "and a file of format five is not carried")
        var differs := _differences(old, now, "", CHANGED_SINCE.get(entry["name"], []))
        assert_true(differs.is_empty(), "%s migrated equals it written now, differing in %s" % [entry["name"], differs])


## Each of the five paints most of its core at 0.8, lays strands whose widths
## differ, and leaves an outline with no repeat in it unless its rim is firm.
func test_each_flat_tip_style_preset_paints_its_core_varies_its_strands_and_breaks_its_edge() -> void:
    for preset: String in FLAT_TIP_STYLE:
        _albedo.clear()
        Fixtures.teardown(_surface)
        _surface = Fixtures.make_surface(CANVAS)
        _use(preset)
        _stroke()
        var core := _core_share()
        var widths := _widths()
        var spread := _spread(widths) / maxf(_mean(widths), 1e-6)
        var off := _off_a_tenth(widths)
        print(
            (
                "flat tip style: %s paints %.3f of its core, %d strands spread %.3f of their mean with %.3f off a tenth"
                % [preset, core, widths.size(), spread, off]
            )
        )
        assert_true(core > MOST, "%s paints %.3f of its core at %.1f, more than %.2f" % [preset, core, PRESSURE, MOST])
        assert_true(widths.size() > 20, "%s lays %d strands across its body, more than 20" % [preset, widths.size()])
        assert_true(
            spread >= WIDTH_SPREAD, "%s's strands spread by %.3f of their mean, at least %.2f" % [preset, spread, WIDTH_SPREAD]
        )
        assert_true(
            off >= WIDTHS_OFF, "%s has %.3f of its strands off a tenth of their mean, at least %.2f" % [preset, off, WIDTHS_OFF]
        )
        var shortest := maxi(1, roundi(_brush.settings.grain_scale))
        var longest := roundi(2.0 * RADIUS)
        for side: int in [-1, 1]:
            if _brush.settings.rim_firmness >= FIRM:
                continue
            var repeat := _greatest_correlation(_outline(side), shortest, longest)
            print("flat tip style: %s side %d correlates %.3f at most" % [preset, side, repeat])
            assert_true(repeat < REPEAT, "%s side %d correlates %.3f with itself, under %.2f" % [preset, side, repeat, REPEAT])


## The preset of before saved as *file*, loaded as the store loads it.
func _load_before(file: String) -> NoiseBrushSettingsScript:
    return ResourceLoader.load(BEFORE.path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as NoiseBrushSettingsScript


## Every stored property of *a* and *b* that differs, by its path under
## *prefix*, a resource's read property by property, less those of *leave*.
func _differences(a: Variant, b: Variant, prefix: String, leave: Array) -> Array[String]:
    var found: Array[String] = []
    if a is Resource and b is Resource:
        if (a as Resource).get_script() != (b as Resource).get_script():
            found.append(prefix + ":script")
            return found
        for property: Dictionary in (a as Resource).get_property_list():
            var name: String = property["name"]
            if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE) or leave.has(name) or name == "script":
                continue
            found.append_array(_differences((a as Resource).get(name), (b as Resource).get(name), prefix + "/" + name, []))
    elif a is Dictionary and b is Dictionary:
        var keys_a := (a as Dictionary).keys()
        var keys_b := (b as Dictionary).keys()
        keys_a.sort()
        keys_b.sort()
        if keys_a != keys_b:
            found.append(prefix + ":keys")
            return found
        for key: Variant in a:
            found.append_array(_differences(a[key], b[key], "%s[%s]" % [prefix, key], []))
    elif a is Array and b is Array:
        if (a as Array).size() != (b as Array).size():
            found.append(prefix + ":size")
            return found
        for i in range((a as Array).size()):
            found.append_array(_differences(a[i], b[i], "%s[%d]" % [prefix, i], []))
    elif typeof(a) != typeof(b) or a != b:
        found.append(prefix)
    return found


## The share of the core painted.
func _core_share() -> float:
    var reach := int(RADIUS * CORE)
    var painted := 0
    var count := 0
    for x in range(int(FROM.x + END_MARGIN * RADIUS), int(TO.x - END_MARGIN * RADIUS)):
        for y in range(int(FROM.y) - reach, int(FROM.y) + reach + 1):
            count += 1
            if _texel(Vector2i(x, y)).a >= PAINTED:
                painted += 1
    return float(painted) / count


## The widths of the strands across the strands row's band, every six pixels along the
## body, less a strand that reaches the band's edge. A strand is a run of
## texels painted at least [constant PAINTED] and no lighter than the
## column's middle tone, so a brush that paints in one tone reads its runs of
## paint as the strands row's suite does, and one that fills its body and lays its field
## as tone reads its darker runs, which is where its strands show.
func _widths() -> Array[float]:
    var widths: Array[float] = []
    var reach := int(RADIUS * STRANDS)
    for x in range(int(FROM.x + END_MARGIN * RADIUS), int(TO.x - END_MARGIN * RADIUS), 6):
        var tones: Array[float] = []
        var painted: Array[float] = []
        for y in range(-reach, reach + 1):
            var texel := _texel(Vector2i(x, int(FROM.y) + y))
            var tone := texel.get_luminance() if texel.a >= PAINTED else INF
            tones.append(tone)
            if tone < INF:
                painted.append(tone)
        if painted.is_empty():
            continue
        painted.sort()
        var middle := painted[floori(painted.size() / 2.0)]
        var at := 0
        while at < tones.size():
            if tones[at] > middle:
                at += 1
                continue
            var start := at
            while at < tones.size() and tones[at] <= middle:
                at += 1
            if start > 0 and at < tones.size():
                widths.append(float(at - start))
    return widths


## The distance from the path to the outermost painted texel on *side*, one to
## a texel along [constant OUTLINE] pixels of the body.
func _outline(side: int) -> PackedFloat32Array:
    var outline := PackedFloat32Array()
    var first := int(FROM.x + END_MARGIN * RADIUS)
    for x in range(first, first + OUTLINE):
        var far := 0.0
        for d in range(int(RADIUS) + 4, 0, -1):
            if _texel(Vector2i(x, int(FROM.y) + side * d)).a >= PAINTED:
                far = d
                break
        outline.append(far)
    return outline


## The greatest autocorrelation of *values* about their mean at a lag from
## *shortest* to *longest*, one for an outline that never moves.
static func _greatest_correlation(values: PackedFloat32Array, shortest: int, longest: int) -> float:
    var mean := 0.0
    for v: float in values:
        mean += v
    mean /= maxi(values.size(), 1)
    var power := 0.0
    for v: float in values:
        power += (v - mean) * (v - mean)
    if power <= 0.0:
        return 1.0
    var greatest := -1.0
    for lag in range(shortest, longest + 1):
        var sum := 0.0
        for i in range(values.size() - lag):
            sum += (values[i] - mean) * (values[i + lag] - mean)
        greatest = maxf(greatest, sum / power)
    return greatest


func _mean(values: Array[float]) -> float:
    var total := 0.0
    for value: float in values:
        total += value
    return total / maxi(values.size(), 1)


func _spread(values: Array[float]) -> float:
    var mean := _mean(values)
    var total := 0.0
    for value: float in values:
        total += (value - mean) * (value - mean)
    return sqrt(total / maxi(values.size(), 1))


## The share of *values* further than a tenth of their mean from it.
func _off_a_tenth(values: Array[float]) -> float:
    var mean := maxf(_mean(values), 1e-6)
    var count := 0
    for value: float in values:
        if absf(value - mean) / mean > 0.1:
            count += 1
    return float(count) / maxi(values.size(), 1)


## *preset* as it ships without its radius taper, at [constant RADIUS] and
## [constant SEED], in [constant COLOUR].
func _use(preset: String) -> void:
    _brush = StateNoiseBrushScript.new()
    _brush.surface = _surface
    _brush.stroke_seed = SEED
    for entry: Dictionary in NoisePresetsScript.entries():
        if entry["name"] == preset:
            var untapered := entry.duplicate(true)
            (untapered["pressure"] as Dictionary).erase("radius")
            _brush.settings = NoisePresetsScript.build(NoiseBrushSettingsScript, untapered)
    _brush.settings.color = COLOUR
    _brush.settings.radius = RADIUS / mini(CANVAS.x, CANVAS.y)


## The level stroke at [constant PRESSURE] all the way.
func _stroke() -> void:
    var clock := 1000.0
    _brush.begin_stroke(FROM, PRESSURE, Vector2.ZERO, clock)
    var steps := ceili(FROM.distance_to(TO) / SPACING)
    for i in range(1, steps + 1):
        clock += SAMPLE_MS
        _brush.add_sample(FROM.lerp(TO, float(i) / steps), PRESSURE, Vector2.ZERO, clock)
    _brush.end_stroke()


## The active layer's texel at *pixel*.
func _texel(pixel: Vector2i) -> Color:
    var layer := _surface.easel.document.active_layer
    for grid: Vector2i in layer.chunks:
        var side := (layer.chunks[grid] as SaChunk).pixel_size()
        var here := Vector2i(floori(float(pixel.x) / side), floori(float(pixel.y) / side))
        if not layer.chunks.has(here):
            return Color.TRANSPARENT
        if not _albedo.has(here):
            @warning_ignore("static_called_on_instance")
            _albedo[here] = SaExport.get_texture_image_float(layer.get_field(here))
        return (_albedo[here] as Image).get_pixelv(pixel - here * side)
    return Color.TRANSPARENT
