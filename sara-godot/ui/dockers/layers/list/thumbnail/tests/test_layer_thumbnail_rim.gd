## The rim around a layer row's picture.
##
## The preview has a rim so there is no empty space when the layer is empty. An empty layer draws no picture at all, so its slot
## in the row was background-coloured pixels with nothing marking the edge, and
## the row read as a gap between the eye and the name.
##
## The rim is geometry rather than a picture, so it is asserted here without a
## GPU. What it looks like on a real row is the scenario layer-preview-rim.
extends "res://tests/test_framework.gd"

## Wider than it is tall, the way a default document is, so a rim that framed
## the whole control rather than the picture would be caught by the height.
const CANVAS := Vector2i(1920, 1080)

## A portrait document, to prove the rim follows the aspect rather than being
## one fixed box.
const TALL := Vector2i(1000, 2000)


## A thumbnail bound to an empty layer of a document that size. The document and
## the layer are built by hand rather than through an easel, because the rim is
## geometry and nothing here wants a compositor or a GPU.
func _thumb(canvas: Vector2i, is_group: bool = false) -> SaLayerThumbnail:
    var document := SaDocument.new()
    document.canvas_size = canvas
    var layer := SaLayer.new()
    layer.is_group = is_group
    document.add_child(layer)
    document.active_layer = layer
    var thumb := SaLayerThumbnail.new()
    thumb.size = Vector2(SaUI.pxf(SaLayerThumbnail.BOX.x), SaUI.pxf(SaLayerThumbnail.BOX.y))
    thumb.bind_layer(layer, document)
    thumb.set_meta("document", document)
    return thumb


## The thumbnail owns nothing but its own node, so the document it was pointed at
## is freed beside it and the suite's leak count stays at zero.
func _drop(thumb: SaLayerThumbnail) -> void:
    var document: SaDocument = thumb.get_meta("document")
    thumb.free()
    document.free()


func test_an_empty_layer_still_has_a_rim() -> void:
    var thumb := _thumb(CANVAS)
    var report := thumb.rim_report()

    assert_true(bool(report["empty"]), "the layer holds no paint, so there is no picture")
    assert_true(float(report["w"]) > 2.0, "and the rim is still a rectangle with width")
    assert_true(float(report["h"]) > 2.0, "and with height")
    assert_true(float(report["width"]) > 0.0, "drawn in a line thick enough to see")
    _drop(thumb)


## The rim frames the picture's own slot. A 16:9 document fitted into a box that
## is 32 by 22 logical units is as wide as the box and shorter than it, so a rim
## as tall as the control would be a rim around empty space rather than around
## the preview.
func test_the_rim_is_the_document_aspect_rather_than_the_control() -> void:
    var thumb := _thumb(CANVAS)
    var rim := thumb.rim_rect()

    var aspect := rim.size.x / rim.size.y
    assert_almost_eq(aspect, 1920.0 / 1080.0, 0.02, "the rim carries the document's aspect")
    assert_true(rim.size.y < thumb.size.y - 1.0, "and is shorter than the control it sits in")
    _drop(thumb)


func test_a_portrait_document_gets_a_portrait_rim() -> void:
    var thumb := _thumb(TALL)
    var rim := thumb.rim_rect()

    assert_true(rim.size.y > rim.size.x, "a document taller than it is wide gets a rim to match")
    assert_almost_eq(rim.size.x / rim.size.y, 0.5, 0.02, "at the document's own ratio")
    _drop(thumb)


## The rim is centred in the room it has, the same way the picture is, or the two
## would not line up.
func test_the_rim_is_centred_in_the_control() -> void:
    var thumb := _thumb(CANVAS)
    var rim := thumb.rim_rect()

    assert_almost_eq(rim.position.x * 2.0 + rim.size.x, thumb.size.x, 0.51, "centred across")
    assert_almost_eq(rim.position.y * 2.0 + rim.size.y, thumb.size.y, 0.51, "and down")
    _drop(thumb)


## A group has no chunks and so never has a picture, which is the empty case
## permanently. Its folder mark is drawn inside the rim rather than beside it.
func test_a_group_row_carries_the_rim_too() -> void:
    var thumb := _thumb(CANVAS, true)
    var report := thumb.rim_report()

    assert_true(bool(report["group"]), "the row is a group's")
    assert_true(float(report["w"]) > 2.0, "and it has a rim like every other row")
    _drop(thumb)


## A control that has not been laid out yet reports no rim rather than a
## rectangle turned inside out by the inset, which is what `_draw` checks before
## drawing. A row is built before the container gives it its size, so this is the
## first state every thumbnail passes through and not a contrived one.
func test_a_control_with_no_room_reports_no_rim() -> void:
    var thumb := SaLayerThumbnail.new()

    assert_eq(thumb.size, Vector2.ZERO, "a control nothing has laid out has no room")
    assert_eq(thumb.rim_rect().size, Vector2.ZERO, "so nothing is framed")
    thumb.free()


## The rim reads the loaded palette rather than a colour written into this file,
## so a theme the painter picks takes it along.
func test_the_rim_takes_its_colour_from_the_palette() -> void:
    var thumb := _thumb(CANVAS)

    assert_eq(thumb.rim_color(), SaTheme.palette.border_secondary, "the muted border of the palette")
    _drop(thumb)
