## The dab kernel, dispatched over a real texture and read back.
##
## Every assertion here is a texel out of `rd.texture_get_data`, the way
## `modules/sara-base-modules/stamp-brush/tests/test_paint_shader.gd` reads its fixture kernel, because a mask generator is
## arithmetic and a screenshot of a stroke cannot tell 0.98 coverage from 1.0.
## What a screenshot is for is the pair of captures that say the
## edge did not move.
extends "res://tests/test_framework.gd"

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SIDE: int = 64

## The workgroups one dispatch of the whole texture needs. Written out rather
## than divided, because `SIDE / 8` is an integer division the language server
## flags and because the kernel's own `[numthreads(8, 8, 1)]` is the number this
## has to agree with rather than a quotient.
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)

## Eight rotations, which is what the box assertion sweeps. Not four: the
## diagonals are where a box computed from the un-rotated half-extents is
## wrong, so a sweep that only visited the axes would pass on a wrong box.
const ROTATIONS: Array = [0.0, PI / 8.0, PI / 4.0, 3.0 * PI / 8.0, PI / 2.0, 5.0 * PI / 8.0, 3.0 * PI / 4.0, PI]


## A tip of the given half-extents and fade, which is what every assertion below
## describes its dab as. The two fades are separate on the resource and equal in
## almost every test, because Sara's Hardness writes both.
func _tip(half_extent: Vector2, fade: Vector2, antialias: bool = true) -> Resource:
    var tip := SaBrushTipScript.new()
    tip.diameter = half_extent.x * 2.0
    tip.ratio = half_extent.y / half_extent.x
    tip.horizontal_fade = fade.x
    tip.vertical_fade = fade.y
    tip.antialias_edges = antialias
    return tip


## One dab into a cleared 64 by 64 texture, read back as an alpha per texel.
##
## The whole texture is dispatched rather than the dab's own box, because this
## suite is about what the kernel computes and the box is asserted separately.
## A kernel dispatched over its box and one dispatched over the texture write
## the same texels: `render_offset` is what puts them in the same place.
## *colour* and *tip_lightness* are the two things a suite about the tip's own
## lightness needs and no other suite does: the dab's colour, because a shift
## on white has nowhere to go, and the strength the tip's picture is applied
## at, which is otherwise the settings' and zero here. Both default to what
## every other caller in this file painted with.
func _paint_tip(
    tip: Resource,
    radians: float = 0.0,
    centre: Vector2 = CENTRE,
    sharpness: float = 0.0,
    sharpness_soft: float = 0.0,
    dab_seed: float = 0.0,
    masking: Resource = null,
    colour: Color = Color(1, 1, 1, 1),
    tip_lightness: float = 0.0,
    space: SaColorSpace = null
) -> PackedFloat32Array:
    var data := _paint_tip_bytes(tip, radians, centre, sharpness, sharpness_soft, dab_seed, masking, colour, tip_lightness, space)
    var out := PackedFloat32Array()
    out.resize(SIDE * SIDE)
    for i in SIDE * SIDE:
        out[i] = data.decode_float(i * 16 + 12)
    return out


## The raw texels of one dab, which the alpha reader above and the two-channel
## reader in `test_dab_image_tip.gd` both decode.
##
## Factored out rather than copied, because a second copy of the binding set is
## a second thing to fix the day the kernel declares a seventh binding: this
## block names every bind, and it is the only one here that does.
func _paint_tip_bytes(
    tip: Resource,
    radians: float = 0.0,
    centre: Vector2 = CENTRE,
    sharpness: float = 0.0,
    sharpness_soft: float = 0.0,
    dab_seed: float = 0.0,
    masking: Resource = null,
    colour: Color = Color(1, 1, 1, 1),
    tip_lightness: float = 0.0,
    space: SaColorSpace = null
) -> PackedByteArray:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    # The kernel declares the softness table whichever generator is running, and
    # a uniform set has to cover every binding the shader declares, so this is
    # bound for a hard circle exactly as it is for a soft one.
    var mask := SaBrushTipMask.load_image(tip.image_path if tip.uses_image() else "")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    # The masking brush's block, bound whether or not there is one, because a
    # uniform set has to cover every binding the kernel declares. Null is a block
    # that is off, which is every dab this suite painted before. The document's
    # space goes with it, because what the lightness row's shift means is a
    # property of the chunks and the kernel cannot ask. Null is the sRGB answer
    # the suites painted under.
    compute.set_buffer(
        SaStampBindings.MASKING_BINDING,
        (
            SaStampBindings
            . of(mask)
            . masking_for(
                masking,
                tip.diameter,
                null,
                tip_lightness,
                SaStampBindings.lightness_mode_for(space),
                SaStampBindings.transfer_for(space)
            )
            . rid
        )
    )
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)

    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            centre,
            Vector2.ZERO,
            colour,
            tip.half_extent(),
            radians,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip,
            sharpness,
            sharpness_soft,
            dab_seed
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)
    return rd.texture_get_data(canvas.rid, 0)


func _paint(
    half_extent: Vector2, radians: float, fade: Vector2, antialias: bool = true, centre: Vector2 = CENTRE
) -> PackedFloat32Array:
    return _paint_tip(_tip(half_extent, fade, antialias), radians, centre)


static func _at(alpha: PackedFloat32Array, x: int, y: int) -> float:
    if x < 0 or y < 0 or x >= SIDE or y >= SIDE:
        return 0.0
    return alpha[y * SIDE + x]


## The painted texels' bounding box, which is what a shape claim is checked
## against when the shape is not a disc.
static func _painted_box(alpha: PackedFloat32Array) -> Rect2i:
    var min_x := SIDE
    var min_y := SIDE
    var max_x := -1
    var max_y := -1
    for y in SIDE:
        for x in SIDE:
            if _at(alpha, x, y) <= 0.0:
                continue
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)
    if max_x < 0:
        return Rect2i()
    return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## The hard end of the slider: opaque at the centre and nothing outside the
## radius. A fade of 1 is the hard edge, which is the mapping a table could
## easily invert.
func test_a_hard_round_dab_is_opaque_inside_and_clear_outside() -> void:
    var alpha := _paint(Vector2(10.0, 10.0), 0.0, Vector2.ONE)
    assert_almost_eq(_at(alpha, 32, 32), 1.0, 1e-4, "The centre is opaque")
    assert_almost_eq(_at(alpha, 37, 32), 1.0, 1e-4, "and so is half way out")
    assert_almost_eq(_at(alpha, 44, 32), 0.0, 1e-4, "Two pixels past the radius is clear")
    assert_almost_eq(_at(alpha, 32, 44), 0.0, 1e-4, "on the other axis too")


## The soft end: a falloff that never rises on the way out. Monotonic rather
## than any particular shape, because the shape is the ratio of two elliptical
## radii and pinning its values would pin the port rather than the property.
func test_a_full_fade_falls_off_monotonically() -> void:
    var alpha := _paint(Vector2(16.0, 16.0), 0.0, Vector2.ZERO)
    assert_almost_eq(_at(alpha, 32, 32), 1.0, 1e-3, "The centre is still opaque")
    var previous := 1.1
    for step in range(0, 20):
        var here := _at(alpha, 32 + step, 32)
        assert_true(here <= previous + 1e-4, "coverage rose again at %d pixels out" % step)
        previous = here
    assert_true(_at(alpha, 40, 32) < 0.95, "and it is a fade rather than a hard edge")
    assert_almost_eq(_at(alpha, 50, 32), 0.0, 1e-4, "with nothing past the radius")


## The ellipse, which is the whole reason the frame is the tip's own rather than
## the document's. A ratio of 0.3 is opaque out to 0.3 of the radius on the
## short axis and clear at half of it.
func test_a_thin_ellipse_is_opaque_on_its_short_axis_and_clear_past_it() -> void:
    var alpha := _paint(Vector2(20.0, 6.0), 0.0, Vector2.ONE)
    # Four rather than five of the six: the antialiasing band is the outermost
    # pixel and a texel inside it is a ramp by design, which is what the fifth
    # reads as 0.994 rather than as 1.
    assert_almost_eq(_at(alpha, 32, 32 + 4), 1.0, 1e-4, "Inside the minor axis is opaque")
    assert_almost_eq(_at(alpha, 32, 32 + 10), 0.0, 1e-4, "and past it is clear")
    assert_almost_eq(_at(alpha, 32 + 18, 32), 1.0, 1e-4, "while the major axis reaches much further")


## The same dab a quarter turn round is the transpose of it. This is the
## assertion that catches a rotation applied the wrong way, which is otherwise
## invisible on a circle and on a symmetric fade.
func test_a_quarter_turn_transposes_the_dab() -> void:
    var flat := _paint(Vector2(20.0, 6.0), 0.0, Vector2.ONE)
    var upright := _paint(Vector2(20.0, 6.0), PI / 2.0, Vector2.ONE)
    for offset: int in [-18, -10, -5, 0, 5, 10, 18]:
        assert_almost_eq(
            _at(upright, 32, 32 + offset),
            _at(flat, 32 + offset, 32),
            1e-4,
            "the turned dab at (32, %d) is the flat one at (%d, 32)" % [32 + offset, 32 + offset]
        )


## The 6 by 6 supersampling exists so a very small brush does not paint a dashed
## line, and a dab under a pixel is where it fires.
##
## **The property is not "no transparent texel", which is not what
## supersampling does.** A dab of half-extent 0.4 covers
## less than one texel, and the texel beside it is a whole pixel from the
## centre: no amount of sampling puts paint there, and it should not. What
## supersampling buys is that the covered texel's alpha is the dab's real area
## rather than a yes or a no, so a stroke of sub-pixel dabs at sub-pixel offsets
## fades smoothly instead of snapping on and off. That snapping is the dashed
## look Krita's comment names, and this is it as two numbers.
func test_supersampling_makes_a_sub_pixel_dab_a_fraction_rather_than_a_switch() -> void:
    var on_centre := _paint(Vector2(0.4, 0.4), 0.0, Vector2.ONE, true)
    var half_over := _paint(Vector2(0.4, 0.4), 0.0, Vector2.ONE, true, CENTRE + Vector2(0.5, 0.0))
    var centre_alpha := _at(on_centre, 32, 32)
    assert_true(centre_alpha > 0.0, "A sub-pixel dab paints something, at %.4f" % centre_alpha)
    assert_true(centre_alpha < 1.0, "and it is a fraction rather than a full texel")
    assert_true(
        absf(_at(half_over, 32, 32) - centre_alpha) > 0.01,
        "and half a pixel of travel changes it, %.4f against %.4f" % [_at(half_over, 32, 32), centre_alpha]
    )


## The same dab with antialiasing off takes one sample at the texel centre, and
## that is the dashed look as two numbers: fully on when the dab sits on the
## texel and fully off half a pixel later, with nothing in between. This is the
## control the assertion above needs to mean anything.
func test_without_antialiasing_the_same_dab_is_a_switch() -> void:
    var on_centre := _paint(Vector2(0.4, 0.4), 0.0, Vector2.ONE, false)
    var half_over := _paint(Vector2(0.4, 0.4), 0.0, Vector2.ONE, false, CENTRE + Vector2(0.5, 0.0))
    assert_almost_eq(_at(on_centre, 32, 32), 1.0, 1e-4, "One sample at the centre reads the whole texel opaque")
    assert_almost_eq(_at(half_over, 32, 32), 0.0, 1e-4, "and half a pixel later reads it empty, which is the dash")


## Hard rule 2 dispatches over the box `SaDabGeometry` computes, so a texel the
## kernel would have painted outside it is paint that never lands. Eight
## rotations of a thin ellipse, which is the shape whose box moves the most.
func test_the_box_contains_every_texel_the_dab_paints() -> void:
    var half_extent := Vector2(18.0, 5.0)
    for radians: float in ROTATIONS:
        var alpha := _paint(half_extent, radians, Vector2.ONE)
        var box := SaDabGeometry.region(CENTRE, half_extent, radians)
        var outside := 0
        for y in SIDE:
            for x in SIDE:
                if _at(alpha, x, y) <= 0.0:
                    continue
                if not box.has_point(Vector2(x, y)):
                    outside += 1
        assert_eq(outside, 0, "at %.3f radians, %d painted texels fall outside the box" % [radians, outside])


## And the box is not simply the whole texture: a claim that it contains
## everything is worth nothing if it contains everything there is.
func test_the_box_is_tight_enough_to_be_worth_dispatching() -> void:
    var box := SaDabGeometry.region(CENTRE, Vector2(18.0, 5.0), 0.0)
    assert_true(box.size.x < 40.0, "the flat ellipse's box is %.1f wide" % box.size.x)
    assert_true(box.size.y < 14.0, "and %.1f tall, which is the minor axis and the fade pixel" % box.size.y)
    var turned := SaDabGeometry.region(CENTRE, Vector2(18.0, 5.0), PI / 2.0)
    assert_almost_eq(turned.size.x, box.size.y, 1e-4, "and a quarter turn swaps the two")
    assert_almost_eq(turned.size.y, box.size.x, 1e-4, "both ways round")


## Krita lies about a spiked dab's shape because the height of one is hard to
## predict, and an upper bound is safer than a wrong bound.
func test_a_spiked_dab_is_boxed_by_its_major_axis_on_both_sides() -> void:
    var plain := SaDabGeometry.half_box(Vector2(18.0, 5.0), 0.0, 2)
    var spiked := SaDabGeometry.half_box(Vector2(18.0, 5.0), 0.0, 5)
    assert_almost_eq(plain.y, 6.0, 1e-4, "Two spikes is the plain ellipse, so the minor axis and a pixel")
    assert_almost_eq(spiked.y, 19.0, 1e-4, "and more than two boxes by the major axis on both sides")
    assert_almost_eq(spiked.x, plain.x, 1e-4, "with the major axis unchanged")


## The push constant is the 128 bytes Vulkan guarantees, and a short array is a
## block of undefined tail on some drivers.
func test_the_push_constant_fills_its_block() -> void:
    var data := SaDabGeometry.pack(CENTRE, Vector2.ZERO, Color(1, 1, 1, 1), Vector2(10.0, 10.0), 0.0, Vector2.ONE, 1.0)
    assert_eq(data.size(), SaDabGeometry.PUSH_FLOATS, "Thirty-two floats")
    assert_eq(data.size() * 4, 128, "which is the 128 bytes the block declares")


## The four generators at one fade, which is a way of asking
## whether they are four things rather than one thing named four ways.
##
## The comparison is the whole radial profile rather than one pixel, because two
## falloffs can agree at any single distance and differ everywhere else. What
## follows the sweep is the distinguishing pixel, one per
## generator, so a future edit that flattens one of them fails on a number
## rather than on a difference.
func test_the_four_generators_paint_four_different_edges() -> void:
    var fade := Vector2(0.5, 0.5)
    var half := Vector2(16.0, 16.0)

    var default_tip := _tip(half, fade)
    var gauss_tip := _tip(half, fade)
    gauss_tip.generator = SaDabGeometry.Generator.GAUSS
    var soft_tip := _tip(half, fade)
    soft_tip.generator = SaDabGeometry.Generator.SOFT
    var rect_tip := _tip(half, fade)
    rect_tip.shape = SaBrushTipScript.Shape.RECTANGLE

    var profiles := {
        "default": _paint_tip(default_tip),
        "gauss": _paint_tip(gauss_tip),
        "soft": _paint_tip(soft_tip),
        "rectangle": _paint_tip(rect_tip),
    }
    var names: Array = profiles.keys()
    for i in names.size():
        for j in range(i + 1, names.size()):
            var biggest := 0.0
            for step in range(0, 17):
                var a: float = _at(profiles[names[i]], 32 + step, 32)
                var b: float = _at(profiles[names[j]], 32 + step, 32)
                biggest = maxf(biggest, absf(a - b))
            assert_true(biggest > 0.02, "%s and %s differ by only %.4f anywhere along the radius" % [names[i], names[j], biggest])

    # One distinguishing pixel each, all fourteen pixels out of sixteen, which
    # is where the four are furthest apart and still inside every one of them.
    # The bands are measured rather than derived, and they do not overlap, so
    # the four values are also in a strict order: default, rectangle, soft,
    # Gaussian, softest last.
    var bands := {
        "default": Vector2(0.27, 0.33),
        "rectangle": Vector2(0.20, 0.27),
        "soft": Vector2(0.10, 0.18),
        "gauss": Vector2(0.02, 0.10),
    }
    for name: String in bands:
        var here: float = _at(profiles[name], 46, 32)
        var band: Vector2 = bands[name]
        assert_true(
            here >= band.x and here <= band.y,
            "%s reads %.4f at fourteen out, outside its %.2f to %.2f band" % [name, here, band.x, band.y]
        )


## A rectangle tip paints a square, which is the claim about the
## shape rather than about the falloff.
func test_a_rectangle_tip_paints_a_square() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2.ONE)
    tip.shape = SaBrushTipScript.Shape.RECTANGLE
    var alpha := _paint_tip(tip)
    var box := _painted_box(alpha)
    assert_eq(box.size.x, box.size.y, "The painted box is square, %d by %d" % [box.size.x, box.size.y])
    # Twenty-three rather than the twenty-five a diameter of 24 suggests: the
    # outermost ring on each side is exactly on the edge, where the fade norm
    # takes the coverage to zero, so the painted box is the diameter less its
    # two edge texels.
    assert_true(box.size.x >= 22, "and it is the diameter less its edge ring, at %d" % box.size.x)
    # The corner is what separates a square from a disc: a circle of the same
    # half-extents paints nothing there at all.
    assert_almost_eq(_at(alpha, 32 + 11, 32 + 11), 1.0, 1e-3, "with an opaque corner")
    var round_alpha := _paint(Vector2(12.0, 12.0), 0.0, Vector2.ONE)
    assert_almost_eq(_at(round_alpha, 32 + 11, 32 + 11), 0.0, 1e-4, "where the circle has nothing")


## Spikes fold the angle into one wedge, so five of them paint five petals. The
## claim is about the bounding box, and the petal count is asserted
## beside it because a box of the full diameter is also what a disc has.
func test_five_spikes_paint_five_petals_across_the_full_diameter() -> void:
    var tip := _tip(Vector2(20.0, 6.0), Vector2.ONE)
    tip.spikes = 5
    var alpha := _paint_tip(tip)
    var box := _painted_box(alpha)
    assert_true(box.size.x >= 36, "The spiked box is the major axis across, at %d" % box.size.x)
    assert_true(box.size.y >= 36, "and the same the other way, at %d, which the plain ellipse is not" % box.size.y)

    # Five petals means the coverage at a fixed radius rises and falls five
    # times round the circle. Counted as runs of paint rather than as peaks,
    # because a run survives the antialiasing the peaks sit inside.
    var radius := 15.0
    var samples := 360
    var runs := 0
    var was_painted := false
    var first_painted := false
    for i in samples:
        var angle := TAU * float(i) / float(samples)
        var x := int(round(32.0 + radius * cos(angle)))
        var y := int(round(32.0 + radius * sin(angle)))
        var painted := _at(alpha, x, y) > 0.5
        if i == 0:
            first_painted = painted
        if painted and not was_painted:
            runs += 1
        was_painted = painted
    # The sweep starts inside a petal, so its first and last runs are one run
    # wrapped round the seam.
    if first_painted and was_painted:
        runs -= 1
    assert_eq(runs, 5, "Five petals at a radius of 15, counted %d" % runs)

    var plain := _paint(Vector2(20.0, 6.0), 0.0, Vector2.ONE)
    assert_true(_painted_box(plain).size.y < 16, "while two spikes stays the flat ellipse it always was")


## The soft generator reads the tip's curve and nothing else, so a flat curve is
## a hard disc and a descending one is a fade. This is the assertion that fails
## when the table is uploaded in the wrong order or indexed by radius rather
## than by its square.
func test_the_soft_generator_paints_the_curve_it_is_given() -> void:
    var flat := _tip(Vector2(16.0, 16.0), Vector2.ONE)
    flat.generator = SaDabGeometry.Generator.SOFT
    flat.softness_curve = Curve.new()
    flat.softness_curve.add_point(Vector2(0.0, 1.0))
    flat.softness_curve.add_point(Vector2(1.0, 1.0))
    var flat_alpha := _paint_tip(flat)
    assert_almost_eq(_at(flat_alpha, 32, 32), 1.0, 1e-3, "A curve that never falls is a hard disc at the centre")
    assert_almost_eq(_at(flat_alpha, 42, 32), 1.0, 1e-3, "and ten pixels out")
    assert_almost_eq(_at(flat_alpha, 50, 32), 0.0, 1e-4, "with nothing past the radius")

    var falling := _tip(Vector2(16.0, 16.0), Vector2.ONE)
    falling.generator = SaDabGeometry.Generator.SOFT
    var falling_alpha := _paint_tip(falling)
    assert_almost_eq(_at(falling_alpha, 32, 32), 1.0, 1e-3, "The default curve is opaque at the centre")
    var previous := 1.1
    for step in range(0, 16):
        var here := _at(falling_alpha, 32 + step, 32)
        assert_true(here <= previous + 1e-3, "and never rises again, but did at %d pixels out" % step)
        previous = here
    # The falloff is the curve read against the *squared* radius, so ten pixels
    # of sixteen is a squared radius of 0.39 and the linear default reads 0.61
    # there rather than the 0.38 a curve read against the radius would give.
    # That square is the assertion: an index by radius would pass a monotonic
    # check and fail this one.
    assert_true(_at(falling_alpha, 42, 32) < 0.75, "at ten out it is under three quarters")
    assert_true(_at(falling_alpha, 42, 32) > 0.55, "and above half, which is the squared radius rather than the radius")


## Softness multiplies the fade, so a softness under one is a softer edge. The
## direction is the assertion: the table says the slot arrives divided by
## softness, and dividing would have sharpened it.
func test_softness_softens_rather_than_sharpens() -> void:
    var full := _tip(Vector2(16.0, 16.0), Vector2.ONE)
    var half := _tip(Vector2(16.0, 16.0), Vector2.ONE)
    half.softness = 0.5
    var full_alpha := _paint_tip(full)
    var half_alpha := _paint_tip(half)
    assert_almost_eq(_at(full_alpha, 42, 32), 1.0, 1e-3, "A softness of one is the hard edge Hardness asked for")
    assert_true(
        _at(half_alpha, 42, 32) < _at(full_alpha, 42, 32) - 0.05,
        "and half of it reads %.4f against %.4f at the same texel" % [_at(half_alpha, 42, 32), _at(full_alpha, 42, 32)]
    )


## Density drops texels and randomness thins the ones that stay, both from a
## hash of the texel rather than from a random source a kernel does not have.
func test_density_thins_the_dab_and_randomness_varies_what_is_left() -> void:
    var solid := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    var sparse := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    sparse.density = 0.5
    var noisy := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    noisy.randomness = 0.8

    var solid_alpha := _paint_tip(solid)
    var sparse_alpha := _paint_tip(sparse)
    var noisy_alpha := _paint_tip(noisy)

    var solid_count := 0
    var sparse_count := 0
    var solid_full := 0
    var noisy_full := 0
    for y in SIDE:
        for x in SIDE:
            if _at(solid_alpha, x, y) > 0.0:
                solid_count += 1
            if _at(sparse_alpha, x, y) > 0.0:
                sparse_count += 1
            if _at(solid_alpha, x, y) > 0.99:
                solid_full += 1
            if _at(noisy_alpha, x, y) > 0.99:
                noisy_full += 1
    assert_true(sparse_count > 0, "Half density still paints something, %d texels" % sparse_count)
    assert_true(sparse_count < solid_count * 0.75, "and well under the solid dab's %d, at %d" % [solid_count, sparse_count])
    assert_true(noisy_full < solid_full * 0.5, "Randomness leaves %d fully opaque of %d" % [noisy_full, solid_full])


## How many texels of a dab are neither clear nor fully opaque, which is what
## sharpness is measured in: a pen has none and a brush has a ring of them.
static func _partial(alpha: PackedFloat32Array) -> int:
    var count := 0
    for value: float in alpha:
        if value > 1e-4 and value < 1.0 - 1e-4:
            count += 1
    return count


## Sharpness at one is a pen: every texel opaque or clear, and not one in
## between. That is the whole claim, and it is a count rather than a picture.
func test_full_sharpness_leaves_no_partial_texel() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var soft := _paint_tip(tip)
    var pen := _paint_tip(tip, 0.0, CENTRE, 1.0)

    assert_true(_partial(soft) > 40, "The unsharpened dab has %d partial texels" % _partial(soft))
    assert_eq(_partial(pen), 0, "and at full sharpness it has none")
    assert_almost_eq(_at(pen, 32, 32), 1.0, 1e-4, "with the centre still opaque")
    assert_almost_eq(_at(pen, 50, 32), 0.0, 1e-4, "and nothing outside the radius")


## Sharpness at zero is exactly what the brush painted without it, texel for
## texel. A control that does nothing at its default is the only way a painter's
## existing brushes are safe from it.
func test_no_sharpness_paints_what_the_kernel_painted_before() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var without := _paint_tip(tip)
    var zero := _paint_tip(tip, 0.0, CENTRE, 0.0, 0.5)
    var biggest := 0.0
    for i in without.size():
        biggest = maxf(biggest, absf(without[i] - zero[i]))
    assert_true(biggest < 1e-6, "Not one texel differs, the worst by %.9f" % biggest)


## Half sharpness pulls the centre half way onto the grid, which is the position
## half rather than the threshold half. Asserted on `SaDabGeometry` rather than
## on texels, because a centre is a number and a dab is a picture of one.
func test_half_sharpness_puts_the_centre_on_a_half_pixel() -> void:
    var off_grid := Vector2(32.4, 32.4)
    assert_eq(SaDabGeometry.snap_to_pixels(off_grid, 0.0), off_grid, "No sharpness leaves the centre alone")
    assert_eq(SaDabGeometry.snap_to_pixels(off_grid, 1.0), Vector2(32.0, 32.0), "and full sharpness rounds it")
    var half := SaDabGeometry.snap_to_pixels(off_grid, 0.5)
    assert_almost_eq(half.x, 32.2, 1e-5, "Half way is half way between the two")
    assert_almost_eq(half.y, 32.2, 1e-5, "on both axes")
    # The blend is Krita's `sharpness * round(pt) + (1 - sharpness) * pt`, which
    # is not the same as rounding to a half pixel: a centre already on the grid
    # stays there at every sharpness.
    assert_eq(SaDabGeometry.snap_to_pixels(Vector2(32.0, 32.0), 0.5), Vector2(32.0, 32.0), "and a whole pixel stays")


## The softness widens the band of coverage the cut leaves alone. It does not
## move the hard edge, which is the assertion that separates the two: the count
## of fully opaque texels is the same and the count of partial ones is not.
##
## **At a sharpness of one rather than a half.** Krita cuts at `1 - sharpness`,
## so a softness of zero was a hard cut wherever that landed and a half left
## nothing partial. Landing wherever the dial says is also what grew the painted
## disc by 42 percent across it while the Size row never moved, so Sara's cut is
## fixed at the tip's half-coverage contour and the dial closes a band round it
## instead. A half is now half closed, which is partial by construction. One is
## where a hard cut is, and the softness band is still the only thing between
## hard and soft there.
func test_sharpness_softness_widens_the_band_without_moving_the_hard_edge() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var hard := _paint_tip(tip, 0.0, CENTRE, 1.0, 0.0)
    var soft := _paint_tip(tip, 0.0, CENTRE, 1.0, 0.9)

    assert_eq(_partial(hard), 0, "A cut with no softness leaves nothing partial")
    assert_true(_partial(soft) > 0, "and one with softness leaves %d texels partial" % _partial(soft))

    var hard_solid := 0
    var soft_solid := 0
    for i in hard.size():
        if hard[i] >= 1.0 - 1e-4:
            hard_solid += 1
        if soft[i] >= 1.0 - 1e-4:
            soft_solid += 1
    assert_eq(hard_solid, soft_solid, "with the same %d texels fully opaque either way" % hard_solid)


## The three counts, in one place, so a regression in the
## threshold is one number rather than three tests.
func test_the_partial_count_falls_as_sharpness_rises() -> void:
    var tip := _tip(Vector2(12.0, 12.0), Vector2(0.4, 0.4))
    var none := _partial(_paint_tip(tip, 0.0, CENTRE, 0.0))
    var half := _partial(_paint_tip(tip, 0.0, CENTRE, 0.5))
    var full := _partial(_paint_tip(tip, 0.0, CENTRE, 1.0))
    assert_true(none > 0, "No sharpness leaves %d partial texels" % none)
    # Krita's cut is hard at every sharpness when the softness is zero. Sara
    # fixes the cut at the tip's own half-coverage contour and makes the dial the width of the band round
    # it, so a half is a
    # band half closed and the count falls to nothing only at one.
    assert_true(half > 0 and half < none, "half leaves %d of the %d, part of the way to the pen" % [half, none])
    assert_eq(full, 0, "and full cuts them all")
    # What half and full differ in is how much is opaque, not how much is partial:
    # the band closes on the contour from both sides, so a higher sharpness turns
    # more of the ramp into solid paint.
    var half_solid := 0
    var full_solid := 0
    for value: float in _paint_tip(tip, 0.0, CENTRE, 0.5):
        if value >= 1.0 - 1e-4:
            half_solid += 1
    for value: float in _paint_tip(tip, 0.0, CENTRE, 1.0):
        if value >= 1.0 - 1e-4:
            full_solid += 1
    assert_true(full_solid > half_solid, "Full sharpness keeps %d texels solid where half keeps %d" % [full_solid, half_solid])


## The mirror flips the tip inside its own rectangle, and a spiked tip is the
## only procedural shape it can be seen on.
##
## **Every generator here is symmetric about both its own axes**, because they
## square the coordinate or take its absolute value the way Krita's do, so a
## mirror of a plain ellipse is the ellipse. The spike fold is not symmetric in
## x, so a spiked tip is what the reflection assertion has to be made on, and
## that is the asymmetric tip.
func test_a_mirrored_spiked_dab_is_the_reflection_of_the_plain_one() -> void:
    var plain := _tip(Vector2(18.0, 6.0), Vector2.ONE)
    plain.spikes = 5
    var flipped := _tip(Vector2(18.0, 6.0), Vector2.ONE)
    flipped.spikes = 5
    flipped.mirror_horizontal = true

    var a := _paint_tip(plain)
    var b := _paint_tip(flipped)
    var worst := 0.0
    var moved := 0
    for y in SIDE:
        for x in SIDE:
            # The centre is on a texel corner, so the reflection of column
            # `32 + d` is column `32 - d`.
            var here := _at(b, x, y)
            worst = maxf(worst, absf(here - _at(a, 64 - x, y)))
            if absf(_at(a, x, y) - here) > 0.2:
                moved += 1
    assert_true(worst < 0.05, "The mirrored dab is the reflection to %.4f" % worst)
    assert_true(moved > 20, "and it is not simply the same dab, %d texels moved" % moved)


## A plain tip is symmetric about both axes already, so mirroring it changes
## nothing. That is the control the assertion above needs, and a finding in its own right.
func test_mirroring_a_plain_tip_changes_nothing() -> void:
    var tip := _tip(Vector2(18.0, 6.0), Vector2(0.5, 0.5))
    var mirrored := _tip(Vector2(18.0, 6.0), Vector2(0.5, 0.5))
    mirrored.mirror_horizontal = true
    mirrored.mirror_vertical = true

    var a := _paint_tip(tip)
    var b := _paint_tip(mirrored)
    var worst := 0.0
    for i in a.size():
        worst = maxf(worst, absf(a[i] - b[i]))
    assert_true(worst < 1e-6, "Not one texel differs, the worst by %.9f" % worst)


## One flipped axis turns the frame left-handed, so an angle measured in it runs
## the other way. Asserted on the tip rather than on texels, because the
## negation is the tool's and the kernel never sees the sign.
func test_one_mirror_flips_the_handedness_and_two_do_not() -> void:
    var tip := _tip(Vector2(10.0, 10.0), Vector2.ONE)
    assert_false(tip.mirror_flips_handedness(), "No mirror keeps the frame right-handed")
    assert_eq(tip.mirror_bits(), 0, "and sends no bits")
    tip.mirror_horizontal = true
    assert_true(tip.mirror_flips_handedness(), "One mirror flips it")
    assert_eq(tip.mirror_bits(), 1, "as bit zero")
    tip.mirror_vertical = true
    assert_false(tip.mirror_flips_handedness(), "Two are a half turn and flip it back")
    assert_eq(tip.mirror_bits(), 3, "as both bits")
    tip.mirror_horizontal = false
    assert_true(tip.mirror_flips_handedness(), "and the other one alone flips it too")
    assert_eq(tip.mirror_bits(), 2, "as bit one")


## Density drops texels and the same seed drops the same ones, which is what
## makes a spatter reproducible rather than a different brush every frame.
func test_density_drops_half_the_texels_and_the_same_half_on_a_repeat() -> void:
    var solid := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    var sparse := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    sparse.density = 0.5

    var full := _paint_tip(solid)
    var half := _paint_tip(sparse, 0.0, CENTRE, 0.0, 0.0, 7.0)
    var again := _paint_tip(sparse, 0.0, CENTRE, 0.0, 0.0, 7.0)

    var full_count := 0
    var half_count := 0
    for i in full.size():
        if full[i] > 0.0:
            full_count += 1
        if half[i] > 0.0:
            half_count += 1
    var share := float(half_count) / float(full_count)
    assert_true(share > 0.35 and share < 0.65, "Half density leaves %.2f of the texels" % share)
    var worst := 0.0
    for i in half.size():
        worst = maxf(worst, absf(again[i] - half[i]))
    assert_true(worst < 1e-6, "and the same seed leaves the same ones, worst %.9f" % worst)


## The seed advances per dab, so two dabs in the same place are not the same
## dab. Without it a spatter is a stencil: every dab of a stroke drops exactly
## the same texels and the stroke is one hole-punched shape repeated.
func test_a_different_seed_drops_a_different_half() -> void:
    var sparse := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    sparse.density = 0.5
    var first := _paint_tip(sparse, 0.0, CENTRE, 0.0, 0.0, 1.0)
    var second := _paint_tip(sparse, 0.0, CENTRE, 0.0, 0.0, 2.0)
    var differ := 0
    for i in first.size():
        if absf(first[i] - second[i]) > 1e-4:
            differ += 1
    assert_true(differ > 50, "Two seeds differ on %d texels" % differ)


## Randomness is Krita's `(1 - randomness) + randomness * hash` on the alpha, so
## at 1.0 the alphas spread over the whole range rather than sitting on one
## value, and at 0.0 nothing moves.
func test_randomness_spreads_the_alphas_rather_than_scaling_them() -> void:
    var even := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    var noisy := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    noisy.randomness = 1.0

    var flat := _paint_tip(even)
    var spread := _paint_tip(noisy, 0.0, CENTRE, 0.0, 0.0, 3.0)

    var buckets := {}
    var solid := 0
    for i in flat.size():
        if flat[i] < 1.0 - 1e-4:
            continue
        solid += 1
        buckets[int(spread[i] * 8.0)] = true
    assert_true(solid > 100, "The even dab has %d fully opaque texels" % solid)
    assert_true(buckets.size() >= 7, "and randomness spreads them over %d of eight bands" % buckets.size())

    var none := _tip(Vector2(14.0, 14.0), Vector2.ONE)
    none.randomness = 0.0
    var unchanged := _paint_tip(none, 0.0, CENTRE, 0.0, 0.0, 3.0)
    var worst := 0.0
    for i in flat.size():
        worst = maxf(worst, absf(flat[i] - unchanged[i]))
    assert_true(worst < 1e-6, "and a randomness of nothing changes nothing, worst %.9f" % worst)


## Two dabs into one texture in the mode the caller names, and the alpha they
## leave where they overlap and where only the first of them landed.
##
## The two dabs are a diameter apart on x, so the left of the first and the right
## of the second are painted once and the middle band is painted twice. That is
## a stroke crossing itself, said in two dispatches rather than in a drag.
func _cross(mode: int, dab_alpha: float) -> Array:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

    var tip := _tip(Vector2(12.0, 12.0), Vector2.ONE)
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image(tip.image_path if tip.uses_image() else "")
    compute.set_buffer(StateBrushScript.SOFTNESS_BINDING, mask.softness_for(tip).rid)
    compute.set_sampled_texture(StateBrushScript.TIP_IMAGE_BINDING, mask.sampler_rid())
    compute.set_sampled_texture(StateBrushScript.PATTERN_BINDING, SaBrushTipMask.stand_in().rid)
    compute.set_buffer(SaStampBindings.MASKING_BINDING, SaStampBindings.of(mask).masking_for(null, tip.diameter).rid)
    SaSmudgeReservoir.bind(compute, null)
    compute.set_texture(StateBrushScript.HEIGHT_BINDING, SaStrokeHeights.held(null).rid)
    compute.set_sampled_texture(SaStampBindings.RAMP_BINDING, SaBrushTipMask.stand_in().rid)

    for centre: Vector2 in [Vector2(24.0, 32.0), Vector2(40.0, 32.0)]:
        compute.set_push_constant_float_array(
            SaDabPacking.pack_dab_params(
                centre,
                Vector2.ZERO,
                Color(1, 1, 1, dab_alpha),
                tip.half_extent(),
                0.0,
                tip.effective_fade(),
                1.0,
                mode,
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
    # The crossing, and a texel only the first dab reached.
    return [_at(out, 32, 32), _at(out, 16, 32)]


## Wash reaches the opacity it was set to and stops, so the crossing is the same
## alpha as the single pass. That is the whole point of the mode and it is two
## numbers.
func test_wash_does_not_darken_where_a_stroke_crosses_itself() -> void:
    var readings := _cross(SaDabGeometry.PaintMode.ALPHA_DARKEN, 0.5)
    assert_almost_eq(readings[0], 0.5, 1e-3, "The crossing is the opacity it was set to")
    assert_almost_eq(readings[1], 0.5, 1e-3, "and so is a single pass")


## Build-up accumulates, so the crossing is measurably darker. Krita's `over`,
## which is what the brush has always done, and the number it produces is
## `a + a * (1 - a)`.
func test_build_up_darkens_where_a_stroke_crosses_itself() -> void:
    var readings := _cross(SaDabGeometry.PaintMode.OVER, 0.5)
    assert_almost_eq(readings[0], 0.75, 1e-3, "Two passes at a half is three quarters")
    assert_almost_eq(readings[1], 0.5, 1e-3, "and a single pass is still a half")
    assert_true(readings[0] > readings[1] + 0.2, "which is measurably darker")


## The colour a wash dab lands is its own, not a weighted average with what is
## under it. That is the second half of alpha darken and the half that reads as
## a bug until the numerator is written out.
func test_wash_lands_its_own_colour_over_a_darker_one() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0.0, 0.0, 0.0, 1.0), 0, 1, 0, 1)

    var tip := _tip(Vector2(12.0, 12.0), Vector2.ONE)
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaBrushTipMask.load_image(tip.image_path if tip.uses_image() else "")
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
            Color(1, 1, 1, 1.0),
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.ALPHA_DARKEN,
            false,
            tip
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)

    var data: PackedByteArray = rd.texture_get_data(canvas.rid, 0)
    var index := (32 * SIDE + 32) * 16
    assert_almost_eq(data.decode_float(index), 1.0, 1e-3, "A full dab lands white over black")
    assert_almost_eq(data.decode_float(index + 12), 1.0, 1e-3, "at the alpha it asked for")
