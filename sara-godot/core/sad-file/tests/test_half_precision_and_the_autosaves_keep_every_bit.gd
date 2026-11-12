## What the painter did not ask to be rounded keeps every bit.
## A half precision document saved as the painter saves writes its colour as
## the card holds it and reopens equal bit for bit, since a half has 11
## significant bits and every one shows. A full precision document saved by
## the autosave, to the recovery copy and to the working file, reopens with its
## colour rounded as a Ctrl+S rounds it.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const Rounding = preload("res://core/sad-file/tests/test_a_full_precision_save_rounds_colour_to_12_significant_bits_once.gd")

static var scratch: String = SaDataRoot.path("test_kept.sad")

var _autosave: SaAutosave = null


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    for path: String in [scratch, scratch + "1", SaAutosave.recovery_path_for(scratch)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A document of one layer at *depth*, its colour over two chunks random from
## below zero to above one, written on the card.
static func painted(depth: SaColorSpace.Depth) -> SaDocument:
    var rd := GlobalShaderCompiler.get_rd()
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(depth))
    var rng := RandomNumberGenerator.new()
    rng.seed = 141
    for grid_pos in Rounding.POSITIONS:
        var colour := doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.ALBEDO)
        var layout: Vector2i = SaSadBlob.LAYOUT[colour.format]
        var bytes := PackedByteArray()
        bytes.resize(colour.size.x * colour.size.y * layout.x * layout.y)
        for at in range(0, bytes.size(), layout.y):
            if layout.y == 2:
                bytes.encode_half(at, rng.randf_range(-3.0, 7.0))
            else:
                bytes.encode_float(at, rng.randf_range(-3.0, 7.0))
        rd.texture_update(colour.rid, 0, bytes)
    return doc


## The colour of *doc*'s active layer at each position, as the card holds it.
static func colour_of(doc: SaDocument) -> Dictionary:
    return Rounding.fields_of(doc)[SaFieldSpec.ALBEDO]


func test_a_half_precision_save_writes_the_card_s_bytes_and_reopens_equal() -> void:
    var source := painted(SaColorSpace.Depth.F16)
    var rd := GlobalShaderCompiler.get_rd()
    var before := colour_of(source)
    assert_true(Rounding.save_as_the_painter(source, scratch), "The painter's save lands")
    var file := _opened(scratch)
    var header: Dictionary[String, Variant] = file[0]
    var region: PackedByteArray = file[1]
    var entry := SaTyped.strings((header.get("layers", []) as Array).back())
    var met := 0
    for chunk: Variant in entry.get("chunks", []):
        var chunk_entry := SaTyped.strings(chunk)
        var grid_pos := Vector2i(SaTyped.int_at(chunk_entry, "x", -1), SaTyped.int_at(chunk_entry, "y", -1))
        var slot := SaTyped.strings(SaTyped.strings(chunk_entry.get("fields", {})).get("albedo", {}))
        var stored := SaSadBlob.read(slot, region)
        var texture := source.active_layer.get_field(grid_pos)
        var card := rd.texture_get_data(texture.rid, 0)
        if SaSadBlob.is_planes(slot):
            var buffer := SaSadBlob.planes_buffer(SaSadBlob.plane_bytes(texture))
            SaSadBlob.planes_into(texture, buffer)
            card = buffer.read()
        assert_eq(stored, card, "The colour of chunk %s, decompressed, is the card's bytes unchanged" % grid_pos)
        met += 1
    assert_eq(met, Rounding.POSITIONS.size(), "and the file holds every painted chunk")
    var back := Rounding.reopened(scratch)
    assert_eq(colour_of(back), before, "The reopened document equals the painted one bit for bit")
    source.free()
    back.free()


func test_the_recovery_copy_rounds_full_precision_colour_as_a_save_does() -> void:
    var source := painted(SaColorSpace.Depth.F32)
    _autosave = _autosave_of(source)
    source.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for the recovery copy")
    assert_true(SaSadFile.finish_saves(), "and it ends")
    var path := _autosave.last_written
    assert_true(FileAccess.file_exists(path), "The recovery copy is on disk")
    _reads_as_painted(source, path, "The recovery copy")
    source.free()


func test_the_working_file_written_by_the_autosave_rounds_full_precision_colour_as_a_save_does() -> void:
    var source := painted(SaColorSpace.Depth.F32)
    source.file_path = scratch
    _autosave = _autosave_of(source)
    _autosave.write_working_file = true
    source.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for the working file")
    assert_true(SaSadFile.finish_saves(), "and it ends")
    assert_true(FileAccess.file_exists(scratch), "The working file is on disk")
    _reads_as_painted(source, scratch, "The working file")
    source.free()


func _reads_as_painted(source: SaDocument, path: String, what: String) -> void:
    var back := Rounding.reopened(path)
    assert_not_null(back, "%s opens" % what)
    if back != null:
        var rounded := {}
        var painted_colour := colour_of(source)
        for grid_pos: Variant in painted_colour:
            var bytes: PackedByteArray = (painted_colour[grid_pos] as PackedByteArray).duplicate()
            for at in range(0, bytes.size(), 4):
                bytes.encode_u32(at, SaSadSnapshot.round_bits(bytes.decode_u32(at)))
            rounded[grid_pos] = bytes
        assert_eq(colour_of(back), rounded, "%s reopens with its colour rounded as a Ctrl+S rounds it" % what)
        back.free()


static func _autosave_of(doc: SaDocument) -> SaAutosave:
    var autosave := SaAutosave.new()
    autosave.follow_settings = false
    autosave.attach(doc)
    return autosave


## The header and the blob region of the file at *path*.
static func _opened(path: String) -> Array:
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
