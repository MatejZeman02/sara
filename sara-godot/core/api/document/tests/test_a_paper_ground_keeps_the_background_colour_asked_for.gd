## A paper ground keeps the background colour asked for.
##
## A New Document with a background of `#f4f2ed`,
## L* 95.6, over the paper ground, read the paper back at a median of
## L* 89.4. The paper's grain mixed the colour asked with a darker second, and
## its median stood half way between them. These make the document the way
## the dialog does, composite it, and read the median CIE L* of every pixel
## against the colour's, for a light colour and a mid grey, in each kind of
## document space the dialog offers.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Two chunks by two, so the median is taken over some four hundred and fifty
## of the paper's cells rather than a handful.
const SIZE := Vector2i(512, 512)
## A light paper colour, L* 95.5.
const LIGHT := Color8(0xf4, 0xf2, 0xed)
## A mid grey, L* 50.0.
const MID_GREY := Color8(0x77, 0x77, 0x77)
## What the note asks of the median, in L*.
const WITHIN := 1.0
## Every fourth pixel each way is read, which leaves the median where the
## whole would put it and costs a sixteenth of the reading.
const STRIDE := 4

var _registries: SaRegistries = null


func before_each() -> void:
    _registries = Fixtures.make_registries()


func after_each() -> void:
    _registries = null


## An easel whose document New Document made in *space*, a colour of *shown*
## over the paper ground, composited whole. The caller frees it.
func _easel_of(shown: Color, space: SaColorSpace) -> SaEasel:
    var easel := SaEasel.create_default(SIZE, null, space)
    easel.compositor.set_registry(_registries.blend_modes)
    var choice := {
        SaDocumentBackground.KIND: SaDocumentBackground.COLOUR,
        SaDocumentBackground.COLOR: shown,
        SaDocumentBackground.GROUND: &"paper",
    }
    easel.document.reset_to_default(SIZE, space, SaDocument.DEFAULT_DPI, choice, _registries.layer_types)
    easel.document.update_caches()
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The CIE L* of *display*, a colour in display sRGB, against D65's white.
static func _lightness(display: Color) -> float:
    var curve := SaTransferFunction.srgb()
    var y := 0.2126 * curve.decode(display.r) + 0.7152 * curve.decode(display.g) + 0.0722 * curve.decode(display.b)
    return 116.0 * pow(y, 1.0 / 3.0) - 16.0 if y > 216.0 / 24389.0 else y * 24389.0 / 27.0


## The L* of the composite *easel* holds at every STRIDE'th texel each way,
## each texel shown through the document's space as the canvas shows it,
## lightest last.
static func _lightnesses(easel: SaEasel) -> PackedFloat32Array:
    var image := SaExport.get_easel_image_float(easel)
    var space := easel.document.color_space
    var values := PackedFloat32Array()
    for y in range(0, image.get_height(), STRIDE):
        for x in range(0, image.get_width(), STRIDE):
            values.append(_lightness(space.to_display(image.get_pixel(x, y))))
    values.sort()
    return values


## The value *share* of the way up the sorted *values*.
static func _at(values: PackedFloat32Array, share: float) -> float:
    return values[floori((values.size() - 1) * share)]


## The paper's median L* within WITHIN of the colour's, and the 5th and 95th
## percentiles either side of it, so a grain that sat wholly to one side of the
## colour with its median there by chance would still fail.
func _assert_paper_keeps(shown: Color, what: String) -> void:
    var asked := _lightness(shown)
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.linear_srgb(), SaColorSpace.oklab()]:
        var easel := _easel_of(shown, space)
        assert_true(easel.document.get_child(0).is_generated(), "The %s paper of a %s document is a ground" % [what, space.id])
        var values := _lightnesses(easel)
        var median := _at(values, 0.5)
        assert_almost_eq(
            median, asked, WITHIN, "and its median L* %.2f is the %.2f asked of a %s document" % [median, asked, space.id]
        )
        var low := _at(values, 0.05)
        var high := _at(values, 0.95)
        assert_true(low < asked and asked < high, "with the mottle either side, %.2f to %.2f" % [low, high])
        easel.free()


## A light colour: a paper of `#f4f2ed` reads that colour at its
## median rather than 5.5 L* under it.
func test_a_light_paper_keeps_its_colour_at_its_median() -> void:
    _assert_paper_keeps(LIGHT, "light")


## A mid grey, which sat 3.1 L* under, holds as well.
func test_a_mid_grey_paper_keeps_its_colour_at_its_median() -> void:
    _assert_paper_keeps(MID_GREY, "mid grey")
