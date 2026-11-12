## A brush a few pixels wide is a single-pixel editor.
##
## The mode is one the brush enters by its size rather than a
## row a painter ticks, so the four questions here are the four halves of that
## switch: where it is, that nothing above it moved, that a diagonal stroke under
## it draws the line a pixel editor draws, and that the mode is cheaper than the
## stroke it replaces rather than dearer.
##
## Three of the four are arithmetic and one dispatches the kernel, because "whole
## texels with no partial coverage" is a statement about what the card wrote and
## nothing else can answer it.
extends "res://tests/test_framework.gd"

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## The threshold test and the walk tests need no card. The suite is marked as
## needing one anyway, because the readback below is half of what it asserts and
## a suite that ran three quarters of itself on a machine without a card would
## report a green that means less than it says.
const REQUIRES_GPU := true

## The texture one dab is stamped into, and the workgroups that covers at the
## kernel's `[numthreads(8, 8, 1)]`.
const SIDE: int = 32
const GROUPS: int = 4

## What counts as painted, the same floor `test_dab_dirty_rect.gd` uses: the
## float path leaves a few texels of the antialiased edge at coverages a painter
## cannot see, and calling those paint would make every dab partial.
const PAINTED: float = 1.0 / 512.0


## Where the switch is, and that it is a band rather than a point.
##
## The number itself is measured and the measurement is in
## `SaDabGeometry.PIXEL_MODE_DIAMETER`'s own comment. What this pins is that the
## constant is the one the three readers agree on and that the comparison is
## strict, so a dab of exactly the threshold is the ordinary brush.
func test_the_mode_is_entered_under_three_pixels_and_not_at_them() -> void:
    assert_almost_eq(SaDabGeometry.PIXEL_MODE_DIAMETER, 3.0, 1e-6, "the measured threshold is three document pixels")
    assert_true(SaDabGeometry.is_pixel_mode(2.99), "a dab just under the threshold is a pixel editor")
    assert_false(SaDabGeometry.is_pixel_mode(3.0), "a dab at the threshold is the ordinary brush")
    assert_false(SaDabGeometry.is_pixel_mode(20.0), "a large dab is the ordinary brush")
    # A caller with no diameter to hand is every suite that packs a dab by
    # itself, and it gets the dab it always got rather than the mode.
    assert_false(SaDabGeometry.is_pixel_mode(-1.0), "no diameter means the caller did not say")
    assert_false(SaDabGeometry.is_pixel_mode(0.0), "a dab of no size is not a mode, it is a dab that is dropped")

    # And the floor, which is what makes the mode a pixel editor rather than a
    # brush that stops working: a dab in the mode is never drawn under a texel,
    # because the threshold it paints through cannot light one from less.
    assert_almost_eq(SaDabGeometry.PIXEL_MODE_FLOOR, 1.5, 1e-6, "the measured floor is a pixel and a half")
    assert_almost_eq(SaDabGeometry.drawn_diameter(0.5), 1.5, 1e-6, "half a pixel is drawn at the floor")
    assert_almost_eq(SaDabGeometry.drawn_diameter(1.5), 1.5, 1e-6, "and the floor at the floor")
    assert_almost_eq(SaDabGeometry.drawn_diameter(2.0), 2.0, 1e-6, "and two at two, the floor being a floor")
    assert_almost_eq(SaDabGeometry.drawn_diameter(20.0), 20.0, 1e-6, "and a large dab is its own size")


## The switch reaches the centre, the push constant and the walk from the one
## constant, so the three cannot drift apart.
func test_the_three_readers_of_the_threshold_agree() -> void:
    var under := SaDabGeometry.PIXEL_MODE_DIAMETER - 0.5
    var over := SaDabGeometry.PIXEL_MODE_DIAMETER + 0.5

    # The centre: snapped the whole way under the threshold with the Sharpness
    # row at nothing, to the texel under it, and left where it fell above it.
    assert_eq(
        SaDabGeometry.snap_to_pixels(Vector2(4.4, 7.6), 0.0, under),
        Vector2(4.0, 7.0),
        "a small dab snaps to the grid with Sharpness off"
    )
    assert_eq(
        SaDabGeometry.snap_to_pixels(Vector2(4.4, 7.6), 0.0, over),
        Vector2(4.4, 7.6),
        "a dab above the threshold is where the painter put it"
    )

    # The push constant: sharpness one and no softness, which is the pair that
    # closes `sa_apply_threshold` onto the half coverage contour.
    var small := _packed(under, 0.0, 1.0)
    assert_almost_eq(small[22], 1.0, 1e-6, "a small dab is pushed at full sharpness")
    assert_almost_eq(small[23], 0.0, 1e-6, "a small dab is pushed with no sharpness softness")
    var large := _packed(over, 0.25, 0.75)
    assert_almost_eq(large[22], 0.25, 1e-6, "a large dab is pushed the Sharpness row's own value")
    assert_almost_eq(large[23], 0.75, 1e-6, "a large dab is pushed the Softness row's own value")

    # The walk, asked the way `state_brush.gd` asks it: through the cadence, which
    # is the one place a tip becomes a step and therefore the one place the size
    # is tested.
    var step := SaDabCadence.spacing_for(_tip(under))
    assert_true(step.pixel_grid, "a small dab walks the grid")
    assert_eq(step.distance, Vector2.ONE, "the grid step is one texel on each axis")
    assert_almost_eq(step.rotation, 0.0, 1e-6, "the grid is the document's frame, not the tip's")
    var ordinary := SaDabCadence.spacing_for(_tip(over))
    assert_false(ordinary.pixel_grid, "a dab above the threshold walks the ellipse")

    # And `effective_spacing` itself is untouched by the mode unless it is told,
    # because three suites drive it directly with sub-pixel sizes to pin Krita's
    # own branch and the mode must not reach in and answer for them.
    var arithmetic := SaStrokeDistance.effective_spacing(under, under, 0.1, 1.0, false, 0.0, false, true, 1.0)
    assert_false(arithmetic.pixel_grid, "a caller that did not ask for the mode does not get it")


## Ignore Spacing is the airbrush's switch and survives the mode, because a held
## pen deposits on its clock whatever the tip's size is.
func test_the_mode_keeps_the_airbrushs_own_switch() -> void:
    var under := SaDabGeometry.PIXEL_MODE_DIAMETER - 0.5
    var ignored := SaDabCadence.spacing_for(_tip(under), 1.0, false)
    assert_true(ignored.pixel_grid, "the mode is still on")
    assert_false(ignored.enabled, "Ignore Spacing still turns the travel gate off under the mode")


## A diagonal one-pixel stroke leaves no gaps and no doubled texels.
##
## **This is why the walk is not the ellipse.** A step of one pixel along a
## forty-five degree line is 0.707 of a texel on each axis, so a walk that
## measured distance would stamp the same texel twice and then skip one. The
## grid walk advances a whole texel on whichever axis runs fastest, which is the
## line every drawing program has drawn since Bresenham.
func test_a_diagonal_one_pixel_stroke_lays_one_texel_per_texel() -> void:
    var texels := _texels_along(Vector2(4.0, 4.0), Vector2(24.0, 24.0), 1.5)
    assert_eq(texels.size(), 20, "twenty texels for a twenty texel diagonal")
    _assert_no_gaps_and_no_doubles(texels, "a forty-five degree diagonal")

    # A shallow line, where one axis runs three times faster than the other, so
    # the staircase is what a pixel editor would draw rather than a diagonal.
    var shallow := _texels_along(Vector2(4.0, 4.0), Vector2(28.0, 12.0), 1.5)
    assert_eq(shallow.size(), 24, "one texel per column of a twenty four column line")
    _assert_no_gaps_and_no_doubles(shallow, "a shallow line")

    # And an axis-aligned one, which is the case the ellipse got right and this
    # must not lose.
    var flat := _texels_along(Vector2(4.0, 9.0), Vector2(24.0, 9.0), 1.5)
    assert_eq(flat.size(), 20, "one texel per column of a horizontal line")
    _assert_no_gaps_and_no_doubles(flat, "a horizontal line")


## The mode costs no more dispatches than the same stroke did.
##
## One dab is one dispatch batch, so a dab count is the cost. The comparison is
## against the spacing the same tip would have walked at without the mode, which
## for a small dab is the tip's own fraction of its size floored at
## [constant SaStrokeDistance.MIN_DISTANCE_SPACING], and that floor is exactly
## the reason the old walk was dear: a two pixel brush at a spacing of a tenth
## asked for a fifth of a pixel and got a half.
func test_the_mode_costs_no_more_dispatches_than_the_stroke_it_replaces() -> void:
    var diameter := 2.0
    var start := Vector2(4.0, 4.0)
    var finish := Vector2(64.0, 44.0)

    var floored := maxf(SaStrokeDistance.MIN_DISTANCE_SPACING, diameter * 0.1)
    var before := SaStrokeDistance.Spacing.new(Vector2(floored, floored))
    var after := SaDabCadence.spacing_for(_tip(diameter))
    assert_true(after.pixel_grid, "the two pixel brush is in the mode")

    var old_count := _walk(before, start, finish).size()
    var new_count := _walk(after, start, finish).size()
    assert_true(new_count <= old_count, "the mode paid %d dispatches where the stroke before it paid %d" % [new_count, old_count])
    # Not merely no dearer. The old walk hit its own floor of half a pixel, so it
    # paid more than two dabs for every texel the stroke crossed, and the mode
    # pays one: measured at 60 against 144 on this stroke.
    assert_eq(new_count, 60, "one dab per column of a sixty column stroke")
    assert_true(new_count * 2 <= old_count, "the mode paid %d where the stroke before it paid %d" % [new_count, old_count])


## Whole texels with no partial coverage anywhere, read off the card.
##
## The dab is stamped through the same packing the tool uses, so what is asserted
## is the mode as it ships rather than a hand-built push constant, and the centre
## goes through [method SaDabGeometry.snap_to_pixels] the way `state_brush.gd`
## sends it.
func test_a_small_dab_writes_whole_texels_and_a_larger_one_is_untouched() -> void:
    var under := SaDabGeometry.PIXEL_MODE_DIAMETER - 1.0
    # Deliberately off the grid on both axes and at the settings that would
    # otherwise leave a soft edge: the Sharpness row at nothing and the tip at
    # half hardness, which is a fade on both axes.
    var alpha := _stamp(under, Vector2(15.35, 16.72))
    var partial := 0
    var lit := 0
    for value in alpha:
        if value <= PAINTED:
            continue
        lit += 1
        if not is_equal_approx(value, 1.0):
            partial += 1
    assert_true(lit > 0, "the small dab painted something")
    assert_eq(partial, 0, "a dab under the threshold wrote %d partial texels of %d lit" % [partial, lit])

    # A dab just above the threshold is untouched: the same texels, one for one,
    # as the dab that goes through no diameter at all, which is what every
    # caller sent before this unit existed. And it is still an antialiased dab,
    # which is the half that would pass on its own if the mode were simply
    # never entered.
    var over := SaDabGeometry.PIXEL_MODE_DIAMETER + 0.5
    var now := _stamp(over, Vector2(15.35, 16.72))
    var was := _stamp(over, Vector2(15.35, 16.72), true)
    var moved := 0
    var soft := 0
    for index in SIDE * SIDE:
        if not is_equal_approx(now[index], was[index]):
            moved += 1
        if was[index] > PAINTED and not is_equal_approx(was[index], 1.0):
            soft += 1
    assert_eq(moved, 0, "a dab just above the threshold moved %d texels" % moved)
    assert_true(soft > 0, "a dab just above the threshold still has an antialiased edge")

    # And the floor, which is the half of the mode a number cannot show: a brush
    # of half a pixel is one whole texel and not the nothing the threshold would
    # otherwise leave. Exactly one, because a single-pixel editor that paints two
    # is not one.
    var tiny := _stamp(0.5, Vector2(15.35, 16.72))
    var tiny_lit := 0
    var tiny_partial := 0
    for value in tiny:
        if value <= PAINTED:
            continue
        tiny_lit += 1
        if not is_equal_approx(value, 1.0):
            tiny_partial += 1
    assert_eq(tiny_lit, 1, "half a pixel of brush lit %d texels" % tiny_lit)
    assert_eq(tiny_partial, 0, "and %d of them partially" % tiny_partial)
    # The texel the canvas shows under the pen, its floor, rather than the
    # nearest kernel centre.
    assert_almost_eq(tiny[16 * SIDE + 15], 1.0, 1e-6, "and it is the texel under the pen, (15, 16)")


## Every texel a grid walk lights between *start* and *finish*, in order.
##
## *chunk* is how long the segments the walk is fed are, because the tool feeds
## it one pointer event at a time rather than the whole stroke: a walk that only
## works when handed the segment whole is a walk that fails on a fast drag.
func _texels_along(start: Vector2, finish: Vector2, chunk: float) -> Array:
    var spacing := SaDabCadence.spacing_for(_tip(2.0))
    var texels: Array = []
    var distance := SaStrokeDistance.new()
    distance.register_dab(start, spacing)
    var here := start
    var steps := int(ceil(start.distance_to(finish) / chunk))
    for index in range(1, steps + 1):
        var to := start.lerp(finish, float(index) / float(steps))
        for _attempt in 4096:
            var t := distance.next_point_position(here, to)
            if t < 0.0:
                break
            var at := here.lerp(to, t)
            texels.append(Vector2i(SaDabGeometry.snap_to_pixels(at, 0.0, 2.0)))
            distance.register_dab(at, spacing)
            here = at
    return texels


## A dab per crossing and nothing else: consecutive texels touch, and no texel
## is stamped twice.
func _assert_no_gaps_and_no_doubles(texels: Array, what: String) -> void:
    var seen := {}
    for index in texels.size():
        var here: Vector2i = texels[index]
        assert_false(seen.has(here), "%s stamped %s twice" % [what, str(here)])
        seen[here] = true
        if index == 0:
            continue
        var previous: Vector2i = texels[index - 1]
        var reach := maxi(absi(here.x - previous.x), absi(here.y - previous.y))
        assert_eq(reach, 1, "%s left a gap between %s and %s" % [what, str(previous), str(here)])


## The walk `test_stroke_distance.gd` uses, with the segment start moved to each
## dab the way the tool moves it.
func _walk(spacing: SaStrokeDistance.Spacing, start: Vector2, finish: Vector2) -> Array:
    var distance := SaStrokeDistance.new()
    distance.register_dab(start, spacing)
    var dabs: Array = []
    var here := start
    for _attempt in 4096:
        var t := distance.next_point_position(here, finish)
        if t < 0.0:
            break
        var at := here.lerp(finish, t)
        dabs.append(at)
        distance.register_dab(at, spacing)
        here = at
    return dabs


## The tip a dab of *diameter* is stamped with, built the way `state_brush.gd`
## builds it: a round tip at half hardness, and the size through the pixel
## mode's own floor, because the floor is what the box, the step and the push
## constant all read.
func _tip(diameter: float) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = SaDabGeometry.drawn_diameter(diameter)
    tip.ratio = 1.0
    tip.horizontal_fade = 0.5
    tip.vertical_fade = 0.5
    tip.antialias_edges = true
    return tip


## One dab's push constant at *diameter*, packed the way the tool packs it.
func _packed(diameter: float, sharpness: float, sharpness_soft: float) -> PackedFloat32Array:
    var tip := _tip(diameter)
    return SaDabPacking.pack_dab_params(
        Vector2(8.0, 8.0),
        Vector2.ZERO,
        Color(1, 1, 1, 1),
        tip.half_extent(),
        0.0,
        tip.effective_fade(),
        1.0,
        SaDabGeometry.PaintMode.OVER,
        false,
        tip,
        sharpness,
        sharpness_soft,
        0.0,
        0.0,
        Vector2.ZERO,
        tip.diameter
    )


## Stamps one dab of *diameter* centred at *centre* into a cleared texture and
## answers the alpha per texel, through the same snap, floor and packing
## `state_brush.gd` sends a dab through.
##
## *as_before* stamps the dab without the pixel mode: no snap and no diameter on
## the packing, which is what every caller sent before it. It is how the
## "untouched to the texel" half is asked, since a dab above the threshold has
## to come out the same either way.
func _stamp(diameter: float, centre: Vector2, as_before: bool = false) -> PackedFloat32Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var tip := _tip(diameter)
    var at := centre if as_before else SaDabGeometry.snap_to_pixels(centre, 0.0, tip.diameter)

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image("")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    # The masking brush's block, bound with no mask, because a uniform set has to
    # cover every binding the kernel declares.
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            at,
            Vector2.ZERO,
            Color(1, 1, 1, 1),
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            0.0,
            0.0,
            0.0,
            0.0,
            Vector2.ZERO,
            -1.0 if as_before else tip.diameter
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out
