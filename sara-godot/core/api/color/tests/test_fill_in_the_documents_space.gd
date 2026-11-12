## Fill with Foreground writes the document's own numbers, not the screen's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The note, 2026-09-09 on the desktop: Ctrl+Backspace filled the canvas with an
## orange, with a grey-purple foreground selected (#a7a2ae), on an Oklab over
## Display P3 document, and the eyedropper read 1.864, -1.021, -0.432 back. The
## fill handed `SaColors.foreground` straight to the layer, so the three display
## numbers were written as L, a and b, and an Oklab of (0.654, 0.634, 0.681) is
## a saturated orange whose display value is exactly that reading.
##
## Under an sRGB document `from_display` is an exact passthrough, which is why
## the bug never showed offscreen and why half of this suite is the sRGB case
## unchanged: a fix that converted twice, or that converted where it should not,
## would move those numbers.
##
## The thumbnail's own half is `scenarios/fill-in-the-documents-space.json`,
## because a `SaLayerThumbnail` needs a docker row around it and the picture is a
## `Texture2DRD` the running app draws.
extends "res://tests/test_framework.gd"

## Fills allocate real chunks and the readback is a real `texture_copy`.
const REQUIRES_GPU := true

## A painter's own foreground, from the note.
const GREY_PURPLE := Color(0.654, 0.634, 0.681, 1.0)

## What the note grades on: a hundredth per channel.
const EPSILON := 0.01

## The eyedropper's reading of the bug, from the note. Asserted against so the
## suite fails loudly if the conversion is ever dropped again rather than
## quietly passing on a colour nobody looked at.
const THE_BUG := Color(1.864, -1.021, -0.432, 1.0)


func _document(space: SaColorSpace) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)
    return doc


## The active layer's texel at the origin, as the eyedropper hands it to the
## colour wheel: read off the albedo field, then through `to_display`.
func _picked(doc: SaDocument) -> Color:
    return doc.color_space.to_display(_stored(doc))


## The same texel before that conversion, which is what the document holds.
func _stored(doc: SaDocument) -> Color:
    var layer := doc.active_layer
    var albedo: SaTexture = layer.get_field(Vector2i(0, 0))
    assert_not_null(albedo, "The fill allocated a chunk at the origin")
    var rd := GlobalShaderCompiler.get_rd()
    return SaFieldSpec.decode_texel(rd.texture_get_data(albedo.rid, 0), albedo.format)


# --- The note's own document --------------------------------------------------


func test_a_fill_on_an_oklab_p3_document_reads_back_as_the_colour_that_was_picked() -> void:
    var doc := _document(SaColorSpace.oklab_p3())

    doc.fill_layer(GREY_PURPLE)

    var picked := _picked(doc)
    assert_almost_eq(picked.r, GREY_PURPLE.r, EPSILON, "red comes back")
    assert_almost_eq(picked.g, GREY_PURPLE.g, EPSILON, "green comes back")
    assert_almost_eq(picked.b, GREY_PURPLE.b, EPSILON, "blue comes back")
    assert_almost_eq(picked.a, 1.0, EPSILON, "and alpha is coverage, carried through")

    doc.free()


## The other half of the same claim: what is *stored* is Oklab, not the screen's
## three numbers. Without this a fill that converted on the way out and not on
## the way in would pass the round trip above.
func test_the_stored_texel_is_the_documents_own_coordinates() -> void:
    var space := SaColorSpace.oklab_p3()
    var doc := _document(space)

    doc.fill_layer(GREY_PURPLE)

    var stored := _stored(doc)
    var wanted := space.from_display(GREY_PURPLE)
    assert_almost_eq(stored.r, wanted.r, EPSILON, "L is stored")
    assert_almost_eq(stored.g, wanted.g, EPSILON, "a is stored")
    assert_almost_eq(stored.b, wanted.b, EPSILON, "b is stored")
    assert_true(absf(stored.r - GREY_PURPLE.r) > EPSILON, "and it is not the display value, which is the whole bug")

    doc.free()


## The reading the note carries, kept as the shape of the failure rather than as
## prose. `to_display` of the display numbers read as Oklab is the orange the
## author saw, and that is what the fill used to leave behind.
##
## Read through the sRGB-gamut Oklab preset. The note was taken while
## the picker spoke sRGB in every document, and a picked triple has meant the
## document's own gamut since, so P3's would move the reading off what was seen.
func test_the_note_reading_is_what_writing_display_numbers_as_oklab_gives() -> void:
    var space := SaColorSpace.oklab()

    var as_if_stored_raw := space.to_display(GREY_PURPLE)

    assert_almost_eq(as_if_stored_raw.r, THE_BUG.r, EPSILON, "red past one, as the eyedropper read it")
    assert_almost_eq(as_if_stored_raw.g, THE_BUG.g, EPSILON, "green below zero")
    assert_almost_eq(as_if_stored_raw.b, THE_BUG.b, EPSILON, "and blue below zero")


# --- The document the bug never showed on --------------------------------------


func test_an_srgb_fill_is_unchanged_because_the_conversion_is_a_passthrough() -> void:
    var space := SaColorSpace.srgb()
    var doc := _document(space)

    assert_true(space.is_display_ready(), "sRGB is what the screen wants already")
    doc.fill_layer(GREY_PURPLE)

    var stored := _stored(doc)
    assert_almost_eq(stored.r, GREY_PURPLE.r, EPSILON, "the texel is the colour that was picked")
    assert_almost_eq(stored.g, GREY_PURPLE.g, EPSILON, "on every channel")
    assert_almost_eq(stored.b, GREY_PURPLE.b, EPSILON, "unconverted")

    doc.free()


## A linear document is the third case and the one that shows the conversion is
## the space's own rather than an Oklab branch: mid grey from the wheel means
## 0.214 there, which is the paragraph `from_display` carries.
func test_a_linear_document_takes_the_curve_and_not_the_coordinates() -> void:
    var space := SaColorSpace.linear_srgb()
    var doc := _document(space)

    doc.fill_layer(Color(0.5, 0.5, 0.5, 1.0))

    var stored := _stored(doc)
    assert_almost_eq(stored.r, 0.214, EPSILON, "mid grey lands where it means")
    assert_almost_eq(_picked(doc).r, 0.5, EPSILON, "and comes back as the half it was picked as")

    doc.free()


# --- What the conversion must not touch ----------------------------------------


## Alpha is coverage, never colour, so the clear branch has to read the same
## whichever space the document is in: a fill of transparent still releases the
## chunks rather than allocating a grid of Oklab zeroes.
func test_clearing_an_oklab_document_still_empties_the_layer() -> void:
    var doc := _document(SaColorSpace.oklab_p3())
    doc.fill_layer(GREY_PURPLE)
    assert_true(doc.active_layer.chunks.size() > 0, "The fill allocated the grid")

    doc.clear_layer()

    assert_eq(doc.active_layer.chunks.size(), 0, "and the clear released it")

    doc.free()


## The generated background takes the same path and had the same bug, which the
## note names. Its colour lives in `generator_params` and
## `SaGeneratedLayer.paint_view` converts it out again, so what is stored there
## is a working-space value like any texel.
##
## The layer is built here rather than through the type registry, which needs an
## easel and a context: a generated layer is one that names a kernel, and naming
## one is all `fill_layer`'s branch asks.
func test_the_generated_background_stores_the_converted_colour() -> void:
    var space := SaColorSpace.oklab_p3()
    var doc := _document(space)
    var paper := SaLayer.new()
    paper.name = "Paper"
    paper.generator = "background"
    paper.generator_params = {"color": Color(0.5, 0.5, 0.5, 1.0)}
    doc.add_child(paper)
    assert_true(paper.is_generated(), "It stores nothing and names a kernel")

    doc.fill_layer(GREY_PURPLE, paper)

    var params: Color = paper.generator_params.get("color", Color.BLACK)
    var wanted := space.from_display(GREY_PURPLE)
    assert_almost_eq(params.r, wanted.r, EPSILON, "L on the background's params")
    assert_almost_eq(params.g, wanted.g, EPSILON, "a")
    assert_almost_eq(params.b, wanted.b, EPSILON, "b")
    assert_almost_eq(space.to_display(params).r, GREY_PURPLE.r, EPSILON, "and the view converts it back out")

    doc.free()
