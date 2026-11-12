## Filter > Colour Balance: the nine amounts, the three bands and what the
## kernel does with them.
##
## The band weighting is the claim worth a test rather than a screenshot: the
## same slider has to move a dark fill and leave a light one, and a picture of
## a ramp cannot say by how much. The pass itself is checked the way Levels and
## Curves are, a flat fill through the kernel and the texel read back off the
## chunk.
extends "res://tests/test_framework.gd"

## A real dispatch, and a real storage buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(64, 64)


func _texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i.ZERO)
    if texture == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    @warning_ignore("static_called_on_instance")
    return SaExport.get_texture_image_float(texture).get_pixel(4, 4)


## *fill* through the colour balance pass with *values*, as the colour out.
func _through(easel: SaEasel, fill: Color, values: Dictionary) -> Color:
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(fill)
    easel.document.set_active_layer(layer)
    var ran := SaPointAdjust.new().apply(easel.document, layer, SaPointAdjust.COLOR_BALANCE, values, "Colour Balance")
    assert_true(ran, "The pass runs")
    return _texel(layer)


## The nine ride above the five lookups and below the colour lookup's palette,
## so every kernel of the file finds its own part at one offset. The buffer is
## one layout in one class, the palette's half included.
func test_the_nine_amounts_sit_above_the_five_lookups() -> void:
    assert_eq(
        SaPointAdjust.BALANCE_BASE,
        SaPointAdjust.CHANNELS.size() * SaCurveEditor.SAMPLES,
        "The base is exactly where the lookups end, which are this module's own"
    )
    assert_eq(
        SaPointAdjust.PALETTE_BASE,
        SaPointAdjust.BALANCE_BASE + SaPointAdjust.BALANCE_FLOATS,
        "and the palette starts exactly where the nine end"
    )
    assert_eq(
        SaPointAdjust.BALANCE_FLOATS,
        SaPointAdjust.BALANCE_BANDS.size() * SaPointAdjust.BALANCE_AXES.size(),
        "and nine is three bands by three axes"
    )

    var table := SaPointAdjust.table({"midtones_mg": 0.4, "highlights_yb": -0.6})
    assert_eq(
        table.size(),
        SaPointAdjust.EQUALIZE_BASE + SaPointAdjust.EQUALIZE_FLOATS,
        "The buffer is the whole layout whichever kind wrote it, so it is written in place"
    )
    assert_almost_eq(table[SaPointAdjust.PALETTE_BASE], 0.0, 1e-6, "and a palette nobody named is a count of nothing")
    assert_almost_eq(table[128], 128.0 / 255.0, 1e-4, "and below them the master lookup is the identity no curve shaped")
    assert_almost_eq(table[SaPointAdjust.BALANCE_BASE + 4], 0.4, 1e-6, "The midtone green is the fifth of the nine")
    assert_almost_eq(table[SaPointAdjust.BALANCE_BASE + 8], -0.6, 1e-6, "and the highlight blue is the ninth")
    assert_almost_eq(table[SaPointAdjust.BALANCE_BASE], 0.0, 1e-6, "An amount nobody set is no shift")


## The toggle is the only one of the ten that fits in the push constant, in the
## slot Levels took for its channel.
func test_preserve_luminosity_rides_the_spare_slot() -> void:
    var off := SaPointAdjust.params_for(SaPointAdjust.COLOR_BALANCE, {})
    assert_almost_eq(float(off[5]), 0.0, 1e-6, "Unticked is zero")
    var on := SaPointAdjust.params_for(SaPointAdjust.COLOR_BALANCE, {"preserve_luminosity": true})
    assert_almost_eq(float(on[5]), 1.0, 1e-6, "and ticked is one")


## What a slider at its end is worth, and it is written here rather than read
## out of the shader because the record has to say what the number is.
const STRENGTH := 0.25


## The whole point of the pass: one slider, two fills, two different answers.
## A shadows slider that moved the highlight as well would be a brightness
## slider with extra steps.
##
## Black and white rather than near-black and near-white, so the weights are
## exactly one and exactly zero and the assertion is the strength itself.
func test_the_shadows_slider_moves_the_dark_and_leaves_the_light() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var reddened := {"shadows_cr": 1.0}

    var dark := _through(easel, Color(0.0, 0.0, 0.0, 1.0), reddened)
    var light := _through(easel, Color(1.0, 1.0, 1.0, 1.0), reddened)

    assert_almost_eq(dark.r, STRENGTH, 5e-3, "The black took the whole shift")
    assert_almost_eq(light.r, 1.0, 5e-3, "and the white took none of it")
    assert_almost_eq(dark.g, 0.0, 5e-3, "Only the red channel moved")
    assert_almost_eq(dark.b, 0.0, 5e-3, "on the cyan-red axis")
    easel.free()


## The mirror of it, so the partition is proved from both ends rather than
## from one and an assumption.
func test_the_highlights_slider_moves_the_light_and_leaves_the_dark() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var blued := {"highlights_yb": 1.0}

    var light := _through(easel, Color(1.0, 1.0, 1.0, 1.0), blued)
    var dark := _through(easel, Color(0.0, 0.0, 0.0, 1.0), blued)

    assert_almost_eq(light.b, 1.0 + STRENGTH, 5e-3, "The white took the whole shift, past white")
    assert_almost_eq(dark.b, 0.0, 5e-3, "and the black took none of it")
    easel.free()


## The bands are cut on Oklab lightness, so the middle is the perceptual one
## and not the numeric one. A colour at L 0.5 is entirely midtones, which is
## what makes the three weights a partition rather than three overlapping
## curves.
func test_the_middle_of_the_bands_is_oklab_lightness_not_the_stored_half() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var pivot := _grey_at_lightness(0.5)

    var by_shadows := _through(easel, pivot, {"shadows_cr": 1.0})
    var by_highlights := _through(easel, pivot, {"highlights_cr": 1.0})
    var by_midtones := _through(easel, pivot, {"midtones_cr": 1.0})

    assert_almost_eq(by_shadows.r, pivot.r, 5e-3, "The shadows slider does not reach the pivot")
    assert_almost_eq(by_highlights.r, pivot.r, 5e-3, "nor does the highlights one")
    assert_almost_eq(by_midtones.r, pivot.r + STRENGTH, 5e-3, "and the midtones slider takes it whole")

    # Where the two middles part company, written down because it surprises:
    # a stored 0.5 reads as lighter than the perceptual half, so it is mostly
    # midtones with a tenth of highlight rather than midtones alone.
    assert_true(pivot.r < 0.45, "The perceptual half is darker than a stored half, at %.4f" % pivot.r)
    var stored_half := _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"highlights_cr": 1.0})
    assert_true(stored_half.r - 0.5 > 0.01, "so a stored half takes a little of the highlight shift")
    assert_true(stored_half.r - 0.5 < 0.05, "and only a little")
    easel.free()


## The encoded grey whose Oklab lightness is *lightness*, so a test can name a
## band's edge rather than a number that happens to land near it.
func _grey_at_lightness(lightness: float) -> Color:
    var linear := OkhsvConversions.oklab_to_linear_srgb(Vector3(lightness, 0.0, 0.0))
    var encoded := OkhsvConversions.srgb_transfer_function(linear)
    return Color(encoded.x, encoded.y, encoded.z, 1.0)


## Preserve luminosity keeps the lightness the pixel had and lets the hue move,
## which is the difference between tinting a picture and lifting it.
func test_preserve_luminosity_keeps_the_lightness_and_moves_the_hue() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var grey := Color(0.5, 0.5, 0.5, 1.0)

    var free_shift := _through(easel, grey, {"midtones_cr": 1.0})
    var pinned := _through(easel, grey, {"midtones_cr": 1.0, "preserve_luminosity": true})

    assert_true(pinned.r > pinned.b + 0.05, "The pinned pixel is still redder than it was blue")
    assert_true(_lightness(pinned) < _lightness(free_shift) - 0.01, "and it is darker than the unpinned one")
    assert_almost_eq(_lightness(pinned), _lightness(grey), 5e-3, "because its lightness is the one it started with")
    easel.free()


## Nothing clamps, so a value above white takes the highlight shift rather than
## being pinned first and shifted after (hard rule 5).
func test_a_value_above_white_is_a_highlight_and_stays_above_white() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var out := _through(easel, Color(3.0, 3.0, 3.0, 1.0), {"highlights_cr": 1.0})
    assert_true(out.r > 3.0, "The red channel took the shift on top of its own value, got %.4f" % out.r)
    assert_almost_eq(out.g, 3.0, 5e-3, "and the other two came through unclamped")
    easel.free()


## Apply is one history step, like the other four adjustments.
func test_apply_is_one_undoable_step() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var before := easel.document.history.step_count()
    _through(easel, Color(0.5, 0.5, 0.5, 1.0), {"midtones_cr": 1.0})
    assert_eq(easel.document.history.step_count(), before + 1, "One step")
    easel.document.undo_redo.undo()
    assert_almost_eq(_texel(easel.document.get_node("Layer 1")).r, 0.5, 2e-3, "which one undo puts back")
    easel.free()


## Oklab L of an sRGB-encoded colour, which is what the bands are cut on.
func _lightness(color: Color) -> float:
    var linear := OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
    return OkhsvConversions.linear_srgb_to_oklab(linear).x
