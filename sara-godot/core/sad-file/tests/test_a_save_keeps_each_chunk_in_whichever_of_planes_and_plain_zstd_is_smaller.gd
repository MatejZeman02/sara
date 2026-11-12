## A save keeps each blob in whichever of planes and plain
## Zstd comes out smaller, and a mask always plain. A document at half and at
## full precision holds a chunk where the planes win, a chunk where plain wins
## and a mask, and is saved in the background and at once. Each blob's stored
## size is the smaller of its two forms compressed alone, the transform is
## named only where the planes won, and every byte comes back.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

## The chunk of smooth paint, where the planes win.
const SMOOTH := Vector2i(0, 0)
## The chunk dithered between two far colours, where plain wins.
const DITHER := Vector2i(1, 0)
const POSITIONS: Array[Vector2i] = [SMOOTH, DITHER]

static var scratch: String = SaDataRoot.path("test_d39_smaller.sad")


func after_each() -> void:
    SaSadSave.finish_all()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## A field of *format*, *side* texels square: with *dithered* each texel is one
## of two colours far apart, chosen at random, and otherwise a ramp that
## crosses zero and white, smooth from one texel to the next. On the ramp each
## difference is small and its high byte planes nearly all zero, so the planes
## win. On the dither plain Zstd finds each texel a repeat of one of two, while
## the planes hold one of three differences a texel spread over every plane.
static func field(format: int, side: int, dithered: bool) -> PackedByteArray:
    var layout: Vector2i = SaSadBlob.LAYOUT[format]
    var rng := RandomNumberGenerator.new()
    rng.seed = 39
    var bytes := PackedByteArray()
    bytes.resize(side * side * layout.x * layout.y)
    var at := 0
    for y in side:
        for x in side:
            var pick := rng.randi() % 2
            for channel in layout.x:
                var value := sin(x * 0.011 + channel) * 1.7 + cos(y * 0.007 - channel) * 0.9
                if dithered:
                    value = 0.137 + channel * 0.21 if pick == 0 else 3.71 - channel * 0.53
                if layout.y == 2:
                    bytes.encode_half(at, value)
                else:
                    bytes.encode_float(at, value)
                at += layout.y
    return bytes


## A document of one layer at *depth* whose colour holds [constant SMOOTH] and
## [constant DITHER], and a mask, a field of both, that holds the ramp over
## the smooth chunk and rests at one over the other.
static func painted(depth: SaColorSpace.Depth) -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(depth))
    var layer := doc.active_layer
    layer.chunks.clear()
    for grid_pos in POSITIONS:
        var size := layer.get_or_create_chunk(grid_pos).pixel_size()
        var texture := layer.get_or_create_field(grid_pos)
        rd.texture_update(texture.rid, 0, field(texture.format, size, grid_pos == DITHER))
    layer.add_mask()
    var coverage := layer.get_field(SMOOTH, SaFieldSpec.MASK)
    rd.texture_update(coverage.rid, 0, field(coverage.format, coverage.size.x, false))
    return doc


## The texture's bytes as they lie and as planes, the two forms a save weighs.
static func forms(texture: SaTexture) -> Array[PackedByteArray]:
    var buffer := SaSadBlob.planes_buffer(SaSadBlob.plane_bytes(texture))
    SaSadBlob.planes_into(texture, buffer)
    return [texture.rd.texture_get_data(texture.rid, 0), buffer.read()]


## The header and the blob region of the file at *path*.
static func opened(path: String) -> Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return [{}, PackedByteArray()]
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    var header := SaTyped.strings(JSON.parse_string(text))
    var region := file.get_buffer(file.get_length() - file.get_position())
    file.close()
    return [header, region]


func test_half_precision_keeps_the_smaller_form_of_each_chunk() -> void:
    _saves_keep_the_smaller(SaColorSpace.Depth.F16, "half")


func test_full_precision_keeps_the_smaller_form_of_each_chunk() -> void:
    _saves_keep_the_smaller(SaColorSpace.Depth.F32, "full")


func _saves_keep_the_smaller(depth: SaColorSpace.Depth, named: String) -> void:
    var path := ProjectSettings.globalize_path(scratch)
    for background: bool in [true, false]:
        var how := "%s precision, saved %s" % [named, "in the background" if background else "at once"]
        var source := painted(depth)
        var layer := source.active_layer
        if background:
            SaSadSave.start(source, path, 0)
            assert_true(SaSadSave.finish_all(), "%s: the save ends" % how)
        else:
            assert_eq(SaSadFile.save_file(source, path, 0), OK, "%s: the save lands" % how)
        var file := opened(path)
        var header: Dictionary[String, Variant] = file[0]
        var region: PackedByteArray = file[1]
        var entry := SaTyped.strings((header.get("layers", []) as Array).back())
        var chunks: Array = entry.get("chunks", [])
        assert_eq(chunks.size(), 2, "%s: both chunks are written" % how)
        var won := {}
        var mask_slots: Dictionary[Vector2i, Dictionary] = {}
        for chunk: Variant in chunks:
            var chunk_entry := SaTyped.strings(chunk)
            var grid_pos := Vector2i(SaTyped.int_at(chunk_entry, "x", -1), SaTyped.int_at(chunk_entry, "y", -1))
            var slots := SaTyped.strings(chunk_entry.get("fields", {}))
            var slot := SaTyped.strings(slots.get("albedo", {}))
            if slots.has("mask"):
                mask_slots[grid_pos] = SaTyped.strings(slots["mask"])
            var two := forms(layer.get_field(grid_pos))
            var plain := two[0].compress(SaSadFile.SAD_BLOB_COMPRESS).size()
            var planes := two[1].compress(SaSadFile.SAD_BLOB_COMPRESS).size()
            var said := [how, grid_pos, plain, planes]
            var smaller := "%s: chunk %s is stored at the smaller of %d plain and %d planes" % said
            assert_eq(SaTyped.int_at(slot, "size", -1), mini(plain, planes), smaller)
            var transform_said := "%s: chunk %s names the transform only where the planes won" % said.slice(0, 2)
            assert_eq(SaSadBlob.is_planes(slot), planes < plain, transform_said)
            var kept := two[1] if planes < plain else two[0]
            assert_true(SaSadBlob.read(slot, region) == kept, "%s: chunk %s holds the form it names" % said.slice(0, 2))
            won[grid_pos] = planes < plain
        assert_eq(won.get(SMOOTH), true, "%s: the planes win on the smooth chunk" % how)
        assert_eq(won.get(DITHER), false, "%s: plain wins on the dithered chunk" % how)

        assert_eq(mask_slots.size(), 2, "%s: the mask writes a chunk under each chunk of paint" % how)
        for grid_pos: Vector2i in mask_slots:
            var mask_slot: Dictionary[String, Variant] = mask_slots[grid_pos]
            var mask_plain := forms(layer.get_field(grid_pos, SaFieldSpec.MASK))[0]
            assert_false(SaSadBlob.is_planes(mask_slot), "%s: the mask at %s is stored plain" % [how, grid_pos])
            assert_eq(
                SaTyped.int_at(mask_slot, "size", -1),
                mask_plain.compress(SaSadFile.SAD_BLOB_COMPRESS).size(),
                "%s: as its bytes compressed alone, with no planes weighed" % how
            )

        var reopened := SaDocument.new()
        assert_eq(SaExport.load_sad(reopened, path, SaCompositor.new()), OK, "%s: the file opens" % how)
        for grid_pos in POSITIONS:
            var back := reopened.active_layer.get_field(grid_pos)
            assert_true(
                back != null and back.rd.texture_get_data(back.rid, 0) == forms(layer.get_field(grid_pos))[0],
                "%s: every byte of chunk %s comes back" % [how, grid_pos]
            )
        for grid_pos in POSITIONS:
            var back_mask := reopened.active_layer.get_field(grid_pos, SaFieldSpec.MASK)
            var mask_was := forms(layer.get_field(grid_pos, SaFieldSpec.MASK))[0]
            assert_true(
                back_mask != null and back_mask.rd.texture_get_data(back_mask.rid, 0) == mask_was,
                "%s: every byte of the mask at %s comes back" % [how, grid_pos]
            )
        source.free()
        reopened.free()


func test_a_mask_of_its_own_is_stored_plain_too() -> void:
    var rd := GlobalShaderCompiler.get_rd()
    var mask := SaMask.own()
    var texture := mask.get_or_create(Vector2i(0, 0))
    rd.texture_update(texture.rid, 0, field(texture.format, texture.size.x, false))
    var blobs := PackedByteArray()
    var chunks: Array = SaSadFile.write_mask(mask, blobs, rd).get("chunks", [])
    assert_eq(chunks.size(), 1, "The mask writes its chunk")
    var slot: Dictionary[String, Variant] = SaTyped.strings(chunks[0]) if chunks.size() == 1 else {}
    assert_false(SaSadBlob.is_planes(slot), "stored plain")
    var alone := forms(texture)[0].compress(SaSadFile.SAD_BLOB_COMPRESS).size()
    assert_eq(SaTyped.int_at(slot, "size", -1), alone, "as its bytes compressed alone")
