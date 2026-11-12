## The first autosave after an open copies what the opened
## file holds. The open leaves a record of the file it read, and a save to
## another path, the autosave's recovery copy, takes the opened file's blobs
## from it, so after one stroke the autosave compresses the one chunk the
## stroke changed and copies the rest. A record of a file changed on disk since
## the open is never used.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The canvas, this many chunks a side.
const SIDE := 2
## Where the stroke lands, inside one chunk.
const STROKE_AT := Vector2(384.0, 128.0)
const RED := Color(0.8, 0.1, 0.05, 1.0)

static var working: String = SaDataRoot.path("test_working.sad")

var _easels: Array[SaEasel] = []
var _autosave: SaAutosave = null
## The blobs the whole save of the document wrote.
var _blobs := 0


## A document of a paint layer filling every chunk with a colour of its own,
## saved without rounding to the working file and closed again.
func before_each() -> void:
    var easel := _easel()
    var doc := easel.document
    var paint := SaLayer.new()
    paint.name = "paint"
    paint.schema = SaFieldSpec.schema_for_space(doc.color_space)
    doc.add_child(paint)
    for y in SIDE:
        for x in SIDE:
            paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.25 * x + 0.125, 0.25 * y + 0.25, 0.5, 1.0))
    doc.active_layer = paint
    var save := SaSadFile.save_in_background(doc, working, 0, null, false)
    assert_true(SaSadFile.finish_saves(), "The document is saved")
    assert_eq(save.error, OK, "and written")
    _blobs = save.reuse.encoded


func after_each() -> void:
    SaSadFile.finish_saves()
    if _autosave != null:
        _autosave.discard_recovery()
        _autosave.free()
        _autosave = null
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path: String in [working, SaAutosave.recovery_path_for(working)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _easels.append(easel)
    return easel


## The file at *path* opened into a document of its own.
func _open(path: String) -> SaDocument:
    var doc := _easel().document
    assert_eq(SaExport.load_sad(doc, path), OK, "The file %s opens" % path.get_file())
    doc.file_path = path
    return doc


## One hard dab of *color* on the active layer of *doc*, as a stroke of its own.
func _stroke(doc: SaDocument, pos: Vector2, radius: float, color: Color) -> void:
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    doc.commit_stroke()


## Runs the autosave of *doc* once, to the recovery copy, and answers its save.
func _autosave_now(doc: SaDocument) -> SaSadSave:
    _autosave = SaAutosave.new()
    _autosave.follow_settings = false
    _autosave.attach(doc)
    _autosave.write_working_file = false
    doc.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for")
    var save: SaSadSave = SaSadSave._saves.back() if not SaSadSave._saves.is_empty() else null
    assert_true(SaSadFile.finish_saves(), "and it ends")
    assert_true(save != null and save.error == OK and save.rounds, "and writes the recovery copy rounding its colour")
    return save


## Every texture of *doc* as the card holds it, by the layer, place and field.
static func _texels(doc: SaDocument) -> Dictionary[String, PackedByteArray]:
    var found: Dictionary[String, PackedByteArray] = {}
    for child in doc.get_children():
        var layer := child as SaLayer
        if layer == null:
            continue
        for grid_pos: Vector2i in layer.chunks:
            var chunk: SaChunk = layer.chunks[grid_pos]
            for field_id: StringName in chunk.fields if chunk != null else {}:
                var texture: SaTexture = chunk.fields[field_id]
                if texture != null and texture.rid.is_valid():
                    found["%s/%s/%s" % [layer.name, grid_pos, field_id]] = texture.rd.texture_get_data(texture.rid, 0)
    return found


## *bytes*, float32 words, each rounded as a save that rounds writes it.
static func _rounded(bytes: PackedByteArray) -> PackedByteArray:
    var out := bytes.duplicate()
    for at in range(0, out.size(), 4):
        out.encode_u32(at, SaSadSnapshot.round_bits(out.decode_u32(at)))
    return out


## The keys of *after* new or holding other texels than in *before*.
static func _changed(before: Dictionary[String, PackedByteArray], after: Dictionary[String, PackedByteArray]) -> Array[String]:
    var found: Array[String] = []
    for key: String in after:
        if not before.has(key) or before[key] != after[key]:
            found.append(key)
    return found


func test_the_first_autosave_after_an_open_compresses_only_the_changed_chunk() -> void:
    var doc := _open(working)
    var before := _texels(doc)
    _stroke(doc, STROKE_AT, 20.0, RED)
    var after := _texels(doc)
    var touched := _changed(before, after)
    assert_eq(touched.size(), 1, "The stroke changed one chunk, %s" % [touched])
    var save := _autosave_now(doc)
    assert_eq(save.reuse.encoded, 1, "The first autosave after the open compresses one blob")
    assert_eq(save.reuse.copied, _blobs - 1, "and copies the rest from the opened file")
    var read := _texels(_open(SaAutosave.recovery_path_for(working)))
    var keys := read.keys()
    var wanted := after.keys()
    keys.sort()
    wanted.sort()
    assert_eq(keys, wanted, "The recovery copy holds the document's textures")
    for key: String in after:
        if key.ends_with("/albedo"):
            after[key] = _rounded(after[key])
    assert_eq(_changed(after, read), [] as Array[String], "each byte for byte, its colour rounded as an autosave rounds it")


func test_an_opened_file_changed_on_disk_is_never_copied() -> void:
    var doc := _open(working)
    var file := FileAccess.open(working, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_8(0)
    file.close()
    var save := _autosave_now(doc)
    assert_eq(save.reuse.copied, 0, "An autosave copies nothing from a file changed since the open")
    assert_eq(save.reuse.encoded, _blobs, "and compresses every blob")
