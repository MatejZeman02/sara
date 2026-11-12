## The open decodes JPEG XL on a pool, then uploads. A half
## precision document of more chunks than `SaSadCodec.Open.WINDOW`, each with
## colour and a height, is saved once by Ctrl+S and once as JPEG XL, and both
## files are opened. Every texture of the JPEG XL copy reads equal to the Zstd
## copy's, so the window let no chunk go unuploaded nor one land in another's
## texture. The open of each still leaves `SaSadSnapshot` its record of every
## blob it filled: the Zstd copy's first Ctrl+S with nothing painted copies
## every blob and compresses none, and so does the JPEG XL copy's, which keeps
## the file's codec now and copies every coded blob as it lies.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

## Seven chunks by six, 42 chunks of at least two coded fields, above the window.
const GRID := Vector2i(7, 6)
const FIELDS: Array[StringName] = [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]

static var zstd: String = SaDataRoot.path("test_zstd.sad")
static var coded: String = SaDataRoot.path("test_coded.sad")

var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null
## The easels the opens read into, freed after each case.
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _registries.register_builtins()
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))


func after_each() -> void:
    SaSadFile.finish_saves()
    SaCodecRegistry.install(_was_installed)
    _was_installed = null
    _registries = null
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path: String in [zstd, coded]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Registers the JPEG XL module into the suite's registries as the loader does,
## false when its library is not built here.
func _load_the_module() -> bool:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return SaCodecRegistry.shared().named(CODEC) != null


## A half precision document whose one layer holds colour and a height in every
## chunk of [constant GRID], each chunk's bytes its own.
func _painted() -> SaDocument:
    var doc := SaDocument.new()
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    doc.setup_default_document(GRID * SaChunk.SIZE, SaCompositor.new(), space)
    var layer := doc.active_layer
    var fields: Array[SaFieldSpec] = [SaFieldSpec.albedo(space.texel_format()), SaFieldSpec.height()]
    layer.schema = fields
    layer.chunks.clear()
    var patterns: Dictionary[int, PackedByteArray] = {}
    var rd := GlobalShaderCompiler.get_rd()
    var number := 0
    for y in GRID.y:
        for x in GRID.x:
            layer.get_or_create_chunk(Vector2i(x, y))
            for field_id in FIELDS:
                var texture := layer.get_or_create_field(Vector2i(x, y), field_id)
                if not patterns.has(texture.format):
                    patterns[texture.format] = _pattern(texture)
                var bytes := patterns[texture.format].duplicate()
                # The chunk's number in its first texel and a row of its own,
                # so a chunk uploaded into another's texture reads unequal.
                bytes.encode_u32(0, number)
                for at in range(number * 64, number * 64 + 64):
                    bytes[at] = number & 0xff
                number += 1
                rd.texture_update(texture.rid, 0, bytes)
    return doc


## Smooth values and busy ones from below zero to above one, a texture's worth.
static func _pattern(texture: SaTexture) -> PackedByteArray:
    var layout: Vector2i = SaSadCodec.LAYOUT[texture.format]
    var rng := RandomNumberGenerator.new()
    rng.seed = 205
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * layout.x * layout.y)
    var at := 0
    while at < bytes.size():
        var texel := floori(at / float(layout.x * layout.y))
        var value := sin(texel * 0.01) * 1.5 if texel % 5 != 0 else rng.randf_range(-0.5, 2.0)
        if layout.y == 2:
            bytes.encode_half(at, value)
        else:
            bytes.encode_float(at, value)
        at += layout.y
    return bytes


## Every texture of *doc*'s painted layers by its chunk and field.
static func _textures(doc: SaDocument) -> Dictionary[String, PackedByteArray]:
    var rd := GlobalShaderCompiler.get_rd()
    var found: Dictionary[String, PackedByteArray] = {}
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null or layer == doc.stroke_layer:
            continue
        for grid_pos: Vector2i in layer.chunks:
            for field_id: StringName in layer.chunks[grid_pos].fields:
                var texture := layer.get_field(grid_pos, field_id)
                if texture != null:
                    found["%s %s %s" % [layer.name, grid_pos, field_id]] = rd.texture_get_data(texture.rid, 0)
    return found


## The document at *path*, opened as File > Open opens it, its history
## emptied and the path named, or null when it would not open.
func _opened(path: String) -> SaDocument:
    var easel := SaEasel.create_default(GRID * SaChunk.SIZE)
    _easels.append(easel)
    var doc := easel.document
    if SaExport.load_sad(doc, path) != OK:
        return null
    doc.undo_redo.clear_history()
    doc.history.reset()
    doc.mark_saved(path)
    return doc


## A Ctrl+S of *doc* to *path*, ended, or null when it did not start or end.
static func _ctrl_s(doc: SaDocument, path: String) -> SaSadSave:
    var save := SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true)
    return save if save != null and SaSadFile.finish_saves() else null


## The coded slots of the file at *path*.
static func _coded_slots(path: String) -> int:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    var count := 0
    for layer: Dictionary in SaTyped.strings(JSON.parse_string(text)).get("layers", []):
        for chunk: Dictionary in layer.get("chunks", []):
            for slot: Dictionary in (chunk.get("fields", {}) as Dictionary).values():
                count += 1 if slot.has(SaSadCodec.KEY) else 0
    return count


func test_the_jpeg_xl_copy_opens_to_every_texture_of_the_zstd_copy() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var source := _painted()
    assert_true(_ctrl_s(source, zstd) != null, "The Zstd copy is saved")
    SaSadFile.save_in_background(source, coded, 0, null, true, Callable(), true, CODEC)
    assert_true(SaSadFile.finish_saves(), "and the JPEG XL copy")
    var fields := _textures(source).size()
    source.free()
    assert_true(fields >= GRID.x * GRID.y * FIELDS.size(), "The document holds every chunk's fields, %d" % fields)
    assert_eq(_coded_slots(coded), fields, "Every field of the JPEG XL copy is coded")
    assert_true(fields > SaSadCodec.Open.WINDOW, "more of them than the open's window")
    var from_zstd := _opened(zstd)
    var from_coded := _opened(coded)
    assert_true(from_zstd != null and from_coded != null, "Both copies open")
    if from_zstd == null or from_coded == null:
        return
    var expected := _textures(from_zstd)
    var read := _textures(from_coded)
    assert_eq(read.size(), fields, "The JPEG XL copy opens every field")
    assert_eq(read.keys(), expected.keys(), "the same fields as the Zstd copy")
    var unequal: Array[String] = []
    for name: String in expected:
        if read.get(name, PackedByteArray()) != expected[name]:
            unequal.append(name)
    assert_eq(unequal, [] as Array[String], "and every texture reads equal to the Zstd copy's")


func test_the_open_leaves_its_record_and_a_save_with_nothing_painted_copies_by_it() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var source := _painted()
    assert_true(_ctrl_s(source, zstd) != null, "The Zstd copy is saved")
    SaSadFile.save_in_background(source, coded, 0, null, true, Callable(), true, CODEC)
    assert_true(SaSadFile.finish_saves(), "and the JPEG XL copy")
    var coded_slots := _coded_slots(coded)
    var painted := _textures(source)
    var fields := painted.size()
    # The record keys a blob by its texels' hash, so textures alike share one.
    var distinct: Dictionary[String, bool] = {}
    for bytes: PackedByteArray in painted.values():
        distinct[Marshalls.raw_to_base64(bytes).sha256_text()] = true
    source.free()
    var from_coded := _opened(coded)
    var record: Variant = SaSadSnapshot._opens.get(coded)
    assert_true(record != null, "The open of the JPEG XL copy leaves a record")
    # A blob read plain is noted under a key for a plain save as well, so the
    # blobs are counted by where they lie.
    var named: Dictionary[int, bool] = {}
    for key: String in record.blobs if record != null else {}:
        if key.ends_with("/" + String(CODEC)):
            named[SaTyped.int_at(record.blobs[key], "offset", -1)] = true
    assert_eq(named.size(), distinct.size(), "holding every blob the pool decoded, under the codec's key")
    var after_coded := _ctrl_s(from_coded, coded)
    assert_true(after_coded != null, "A Ctrl+S of the JPEG XL copy ends")
    if after_coded != null:
        # A Ctrl+S keeps the file's codec, "Yes, saving respects the
        # codec", and copies each JPEG XL blob the open filled.
        assert_eq(after_coded.reuse.encoded, 0, "and compresses nothing, nothing being painted")
        assert_eq(after_coded.reuse.copied, fields, "copying every JPEG XL blob the open filled")
        assert_eq(_coded_slots(coded), coded_slots, "so every slot the save as JPEG XL coded still names the codec")
    var from_zstd := _opened(zstd)
    var after_zstd := _ctrl_s(from_zstd, zstd)
    assert_true(after_zstd != null, "A Ctrl+S of the Zstd copy ends")
    if after_zstd != null:
        assert_eq(after_zstd.reuse.encoded, 0, "and compresses nothing, nothing being painted")
        assert_eq(after_zstd.reuse.copied, fields, "copying every blob the open filled")
