## The clipboard is shared between open documents, so a region
## copied in one painting pastes into another, converted from the source's
## colour space to the target's, and a copy outlives its document being closed.
##
## The source is an sRGB document painted with a gradient that differs at every
## texel, so a paste that lands one texel off or skips the conversion reads
## wrong rather than plausibly right. The target is a Display P3 document. What
## the paste must hold is worked out on the CPU from the source's texels: the
## sRGB curve taken off, the sRGB to Display P3 matrix, and the Display P3 curve,
## which is the sRGB one, put back on.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

const CANVAS := Vector2i(512, 512)

## Across all four chunks, so the copy and the paste cross chunk edges.
const REGION := Rect2i(200, 180, 150, 120)

## The largest difference allowed between a pasted texel and the CPU's
## conversion of the source's. Float32 on both sides, the GPU's pow against the
## CPU's. The largest found was 5.4e-7, and each run prints its own.
const BOUND := 1.0e-5

var _documents: SaDocuments = null
var _source: SaSurface = null
var _target: SaSurface = null


func before_each() -> void:
    _documents = SaDocuments.new()
    _source = Fixtures.make_surface(CANVAS)
    _source.easel.document.reset_to_default(CANVAS, SaColorSpace.srgb())
    _target = Fixtures.make_surface(CANVAS)
    _target.easel.document.reset_to_default(CANVAS, SaColorSpace.display_p3())
    _documents.add(_source)
    _documents.add(_target)


func after_each() -> void:
    for surface: SaSurface in [_source, _target]:
        if surface != null and surface.easel != null and is_instance_valid(surface.easel):
            Fixtures.teardown(surface)
    _source = null
    _target = null
    _documents = null


## Every texel of the source's active layer a colour of its own: red across,
## green down, a constant blue, opaque, written straight into each chunk.
func _paint_gradient(document: SaDocument) -> void:
    var layer := document.active_layer
    layer.fill(Color(0.0, 0.0, 0.0, 1.0))
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var side := chunk.pixel_size()
        var picture := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
        for y in side:
            for x in side:
                var at := grid_pos * side + Vector2i(x, y)
                picture.set_pixel(x, y, _painted(at))
        rd.texture_update(layer.get_field(grid_pos).rid, 0, picture.get_data())


func _painted(at: Vector2i) -> Color:
    return Color(float(at.x) / CANVAS.x, float(at.y) / CANVAS.y, 0.35, 1.0)


## What the source's colour at *at* is once it is moved into Display P3.
func _converted(at: Vector2i) -> Color:
    var from := SaColorSpace.srgb()
    var to := SaColorSpace.display_p3()
    var painted := _painted(at)
    var light := Vector3(from.transfer.decode(painted.r), from.transfer.decode(painted.g), from.transfer.decode(painted.b))
    var moved: Vector3 = from.to_space_matrix(to) * light
    return Color(to.transfer.encode(moved.x), to.transfer.encode(moved.y), to.transfer.encode(moved.z), painted.a)


## Every texel of *layer* inside *area*, keyed by document pixel.
func _texels(layer: SaLayer, area: Rect2i) -> Dictionary[Vector2i, Color]:
    var read: Dictionary[Vector2i, Color] = {}
    var rd := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var side := chunk.pixel_size()
        var texture := layer.get_field(grid_pos)
        var bytes := rd.texture_get_data(texture.rid, 0)
        var reach := Rect2i(grid_pos * side, Vector2i(side, side)).intersection(area)
        for y in range(reach.position.y, reach.end.y):
            for x in range(reach.position.x, reach.end.x):
                var local := Vector2i(x, y) - grid_pos * side
                read[Vector2i(x, y)] = SaFieldSpec.decode_texel(bytes, texture.format, local.y * side + local.x)
    return read


## The largest channel difference between the pasted texels and the CPU's
## conversion, and where it is.
func _worst(pasted: Dictionary[Vector2i, Color]) -> Array:
    var worst := 0.0
    var where := Vector2i(-1, -1)
    for at: Vector2i in pasted:
        var want := _converted(at)
        var got: Color = pasted[at]
        for i in 4:
            var off := absf(got[i] - want[i])
            if off > worst:
                worst = off
                where = at
    return [worst, where]


func _copy_region() -> void:
    var document := _source.easel.document
    _paint_gradient(document)
    document.selection.select_rect(REGION)
    assert_true(_documents.clipboard.copy(document, document.active_layer) > 0, "Copy in the sRGB document took the region")


func _paste_into_target() -> SaLayer:
    var target := _target.easel.document
    var layer := _documents.clipboard.paste(target)
    assert_not_null(layer, "Paste in the Display P3 document made a layer")
    return layer


func test_a_region_copied_in_srgb_pastes_into_display_p3_converted() -> void:
    _copy_region()
    assert_true(_documents.bring_to_front(_target), "The Display P3 document comes to the front")
    var layer := _paste_into_target()
    if layer == null:
        return
    var pasted := _texels(layer, REGION)
    assert_eq(pasted.size(), REGION.get_area(), "Every texel of the region was pasted")
    var worst := _worst(pasted)
    var largest := "%s at %s" % [String.num_scientific(float(worst[0])), worst[1]]
    print("largest difference between the pasted texels and the conversion, %s" % largest)
    assert_true(float(worst[0]) <= BOUND, "The paste holds the source converted, worst %s" % largest)
    var plain := _painted(REGION.position + Vector2i(100, 50))
    var moved: Color = pasted[REGION.position + Vector2i(100, 50)]
    assert_true(absf(plain.r - moved.r) > 1.0e-2, "and it is not the sRGB numbers carried over unconverted")
    var outside := _texels(layer, Rect2i(REGION.position - Vector2i(4, 4), Vector2i(3, 3)))
    for at: Vector2i in outside:
        assert_almost_eq((outside[at] as Color).a, 0.0, 1.0e-6, "and nothing outside the region at %s" % at)


func test_a_copy_outlives_its_document_being_closed() -> void:
    _copy_region()
    var before := _texels(_paste_into_target(), REGION)
    assert_true(_documents.remove(_source), "The sRGB document closes")
    Fixtures.teardown(_source)
    _source = null
    assert_eq(_documents.surfaces, [_target] as Array[SaSurface], "leaving the Display P3 one alone")
    assert_false(_documents.clipboard.is_empty(), "The clipboard still holds the copy")
    var layer := _paste_into_target()
    if layer == null:
        return
    var after := _texels(layer, REGION)
    assert_eq(after.size(), before.size(), "The second paste covers the region")
    var differing := 0
    for at: Vector2i in before:
        if after.get(at, Color()) != before[at]:
            differing += 1
    assert_eq(differing, 0, "and holds the same texels as the paste before the close")
    assert_true(float(_worst(after)[0]) <= BOUND, "which are the source converted")


## The app's host holds the owner as `documents`, and the clipboard is the
## owner's, so every open document reaches one clipboard.
func test_the_clipboard_is_the_owners_and_the_host_reaches_it() -> void:
    var host := Host.new()
    host.documents = _documents
    assert_eq(SaDocuments.clipboard_in(host), _documents.clipboard, "The host's owner holds the clipboard")
    var bare := Node.new()
    assert_null(SaDocuments.clipboard_in(bare), "and a host with no owner holds none")
    bare.free()
    host.free()


class Host:
    extends Node
    var documents: SaDocuments = null
