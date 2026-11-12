## The door's `save` step takes
## `{"save": {"path": ..., "codec": "jxl"}}` and saves through the codec File >
## Save as JPEG XL asks for, waiting until the file is on disk, with
## `last_save` naming the codec. The plain String form still writes Zstd. A
## codec no module registers is refused with the menu's own line, and nothing
## is written.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and a load writes them.
const REQUIRES_GPU := true

const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

const SIZE := Vector2i(512, 256)
## Two chunks side by side, so the codec meets more than one.
const POSITIONS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
## The menu's line when the codec is missing, which the step answers with.
const REFUSAL := "Save as JPEG XL needs the JPEG XL module, which this Sara did not load. Nothing was saved."

static var folder: String = SaDataRoot.path("test_save_step")

## The codec registry a save asked when the case began, put back after.
var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null
var _host: Node = null
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _registries.register_builtins()
    var base := BaseModule.new()
    base.register(_registries.context.for_module(base.get_id()))
    _host = Node.new()
    _host.name = "U384SaveStepHost"
    EventBus.add_child(_host)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))


func after_each() -> void:
    SaSadFile.finish_saves()
    SaCodecRegistry.install(_was_installed)
    _was_installed = null
    _registries = null
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    var where := ProjectSettings.globalize_path(folder)
    for name in DirAccess.get_files_at(where):
        DirAccess.remove_absolute(where.path_join(name))
    DirAccess.remove_absolute(where)


## Registers the JPEG XL module into the suite's registries as the loader does,
## false when its library is not built here.
func _load_the_module() -> bool:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return SaCodecRegistry.shared().named(CODEC) != null


## A live canvas in front, whose half precision document holds smooth and busy
## colour over [constant POSITIONS], values from below zero to above one.
func _painted_canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    var space := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    canvas.easel = SaEasel.create_default(SIZE, null, space)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var layer := canvas.easel.document.active_layer
    var rng := RandomNumberGenerator.new()
    rng.seed = 384
    for grid_pos in POSITIONS:
        _fill(layer.get_or_create_chunk(grid_pos).albedo(), rng)
    _front = Fixtures.FrontDocuments.over(canvas)
    return canvas


## Fills *texture* with smooth values and busy ones.
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


## Every chunk's colour of the document at *path*, reopened, by its place.
static func _colour_of(path: String) -> Dictionary:
    var doc := SaDocument.new()
    var found := {}
    if SaExport.load_sad(doc, path, SaCompositor.new()) == OK:
        var rd := GlobalShaderCompiler.get_rd()
        var layer := doc.active_layer
        for grid_pos: Vector2i in layer.chunks:
            found[grid_pos] = rd.texture_get_data(layer.get_field(grid_pos, SaFieldSpec.ALBEDO).rid, 0)
    doc.free()
    return found


## Every colour blob slot of the `.sad` at *path*, read as the v4 reader does.
static func _colour_slots(path: String) -> Array:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return []
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    file.close()
    var header: Dictionary = JSON.parse_string(text)
    var slots := []
    for layer: Dictionary in header.get("layers", []):
        for chunk: Dictionary in layer.get("chunks", []):
            var fields: Dictionary = chunk.get("fields", {})
            if fields.has(String(SaFieldSpec.ALBEDO)):
                slots.append(fields[String(SaFieldSpec.ALBEDO)])
    return slots


func test_a_save_in_jpeg_xl_reads_back_as_the_zstd_one_and_names_its_codec() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var canvas := _painted_canvas()
    var run := SaCaptureRun.new(folder)
    var step := ScenarioDocument.new(run)
    var zstd := folder.path_join("plain.sad")
    var jxl := folder.path_join("coded.sad")

    step.save_document(zstd)
    var plain: Dictionary = run.last_save.duplicate()
    step.save_document({"path": jxl, "codec": "jxl"})
    var coded: Dictionary = run.last_save.duplicate()

    assert_eq(plain.get("error"), error_string(OK), "the plain form saved: %s" % plain)
    assert_eq(plain.get("codec"), "zstd", "and its last_save names Zstd")
    assert_eq(coded.get("error"), error_string(OK), "the codec form saved: %s" % coded)
    assert_eq(coded.get("codec"), "jxl", "and its last_save names the codec")
    assert_true(int(coded.get("bytes", 0)) > 0, "the file was on disk when the step ended")
    assert_true(FileAccess.file_exists(jxl), "the JPEG XL file is there")
    assert_eq(canvas.easel.document.file_path, jxl, "the document is marked as that file, as the menu marks it")
    var slots := _colour_slots(jxl)
    # The painted chunks and the ground layer's, which a default document has.
    assert_true(slots.size() >= POSITIONS.size(), "a colour slot for each painted chunk at least: %d" % slots.size())
    for slot: Dictionary in slots:
        assert_eq(slot.get(SaSadCodec.KEY), String(CODEC), "each colour slot names the codec: %s" % slot)
    for slot: Dictionary in _colour_slots(zstd):
        assert_false(slot.has(SaSadCodec.KEY), "the Zstd file's slots name no codec")
    var from_zstd := _colour_of(zstd)
    var from_jxl := _colour_of(jxl)
    assert_eq(from_jxl.size(), POSITIONS.size(), "the JPEG XL file opens with every chunk")
    for grid_pos: Vector2i in from_zstd:
        assert_true(from_jxl.get(grid_pos) == from_zstd[grid_pos], "chunk %s reads the same pixels from both files" % grid_pos)


func test_a_codec_no_module_registers_is_refused_and_writes_nothing() -> void:
    _painted_canvas()
    var run := SaCaptureRun.new(folder)
    var step := ScenarioDocument.new(run)
    var path := folder.path_join("never.sad")

    step.save_document({"path": path, "codec": "jxl"})

    assert_false(FileAccess.file_exists(path), "no file was written")
    assert_false(FileAccess.file_exists(path + SaSadFile.SAD_TEMP_SUFFIX), "nor a side file")
    assert_eq(run.last_save.get("codec"), "jxl", "the answer names the codec asked for")
    assert_eq(run.last_save.get("said"), TranslationServer.translate(REFUSAL), "and carries the menu's refusal")
    assert_true(run.last_save.get("error") != error_string(OK), "and an error")
