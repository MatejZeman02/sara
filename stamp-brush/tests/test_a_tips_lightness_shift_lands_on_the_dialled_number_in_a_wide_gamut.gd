## A tip's lightness map moves a dab's colour by the number its picture dials on
## an RGB document of any gamut, and leaves an sRGB document's texels as they
## were.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kernel's RGB branch decodes the dab's colour through the document's own
## curve and goes into Oklab, shifts its lightness and comes back. Treating
## the linear values as sRGB's primaries would, on a Display P3, ACEScg or
## Rec.2020 document, bring back a colour other than the one the shift asked
## for. The document's two gamut matrices ride
## the masking buffer, and this suite holds every texel of a dab to the colour
## the CPU makes through those same matrices.
##
## **Painted through `SaStampBindings.bind`**, the call the brush makes with
## `SaDocument.color_space`, so the matrices reach the kernel by the road a
## stroke takes rather than by a binding written for the suite.
##
## **Each tip's picture is one colour edge to edge**, so every texel the dab
## covers is shifted by the same amount and the CPU knows it from the picture
## alone: `SaTipImage.luminance_of` of the decoded file, less the neutral, times
## the row's strength. A ramp would put the sampler's interpolation between the
## shift the picture gives and the shift a texel gets, which is not this row's
## arithmetic. One tip lightens and the other darkens, so the shift is checked
## in both directions.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SaBrushTipScript = preload("res://core/api/tip/sa_brush_tip.gd")

const SIDE: int = 64
## The workgroups one dispatch of the whole canvas needs, the kernel's
## `[numthreads(8, 8, 1)]` into the side.
const GROUPS: int = 8
const CENTRE := Vector2(32.0, 32.0)
const HALF_EXTENT := Vector2(24.0, 24.0)
const PICTURE_SIDE: int = 16

## The colour the picker holds for every dab, saturated so that the gamut the
## triple is read in decides where its lightness lands.
const PICKED := Color(0.8, 0.3, 0.2, 1.0)

## The two pictures, one well above mid grey and one well below, each a colour
## rather than a grey so the tip loads as a lightness map and not as a mask.
const LIGHT_PICTURE := Color(0.95, 0.8, 0.35, 1.0)
const DARK_PICTURE := Color(0.1, 0.25, 0.6, 1.0)

## How close each texel lands to the CPU's colour, the row's own number.
const TOLERANCE: float = 1e-3

## The SHA-256 of the two dabs painted on an sRGB document, recorded by this
## suite's `_srgb_hash` before the matrices joined the buffer, on the GPU the other
## recorded hashes come from. A change that means to change what an sRGB document
## paints records it again and says why in its commit.
const SRGB_HASH_BEFORE: String = "71be9afc01c9b5029921b483ff2c5cb193314de6ad55ee152c8cd8d4b070ae82"

static var light_path: String = SaDataRoot.path("test_b2_plan39_light_tip.png")
static var dark_path: String = SaDataRoot.path("test_b2_plan39_dark_tip.png")


func after_all() -> void:
    for path: String in [light_path, dark_path]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## Every texel of a dab on a Display P3, an ACEScg and a Rec.2020 document is
## the picked colour taken through that document's matrices into Oklab, moved
## by the tip's shift and taken back, within the row's 1e-3.
func test_every_texel_lands_on_the_cpus_colour_in_three_wide_gamuts() -> void:
    for space: SaColorSpace in [SaColorSpace.display_p3(), SaColorSpace.acescg(), SaColorSpace.rec2020()]:
        for path: String in [_write_picture(light_path, LIGHT_PICTURE), _write_picture(dark_path, DARK_PICTURE)]:
            var stored := space.from_display(PICKED)
            var shift := _shift_of(path)
            var expected := _expected(space, stored, shift)
            var texels := _texels(_paint(path, stored, space))
            var label := "%s, %s tip" % [space.id, path.get_file().get_basename()]
            var covered := 0
            var worst := 0.0
            for texel: Color in texels:
                if texel.a <= 0.0:
                    continue
                covered += 1
                worst = maxf(worst, _distance(texel, expected))
            assert_true(covered > 1000, "%s: the dab covers its picture's square, %d texels" % [label, covered])
            assert_true(worst <= TOLERANCE, "%s: every texel within 1e-3 of the CPU's colour, the worst %f" % [label, worst])
            # The shift is not nought, so the texels moved and the comparison
            # is with a colour the dab did not start at.
            assert_true(absf(shift) > 0.2, "%s: the picture dials a shift worth reading, %f" % [label, shift])
            # And the old arithmetic, the same round trip read in sRGB's
            # primaries, is more than the tolerance away, so a kernel that
            # had not received the matrices could not pass the line above.
            var as_srgb := _expected_in_srgb_primaries(space, stored, shift)
            assert_true(_distance(as_srgb, expected) > 3.0 * TOLERANCE, "%s: sRGB's primaries would land elsewhere" % label)


## The same two dabs on an sRGB document write the texels the kernel wrote
## before the change, to the bit, by the hash recorded then.
func test_an_srgb_document_paints_the_texels_it_painted_before() -> void:
    var painted := _srgb_hash()
    if SRGB_HASH_BEFORE.is_empty():
        print("sRGB hash: ", painted)
    assert_eq(painted, SRGB_HASH_BEFORE, "An sRGB document's dabs are the texels they were before the matrices")


## The block carries the document's two matrices where the kernel reads them,
## and follows a change of gamut when nothing else it carries moved.
##
## **Display P3 then sRGB is the case that needs the second half.** The two share
## the sRGB curve, so a block that is off and compared only by its lightness,
## mode and curve would answer the P3 matrices to the sRGB document.
func test_the_block_carries_the_documents_matrices_and_follows_a_change_of_gamut() -> void:
    var bindings := SaStampBindings.of(SaBrushTipMask.load_image(""))
    var p3 := SaColorSpace.display_p3()
    var srgb := SaColorSpace.srgb()
    for space: SaColorSpace in [p3, srgb]:
        bindings.masking_for(
            null,
            40.0,
            null,
            0.5,
            SaStampBindings.lightness_mode_for(space),
            SaStampBindings.transfer_for(space),
            SaStampBindings.gamut_for(space)
        )
        var block := bindings.masking_values
        var into := SaStampBindings.MASK_TO_LINEAR_SRGB
        var back := SaStampBindings.MASK_FROM_LINEAR_SRGB
        assert_eq(
            block.slice(into, into + SaStampBindings.GAMUT_FLOATS),
            space.to_push_constant().slice(0, SaStampBindings.GAMUT_FLOATS),
            "%s: both matrices, as the composite kernels' push constant packs them" % space.id
        )
        var column := Vector3(block[into], block[into + 1], block[into + 2])
        assert_true(column.is_equal_approx(space.to_linear_srgb_matrix().x), "%s: the first is into linear sRGB" % space.id)
        column = Vector3(block[back], block[back + 1], block[back + 2])
        assert_true(column.is_equal_approx(space.from_linear_srgb_matrix().x), "%s: the second is back out of it" % space.id)
    assert_eq(SaStampBindings.MASK_FROM_LINEAR_SRGB, SaStampBindings.MASK_TO_LINEAR_SRGB + 9, "The second follows the first")
    assert_eq(SaStampBindings.MASK_HEADER, SaStampBindings.MASK_FROM_LINEAR_SRGB + 10, "and the seed, then the softness table")
    assert_eq(
        bindings.masking_values[SaStampBindings.MASK_TO_LINEAR_SRGB],
        1.0,
        "After Display P3, an sRGB document's block reads the identity, so the off block was rebuilt"
    )


## The two dabs on an sRGB document as one SHA-256 over their float texels.
func _srgb_hash() -> String:
    var space := SaColorSpace.srgb()
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    for path: String in [_write_picture(light_path, LIGHT_PICTURE), _write_picture(dark_path, DARK_PICTURE)]:
        context.update(_paint(path, space.from_display(PICKED), space))
    return context.finish().hex_encode()


## Writes a picture of one colour, opaque edge to edge, and answers its path.
static func _write_picture(path: String, colour: Color) -> String:
    var image := Image.create_empty(PICTURE_SIDE, PICTURE_SIDE, false, Image.FORMAT_RGBA8)
    image.fill(colour)
    image.save_png(path)
    return path


## The shift the picture at *path* gives at the whole row's strength, read on
## the CPU off the decoded file the kernel's texture is made from.
static func _shift_of(path: String) -> float:
    var picture := SaTipImage.load_from(path)
    return picture.lightness_at(0, 0) - SaTipImage.NEUTRAL_LIGHTNESS


## *stored* through *space*'s curve and its own matrix into Oklab, its
## lightness moved by *shift*, and back through the inverse matrix and the
## curve, which is the colour the row asks the kernel to lay.
static func _expected(space: SaColorSpace, stored: Color, shift: float) -> Color:
    return _round_trip(space, stored, shift, space.to_linear_srgb_matrix(), space.from_linear_srgb_matrix())


## The same round trip with sRGB's primaries in place of the document's, which
## is what the kernel did before the row.
static func _expected_in_srgb_primaries(space: SaColorSpace, stored: Color, shift: float) -> Color:
    return _round_trip(space, stored, shift, Basis.IDENTITY, Basis.IDENTITY)


static func _round_trip(space: SaColorSpace, stored: Color, shift: float, into: Basis, back: Basis) -> Color:
    var curve := space.transfer
    var linear := Vector3(curve.decode(stored.r), curve.decode(stored.g), curve.decode(stored.b))
    var lab := SaOklab.from_linear_srgb(into * linear)
    lab.x += shift
    var out := back * SaOklab.to_linear_srgb(lab)
    return Color(curve.encode(out.x), curve.encode(out.y), curve.encode(out.z), stored.a)


static func _distance(a: Color, b: Color) -> float:
    return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


## One dab of the picture at *path*, its lightness row at full strength, in
## *colour* on a document of *space*, read back as the canvas's raw bytes.
func _paint(path: String, colour: Color, space: SaColorSpace) -> PackedByteArray:
    var tip := SaBrushTipScript.new()
    tip.diameter = HALF_EXTENT.x * 2.0
    tip.horizontal_fade = 1.0
    tip.vertical_fade = 1.0
    tip.generator = SaDabGeometry.Generator.IMAGE
    tip.image_path = path
    tip.lightness_strength = 1.0

    var rd := GlobalShaderCompiler.get_rd()
    var canvas := SaTexture.new(Vector2i(SIDE, SIDE))
    rd.texture_clear(canvas.rid, Color(0, 0, 0, 0), 0, 1, 0, 1)
    var compute := SaCompute.new("dab")
    compute.set_texture(0, canvas.rid)
    var selection := SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
    selection.clear(Color(1.0, 1.0, 1.0, 1.0))
    compute.set_texture(SaSelection.BINDING, selection.rid)
    var mask := SaStampBindings.bind(compute, tip, null, null, null, space)
    assert_true(mask.colourful, "%s loads as a lightness map" % path.get_file())
    compute.set_push_constant_float_array(
        SaDabPacking.pack_dab_params(
            CENTRE,
            Vector2.ZERO,
            colour,
            tip.half_extent(),
            0.0,
            tip.effective_fade(),
            1.0,
            SaDabGeometry.PaintMode.OVER,
            false,
            tip
        )
    )
    compute.dispatch_kernel("dab", GROUPS, GROUPS, 1)
    return rd.texture_get_data(canvas.rid, 0)


static func _texels(data: PackedByteArray) -> Array[Color]:
    var out: Array[Color] = []
    for i in SIDE * SIDE:
        var at := i * 16
        out.append(Color(data.decode_float(at), data.decode_float(at + 4), data.decode_float(at + 8), data.decode_float(at + 12)))
    return out
