## A save in the background keeps every chunk of a layer
## whose chunks are not the 256 texels across the planes kernels take.
## `SaSadSave.take` answered answering an empty slot for every blob it would
## store plain, which `SaSadFile.header_of` read as a texture that gave
## nothing, so the chunk was compressed into the file and left out of its
## header. Its own suite paints chunks at full size only.
##
## A document here holds a layer at the document's resolution and one of each
## kind the session can make whose chunks are another size: a layer at half
## resolution, which `SaLayerOps.add` makes at any scale and the save stores
## plain because only the card undoes planes, a layer at double resolution as
## New Layer at Double Resolution makes it, and a layer at a scale a file may
## name whose chunk side is no multiple of four, which `SaSadBlob.takes`
## refuses. Every chunk holds a pattern of its own, the document is saved in
## the background and opened, and every chunk reads back as it was painted,
## the half resolution layer's widened as the reader widens it.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const POSITIONS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]

## The layers the document holds, by name, at the scale each is made at.
const SCALES := {"Full": 1.0, "Half": 0.5, "Double": 2.0, "Odd": 1.01}

static var scratch: String = SaDataRoot.path("test_below_full.sad")


func after_each() -> void:
    SaSadSave.finish_all()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## A field of *format*, *side* texels square, of values drawn from the seed
## *drawn_from*, so no two chunks hold the same bytes and a chunk read back in
## another's place is told apart.
static func pattern(format: int, side: int, drawn_from: int) -> PackedByteArray:
    var layout: Vector2i = SaSadBlob.LAYOUT[format]
    var rng := RandomNumberGenerator.new()
    rng.seed = drawn_from
    var bytes := PackedByteArray()
    bytes.resize(side * side * layout.x * layout.y)
    for at in range(0, bytes.size(), layout.y):
        var value := rng.randf_range(-1.5, 3.5)
        if layout.y == 2:
            bytes.encode_half(at, value)
        else:
            bytes.encode_float(at, value)
    return bytes


static func named(doc: SaDocument, layer_name: String) -> SaLayer:
    for child in doc.get_children():
        if child is SaLayer and str(child.name) == layer_name:
            return child
    return null


## A document at half precision, which a save keeps to the bit, holding a
## layer of each scale of [constant SCALES], each chunk painted with its own
## pattern. Answers the document and the bytes each chunk was given, keyed
## by the layer's name and the chunk's place.
func painted() -> Array:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), space)
    doc.active_layer.name = "Full"
    doc.active_layer.chunks.clear()
    for layer_name: String in SCALES:
        if layer_name != "Full":
            SaLayerOps.new(doc).add(&"", null, SCALES[layer_name]).name = layer_name
    var given := {}
    var next_seed := 190
    for layer_name: String in SCALES:
        var layer := named(doc, layer_name)
        for grid_pos in POSITIONS:
            var chunk := layer.get_or_create_chunk(grid_pos)
            var side := chunk.pixel_size()
            var said := "%s: chunk %s is %d across" % [layer_name, grid_pos, side]
            assert_eq(side, roundi(SaChunk.SIZE * float(SCALES[layer_name])), said)
            var texture := chunk.albedo()
            var bytes := pattern(texture.format, side, next_seed)
            next_seed += 1
            rd.texture_update(texture.rid, 0, bytes)
            given[[layer_name, grid_pos]] = bytes
    return [doc, given]


func test_every_chunk_of_every_layer_comes_back_from_a_background_save() -> void:
    var path := ProjectSettings.globalize_path(scratch)
    var made := painted()
    var source: SaDocument = made[0]
    var given: Dictionary = made[1]
    var odd := named(source, "Odd").chunks[POSITIONS[0]].albedo()
    assert_false(SaSadBlob.takes(odd), "The odd layer's chunk is one the planes kernels do not take")

    var save := SaSadSave.start(source, path, 0)
    assert_true(SaSadSave.is_running(), "The save runs in the background rather than at once")
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(save.error, OK, "with no error")
    var copied := "having copied every chunk on the card, %d copies" % save.taken
    assert_true(save.taken >= SCALES.size() * POSITIONS.size(), copied)

    var reopened := SaDocument.new()
    assert_eq(SaExport.load_sad(reopened, path, SaCompositor.new()), OK, "The file opens")
    for layer_name: String in SCALES:
        var layer := named(reopened, layer_name)
        assert_not_null(layer, "with the layer %s" % layer_name)
        if layer == null:
            continue
        for grid_pos in POSITIONS:
            var scale: float = SCALES[layer_name]
            var bytes: PackedByteArray = given[[layer_name, grid_pos]]
            var expected := SaSadCoarseLayer.widened(bytes, scale)
            var chunk: SaChunk = layer.chunks.get(grid_pos)
            var said := "%s at %s: chunk %s" % [layer_name, scale, grid_pos]
            assert_not_null(chunk, "%s is in the file" % said)
            if chunk == null:
                continue
            var side := roundi(SaChunk.SIZE * SaSadCoarseLayer.chunk_scale(scale))
            assert_eq(chunk.pixel_size(), side, "%s opens %d across" % [said, side])
            var back := chunk.albedo()
            var read := back.rd.texture_get_data(back.rid, 0)
            assert_true(read == expected, "%s reads back every texel it was painted with" % said)
    source.free()
    reopened.free()
