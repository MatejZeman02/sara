## A save the painter asks for rewrites only the chunks that
## changed since the last save to the same path and copies every other blob
## from the file it replaces. A chunk is known changed by a hash of its texels
## on the card, so a brush, a filter, a fill and an undo are all seen. The copy
## is trusted only while the file is as the last save left it and the document
## is the one that saved it, so a file changed behind Sara's back and a
## document opened from the file into another are saved whole. An autosave keeps a record of
## its own, so a save after it copies what it may.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const InvertFilter = preload("res://tests/fixtures/modules/point-fixture/invert_filter.gd")

## Layers added to the two a new document holds, each painted over every chunk of a canvas this many chunks a side.
const LAYERS := 2
const SIDE := 2
## The chunk a stroke is painted over.
const STROKED := Vector2i(1, 0)

static var first: String = SaDataRoot.path("test_first.sad")
static var other: String = SaDataRoot.path("test_other.sad")

var _easel: SaEasel = null
var _autosave: SaAutosave = null
var _opened: Array[SaDocument] = []


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    for doc in _opened:
        doc.free()
    _opened.clear()
    if _easel != null:
        _easel.free()
        _easel = null
    for path: String in [first, first + "1", other, other + "1"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A document of [constant LAYERS] layers more than a new one at *depth*, every chunk of each a
## colour of its own, and the first chunk of the active layer random texels,
## on an easel whose compositor knows the fixture invert.
func _painted(depth: SaColorSpace.Depth) -> SaDocument:
    _easel = SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE, null, SaColorSpace.srgb().with_depth(depth))
    _easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    filters.register(InvertFilter.new(), Bench.OWNER)
    _easel.compositor.filter_chain.registry = filters
    var doc := _easel.document
    for i in LAYERS:
        var layer := SaLayer.new()
        layer.name = "Painted %d" % i
        layer.schema = SaFieldSpec.schema_for_space(doc.color_space)
        doc.add_child(layer)
    var shade := 0
    for layer in _layers(doc):
        for y in SIDE:
            for x in SIDE:
                shade += 1
                layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(shade / 16.0, 1.0 - shade / 16.0, 0.5 + shade, 0.75))
    var colour := doc.active_layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO)
    var layout: Vector2i = SaSadBlob.LAYOUT[colour.format]
    var bytes := PackedByteArray()
    bytes.resize(colour.size.x * colour.size.y * layout.x * layout.y)
    var rng := RandomNumberGenerator.new()
    rng.seed = 141
    for at in range(0, bytes.size(), layout.y):
        if layout.y == 2:
            bytes.encode_half(at, rng.randf_range(-2.0, 3.0))
        else:
            bytes.encode_float(at, rng.randf_range(-2.0, 3.0))
    colour.rd.texture_update(colour.rid, 0, bytes)
    return doc


## The layers of *doc* a save writes, the stroke buffer left out.
static func _layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(child)
    return found


## Every field of every chunk of *doc*'s layers as the card holds it, by layer
## name, position and field.
static func _texels(doc: SaDocument) -> Dictionary[String, PackedByteArray]:
    var found: Dictionary[String, PackedByteArray] = {}
    for layer in _layers(doc):
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            for field_id: StringName in chunk.fields:
                var texture: SaTexture = chunk.fields[field_id]
                if texture != null and texture.rid.is_valid():
                    found["%s %s %s" % [layer.name, grid_pos, field_id]] = texture.rd.texture_get_data(texture.rid, 0)
    return found


## The textures of *after* that are new or hold other texels than in *before*.
static func _changed(before: Dictionary[String, PackedByteArray], after: Dictionary[String, PackedByteArray]) -> int:
    var count := 0
    for key: String in after:
        if not before.has(key) or before[key] != after[key]:
            count += 1
    return count


## Saves *doc* to *path* as the painter's File > Save does, in the background
## with the rounding asked for, and answers the save once it ended.
func _save(doc: SaDocument, path: String = first) -> SaSadSave:
    var save := SaSadFile.save_in_background(doc, path, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "The save of %s ends" % path.get_file())
    assert_eq(save.error, OK, "and writes the file")
    return save


## The document at *path*, freed after the test.
func _reopened(path: String) -> SaDocument:
    var doc := SaDocument.new()
    _opened.append(doc)
    assert_eq(SaExport.load_sad(doc, path, SaCompositor.new()), OK, "%s opens" % path.get_file())
    return doc


## Reads that the file at *path* opens equal to *doc* texel for texel.
func _reads_as(doc: SaDocument, path: String, how: String) -> void:
    var live := _texels(doc)
    var back := _texels(_reopened(path))
    assert_eq(back.size(), live.size(), "%s: the file holds every texture of the document" % how)
    var differ := 0
    for key: String in live:
        if back.get(key, PackedByteArray()) != live[key]:
            differ += 1
    assert_eq(differ, 0, "%s: every texture reopens as the document holds it" % how)


## Reads that *save* wrote the whole file, every blob compressed afresh.
func _whole(save: SaSadSave, doc: SaDocument, how: String) -> void:
    assert_eq(save.reuse.copied, 0, "%s: nothing is copied" % how)
    assert_eq(save.reuse.encoded, _texels(doc).size(), "%s: every chunk's blob is written" % how)
    assert_eq(save.taken, _texels(doc).size(), "%s: and the snapshot copies every texture" % how)


## Reads that *save* wrote only the *changed* textures and copied the rest.
func _only(save: SaSadSave, doc: SaDocument, changed: int, how: String) -> void:
    assert_true(changed > 0, "%s: the change reached a texture" % how)
    assert_eq(save.reuse.encoded, changed, "%s: only the changed chunk's blobs are written" % how)
    assert_eq(save.reuse.copied, _texels(doc).size() - changed, "%s: every other blob is copied" % how)
    assert_eq(save.taken, changed, "%s: and the snapshot copies only the changed textures" % how)


## A stroke over [constant STROKED] of the active layer.
static func _stroke(doc: SaDocument, colour: Color) -> void:
    doc.begin_stroke(0.8, &"normal")
    doc.stroke_layer.get_or_create_field(STROKED, SaFieldSpec.ALBEDO).clear(colour)
    doc.commit_stroke()


func test_a_second_save_writes_only_the_painted_chunk_and_copies_the_rest() -> void:
    var doc := _painted(SaColorSpace.Depth.F16)
    _whole(_save(doc), doc, "The first save")
    var before := _texels(doc)
    _stroke(doc, Color(0.9, 0.2, 0.1, 1.0))
    assert_eq(_changed(before, _texels(doc)), 1, "The stroke changed one chunk's colour")
    _only(_save(doc), doc, 1, "The save after the stroke")
    _reads_as(doc, first, "The second file")
    var third := _save(doc)
    assert_eq(third.reuse.encoded, 0, "A save with nothing painted since writes no blob")
    assert_eq(third.taken, 0, "and its snapshot copies nothing")
    _reads_as(doc, first, "The third file")


func test_a_file_changed_behind_sara_s_back_is_saved_whole() -> void:
    var doc := _painted(SaColorSpace.Depth.F16)
    _save(doc)
    var file := FileAccess.open(first, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_8(0)
    file.close()
    _whole(_save(doc), doc, "After a byte was appended")
    _reads_as(doc, first, "The file saved after the byte")
    var size := FileAccess.get_file_as_bytes(first).size()
    var touched := OS.execute("touch", ["-d", "2001-02-03 04:05:06", ProjectSettings.globalize_path(first)])
    assert_eq(touched, 0, "The file's modified time is set back")
    assert_eq(FileAccess.get_file_as_bytes(first).size(), size, "with its size held")
    _whole(_save(doc), doc, "After the modified time changed")
    _reads_as(doc, first, "The file saved after the time")


func test_a_filter_a_fill_and_an_undo_are_each_rewritten() -> void:
    var doc := _painted(SaColorSpace.Depth.F16)
    var layer := doc.active_layer
    _stroke(doc, Color(0.1, 0.8, 0.3, 1.0))
    _save(doc)
    var before := _texels(doc)
    var ctx := SaFilterContext.new(doc, layer, Bench.OWNER, "Invert")
    assert_true(SaFilterApply.call_run(InvertFilter.new(), ctx), "The invert runs")
    assert_true(SaFilterApply.apply(ctx, "Invert"), "and is applied to the layer")
    _only(_save(doc), doc, _changed(before, _texels(doc)), "The save after a filter")
    _reads_as(doc, first, "The file after a filter")
    before = _texels(doc)
    var below: SaLayer = _layers(doc)[0]
    doc.fill_layer(Color(0.3, 0.6, 0.9, 1.0), below)
    _only(_save(doc), doc, _changed(before, _texels(doc)), "The save after a fill")
    _reads_as(doc, first, "The file after a fill")
    before = _texels(doc)
    assert_true(doc.undo(), "The fill is undone")
    assert_true(doc.undo(), "The filter is undone")
    assert_true(doc.undo(), "The stroke is undone")
    _only(_save(doc), doc, _changed(before, _texels(doc)), "The save after the undos")
    _reads_as(doc, first, "The file after the undos")


func test_a_document_opened_from_the_file_saves_it_whole_and_one_after_an_autosave_copies_it() -> void:
    var doc := _painted(SaColorSpace.Depth.F16)
    _save(doc)
    var opened := _reopened(first)
    _whole(_save(opened, first), opened, "The first save of a second document opened from the file")
    _save(doc, other)
    assert_eq(SaExport.load_sad(doc, other), OK, "The file is opened again in the document that saved it")
    assert_eq(_save(doc, other).reuse.encoded, 0, "The first save after the document was opened copies what it read")
    _autosave = SaAutosave.new()
    _autosave.follow_settings = false
    _autosave.attach(doc)
    _autosave.write_working_file = true
    doc.file_path = other
    doc.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave writes the working file")
    assert_true(SaSadFile.finish_saves(), "and ends")
    # The autosave keeps a record too, and half precision colour is
    # never rounded, so the save after it copies every blob the autosave wrote.
    var after := _save(doc, other)
    assert_eq(after.reuse.encoded, 0, "The save after an autosave compresses nothing")
    assert_eq(after.reuse.copied, _texels(doc).size(), "and copies every blob")
    _reads_as(doc, other, "The file saved after the autosave")


func test_a_reused_chunk_of_full_precision_colour_is_a_rounded_one() -> void:
    var doc := _painted(SaColorSpace.Depth.F32)
    _save(doc)
    _stroke(doc, Color(5.123457, -0.3141593, 0.7777777, 0.61803))
    var second := _save(doc)
    assert_true(second.reuse.copied > 0, "The second save copies the chunks it did not paint")
    var unrounded := 0
    var colour := 0
    for layer in _layers(_reopened(first)):
        for chunk: SaChunk in layer.chunks.values():
            var texture: SaTexture = chunk.fields.get(SaFieldSpec.ALBEDO)
            if texture == null:
                continue
            colour += 1
            var bytes := texture.rd.texture_get_data(texture.rid, 0)
            for at in range(0, bytes.size(), 4):
                var bits := bytes.decode_u32(at)
                if SaSadSnapshot.round_bits(bits) != bits:
                    unrounded += 1
    assert_eq(colour, _layers(doc).size() * SIDE * SIDE, "Every chunk's colour reopens")
    assert_eq(unrounded, 0, "and every channel of it equals its own 12 significant bit rounding")
