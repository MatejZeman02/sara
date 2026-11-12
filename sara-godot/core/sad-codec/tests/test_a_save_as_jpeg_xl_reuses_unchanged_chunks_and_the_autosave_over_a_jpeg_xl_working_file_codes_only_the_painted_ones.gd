## A save as JPEG XL reuses unchanged chunks, and the autosave
## over a JPEG XL working file codes only the painted ones. A small half
## precision document of four chunks, each with colour and a height, is saved as
## JPEG XL, one chunk's colour is painted again, and the file is written once
## more by Ctrl+S or by the autosave to the working file. Each codes the
## painted chunk alone in JPEG XL and copies the other blobs, codestream and
## codec key alike, and the file reopens as the document stands. The recovery
## copy of a document saved as JPEG XL, and a Ctrl+S of a document never saved
## as JPEG XL, hold Zstd blobs only.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const Coded = preload(
    "res://core/sad-codec/tests/test_file_save_as_jpeg_xl_writes_a_smaller_file_the_painter_asked_for_by_name.gd"
)
const MODULE_PATH := "res://modules/sara-jxl/module.gd"
const CODEC := &"jxl"

## Four chunks, two by two, and the one painted again.
const POSITIONS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const PAINTED := Vector2i(1, 1)
const FIELDS: Array[StringName] = [SaFieldSpec.ALBEDO, SaFieldSpec.HEIGHT]

static var working: String = SaDataRoot.path("test_working.sad")

## The codec registry a save asked when the case began, put back after.
var _was_installed: SaCodecRegistry = null
var _registries: SaRegistries = null
var _autosave: SaAutosave = null
var _docs: Array[SaDocument] = []
var _easels: Array[SaEasel] = []


func before_each() -> void:
    _was_installed = SaCodecRegistry.shared()
    _registries = SaRegistries.new()
    _registries.build_context(Callable(), Callable())
    _registries.register_builtins()


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    for doc in _docs:
        doc.free()
    _docs.clear()
    for easel in _easels:
        easel.free()
    _easels.clear()
    SaCodecRegistry.install(_was_installed)
    _was_installed = null
    _registries = null
    for path: String in [working, working + "1", SaAutosave.recovery_path_for(working)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Registers the JPEG XL module into the suite's registries as the loader does,
## false when its library is not built here.
func _load_the_module() -> bool:
    var module: SaModule = (load(MODULE_PATH) as Script).new()
    var scoped := _registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return SaCodecRegistry.shared().named(CODEC) != null


## A half precision document of [constant POSITIONS], colour and a height in
## each chunk of its painted layer over the background's colour, its file [member working], kept for [method after_each] to free.
func _document() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(512, 512), SaCompositor.new(), SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16))
    var layer := doc.active_layer
    var fields: Array[SaFieldSpec] = [SaFieldSpec.albedo(doc.color_space.texel_format()), SaFieldSpec.height()]
    layer.schema = fields
    layer.chunks.clear()
    var rng := RandomNumberGenerator.new()
    rng.seed = 206
    for grid_pos in POSITIONS:
        layer.get_or_create_chunk(grid_pos)
        for field_id in FIELDS:
            Coded._fill(layer.get_or_create_field(grid_pos, field_id), rng)
    doc.file_path = working
    _docs.append(doc)
    return doc


## Paints [constant PAINTED]'s colour again, the one chunk the next save codes.
static func _paint(doc: SaDocument) -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 2060
    Coded._fill(doc.active_layer.get_field(PAINTED, SaFieldSpec.ALBEDO), rng)


## Saves *doc* to *path* in the background as the painter's commands do, in
## *codec* or with none asked for, as Ctrl+S, and answers the save once ended.
func _save(doc: SaDocument, path: String, codec := &"") -> SaSadSave:
    var save := SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true, codec)
    assert_true(SaSadFile.finish_saves(), "The save of %s ends" % path.get_file())
    assert_true(save != null and save.error == OK, "and writes its file")
    return save


## Runs the autosave of *doc* once, to the working file when *to_working_file*
## holds and otherwise to the recovery copy, and answers its save.
func _autosave_now(doc: SaDocument, to_working_file: bool) -> SaSadSave:
    if _autosave == null:
        _autosave = SaAutosave.new()
        _autosave.follow_settings = false
        _autosave.attach(doc)
    _autosave.write_working_file = to_working_file
    doc.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for")
    var save: SaSadSave = SaSadSave._saves.back() if not SaSadSave._saves.is_empty() else null
    assert_true(SaSadFile.finish_saves(), "and it ends")
    assert_true(save != null and save.error == OK, "and writes its file")
    return save


## Every colour and height slot of the file at *path* by its chunk and field.
static func _chunk_slots(path: String) -> Dictionary[String, Dictionary]:
    var found: Dictionary[String, Dictionary] = {}
    for layer: Dictionary in Coded._header(path).get("layers", []):
        for chunk: Dictionary in layer.get("chunks", []):
            var fields: Dictionary = chunk.get("fields", {})
            for field_name: String in fields:
                var grid_pos := Vector2i(SaTyped.int_at(chunk, "x", 0), SaTyped.int_at(chunk, "y", 0))
                found["%s %s %s" % [layer.get("name", ""), grid_pos, field_name]] = fields[field_name]
    return found


## How many blobs of the file at *path* name a codec, of every kind.
static func _coded_blobs(path: String) -> int:
    var slots := Coded._slots(Coded._header(path))
    var named := 0
    for kind: String in slots:
        named += Coded._naming(slots[kind])
    return named


## The stored bytes of *slot*'s blob in the file at *path*.
static func _blob(path: String, slot: Dictionary) -> PackedByteArray:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return PackedByteArray()
    file.seek(8)
    var region := SaSadSnapshot.HEAD_BYTES + file.get_32()
    file.seek(region + SaTyped.int_at(slot, "offset", 0))
    return file.get_buffer(SaTyped.int_at(slot, "size", 0))


## Reads that the file at *path*, written by *save* over the save as JPEG XL
## whose slots were *first* and whose stored blobs were *first_blobs*, coded
## the painted chunk alone, copied every other blob with its codec key and its
## bytes, holds no Zstd colour or height blob and reopens as *doc* stands.
func _reads_the_painted_chunk_coded_alone(
    doc: SaDocument, save: SaSadSave, path: String, first: Dictionary[String, Dictionary], first_blobs: Dictionary, how: String
) -> void:
    var slots := _chunk_slots(path)
    assert_eq(save.reuse.encoded, 1, "%s compresses the painted chunk alone" % how)
    assert_eq(save.reuse.copied, slots.size() - 1, "%s and copies every other blob" % how)
    assert_eq(slots.keys(), first.keys(), "%s writes every chunk's colour and height" % how)
    var coded := 0
    var kept := 0
    for what: String in slots:
        if slots[what].has(SaSadCodec.KEY):
            coded += 1
        if not _is_painted(what, doc) and _blob(path, slots[what]) == first_blobs[what] and slots[what].has(SaSadCodec.KEY):
            kept += 1
    assert_eq(coded, slots.size(), "%s holds no Zstd colour or height blob" % how)
    assert_eq(kept, slots.size() - 1, "%s keeps each copied blob's codec key and its bytes" % how)
    assert_eq(SaSadFile.version_at(path), SaSadFile.SAD_VERSION_CODED, "%s keeps the codec's stamp" % how)
    var back := Coded._reopened(path)
    assert_not_null(back, "%s opens" % how)
    if back != null:
        _docs.append(back)
        assert_eq(Coded._textures(back), Coded._textures(doc), "%s reopens with every texture as the document holds it" % how)


## Whether *what*, a slot's name from [method _chunk_slots], is the painted
## chunk's colour, on the painted layer and not the background beneath it.
static func _is_painted(what: String, doc: SaDocument) -> bool:
    return what == "%s %s %s" % [doc.active_layer.name, PAINTED, SaFieldSpec.ALBEDO]


## The stored bytes of every slot of *slots* in the file at *path*.
static func _blobs(path: String, slots: Dictionary[String, Dictionary]) -> Dictionary:
    var found := {}
    for what: String in slots:
        found[what] = _blob(path, slots[what])
    return found


func test_a_ctrl_s_over_a_file_saved_as_jpeg_xl_codes_the_painted_chunk_alone_and_copies_the_rest() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var doc := _document()
    var first := _save(doc, working, CODEC)
    var slots := _chunk_slots(working)
    var each := POSITIONS.size() * (FIELDS.size() + 1)
    assert_eq(slots.size(), each, "Every chunk's colour and height, and the background's colour")
    assert_eq(first.reuse.encoded, slots.size(), "The save as JPEG XL codes each of them")
    assert_eq(_coded_blobs(working), slots.size(), "and every one names the codec")
    var blobs := _blobs(working, slots)
    _paint(doc)
    var again := _save(doc, working)
    assert_eq(again.codec.name if again.codec != null else &"", CODEC, "Ctrl+S over it keeps the file's codec")
    _reads_the_painted_chunk_coded_alone(doc, again, working, slots, blobs, "Ctrl+S")


func test_the_autosave_over_a_jpeg_xl_working_file_codes_the_painted_chunk_alone() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var doc := _document()
    _save(doc, working, CODEC)
    var slots := _chunk_slots(working)
    var blobs := _blobs(working, slots)
    _paint(doc)
    var autosaved := _autosave_now(doc, true)
    assert_eq(autosaved.path, working, "The autosave writes the working file")
    _reads_the_painted_chunk_coded_alone(doc, autosaved, working, slots, blobs, "The autosave")


func test_the_recovery_copy_of_a_document_saved_as_jpeg_xl_is_zstd() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var doc := _document()
    _save(doc, working, CODEC)
    _paint(doc)
    var recovered := _autosave_now(doc, false)
    var path := SaAutosave.recovery_path_for(working)
    assert_eq(recovered.path, path, "The autosave writes the recovery copy")
    assert_null(recovered.codec, "in no codec")
    assert_eq(_chunk_slots(path).keys(), _chunk_slots(working).keys(), "The recovery copy holds every chunk")
    assert_eq(_coded_blobs(path), 0, "and no blob of it names a codec")
    assert_true(SaSadFile.version_at(path) < SaSadFile.SAD_VERSION_CODED, "nor is it stamped as a coded file")
    assert_eq(_coded_blobs(working), _chunk_slots(working).size(), "and the working file still holds JPEG XL")


func test_a_ctrl_s_of_a_document_never_saved_as_jpeg_xl_writes_zstd() -> void:
    _load_the_module()
    var doc := _document()
    var first := _save(doc, working)
    assert_null(first.codec, "A first Ctrl+S asks for no codec")
    _paint(doc)
    var again := _save(doc, working)
    assert_null(again.codec, "and a Ctrl+S over its file asks for none")
    assert_eq(_coded_blobs(working), 0, "so no blob names a codec")
    assert_true(again.reuse.copied > 0, "and it copies the Zstd blobs that did not change, as today")
    assert_true(SaSadFile.version_at(working) < SaSadFile.SAD_VERSION_CODED, "under the stamp it had")


## The file at [member working] opened as File > Open opens it, into a
## document of its own: read, its history emptied and the path named.
func _open() -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    _easels.append(easel)
    var doc := easel.document
    assert_eq(SaExport.load_sad(doc, working), OK, "The file saved as JPEG XL opens")
    doc.undo_redo.clear_history()
    doc.history.reset()
    doc.mark_saved(working)
    return doc


func test_a_file_saved_as_jpeg_xl_and_opened_again_keeps_its_codec_at_the_next_ctrl_s() -> void:
    if not _load_the_module():
        assert_true(true, "Skipped: the JPEG XL library is not built in this checkout")
        return
    var doc := _document()
    _save(doc, working, CODEC)
    var opened := _open()
    _paint(opened)
    var again := _save(opened, working)
    assert_eq(again.codec.name if again.codec != null else &"", CODEC, "A Ctrl+S of the opened file keeps its codec")
    assert_eq(_coded_blobs(working), _chunk_slots(working).size(), "and every colour and height blob names it")
    assert_true(again.reuse.copied > 0, "copying what the open filled and nothing changed")
