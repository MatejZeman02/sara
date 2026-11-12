## A previewed point filter reads its chunk's document corner.
##
## Apply, the attached chain and the flatten are handed each chunk's
## document corner, and a preview left at zero showed a dither that
## repeated per chunk with Preview ticked. The fixture kernel writes its texel's
## place plus the corner into red and green, so one local place in two chunks
## reads a chunk's side apart when the corner arrives, and alike when it does
## not. The canvas preview and the browser's picture are read here, as
## `test_a_point_kernel_reads_its_chunks_document_corner.gd` reads Apply.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

## The fixture's folder, which the shader index files the corner kernel under.
const OWNER: StringName = &"point-fixture"

var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _easel = Bench.easel(Vector2i(2 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    _doc = _easel.document
    _doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    Bench.composite(_easel)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


func _record() -> SaFilterContext:
    var ctx := SaFilterContext.new(_doc, _doc.active_layer, OWNER, "Corner", true)
    ctx.point_pass("corner", "corner", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
    return ctx


## Reads *at*, its chunk right of it and the one below, and checks the three
## are a chunk's side apart, which is the corner arriving.
func _check_apart(picture: SaTexture, at: Vector2i, where: String) -> void:
    var side := SaChunk.SIZE
    var first := Bench.texel(picture, at)
    var across := Bench.texel(picture, at + Vector2i(side, 0))
    var down := Bench.texel(picture, at + Vector2i(0, side))
    assert_almost_eq(first.r, float(at.x), 1e-2, "%s: the first chunk's texel is at its document place: %s" % [where, first])
    assert_almost_eq(across.r - first.r, float(side), 1e-2, "%s: the chunk across is a side on: %s" % [where, across])
    assert_almost_eq(across.g, first.g, 1e-2, "%s: at the same height" % where)
    assert_almost_eq(down.g - first.g, float(side), 1e-2, "%s: and the chunk below a side down: %s" % [where, down])


func test_the_canvas_preview_hands_each_chunk_its_corner() -> void:
    var ctx := _record()
    assert_not_null(ctx.point, "The run recorded a pass")
    _easel.compositor.point_preview.set_pass(_doc, ctx.point)
    Bench.composite(_easel)
    _check_apart(_easel.output, Vector2i(10, 20), "canvas preview")
    var layer := Bench.texel(_doc.active_layer.get_field(Vector2i(1, 0)), Vector2i(10, 20))
    assert_almost_eq(layer.r, 0.5, 1e-6, "while the layer is what it was: %s" % layer)
    _easel.compositor.point_preview.clear(_doc)


func test_the_browser_preview_hands_each_chunk_its_corner() -> void:
    var ctx := _record()
    var picture := SaFilterBrowser.PassPicture.evaluate(ctx)
    assert_not_null(picture, "The browser has a picture")
    if picture == null:
        return
    assert_eq(ctx.rect.position, Vector2i.ZERO, "over the whole document, so a picture texel is a document pixel")
    _check_apart(picture, Vector2i(10, 20), "browser preview")
