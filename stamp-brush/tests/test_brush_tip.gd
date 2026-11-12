## The brush tip resource: its defaults, its arithmetic, and the preset round
## trip that tests whether a `Curve` survives a save.
##
## No GPU here. What the kernel does with these numbers is
## `test_dab_shader.gd`, and what a painter sees is the scenario.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")

## Its own folder under the sandboxed `user://`, so a run neither reads nor
## writes the presets a painter has saved.
static var scratch_preset_dir: String = SaDataRoot.path("test_brush_tip_presets")


func after_each() -> void:
    if DirAccess.dir_exists_absolute(scratch_preset_dir):
        var dir := DirAccess.open(scratch_preset_dir)
        for file in dir.get_files():
            dir.remove(file)
        DirAccess.remove_absolute(scratch_preset_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


## The defaults are a table, and they are a claim rather than a
## formality: a preset written before this field existed loads with every one of
## them, so each is what an old brush becomes.
func test_a_fresh_tip_is_the_circle_the_brush_already_painted() -> void:
    var tip := SaBrushTipScript.new()
    assert_eq(tip.kind, SaBrushTipScript.Kind.PROCEDURAL, "Procedural, so nothing goes looking for a file")
    assert_eq(tip.generator, SaDabGeometry.Generator.DEFAULT, "the ratio-of-norms falloff")
    assert_eq(tip.shape, SaBrushTipScript.Shape.CIRCLE, "a circle")
    assert_almost_eq(tip.ratio, 1.0, 1e-6, "with no ellipse in it")
    assert_eq(tip.spikes, 2, "two spikes, which is the plain shape")
    assert_true(tip.antialias_edges, "antialiased")
    assert_almost_eq(tip.density, 1.0, 1e-6, "solid")
    assert_almost_eq(tip.randomness, 0.0, 1e-6, "and even")
    assert_almost_eq(tip.softness, 1.0, 1e-6, "Softness of one changes nothing, which is why the table could omit it")


## The half-extents are what the box and the kernel are both handed, so the
## ratio has to reach them and only the minor axis may move.
func test_the_ratio_reaches_the_minor_axis_and_nothing_else() -> void:
    var tip := SaBrushTipScript.new()
    tip.diameter = 40.0
    assert_almost_eq(tip.half_extent().x, 20.0, 1e-6, "The major radius is half the diameter")
    assert_almost_eq(tip.half_extent().y, 20.0, 1e-6, "and a ratio of one makes it a circle")
    tip.ratio = 0.25
    assert_almost_eq(tip.half_extent().x, 20.0, 1e-6, "A ratio leaves the major axis alone")
    assert_almost_eq(tip.half_extent().y, 5.0, 1e-6, "and takes the minor one down to a quarter")
    assert_almost_eq(tip.half_extent(10.0).y, 1.25, 1e-6, "An override is the diameter for this dab only")
    assert_almost_eq(tip.diameter, 40.0, 1e-6, "and does not write itself back")


## **Softness multiplies.** The push-constant table says the fade slot
## arrives already divided by softness, and that is the wrong operation: what the
## kernel divides is the fade *coefficient*, which is one over the fade, so the
## fade itself is multiplied. Dividing would have made a softness under one
## sharpen the edge, which is the opposite of the word.
func test_softness_multiplies_the_fade() -> void:
    var tip := SaBrushTipScript.new()
    tip.horizontal_fade = 0.8
    tip.vertical_fade = 0.4
    assert_almost_eq(tip.effective_fade().x, 0.8, 1e-6, "A softness of one is the fade untouched")
    tip.softness = 0.5
    assert_almost_eq(tip.effective_fade().x, 0.4, 1e-6, "and half of it halves the fade, which softens")
    assert_almost_eq(tip.effective_fade().y, 0.2, 1e-6, "on both axes")
    tip.softness = 0.0
    assert_almost_eq(
        tip.effective_fade().x,
        0.8 * SaBrushTipScript.SOFTNESS_FLOOR,
        1e-6,
        "and zero is held at the floor rather than collapsing the fade to nothing"
    )


## The table is the falloff the kernel indexes, so its ends are the claim: one
## at the centre and nothing at the edge, in that order.
func test_the_softness_table_runs_from_the_centre_outwards() -> void:
    var tip := SaBrushTipScript.new()
    var table := tip.softness_table()
    assert_eq(table.size(), SaBrushTipScript.SOFTNESS_SAMPLES, "Two hundred and fifty-six samples")
    assert_almost_eq(table[0], 1.0, 1e-3, "opaque at the centre")
    assert_almost_eq(table[table.size() - 1], 0.0, 1e-3, "and clear at the edge")
    var previous := 1.01
    for value: float in table:
        assert_true(value <= previous + 1e-3, "with a falloff that never climbs")
        previous = value


## Softness lerps each interior sample between full coverage and the curve, and
## holds the two ends. Multiplying them instead is the version that sent the whole
## table to zero at the bottom of the row, so the ends are the part that has to
## stay put and this is the case that says so.
func test_softness_reshapes_the_table_and_holds_its_ends() -> void:
    var tip := SaBrushTipScript.new()
    var full := tip.softness_table()
    tip.softness = 0.5
    var half := tip.softness_table()
    assert_almost_eq(half[0], full[0], 1e-6, "The centre is held")
    assert_almost_eq(half[half.size() - 1], full[full.size() - 1], 1e-6, "and so is the edge")
    var middle := int(full.size() / 2.0)
    var wanted := lerpf(1.0, full[middle], 0.5)
    assert_almost_eq(half[middle], wanted, 1e-4, "while the middle moves half way towards a hard edge")


## The bottom of the Softness row is a hard-edged disc, and the reading that
## missed that it was not is worth keeping beside the one that catches it.
##
## `peak > 0.5` over the whole table always passed, because sample zero is the
## held centre and the curve is 1.0 there. What the old reshaping left was that
## one sample and 254 zeros, which the kernel reads as a three texel spike inside
## a fifty-eight texel dab. A reading that means anything has to be taken well
## inside the dab rather than at the point the reshaping never touches.
func test_the_soft_generator_paints_something_at_the_bottom_of_its_softness_row() -> void:
    var tip := SaBrushTipScript.new()
    tip.generator = SaDabGeometry.Generator.SOFT
    tip.softness = 0.0
    var table := tip.softness_table()
    var quarter := table[int(table.size() / 4.0)]
    var middle := table[int(table.size() / 2.0)]
    assert_almost_eq(quarter, 1.0, 1e-4, "A softness of zero covers a quarter of the way out, %.4f" % quarter)
    assert_almost_eq(middle, 1.0, 1e-4, "and half way out too, %.4f" % middle)
    assert_almost_eq(table[table.size() - 1], 0.0, 1e-4, "with the edge still the edge")


## A tip whose curve is missing is a preset written before the field existed,
## and the answer is the default falloff rather than an empty dab.
func test_a_tip_with_no_curve_still_has_a_falloff() -> void:
    var tip := SaBrushTipScript.new()
    tip.softness_curve = null
    var table := tip.softness_table()
    assert_almost_eq(table[0], 1.0, 1e-3, "Opaque at the centre")
    assert_almost_eq(table[table.size() - 1], 0.0, 1e-3, "and clear at the edge")


## The test of the resource: the soft generator's curve survives a
## preset save and load through `core/presets/sa_preset_store.gd`.
##
## The curve is edited away from its default first, because a round trip that
## only proves the default comes back proves that a default exists.
func test_the_softness_curve_survives_a_preset_round_trip() -> void:
    var settings := BrushSettingsScript.new()
    settings.tip.generator = SaDabGeometry.Generator.SOFT
    settings.tip.shape = SaBrushTipScript.Shape.RECTANGLE
    settings.tip.ratio = 0.4
    settings.tip.spikes = 7
    settings.tip.softness = 0.6
    var curve := Curve.new()
    curve.add_point(Vector2(0.0, 1.0))
    curve.add_point(Vector2(0.5, 0.9))
    curve.add_point(Vector2(1.0, 0.0))
    settings.tip.softness_curve = curve
    var before: PackedFloat32Array = settings.tip.softness_table()

    var store := _store()
    assert_true(store.save_preset("Soft round trip", settings) != "", "The preset saves")

    var loaded := store.load_preset("Soft round trip")
    assert_true(loaded != null, "and loads again")
    assert_true(loaded.tip != null, "with a tip on it")
    assert_eq(loaded.tip.generator, SaDabGeometry.Generator.SOFT, "the generator came back")
    assert_eq(loaded.tip.shape, SaBrushTipScript.Shape.RECTANGLE, "the shape came back")
    assert_eq(loaded.tip.spikes, 7, "the spikes came back")
    assert_almost_eq(loaded.tip.ratio, 0.4, 1e-5, "the ratio came back")
    assert_almost_eq(loaded.tip.softness, 0.6, 1e-5, "the softness came back")
    assert_true(loaded.tip.softness_curve != null, "and the curve is a curve rather than a null")

    var after: PackedFloat32Array = loaded.tip.softness_table()
    assert_eq(after.size(), before.size(), "The table is the same length")
    var biggest := 0.0
    for i in before.size():
        biggest = maxf(biggest, absf(after[i] - before[i]))
    assert_true(biggest < 1e-4, "and reads the same to %.6f everywhere" % biggest)


## The saved tip is the preset's own, not the live one. A preset that handed the
## same object back would mean dragging Softness edits every brush ever saved,
## which is the bug `copy_settings` deep-duplicates a resource to avoid.
func test_a_loaded_tip_is_not_the_one_that_was_saved() -> void:
    var settings := BrushSettingsScript.new()
    settings.tip.ratio = 0.3
    var store := _store()
    store.save_preset("Detached", settings)
    var loaded := store.load_preset("Detached")
    assert_true(loaded.tip != settings.tip, "Two objects")
    loaded.tip.ratio = 0.9
    assert_almost_eq(settings.tip.ratio, 0.3, 1e-6, "and writing one leaves the other alone")
