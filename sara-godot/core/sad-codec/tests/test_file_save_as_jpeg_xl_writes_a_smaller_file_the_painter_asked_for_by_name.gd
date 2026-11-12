## File > Save as JPEG XL writes a smaller file the painter
## asked for by name. A small half precision document and a small full
## precision one, each with a mask, a height layer and a simulation's seed,
## are saved through the codec `&"jxl"`, the JPEG XL module's, and reopened.
## Every texture comes back as it was, the full precision colour as the
## rounding gives it, the masks' and seeds' blobs name no codec, the file is
## stamped above 15, and a Ctrl+S of the reopened document writes Zstd again.
## With no codec registered, the open of such a file fills no chunk with what
## the stream holds, so no noise shows.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Rounding = preload("res://core/sad-file/tests/test_a_full_precision_save_rounds_colour_to_12_significant_bits_once.gd")
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

## Two chunks side by side on the painted layer, and one on the simulated one.
const POSITIONS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const FIELDS: Array[StringName] = [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT, SaFieldSpec.MASK]
const SIMULATED := "Simulated"

static var coded: String = SaDataRoot.path("test_coded.sad")
static var again: String = SaDataRoot.path("test_again.sad")

## The codec registry a save asked when the case began, put back after.
var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null


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
    for path: String in [coded, again]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Registers the JPEG XL module into the suite's registries as the loader does,
## false when its library is not built here.
func _load_the_module() -> bool:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return SaCodecRegistry.shared().named(CODEC) != null


## A document at *depth* whose first layer holds colour, a height and a mask
## over [constant POSITIONS], each of busy values from below zero to above one,
## and a second layer, [constant SIMULATED], painted and given Spread, which
## copies its paint into the simulation's seed.
func _painted(depth: SaColorSpace.Depth) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 256), SaCompositor.new(), SaColorSpace.srgb().with_depth(depth))
    var layer := doc.active_layer
    var fields: Array[SaFieldSpec] = [
        SaFieldSpec.albedo(doc.color_space.texel_format()), SaFieldSpec.height(), SaFieldSpec.mask()
    ]
    layer.schema = fields
    layer.chunks.clear()
    var rng := RandomNumberGenerator.new()
    rng.seed = 204
    for grid_pos in POSITIONS:
        layer.get_or_create_chunk(grid_pos)
        for field_id in FIELDS:
            _fill(layer.get_or_create_field(grid_pos, field_id), rng)
    var simulated := SaLayerOps.new(doc).add()
    simulated.name = SIMULATED
    _fill(simulated.get_or_create_chunk(Vector2i.ZERO).albedo(), rng)
    SaSimulation.put_on(simulated, _registries.simulation_rules.find(&"spread"))
    return doc


## Fills *texture* with smooth values and busy ones, so the codec meets both.
static func _fill(texture: SaTexture, rng: RandomNumberGenerator) -> void:
    var layout: Vector2i = SaSadBlob.LAYOUT[texture.format]
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
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)


## Every texture of *doc* a save writes, by a name the reopened one has too:
## each field of the first layer's chunks, the simulated layer's colour, and
## its seed.
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
        var record := SaSimulation.record_of(layer)
        if record != null:
            for grid_pos: Vector2i in record.seed_chunks:
                found["%s seed %s" % [layer.name, grid_pos]] = rd.texture_get_data(record.seed_chunks[grid_pos].rid, 0)
    return found


## The header of the `.sad` at *path*, as the v4 reader reads it.
static func _header(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    return SaTyped.strings(JSON.parse_string(text))


## Every blob slot of *header* by what it holds: `colour`, `height`, `mask`
## and `seed`, each a list of slots.
static func _slots(header: Dictionary) -> Dictionary:
    var found := {"colour": [], "height": [], "mask": [], "seed": []}
    for layer: Dictionary in header.get("layers", []):
        for chunk: Dictionary in layer.get("chunks", []):
            var fields: Dictionary = chunk.get("fields", {})
            for field_name: String in fields:
                var kind := "colour" if field_name == String(SaFieldSpec.ALBEDO) else field_name
                found[kind].append(fields[field_name])
        var simulation: Dictionary = layer.get("simulation", {})
        found["seed"].append_array(simulation.get("seed", []))
    return found


## How many of *slots* name the codec.
static func _naming(slots: Array) -> int:
    var count := 0
    for slot: Dictionary in slots:
        if slot.has(SaSadCodec.KEY):
            count += 1
    return count


## The document at *path*, or null when it would not open.
static func _reopened(path: String) -> SaDocument:
    var doc := SaDocument.new()
    if SaExport.load_sad(doc, path, SaCompositor.new()) != OK:
        doc.free()
        return null
    return doc


## Saves *doc* to *path* as File > Save as JPEG XL does, in the background with
## the rounding and the codec asked for, and answers whether it ended.
static func _save_as_jpeg_xl(doc: SaDocument, path: String) -> bool:
    SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true, CODEC)
    return SaSadFile.finish_saves()


func test_a_half_and_a_full_precision_document_come_back_from_a_save_as_jpeg_xl() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    for depth: SaColorSpace.Depth in [SaColorSpace.Depth.F16, SaColorSpace.Depth.F32]:
        var how := "half precision" if depth == SaColorSpace.Depth.F16 else "full precision"
        var source := _painted(depth)
        var before := _textures(source)
        var colours := before.keys().filter(func(what: String) -> bool: return what.ends_with(String(SaFieldSpec.ALBEDO))).size()
        assert_true(colours >= 3 and before.has("%s seed (0, 0)" % SIMULATED), "%s: colour, a height, a mask and a seed" % how)
        assert_true(_save_as_jpeg_xl(source, coded), "%s: the save as JPEG XL ends" % how)
        var header := _header(coded)
        assert_true(SaSadFile.version_at(coded) > 15, "%s: the file is stamped above 15" % how)
        assert_eq(SaSadFile.version_at(coded), SaSadFile.SAD_VERSION_CODED, "%s: at %d" % [how, SaSadFile.SAD_VERSION_CODED])
        var slots := _slots(header)
        assert_eq(slots["colour"].size(), colours, "%s: every colour blob is written" % how)
        assert_eq(_naming(slots["colour"]), colours, "%s: and every one names the codec" % how)
        assert_eq(_naming(slots["height"]), slots["height"].size(), "%s: every height blob names it too" % how)
        assert_eq(slots["mask"].size(), 2, "%s: two mask blobs are written" % how)
        assert_eq(_naming(slots["mask"]), 0, "%s: and none names a codec" % how)
        assert_eq(slots["seed"].size(), 1, "%s: the seed's blob is written" % how)
        assert_eq(_naming(slots["seed"]), 0, "%s: and names no codec" % how)
        var back := _reopened(coded)
        assert_not_null(back, "%s: the file opens" % how)
        if back == null:
            source.free()
            continue
        var opened := _textures(back)
        assert_eq(opened.keys(), before.keys(), "%s: every texture comes back" % how)
        for what: String in before:
            var said := "%s: %s comes back" % [how, what]
            if depth == SaColorSpace.Depth.F32 and what.ends_with(String(SaFieldSpec.ALBEDO)):
                _reads_rounded(before[what], opened.get(what, PackedByteArray()), said)
            else:
                assert_eq(opened.get(what, PackedByteArray()), before[what], "%s byte for byte" % said)
        assert_true(SaSadFile.save_in_background(back, again, 0, null, true, Callable(), true) != null, "%s: Ctrl+S" % how)
        assert_true(SaSadFile.finish_saves(), "%s: a Ctrl+S of the reopened document ends" % how)
        var zstd := _slots(_header(again))
        var named := 0
        for kind: String in zstd:
            named += _naming(zstd[kind])
        assert_eq(named, 0, "%s: and writes no blob that names a codec" % how)
        assert_true(SaSadFile.version_at(again) < SaSadFile.SAD_VERSION_CODED, "%s: nor the codec's stamp" % how)
        var zstd_back := _reopened(again)
        assert_eq(_textures(zstd_back), opened, "%s: and that file opens as the coded one did" % how)
        for doc: SaDocument in [source, back, zstd_back]:
            doc.free()


## Reads every channel of *opened* the 12 bit rounding of the same channel of
## *painted*, as the sibling suite reads it.
func _reads_rounded(painted: PackedByteArray, opened: PackedByteArray, how: String) -> void:
    assert_eq(opened.size(), painted.size(), "%s whole" % how)
    if opened.size() != painted.size():
        return
    var wrong := 0
    for at in range(0, painted.size(), 4):
        if opened.decode_u32(at) != SaSadSnapshot.round_bits(painted.decode_u32(at)):
            wrong += 1
    assert_eq(wrong, 0, "%s as the rounding gives it" % how)


## A save in a codec copies each blob whose key matches, and the key
## names the codec, so of a Zstd file it copies the masks alone.
func test_a_save_as_jpeg_xl_over_a_ctrl_s_copies_its_masks_alone() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var source := _painted(SaColorSpace.Depth.F16)
    assert_true(SaSadFile.save_in_background(source, again, 0, null, true, Callable(), true) != null, "Ctrl+S starts")
    assert_true(SaSadFile.finish_saves(), "and ends")
    var save := SaSadFile.save_in_background(source, again, 0, null, true, Callable(), true, CODEC)
    assert_true(SaSadFile.finish_saves(), "A save as JPEG XL over the same file ends")
    var slots := _slots(_header(again))
    assert_eq(_naming(slots["colour"]), slots["colour"].size(), "every colour blob is coded")
    assert_eq(_naming(slots["height"]), slots["height"].size(), "and every height blob")
    assert_eq(save.reuse.copied, slots["mask"].size(), "and of the Zstd file it replaces only the masks are copied")
    source.free()


## A save in a codec where the window's device is not the save's walks at
## once, coding each chunk as it reads it, and names the codec in each slot it
## coded, or the open reads the stream as Zstd.
func test_a_save_at_once_in_a_codec_names_it_in_every_coded_slot() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var source := _painted(SaColorSpace.Depth.F16)
    var before := _textures(source)
    var codec := SaCodecRegistry.shared().named(CODEC)
    var saved: Variant = SaSadCodec.during(codec, SaSadFile.save_file.bind(source, coded, 0, null))
    assert_eq(saved, OK, "The save at once ends")
    source.free()
    var slots := _slots(_header(coded))
    assert_eq(_naming(slots["colour"]), slots["colour"].size(), "every colour blob names the codec")
    assert_eq(_naming(slots["height"]), slots["height"].size(), "and every height blob")
    assert_eq(_naming(slots["mask"]), 0, "and no mask's")
    assert_eq(SaSadFile.version_at(coded), SaSadFile.SAD_VERSION_CODED, "stamped at %d" % SaSadFile.SAD_VERSION_CODED)
    var back := _reopened(coded)
    assert_not_null(back, "The file opens")
    if back == null:
        return
    var after := _textures(back)
    for what: String in before:
        assert_eq(after.get(what, PackedByteArray()), before[what], "%s comes back as it was" % what)
    back.free()


func test_a_coded_file_opened_with_no_codec_fills_no_chunk_with_the_stream() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var source := _painted(SaColorSpace.Depth.F16)
    assert_true(_save_as_jpeg_xl(source, coded), "The save as JPEG XL ends")
    source.free()
    var bare := SaRegistries.new()
    bare.build_context(Callable(), Callable())
    bare.register_builtins()
    assert_null(SaCodecRegistry.shared().named(CODEC), "With the module left out no codec is called jxl")
    var back := _reopened(coded)
    assert_not_null(back, "The file still opens, its coded chunks left out")
    if back == null:
        return
    var opened := _textures(back)
    for what: String in opened:
        if what.ends_with(String(SaFieldSpec.ALBEDO)) and not what.begins_with(SIMULATED):
            var zeroes := PackedByteArray()
            zeroes.resize(opened[what].size())
            assert_eq(opened[what], zeroes, "%s holds nothing, no noise from the stream" % what)
    back.free()
    bare = null


func test_a_codec_nobody_registered_is_never_asked_for() -> void:
    var bare := SaRegistries.new()
    bare.build_context(Callable(), Callable())
    bare.register_builtins()
    var source := _painted(SaColorSpace.Depth.F16)
    assert_true(_save_as_jpeg_xl(source, coded), "A save naming a codec nobody registered still ends")
    var slots := _slots(_header(coded))
    assert_eq(_naming(slots["colour"]) + _naming(slots["height"]), 0, "and writes Zstd")
    assert_true(SaSadFile.version_at(coded) < SaSadFile.SAD_VERSION_CODED, "under the stamp its features ask")
    source.free()
    bare = null


## A save that copies every chunk sweeps for the chunks that hold nothing a
## share a turn after its snapshot rather than all in its frame, which on
## 4k-30's 1667 copies was a third of a second. More copies than a turn's share,
## every third holding paint, are swept to the last before the words are asked
## for, and the file holds the painted chunks alone.
func test_more_copies_than_a_turns_share_of_the_sweep_leave_out_every_chunk_that_holds_nothing() -> void:
    var doc := SaDocument.new()
    var side := 16
    doc.setup_default_document(Vector2i(side * 256, side * 256), SaCompositor.new(), SaColorSpace.srgb())
    var layer := doc.active_layer
    layer.chunks.clear()
    var painted := 0
    for at in SaSadClearChunks.SWEEPS_A_TURN + 20:
        var grid_pos := Vector2i(at % side, floori(at / float(side)))
        layer.get_or_create_chunk(grid_pos)
        if at % 3 == 0:
            layer.get_or_create_field(grid_pos, SaFieldSpec.ALBEDO).clear(Color(0.2, 0.4, 0.6, 1.0))
            painted += 1
    assert_true(SaSadFile.save_in_background(doc, again, 0, null, true, Callable(), true) != null, "The save starts")
    assert_true(SaSadFile.finish_saves(), "and ends")
    var written := 0
    for entry: Dictionary in _header(again).get("layers", []):
        if entry.get("name", "") == String(layer.name):
            written = (entry.get("chunks", []) as Array).size()
    assert_eq(written, painted, "The file holds the %d painted chunks and none of the others" % painted)
    doc.free()
