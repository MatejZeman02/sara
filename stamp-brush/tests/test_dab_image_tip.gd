## The image tip, stamped and read back.
##
## A sibling of `test_dab_shader.gd` rather than more of it, because the image
## tip is a whole generator with a loader behind it. The cut is by subject:
## everything here needs a file on disk, and nothing there does.
##
## It inherits the parent suite's helpers rather than repeating them, which is
## what makes `_paint_tip` one implementation: a second copy of the binding set
## would be a second thing to fix the day the kernel declares a sixth binding.
extends "res://modules/sara-base-modules/stamp-brush/tests/test_dab_shader.gd"

## A generated PNG tip, written to the sandboxed `user://` so a run neither reads
## nor writes anything a painter owns.
##
## An L shape rather than a blob, because it is asymmetric on both axes: a
## picture that is symmetric proves nothing about the mapping, the rotation or
## the mirror, which is the lesson the procedural generators taught.
static var scratch_tip_path: String = SaDataRoot.path("test_b11_tip.png")
const TIP_SIDE: int = 32

## A second generated tip, opaque edge to edge, for the Hardness rows below. The
## L proves the mapping and proves nothing about a falloff, because most of its
## own rectangle is already clear: a square is the only picture whose corners
## are its own to lose.
static var scratch_square_path: String = SaDataRoot.path("test_b2_square_tip.png")


func _write_tip() -> String:
    var image := Image.create(TIP_SIDE, TIP_SIDE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))
    # The upright of the L, on the left, and its foot along the bottom.
    for y in range(4, TIP_SIDE - 4):
        for x in range(4, 12):
            image.set_pixel(x, y, Color(0, 0, 0, 1))
    for x in range(4, TIP_SIDE - 8):
        for y in range(TIP_SIDE - 12, TIP_SIDE - 4):
            image.set_pixel(x, y, Color(0, 0, 0, 1))
    image.save_png(scratch_tip_path)
    return scratch_tip_path


## The generator and the path, and deliberately **not** `kind`: that is exactly
## what the Tip row and a scenario write, so a suite that also set `kind` would
## pass over the bug where the two fields disagree.
func _image_tip(half_extent: Vector2) -> Resource:
    var tip := _tip(half_extent, Vector2.ONE)
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = _write_tip()
    return tip


func _write_square_tip() -> String:
    var image := Image.create(TIP_SIDE, TIP_SIDE, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 1))
    image.save_png(scratch_square_path)
    return scratch_square_path


## A square image tip at *hardness*, which is what the kernel calls a fade.
func _square_tip(half_extent: Vector2, hardness: float) -> Resource:
    var tip := _tip(half_extent, Vector2(hardness, hardness))
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = _write_square_tip()
    return tip


func after_each() -> void:
    for path: String in [scratch_tip_path, scratch_square_path, scratch_lightness_tip_path]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The image tip paints its own shape rather than a disc, which is the whole
## claim and is a count of texels in two places rather than a picture.
func test_an_image_tip_paints_its_own_shape() -> void:
    var alpha := _paint_tip(_image_tip(Vector2(12.0, 12.0)))
    # The L's upright is on the left of the tip and its corner is bottom right,
    # which the map puts left of and below the dab centre.
    assert_true(_at(alpha, 32 - 8, 32) > 0.5, "The upright is painted")
    assert_true(_at(alpha, 32 + 6, 32 - 6) < 0.5, "the top right of the L is not")
    assert_true(_at(alpha, 32 + 4, 32 + 7) > 0.5, "and the foot is")

    var procedural := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2.ONE))
    assert_true(_at(procedural, 32 + 6, 32 - 6) > 0.5, "where a disc of the same size covers that corner")


## One texture at two sizes is two sizes of one shape. The count of painted
## texels goes as the area, which is what says the sampler is doing the scaling
## rather than the loader.
func test_one_texture_paints_two_sizes_of_one_shape() -> void:
    var small := _paint_tip(_image_tip(Vector2(6.0, 6.0)))
    var large := _paint_tip(_image_tip(Vector2(12.0, 12.0)))
    var small_count := 0
    var large_count := 0
    for i in small.size():
        if small[i] > 0.5:
            small_count += 1
        if large[i] > 0.5:
            large_count += 1
    assert_true(small_count > 20, "The small stamp paints %d texels" % small_count)
    var ratio := float(large_count) / float(small_count)
    assert_true(ratio > 3.0 and ratio < 5.0, "and the large one about four times as many, at %.2f" % ratio)


## A quarter turn turns the picture, which is the assertion that catches a
## sample coordinate built before the rotation rather than after it.
func test_an_image_tip_turns_with_the_dab() -> void:
    var flat := _paint_tip(_image_tip(Vector2(12.0, 12.0)))
    var turned := _paint_tip(_image_tip(Vector2(12.0, 12.0)), PI / 2.0)
    var worst := 0.0
    var moved := 0
    for y in SIDE:
        for x in SIDE:
            var here := _at(turned, x, y)
            # A quarter turn maps (dx, dy) to (dy, -dx) about the centre.
            var dx := x - 32
            var dy := y - 32
            worst = maxf(worst, absf(here - _at(flat, 32 + dy, 32 - dx)))
            if absf(_at(flat, x, y) - here) > 0.5:
                moved += 1
    assert_true(worst < 0.35, "The turned stamp is the flat one rotated, worst %.3f" % worst)
    assert_true(moved > 50, "and it is not the same picture, %d texels moved" % moved)


## The ratio squashes an image tip the way it squashes a procedural one, because
## the map divides by the half-extents rather than by one number.
func test_an_image_tip_squashes_with_the_ratio() -> void:
    var round_tip := _image_tip(Vector2(12.0, 12.0))
    var flat_tip := _image_tip(Vector2(12.0, 12.0))
    flat_tip.ratio = 0.4
    var round_box := _painted_box(_paint_tip(round_tip))
    var flat_box := _painted_box(_paint_tip(flat_tip))
    assert_true(
        flat_box.size.y < round_box.size.y * 0.6, "The squashed stamp is %d tall against %d" % [flat_box.size.y, round_box.size.y]
    )
    assert_eq(flat_box.size.x, round_box.size.x, "and the same width")


## A mirrored image tip is the reflection of the plain one. **This is the tip a
## mirror can be seen on**, which could only be said of a spiked one before: a
## picture is not symmetric about its own axes and every procedural generator is.
func test_a_mirrored_image_tip_is_the_reflection_of_the_plain_one() -> void:
    var plain := _image_tip(Vector2(12.0, 12.0))
    var flipped := _image_tip(Vector2(12.0, 12.0))
    flipped.mirror_horizontal = true
    var a := _paint_tip(plain)
    var b := _paint_tip(flipped)
    var worst := 0.0
    var moved := 0
    for y in SIDE:
        for x in SIDE:
            var here := _at(b, x, y)
            worst = maxf(worst, absf(here - _at(a, 64 - x, y)))
            if absf(_at(a, x, y) - here) > 0.5:
                moved += 1
    assert_true(worst < 0.35, "The mirrored stamp is the reflection, worst %.3f" % worst)
    assert_true(moved > 50, "and it is not the same picture, %d texels moved" % moved)


## Switching back to a procedural generator paints what it painted before the
## image, texel for texel. An image tip that leaves anything behind is a brush
## a painter cannot get out of.
func test_switching_back_to_a_procedural_generator_paints_what_it_did() -> void:
    var before := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2(0.5, 0.5)))
    _paint_tip(_image_tip(Vector2(12.0, 12.0)))
    var after := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2(0.5, 0.5)))
    var worst := 0.0
    for i in before.size():
        worst = maxf(worst, absf(before[i] - after[i]))
    assert_true(worst < 1e-6, "Not one texel differs, the worst by %.9f" % worst)


## The mask holds the texture, which is the whole reason the class exists: an
## `SaTexture` bound and then dropped is freed before the dispatch and the
## dispatch reports an invalid binding.
func test_the_mask_holds_what_it_bound() -> void:
    var mask := SaBrushTipMask.load_image(_write_tip())
    assert_true(mask.has_image(), "The tip loaded")
    assert_eq(mask.size, Vector2i(TIP_SIDE, TIP_SIDE), "at its own resolution")
    assert_true(mask.sampler_rid().is_valid(), "and the rid it binds is valid")
    assert_true(mask.error.is_empty(), "with nothing to report")

    var procedural := SaBrushTipMask.load_image("")
    assert_false(procedural.has_image(), "A procedural tip has no image")
    assert_true(procedural.sampler_rid().is_valid(), "and binds the stand-in rather than nothing")
    assert_true(procedural.error.is_empty(), "which is not an error")

    var missing := SaBrushTipMask.load_image(SaDataRoot.path("there_is_no_such_tip.png"))
    assert_false(missing.has_image(), "A path that is not a tip loads nothing")
    assert_false(missing.error.is_empty(), "and says why: %s" % missing.error)


## Image with no picture behind it is the procedural tip, not a solid square.
##
## **This is the bug the scenario caught and no unit test would have.** Every
## test above set the generator and the path together, and the Tip row sets the
## generator on its own: the kernel then took the IMAGE branch, sampled the
## stand-in and painted the whole of the dab's box, so three sizes of an L came
## out as three black squares.
func test_the_image_generator_with_no_picture_paints_the_procedural_tip() -> void:
    var empty := _tip(Vector2(12.0, 12.0), Vector2.ONE)
    empty.generator = SaDabGeometry.Generator.IMAGE
    assert_false(empty.uses_image(), "Image with no path does not sample a picture")
    assert_eq(empty.effective_generator(), SaDabGeometry.Generator.DEFAULT, "and the kernel is pushed the default falloff")

    var alpha := _paint_tip(empty)
    var procedural := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2.ONE))
    var worst := 0.0
    for i in alpha.size():
        worst = maxf(worst, absf(alpha[i] - procedural[i]))
    assert_true(worst < 1e-6, "and paints exactly what the procedural tip paints, worst %.9f" % worst)
    # The corner of the box, which a stand-in would fill.
    assert_true(_at(alpha, 32 + 11, 32 + 11) < 0.5, "The corner of the dab's box is clear rather than solid")


## A path that is not a tip paints nothing rather than a square, and says why.
##
## The refusal already existed, but the white stand-in behind it meant a failed
## load painted the whole box: the message said the file was wrong while the
## canvas showed a solid block. A clear stand-in is what makes the two agree.
func test_a_tip_that_could_not_be_loaded_paints_nothing() -> void:
    var broken := _tip(Vector2(12.0, 12.0), Vector2.ONE)
    broken.generator = SaDabGeometry.Generator.IMAGE
    broken.image_path = SaDataRoot.path("there_is_no_such_tip.png")
    assert_true(broken.uses_image(), "A path that is set is a picture as far as the tip is concerned")

    var alpha := _paint_tip(broken)
    var painted := 0
    for i in alpha.size():
        if alpha[i] > 0.01:
            painted += 1
    assert_eq(painted, 0, "and a picture that would not load covers no texel at all")


## The tool's binding names and the mask's are the same three numbers.
##
## They are written out in both files rather than read from one, because a
## `const` on `StateBrush` whose initializer names `SaBrushTipMask` is resolved
## before the class cache holds it and takes the whole engine down with
## `Nonexistent function 'new' in base 'GDScript'`. This is what keeps them in
## step instead.
func test_the_binding_numbers_agree_with_the_mask() -> void:
    assert_eq(StateBrushScript.SOFTNESS_BINDING, SaBrushTipMask.SOFTNESS_BINDING, "The softness table")
    assert_eq(StateBrushScript.TIP_IMAGE_BINDING, SaBrushTipMask.TIP_IMAGE_BINDING, "the image tip sampler")
    assert_eq(StateBrushScript.PATTERN_BINDING, SaStampBindings.PATTERN_BINDING, "the reserved pattern slot")
    assert_eq(StateBrushScript.HEIGHT_BINDING, SaStampBindings.HEIGHT_BINDING, "and the paint's height")


## The ellipse Hardness softens an image tip along reaches the corners of the
## picture's own rectangle, which is the arithmetic behind every row below.
##
## A squared norm of exactly one at the corner is what makes full hardness paint
## the picture unchanged: `sa_circle_coverage` refuses above one and returns full
## coverage at one, so the whole rectangle is core at a fade of one.
func test_the_hardness_ellipse_reaches_the_pictures_corners() -> void:
    var half := Vector2(12.0, 12.0)
    var radius := SaDabGeometry.falloff_radius(half)
    var corner := Vector2(half.x / radius.x, half.y / radius.y)
    assert_almost_eq(corner.dot(corner), 1.0, 1e-6, "The corner of a square tip sits exactly on the ellipse")

    var squashed := SaDabGeometry.falloff_radius(Vector2(12.0, 4.8))
    assert_almost_eq(squashed.y / squashed.x, 0.4, 1e-6, "and a squashed tip keeps its own proportions")

    var packed := SaDabGeometry.pack(Vector2.ZERO, Vector2.ZERO, Color(1, 1, 1, 1), half, 0.0, Vector2.ONE, 1.0)
    assert_almost_eq(packed[27], radius.x, 1e-4, "and the pair goes to the kernel in the two slots after mirror")
    assert_almost_eq(packed[28], radius.y, 1e-4, "the second of them the minor radius")


## Full hardness paints the picture unchanged, corners included, which is the
## clause that a naive inscribed ellipse would break.
func test_a_square_image_tip_at_full_hardness_keeps_its_corners() -> void:
    var alpha := _paint_tip(_square_tip(Vector2(12.0, 12.0), 1.0))
    var centre := _at(alpha, 32, 32)
    assert_almost_eq(centre, 1.0, 1e-4, "The centre of a solid square tip is opaque")
    for corner: Vector2i in [Vector2i(-10, -10), Vector2i(10, -10), Vector2i(-10, 10), Vector2i(10, 10)]:
        var here := _at(alpha, 32 + corner.x, 32 + corner.y)
        assert_almost_eq(here, 1.0, 1e-4, "and so is the corner at %s" % corner)


## Lowering Hardness softens the picture along its own outline, the corners
## first, and leaves the centre where it was.
func test_a_square_image_tip_softens_from_its_corners() -> void:
    var soft := _paint_tip(_square_tip(Vector2(12.0, 12.0), 0.2))
    assert_almost_eq(_at(soft, 32, 32), 1.0, 1e-3, "The centre is untouched by Hardness")
    # Ten texels out on each axis of a 12 by 12 rectangle, so the corner sits at
    # a squared norm of 0.69 on the ellipse and the edge midpoint at 0.35, and
    # the falloff reads 0.32 and 0.68 there. Both are the picture's own 1.0
    # before Hardness touches it.
    var corner := _at(soft, 32 + 10, 32 + 10)
    var edge := _at(soft, 32 + 10, 32)
    assert_true(corner < 0.4, "The corner is softened to %.3f from the picture's own 1.0" % corner)
    assert_true(edge > corner + 0.3, "and the middle of the edge, nearer the centre, is %.3f" % edge)
    assert_true(edge < 0.8, "which is itself well below the picture's own coverage")


## The falloff is fitted to the picture's rectangle rather than to a circle, so a
## squashed tip softens the same amount at the end of each axis.
func test_the_falloff_follows_a_squashed_tips_own_outline() -> void:
    var tip := _square_tip(Vector2(12.0, 12.0), 0.5)
    tip.ratio = 0.4
    var alpha := _paint_tip(tip)
    # Nine tenths of the way out along each axis of a 12 by 4.8 rectangle.
    var along_x := _at(alpha, 32 + 10, 32)
    var along_y := _at(alpha, 32, 32 + 4)
    assert_true(along_x > 0.05, "The tip is painted along its major axis, at %.3f" % along_x)
    assert_almost_eq(along_y, along_x, 0.12, "and softened the same at the end of its minor one, %.3f" % along_y)


## Hard rule 2 dispatches over the box `SaDabGeometry` computes, so a texel a
## rotated square image tip paints outside it is paint that never lands. The
## parent suite's own box sweep, `SaDabGeometry.region`, but with the
## generator the kernel is actually pushed, which is what tells the box to
## bound the rectangle a picture fills rather than the ellipse inscribed in
## it.
func test_a_rotated_square_image_tips_corners_stay_inside_its_own_box() -> void:
    var half_extent := Vector2(12.0, 12.0)
    for radians: float in ROTATIONS:
        var tip := _square_tip(half_extent, 1.0)
        var alpha := _paint_tip(tip, radians)
        var box := SaDabGeometry.region(CENTRE, half_extent, radians, tip.spikes, tip.effective_generator())
        var outside := 0
        for y in SIDE:
            for x in SIDE:
                if _at(alpha, x, y) <= 0.0:
                    continue
                if not box.has_point(Vector2(x, y)):
                    outside += 1
        assert_eq(
            outside, 0, "at %.3f radians, %d painted texels of the square tip fall outside its own box" % [radians, outside]
        )


## A procedural tip is untouched by any of this, because the falloff pair is read
## on the image branch only.
func test_hardness_on_a_procedural_tip_is_what_it_was() -> void:
    var hard := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2.ONE))
    assert_almost_eq(_at(hard, 32, 32), 1.0, 1e-4, "A hard disc is opaque at the centre")
    assert_almost_eq(_at(hard, 32 + 11, 32 + 11), 0.0, 1e-4, "and paints nothing in the corner of its box")
    var soft := _paint_tip(_tip(Vector2(12.0, 12.0), Vector2(0.2, 0.2)))
    assert_true(_at(soft, 32 + 8, 32) < _at(hard, 32 + 8, 32), "and a soft one is still the softer of the two")


# --- The tip's own lightness ----------------------------------

## A dab's colour in these tests, and mid grey on purpose: a shift has nowhere
## to go on white, and a grey has no hue to lose, so a texel that comes out off
## grey is the map doing something other than moving lightness.
const GREY := Color(0.5, 0.5, 0.5, 1.0)

## The tip the three tests below paint with: a picture that carries colour, and
## a ramp from one end of the lightness range to the other.
##
## **A grey picture would prove nothing**, which is the point of the fixture: red
## falls and green rises from the left column to the right, so luminance is 0.71
## at one edge of the picture and 0.29 at the other, both about a fifth of the
## range away from the neutral a mask carries.
static var scratch_lightness_tip_path: String = SaDataRoot.path("test_k2_lightness.png")
const LIGHTNESS_SIDE: int = 32

## The columns of the ramp both tests read, inside the picture's own rectangle
## at a half-extent of 24 and far enough from its edges that the sample is one
## column of the ramp rather than two interpolated.
const RAMP_LIGHT_X: int = 12
const RAMP_DARK_X: int = 52


func _write_lightness_tip() -> String:
    var image := Image.create_empty(LIGHTNESS_SIDE, LIGHTNESS_SIDE, false, Image.FORMAT_RGBA8)
    for x in LIGHTNESS_SIDE:
        var v := float(x) / float(LIGHTNESS_SIDE - 1)
        image.fill_rect(Rect2i(x, 0, 1, LIGHTNESS_SIDE), Color(v, 1.0 - v, 0.5, 1.0))
    image.save_png(scratch_lightness_tip_path)
    return scratch_lightness_tip_path


## A tip whose picture carries colour, opaque edge to edge so the coverage is
## one everywhere and every texel's colour is the map's answer alone.
func _colourful_tip(half_extent: Vector2) -> Resource:
    var tip := _tip(half_extent, Vector2.ONE)
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = _write_lightness_tip()
    return tip


## One texel of a raw dab readback as its colour, which is what these tests are
## about rather than the coverage the parent's reader decodes.
func _rgba(data: PackedByteArray, x: int, y: int) -> Color:
    var at := (y * SIDE + x) * 16
    return Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12))


## The ask's second half: the picture's lightness moves the colour the dab lays,
## and does it by lightness rather than by the channels.
##
## Read at the two ends of the ramp, which the flat sample beside them proves
## were the same colour before the map: the light end of the picture lightens
## the paint where it covers, and the dark end darkens it.
func test_a_colourful_tip_moves_the_colour_it_lays_by_its_own_lightness() -> void:
    var tip := _colourful_tip(Vector2(24.0, 24.0))
    var flat := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 0.0)
    var mapped := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 1.0)

    var light_before := _rgba(flat, RAMP_LIGHT_X, 32)
    var light_after := _rgba(mapped, RAMP_LIGHT_X, 32)
    var dark_before := _rgba(flat, RAMP_DARK_X, 32)
    var dark_after := _rgba(mapped, RAMP_DARK_X, 32)

    assert_almost_eq(light_before.r, GREY.r, 1e-4, "Without the map both ends of the ramp lay the same colour")
    assert_almost_eq(dark_before.r, GREY.r, 1e-4, "which is the flat dab the comparison is against")
    assert_true(light_after.r > GREY.r + 0.1, "The light end of the picture lightens it: %f" % light_after.r)
    assert_true(dark_after.r < GREY.r - 0.1, "and the dark end darkens it: %f" % dark_after.r)

    # Lightness and not the channels: a grey shifted in Oklab's L is still grey,
    # where a multiply on the channels of a coloured dab would tint it.
    assert_almost_eq(light_after.r, light_after.g, 1e-3, "and the colour stays on the grey line it started on")
    assert_almost_eq(light_after.g, light_after.b, 1e-3, "where a channel rule would have tinted it")
    assert_almost_eq(dark_after.r, dark_after.g, 1e-3, "at both ends of the ramp")
    assert_almost_eq(dark_after.g, dark_after.b, 1e-3, "and in the dark one too")

    # The row moves the colour and nothing else, which is the whole of what it
    # is allowed to touch: coverage is the picture's alpha and stays it.
    assert_almost_eq(light_after.a, light_before.a, 1e-4, "The coverage is untouched")
    assert_almost_eq(dark_after.a, dark_before.a, 1e-4, "at both ends")


## The same ramp at half strength moves the colour half as far, so the row is a
## strength rather than a switch.
func test_the_lightness_row_is_a_strength() -> void:
    var tip := _colourful_tip(Vector2(24.0, 24.0))
    var full := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 1.0)
    var half := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 0.5)

    var moved_full := _rgba(full, RAMP_LIGHT_X, 32).r - GREY.r
    var moved_half := _rgba(half, RAMP_LIGHT_X, 32).r - GREY.r
    assert_true(moved_full > 0.1, "The whole row moves the colour: %f" % moved_full)
    assert_almost_eq(moved_half, moved_full * 0.5, 0.03, "and half the row moves it half as far")


## A document storing Oklab coordinates takes the shift as one add, which is the
## branch Sara's own default document is on.
##
## **The dab's colour is written in the document's own coordinates**, so what a
## dab is dispatched with here is the Oklab triple an Oklab document would hold
## for the grey the other tests paint with, converted the way `StateBrush` does
## it. The shift then moves the first number and nothing else, which is the
## whole claim: no curve, no round trip, no approximation to be off by.
##
## The comparison against the same triple bound with no document is the part
## that proves the mode reached the kernel rather than merely being written. An
## RGB document would read those three numbers as a saturated red and move two
## of them, so the two runs cannot agree.
func test_an_oklab_document_takes_the_lightness_shift_as_one_add() -> void:
    var tip := _colourful_tip(Vector2(24.0, 24.0))
    var space := SaColorSpace.oklab()
    var stored := space.from_display(GREY)

    var flat := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, stored, 0.0, space)
    var mapped := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, stored, 1.0, space)
    var as_rgb := _paint_tip_bytes(tip, 0.0, CENTRE, 0.0, 0.0, 0.0, null, stored, 1.0, null)

    var before := _rgba(flat, RAMP_LIGHT_X, 32)
    var after := _rgba(mapped, RAMP_LIGHT_X, 32)
    var other := _rgba(as_rgb, RAMP_LIGHT_X, 32)

    assert_almost_eq(before.r, stored.r, 1e-4, "The row switched off lays the dab's own colour")
    assert_true(after.r > before.r + 0.15, "The light end of the picture lightens it: %f" % (after.r - before.r))
    assert_eq(after.g, before.g, "and moves the second coordinate not at all")
    assert_eq(after.b, before.b, "nor the third")

    # The dark end of the ramp takes it the other way, so the add is signed and
    # not a one-way lift.
    var dark_before := _rgba(flat, RAMP_DARK_X, 32)
    var dark_after := _rgba(mapped, RAMP_DARK_X, 32)
    assert_true(dark_after.r < dark_before.r - 0.15, "The dark end darkens it: %f" % (dark_after.r - dark_before.r))
    assert_eq(dark_after.g, dark_before.g, "with the other two coordinates untouched there too")
    assert_eq(dark_after.b, dark_before.b, "at the dark end as at the light one")

    # The mode is what makes the difference, so an RGB document given the very
    # same triple must not agree with either coordinate.
    assert_true(absf(other.g - before.g) > 1e-3, "An RGB document reads those numbers as a red and moves its green")
    assert_true(absf(other.b - before.b) > 1e-3, "and its blue")


## A tip whose picture carries no colour is untouched by the row, texel for
## texel, which is the promise that no brush Sara already had moves.
func test_a_tip_with_no_colour_paints_the_texels_it_always_did() -> void:
    # A procedural tip, which has no picture at all.
    var plain := _tip(Vector2(24.0, 24.0), Vector2.ONE)
    assert_eq(
        _paint_tip(plain, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 1.0),
        _paint_tip(plain, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 0.0),
        "A disc is the same disc at any strength, to the bit"
    )

    # And an image tip whose picture is a grey mask rather than a colour map.
    var grey_picture := _image_tip(Vector2(24.0, 24.0))
    assert_eq(
        _paint_tip(grey_picture, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 1.0),
        _paint_tip(grey_picture, 0.0, CENTRE, 0.0, 0.0, 0.0, null, GREY, 0.0),
        "and a grey tip's second channel is the neutral one"
    )
