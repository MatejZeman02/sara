## The Stats docker's saturation by value reads the band the saturated paint
## sits in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row's Done line: a document whose saturated paint all sits below Oklab L
## 0.35 and whose lighter paint is grey reads the darkest band the most
## saturated and the lightest at nought, and the mirror of that document reads
## the other way round. So the suite paints the colours a chunk at a time on a
## real easel, and the part's reduction runs through a service of its own when
## a real idle clock fires, read back at once so an assertion can follow it.
## Then the same colours on a Display P3 document, the canvas nobody painted,
## and the rows the docker shows.
extends "res://tests/test_framework.gd"

## Real composites and the real kernel over them.
const REQUIRES_GPU := true

const Saturation := preload("../saturation_by_value.gd")

## Two chunks by two, so a colour over a half is two chunks and a quarter is one.
const SIZE := Vector2i(512, 512)

## Inside sRGB, so the colours are the same paint on either document. Both
## saturated ones carry an Oklab chroma of 0.12.
const DARK_BLUE := Vector3(0.25, 0.0, -0.12)
const DARK_GREY := Vector3(0.25, 0.0, 0.0)
const LIGHT_ORANGE := Vector3(0.8, 0.0, 0.12)
const LIGHT_GREY := Vector3(0.8, 0.0, 0.0)
const CHROMA := 0.12

var _easel: SaEasel = null
var _clock: SaIdleClock = null
var _service: SaReductionService = null
var _part: Saturation = null


func before_each() -> void:
    _start(SaColorSpace.srgb())


func after_each() -> void:
    _end()


func _start(space: SaColorSpace) -> void:
    _easel = SaEasel.create_default(SIZE, null, space)
    _easel.process_pending_composite()
    _clock = SaIdleClock.new()
    _clock.follow_settings = false
    _clock.follow_main = false
    _clock.idle_seconds = 1.0
    _clock.attach(_easel.document)
    _service = SaReductionService.new()
    _service.watch(_easel)
    _service.listen(_clock)
    _part = Saturation.new()
    _numbers().read_at_once = true


func _end() -> void:
    _numbers().let_go()
    _part = null
    _service.free()
    _clock.free()
    _easel.free()


func _numbers() -> SaReductionService.OverDocument:
    return _part.reduction as SaReductionService.OverDocument


## The Oklab colour *lab* as the document stores it, carried through its own
## gamut and curve.
func _stored(lab: Vector3) -> Color:
    var space := _easel.document.color_space
    if space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return Color(lab.x, lab.y, lab.z)
    var own := space.from_linear_srgb_matrix() * SaOklab.to_linear_srgb(lab)
    return Color(space.transfer.encode(own.x), space.transfer.encode(own.y), space.transfer.encode(own.z))


## Paints the chunk at *grid_pos* of the paint layer one colour and tells the
## document, the way a dab inside one chunk does.
func _paint_chunk(grid_pos: Vector2i, colour: Color) -> void:
    var document := _easel.document
    document.active_layer.get_or_create_chunk(grid_pos).clear(colour)
    document.invalidate_chunk_regions({grid_pos: Rect2i(Vector2i.ZERO, Vector2i.ONE * SaLayer.CHUNK_SIZE)})


## The left half in *left* and the right half in *right*, Oklab both.
func _halves(left: Vector3, right: Vector3) -> void:
    _paint_chunk(Vector2i(0, 0), _stored(left))
    _paint_chunk(Vector2i(0, 1), _stored(left))
    _paint_chunk(Vector2i(1, 0), _stored(right))
    _paint_chunk(Vector2i(1, 1), _stored(right))


## The painter stops, and the service runs what is registered.
func _stop() -> bool:
    _clock.note_edit()
    return _clock.tick(_clock.idle_seconds)


## The bands the part finds now, after a stop.
func _bands() -> Array:
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    return _part.bands_of(_easel.document)


## Reads *bands* as half the canvas saturated at *saturated* and half grey at
## *grey*, two of the three bands, with the empty one at nought.
func _reads(bands: Array, saturated: int, grey: int, said: String) -> void:
    assert_eq(bands.size(), Saturation.BANDS.size(), "%s: a band each" % said)
    if bands.size() != Saturation.BANDS.size():
        return
    var held: Saturation.Band = bands[saturated]
    var flat: Saturation.Band = bands[grey]
    assert_true(absf(held.chroma - CHROMA) <= 0.005, "%s: the saturated band reads its chroma, read %.4f" % [said, held.chroma])
    assert_true(absf(held.share - 0.5) <= 0.01, "%s: over half the canvas, read %.4f" % [said, held.share])
    assert_true(flat.chroma <= 0.001, "%s: the grey band reads nought, read %.5f" % [said, flat.chroma])
    assert_true(absf(flat.share - 0.5) <= 0.01, "%s: over the other half, read %.4f" % [said, flat.share])
    var middle: Saturation.Band = bands[1]
    assert_eq(middle.share, 0.0, "%s: the midtones hold nothing" % said)
    assert_eq(middle.chroma, 0.0, "%s: and read nought" % said)
    assert_eq(Saturation.most_saturated(bands), saturated, "%s: the saturated band is named the most saturated" % said)


func test_saturation_below_l_0_35_reads_the_darkest_band_the_most_saturated() -> void:
    assert_true(DARK_BLUE.x < 0.35, "The saturated paint sits below L 0.35")
    _halves(DARK_BLUE, LIGHT_GREY)
    var bands := _bands()
    _reads(bands, 0, 2, "dark blue and light grey")
    if bands.size() == Saturation.BANDS.size():
        var darkest: Saturation.Band = bands[0]
        var lightest: Saturation.Band = bands[2]
        assert_true(darkest.chroma > lightest.chroma, "The darkest band is the most saturated")
        assert_eq(snappedf(lightest.chroma, 0.001), 0.0, "and the lightest at nought")


func test_the_mirror_reads_the_lightest_band_the_most_saturated() -> void:
    _halves(DARK_GREY, LIGHT_ORANGE)
    var bands := _bands()
    _reads(bands, 2, 0, "dark grey and light orange")
    if bands.size() == Saturation.BANDS.size():
        var darkest: Saturation.Band = bands[0]
        var lightest: Saturation.Band = bands[2]
        assert_true(lightest.chroma > darkest.chroma, "The lightest band is the most saturated")
        assert_eq(snappedf(darkest.chroma, 0.001), 0.0, "and the darkest at nought")


## Value and chroma are taken through the document's own colour space, so a
## wide gamut document painted in the same Oklab colours reads the same.
func test_a_display_p3_document_reads_the_same_oklab_colours_the_same() -> void:
    _end()
    _start(SaColorSpace.display_p3())
    assert_false(_easel.document.color_space.shares_gamut(SaColorSpace.srgb()), "The document is wider than sRGB")
    assert_false(_stored(DARK_BLUE).is_equal_approx(_stored_in_srgb(DARK_BLUE)), "so it stores the blue otherwise")
    _halves(DARK_BLUE, LIGHT_GREY)
    _reads(_bands(), 0, 2, "Display P3, dark blue and light grey")
    _end()
    _start(SaColorSpace.display_p3())
    _halves(DARK_GREY, LIGHT_ORANGE)
    _reads(_bands(), 2, 0, "Display P3, dark grey and light orange")


func _stored_in_srgb(lab: Vector3) -> Color:
    var linear := SaOklab.to_linear_srgb(lab)
    return Color(linear.x, linear.y, linear.z).linear_to_srgb()


## A transparent document of four chunks with paint in one, the dark blue. One
## chunk is dispatched over and the other three are added as the grey
## checkerboard they show, in the band of its lightness at no chroma.
func test_the_canvas_nobody_painted_counts_as_the_background_it_shows() -> void:
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    _easel.document.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    assert_not_null(_easel.resize_output(SIZE), "the output is the canvas's size")
    assert_true(_easel.document.active_layer.chunks.is_empty(), "The transparent document holds no chunk")
    _paint_chunk(Vector2i(0, 0), _stored(DARK_BLUE))
    var bands := _bands()
    assert_eq(_numbers().dispatched, [Vector2i(0, 0)] as Array[Vector2i], "The painted chunk is all it read")
    var checker := Saturation.background_shown()
    assert_true(checker.x > 0.35 and checker.x < 0.65, "The checkerboard is a midtone, read L %.3f" % checker.x)
    assert_true(checker.y < 0.001, "and grey, read chroma %.5f" % checker.y)
    if bands.size() != Saturation.BANDS.size():
        return
    var shadows: Saturation.Band = bands[0]
    var midtones: Saturation.Band = bands[1]
    assert_true(absf(shadows.share - 0.25) <= 0.01, "The blue covers a quarter, read %.4f" % shadows.share)
    assert_true(absf(shadows.chroma - CHROMA) <= 0.005, "at its chroma, read %.4f" % shadows.chroma)
    assert_true(absf(midtones.share - 0.75) <= 0.01, "and the checkerboard the rest, read %.4f" % midtones.share)
    assert_true(midtones.chroma <= 0.001, "at no chroma, read %.5f" % midtones.chroma)


## A texel half covered weighs half, and what it leaves is the background.
func test_half_covered_paint_weighs_half() -> void:
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    _easel.document.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    assert_not_null(_easel.resize_output(SIZE), "the output is the canvas's size")
    var blue := _stored(DARK_BLUE)
    blue.a = 0.5
    _paint_chunk(Vector2i(1, 1), blue)
    var bands := _bands()
    if bands.size() != Saturation.BANDS.size():
        return
    var shadows: Saturation.Band = bands[0]
    assert_true(absf(shadows.share - 0.125) <= 0.01, "Half a quarter, read %.4f" % shadows.share)
    assert_true(absf(shadows.chroma - CHROMA) <= 0.005, "and the chroma of the paint itself, read %.4f" % shadows.chroma)


func test_a_document_of_greys_names_no_band() -> void:
    _halves(DARK_GREY, LIGHT_GREY)
    var bands := _bands()
    for band: Saturation.Band in bands:
        assert_true(band.chroma <= 0.001, "Band %d reads nought, read %.5f" % [band.index, band.chroma])
    assert_eq(Saturation.most_saturated(bands), -1, "and none is the most saturated")


func test_a_lightness_past_white_is_a_light_and_one_below_black_a_shadow() -> void:
    assert_eq(Saturation.band_of(-0.2), 0, "Below black, a shadow")
    assert_eq(Saturation.band_of(0.34), 0, "Under 0.35, a shadow")
    assert_eq(Saturation.band_of(0.35), 1, "At 0.35, a midtone")
    assert_eq(Saturation.band_of(0.65), 2, "At 0.65, a light")
    assert_eq(Saturation.band_of(1.6), 2, "Past white, a light")
    for band in Saturation.BANDS.size() - 1:
        var below: float = Saturation.BANDS[band]["below"]
        var step := below * Saturation.BINS
        assert_true(is_equal_approx(step, roundf(step)), "Edge %.2f sits on a step of the tally" % below)


func test_the_rows_show_each_bands_chroma_and_name_the_most_saturated() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var sits := page.row(&"saturation_sits")
    assert_eq(sits.value, Saturation.NOWHERE, "Before a run no band is named")
    var hint := page.row(&"saturation_shadows").line.get_node_or_null(^"Labels/Hint") as Label
    assert_not_null(hint, "and a band's row has the line its share will take")

    _halves(DARK_BLUE, LIGHT_GREY)
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    _part.follow(_easel.document)
    var shadows := page.row(&"saturation_shadows")
    var lights := page.row(&"saturation_lights")
    assert_eq(shadows.label, "Shadows", "The darkest row is the shadows")
    assert_true(absf(float(shadows.value) - CHROMA) <= 0.005, "and reads the blue's chroma, read %s" % str(shadows.value))
    assert_eq((shadows.control as Label).text, "0.12", "and shows it")
    assert_eq(shadows.explanation, "50 % of the canvas", "with its share under its title")
    if hint != null:
        assert_eq(hint.text, "50 % of the canvas", "on screen")
    assert_eq(lights.value, 0.0, "The lights read nought")
    assert_eq(sits.value, "Shadows", "The shadows are named the most saturated")
    assert_eq((sits.control as Label).text, "The most saturated paint is in the shadows.", "on screen")
    assert_eq(sits.label, "", "in a sentence with no title, so it spans the docker")
    assert_eq(Saturation.sits_words(-1), "No value holds saturated paint.", "and one says when none is")
    assert_false((shadows.control as Label).tooltip_text.is_empty(), "What is measured is on hover")
    var described: Dictionary = page.describe()
    assert_true(str(described).contains("saturation_sits"), "and the page describes the rows")
    box.free()


func test_the_rows_ask_for_frames_while_the_tally_is_on_its_way() -> void:
    var page := SaPage.new(_part.declare)
    page.declare_rows()
    var box := VBoxContainer.new()
    page.realize(box)
    var shadows := page.row(&"saturation_shadows")
    var words := shadows.control as Saturation.Readout
    _numbers().read_at_once = false
    _paint_chunk(Vector2i(0, 0), _stored(DARK_BLUE))
    _service.add(_part.reduction)
    assert_true(_stop(), "The clock fires")
    assert_eq(_numbers().waiting, 1, "The run asked the device for its tally")
    _part.follow(_easel.document)
    assert_eq(shadows.value, 0.0, "The rows wait for the answer")
    assert_true(words.is_processing(), "and their words ask for a frame each frame meanwhile")
    for frame in 8:
        if _numbers().waiting == 0:
            break
        words.notification(Node.NOTIFICATION_PROCESS)
        RenderingServer.force_draw(false, 0.0)
    assert_eq(_numbers().waiting, 0, "The device answered within a few frames")
    words.notification(Node.NOTIFICATION_PROCESS)
    assert_false(words.is_processing(), "and the asking stops once it is in")
    _part.follow(_easel.document)
    assert_true(float(shadows.value) > 0.0, "Then the rows show what came back")
    box.free()
