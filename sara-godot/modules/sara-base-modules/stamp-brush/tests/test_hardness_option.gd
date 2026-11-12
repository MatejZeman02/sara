## Hardness as the eleventh curve option, from the evaluator down to the
## texel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One hardness slider on every brush, randomised so one
## brush makes all three edges, hard, soft and lost, rests on three claims,
## and the middle one is the one worth writing down: **an option that is off has
## to leave the picture alone to the texel**, because the option multiplies the
## row every existing preset already carries, and a multiply that is not exactly
## one moves every brush in the tree.
##
## The edge is measured as the count of partly covered texels rather than as a
## radius. A radius needs a threshold to be read off, and the threshold is the
## thing under test: what a softer edge does is spread coverage over more texels,
## and counting the texels that are neither empty nor full says that directly.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const ModuleScript = preload("res://modules/sara-base-modules/stamp-brush/module.gd")

## Needs a RenderingDevice for the three texel claims. The runner skips this
## suite without one.
const REQUIRES_GPU := true

## The canvas every dab is stamped into, and the workgroups that covers at the
## kernel's own eight by eight.
const SIDE: int = 64
const GROUPS: int = 8

## The dab: centred, and small enough that the softest edge still falls inside
## the canvas. A lost edge spreads coverage over the whole disc, so a dab that
## reached the border would have its ramp clipped by the canvas rather than by
## the kernel and the counts below would measure the crop.
const HALF_EXTENT := Vector2(18.0, 18.0)
const CENTRE := Vector2(32.0, 32.0)

## What counts as painted, the way the dirty-rect suite counts it.
const PAINTED: float = 1.0 / 512.0

## Where a texel stops counting as partly covered. Full coverage comes back as
## exactly one from the kernel, so the margin is only there to keep a rounding
## step in the sampler from being read as a ramp.
const FULL: float = 1.0 - 1.0 / 512.0


func _settings() -> SaStampBrushSettings:
    return SaStampBrushSettings.new()


func _sample(pressure: float) -> SaStrokeInfo:
    var info := SaStrokeInfo.new()
    info.begin(Vector2.ZERO, 4242)
    info.hovering = false
    info.position = Vector2.ZERO
    info.pressure = pressure
    return info


## The option switched on and reading one sensor, which is the state a painter
## reaches by ticking a box.
func _tick(option: SaCurveOption, id: SaSensor.Id) -> void:
    option.enabled = true
    option.set_sensor(SaSensor.create(id, true))


# --- The evaluator ------------------------------------------------------------


## The dab's hardness is the option's own answer at a fixed sample.
##
## Pressure with the identity curve every fresh option carries, so the expected
## number is the pressure itself and the assertion is arithmetic rather than a
## second call to the thing under test.
func test_the_dab_hardness_is_the_option_at_a_fixed_sample() -> void:
    var settings := _settings()
    _tick(settings.hardness_option, SaSensor.Id.PRESSURE)
    var dynamics := SaDynamics.new(settings)

    for pressure: float in [0.25, 0.5, 0.75, 1.0]:
        var dab := dynamics.evaluate(_sample(pressure), 40.0)
        assert_almost_eq(dab.hardness, pressure, 1e-6, "Hardness at pressure %f is the option's value" % pressure)


## An option nobody switched on answers the one that changes nothing, which is
## what makes the multiply in `hardness_for_dab` safe on every preset in the
## tree.
func test_an_option_that_is_off_answers_one() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)

    assert_false(settings.hardness_option.enabled, "A new brush has the option off")
    for pressure: float in [0.0, 0.5, 1.0]:
        var dab := dynamics.evaluate(_sample(pressure), 40.0)
        assert_almost_eq(dab.hardness, 1.0, 1e-6, "and answers one at pressure %f" % pressure)


## The row and the option meet by a multiply, and the row is the ceiling.
func test_the_row_is_the_ceiling_and_the_option_can_only_soften() -> void:
    assert_almost_eq(SaDabPacking.hardness_for_dab(1.0, 1.0), 1.0, 1e-6, "The row untouched")
    assert_almost_eq(SaDabPacking.hardness_for_dab(0.8, 1.0), 0.8, 1e-6, "An option that is off is the row")
    assert_almost_eq(SaDabPacking.hardness_for_dab(0.8, 0.5), 0.4, 1e-6, "and half of it halves the row")
    assert_almost_eq(SaDabPacking.hardness_for_dab(1.0, 0.0), 0.0, 1e-6, "Zero is allowed through, which is the lost edge")
    assert_almost_eq(
        SaDabPacking.hardness_for_dab(4.0, 4.0), 1.0, 1e-6, "and neither side can push it above the row's own ceiling"
    )


## The random sensor spreads one stroke's dabs across the range, which is
## hard, soft and lost in the same stroke, in numbers.
##
## The seed is the stroke's, so this is one stroke's own spread rather than a
## sample of the runner's entropy, and it is asserted as a spread rather than as
## a list of values because the generator's sequence is not this unit's contract.
func test_the_random_sensor_spreads_one_stroke_across_the_range() -> void:
    var settings := _settings()
    _tick(settings.hardness_option, SaSensor.Id.FUZZY_PER_DAB)
    var dynamics := SaDynamics.new(settings)
    var info := _sample(1.0)
    dynamics.begin_stroke()

    var lowest := 1.0
    var highest := 0.0
    var middling := 0
    for i in range(200):
        var hardness := dynamics.evaluate(info, 40.0).hardness
        lowest = minf(lowest, hardness)
        highest = maxf(highest, hardness)
        if hardness > 0.25 and hardness < 0.75:
            middling += 1

    assert_true(lowest < 0.1, "One stroke reaches a lost edge, lowest %f" % lowest)
    assert_true(highest > 0.9, "and a hard one, highest %f" % highest)
    assert_true(middling > 20, "and lays soft ones in between, %d of two hundred" % middling)


# --- The texel ----------------------------------------------------------------


## One dab into a cleared canvas at *hardness*, read back as an alpha per texel.
##
## The whole canvas is dispatched rather than the dab's own box, for the reason
## `test_dab_shader.gd` gives: this suite is about what the kernel computes from
## the fade it was handed, and where it is allowed to write is asserted there.
func _paint(hardness: float) -> PackedFloat32Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    # The live brush writes the row onto both of the tip's fades and the tip
    # builds the pair, so the suite goes the same way round rather than calling
    # `fade_for_hardness`: what is under test is the number that reaches the tip.
    var tip := SaBrushTipScript.new()
    tip.diameter = HALF_EXTENT.x * 2.0
    tip.ratio = 1.0
    tip.horizontal_fade = hardness
    tip.vertical_fade = hardness
    tip.antialias_edges = true

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            HALF_EXTENT,
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


## How many texels the dab left neither empty nor full, which is the width of
## its edge without a threshold having to be chosen.
static func _ramp_texels(alpha: PackedFloat32Array) -> int:
    var count := 0
    for value: float in alpha:
        if value > PAINTED and value < FULL:
            count += 1
    return count


## The claim the whole option rests on: with it off, the picture is the one the
## row alone painted, texel for texel.
##
## The two dispatches differ only in how the number reached the tip, which is
## the mutation this catches: a `hardness_for_dab` that floored, rounded or
## added anything would move some texel here, and every preset in the tree with
## it.
func test_an_option_that_is_off_leaves_the_row_untouched_to_the_texel() -> void:
    var settings := _settings()
    var dynamics := SaDynamics.new(settings)
    var row := 0.7
    var dab := dynamics.evaluate(_sample(0.6), 40.0)

    var before := _paint(row)
    var after := _paint(SaDabPacking.hardness_for_dab(row, dab.hardness))

    assert_eq(before.size(), after.size(), "The same canvas both times")
    var moved := 0
    for i in before.size():
        if not is_equal_approx(before[i], after[i]):
            moved += 1
    assert_eq(moved, 0, "Not one texel moved with the option off")


## Hard, soft and lost, as three widths of one edge.
##
## The counts are the same dab at three hardnesses, so they are comparable
## without any of them being written down: a softer edge spreads its coverage
## over more texels, and the lost one has no full-coverage core left at all.
func test_the_edge_goes_hard_then_soft_then_lost() -> void:
    var hard := _paint(1.0)
    var soft := _paint(0.5)
    var lost := _paint(0.0)

    var hard_ramp := _ramp_texels(hard)
    var soft_ramp := _ramp_texels(soft)
    var lost_ramp := _ramp_texels(lost)

    assert_true(hard_ramp > 0, "A hard edge is still antialiased, %d texels" % hard_ramp)
    assert_true(soft_ramp > hard_ramp, "A half hardness spreads the edge wider, %d against %d" % [soft_ramp, hard_ramp])
    assert_true(lost_ramp > soft_ramp, "and a hardness of nothing wider again, %d" % lost_ramp)

    var hard_core := 0
    var lost_core := 0
    for i in hard.size():
        if hard[i] >= FULL:
            hard_core += 1
        if lost[i] >= FULL:
            lost_core += 1
    assert_true(hard_core > 0, "The hard edge has a solid core, %d texels" % hard_core)
    assert_true(lost_core * 20 < hard_core, "and the lost one has all but none of it left, %d" % lost_core)


# --- The page -----------------------------------------------------------------


## The module declares Hardness as a page of its own, and the editor lists it
## beside Softness rather than after everything else.
##
## The adjacency is the assertion rather than an index, because the list grows:
## what has to stay true is that the two readings of one edge sit together.
func test_the_editor_lists_hardness_beside_softness() -> void:
    var pages: Array = SaBrushEditorPages.pages_from(ModuleScript.brush_options())
    var titles: Array = []
    for page: Dictionary in pages:
        titles.append(String(page["title"]))

    assert_true(titles.has("Hardness"), "Hardness is a page")
    assert_eq(titles.find("Hardness"), titles.find("Softness") + 1, "listed straight after Softness")

    var hardness: Dictionary = {}
    for page: Dictionary in pages:
        if String(page["title"]) == "Hardness":
            hardness = page
    assert_not_null(hardness.get("curve"), "with a curve option behind its checkbox")


# --- The migration ------------------------------------------------------------


## A preset written before this option loads with it off, so it paints what it
## painted.
##
## Both versions that exist in the wild: one written before the curve options
## and one written at version 3. Neither has the key at all, so both take the
## exported default, and the assertion is that the default is the one that
## changes nothing.
func test_the_migration_leaves_an_existing_preset_painting_what_it_painted() -> void:
    for version: int in [1, 2, 3]:
        var settings := _settings()
        settings.hardness.value = 0.65
        settings.format_version = version
        settings.migrate()
        var dynamics := SaDynamics.new(settings)

        assert_false(settings.hardness_option.enabled, "A version %d preset loads with Hardness off" % version)
        var dab := dynamics.evaluate(_sample(0.4), 40.0)
        assert_almost_eq(
            SaDabPacking.hardness_for_dab(settings.hardness.raw(), dab.hardness),
            settings.hardness.raw(),
            1e-6,
            "and the number the tip is written from is its own row, at version %d" % version
        )


## The migration's version 3 step switches the curve on for every option it
## finds, and finding an eleventh is not the same as switching it on.
func test_the_curve_step_does_not_switch_the_new_option_on() -> void:
    var settings := _settings()
    settings.format_version = 2
    settings.migrate()

    assert_true(settings.hardness_option.use_curve, "The curve is read, as it is on all eleven")
    assert_false(settings.hardness_option.enabled, "but the option is still off, which is the off switch")
    assert_true(settings.hardness_option.sensors.is_empty(), "and it was given no sensor")
