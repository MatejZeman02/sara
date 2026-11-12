## A save right after the shown season and light change takes
## as long as any other save. What made that save slow was not the change of
## season but its path: the door saves at once, and the first save at once to a
## path with no record of its own, after a save to the document's own file, had
## no record to copy from and compressed every blob again. It now copies from
## the last save to the document's own file, as the autosave already did.
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

static var own: String = SaDataRoot.path("test_own.sad")
static var final: String = SaDataRoot.path("test_final.sad")
static var later: String = SaDataRoot.path("test_later.sad")

var _easels: Array[SaEasel] = []
var _opened: Array[SaDocument] = []


func after_each() -> void:
    for doc in _opened:
        doc.free()
    _opened.clear()
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path: String in [own, final, later]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A document of a paint layer filling every chunk with a colour of its own.
func _document() -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _easels.append(easel)
    var doc := easel.document
    var paint := SaLayer.new()
    paint.name = "paint"
    paint.schema = SaFieldSpec.schema_for_space(doc.color_space)
    doc.add_child(paint)
    for y in SIDE:
        for x in SIDE:
            paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.25 * x + 0.125, 0.25 * y + 0.25, 0.5, 1.0))
    doc.active_layer = paint
    return doc


## Saves *doc* at once to *path* as the door's save does, `SaExport.save_sad`
## rounding and then the document marked as that file, and answers what the
## save reused and wrote. The three calls are `save_sad`'s own, made here so
## the suite holds the save's record of what it copied.
func _save_at_once(doc: SaDocument, path: String) -> SaSadSnapshot.Reuse:
    SaSadSnapshot.begin(doc, true, path)
    var saved := SaSadFile.save_file(doc, path, 0, null)
    var reuse := SaSadSnapshot.end()
    SaSadSnapshot.remember(reuse, saved == OK)
    assert_eq(saved, OK, "The save at once to %s lands" % path.get_file())
    doc.mark_saved(path)
    return reuse


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


## Reads that the file at *path* opens with the texels a save of *doc* writes,
## each one as the first save to the document's own file wrote it.
func _reads_as(path: String, wrote: Dictionary[String, PackedByteArray], how: String) -> void:
    var doc := SaDocument.new()
    _opened.append(doc)
    assert_eq(SaExport.load_sad(doc, path, SaCompositor.new()), OK, "%s: the file opens" % how)
    var back := _texels(doc)
    assert_eq(back.keys(), wrote.keys(), "%s: with every chunk of the document" % how)
    var differ := 0
    for key: String in wrote:
        if back.get(key, PackedByteArray()) != wrote[key]:
            differ += 1
    assert_eq(differ, 0, "%s: each as the copied file holds it" % how)


func test_a_save_at_once_to_another_path_after_a_save_to_the_own_file_copies_every_blob() -> void:
    var doc := _document()
    var whole := _save_at_once(doc, own)
    var blobs := whole.encoded
    assert_eq(whole.copied, 0, "The first save copies nothing")
    assert_true(blobs >= SIDE * SIDE, "and writes a blob of each chunk at least, %d" % blobs)
    var wrote := _texels(_open_copy(own))
    var elsewhere := _save_at_once(doc, final)
    assert_eq(elsewhere.encoded, 0, "A save at once to another path compresses no blob")
    assert_eq(elsewhere.copied, blobs, "and copies every one from the save to the document's own file")
    _reads_as(final, wrote, "The file the copying save wrote")
    var again := _save_at_once(doc, final)
    assert_eq([again.encoded, again.copied], [0, blobs], "A save again at once copies as many")


func test_a_stroke_before_the_save_at_once_to_another_path_compresses_its_chunk_alone() -> void:
    var doc := _document()
    var blobs := _save_at_once(doc, own).encoded
    _stroke(doc, STROKE_AT, 20.0, RED)
    var after := _save_at_once(doc, later)
    assert_eq(after.encoded, 1, "The save compresses the chunk the stroke changed")
    assert_eq(after.copied, blobs - 1, "and copies every other")
    var wrote := _texels(_open_copy(later))
    _reads_as(later, wrote, "The file after the stroke")
    var differ := 0
    var live := _texels(doc)
    for key: String in live:
        if wrote.get(key, PackedByteArray()) != live[key]:
            differ += 1
    assert_true(differ <= 1, "and every chunk but the stroked one reopens as the document holds it, %d differ" % differ)


## The file at *path* opened into a document of its own, freed after the test.
func _open_copy(path: String) -> SaDocument:
    var doc := SaDocument.new()
    _opened.append(doc)
    assert_eq(SaExport.load_sad(doc, path, SaCompositor.new()), OK, "%s opens" % path.get_file())
    return doc
