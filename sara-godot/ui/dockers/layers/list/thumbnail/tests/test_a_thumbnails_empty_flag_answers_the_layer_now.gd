## A layer thumbnail's `empty` is the layer now, not the last redraw.
##
## Running a scenario through a file and through the door disagreed on one
## field only: `rows[0].thumb_rim.empty`. The
## thumbnail redraws a quarter of a second after `mark_dirty`, and `empty` read
## whether that redraw had happened, so a dump ten frames after a fill said
## empty and the door, slower per step, said painted, and after a clear the
## other way round. The report now takes a redraw that is still waiting before
## it answers. Both cases below fail with that one call taken out.
extends "res://tests/test_framework.gd"

## The redraw is a compute dispatch over the layer's chunks.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 256))
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    return easel


## `bind_layer` marks the picture dirty and leaves the redraw to the next frame
## past the interval, which a test never runs, so this is the dump a scenario
## takes the moment after a fill.
func test_a_painted_layer_reads_painted_before_the_interval_passes() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), doc.active_layer)

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(doc.active_layer, doc)
    assert_null(thumb._texture, "nothing has redrawn the picture yet")

    var report := thumb.rim_report()
    assert_false(bool(report["empty"]), "and the report still says the layer holds paint")
    assert_not_null(thumb._texture, "because it took the redraw that was waiting")
    thumb.free()
    easel.free()


## The other direction: a picture drawn, then the paint gone and the redraw not
## yet due. The old report read the texture the last redraw left.
func test_a_cleared_layer_reads_empty_before_the_interval_passes() -> void:
    var easel := _easel()
    var doc := easel.document
    var layer := doc.active_layer
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), layer)

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(layer, doc)
    thumb.refresh()
    assert_not_null(thumb._texture, "the painted layer has a picture")

    layer.release_chunks()
    thumb.mark_dirty()
    assert_true(bool(thumb.rim_report()["empty"]), "and once its paint is gone the report says so at once")
    thumb.free()
    easel.free()


## A report with nothing waiting redraws nothing, so a dump of a docker full of
## rows does not dispatch a kernel per row every time it is taken.
func test_a_report_with_no_redraw_waiting_leaves_the_picture_alone() -> void:
    var easel := _easel()
    var doc := easel.document
    doc.fill_layer(Color(0.9, 0.2, 0.1, 1.0), doc.active_layer)

    var thumb := SaLayerThumbnail.new()
    thumb.bind_layer(doc.active_layer, doc)
    thumb.rim_report()
    var picture: SaTexture = thumb._texture

    doc.active_layer.release_chunks()
    assert_false(bool(thumb.rim_report()["empty"]), "nothing marked the picture dirty, so the last redraw stands")
    assert_true(thumb._texture == picture, "and it is the same texture rather than a new one")
    thumb.free()
    easel.free()
