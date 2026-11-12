## The frame that takes the snapshot of a save stays under a
## tenth of a second. A Ctrl+S takes its preview on the card and reads it over
## the save's frames, `SaExport.PreviewShot`, and asks for the hashes in the
## frame of the key and walks in the turn they come back in. So the file a
## save writes that way opens with every chunk of every layer as the document
## holds it, its preview is the one the read in one frame made, to the byte,
## and a change made before the hashes are in is in the file and the document
## is marked saved as it stands.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice: the save reads its copies and the
## preview's cells back as frames are drawn.
const REQUIRES_GPU := true

## Wider than two chunks and taller than one, neither a whole number of them,
## so the preview has cells cut short at its right and bottom edges.
const SIZE := Vector2i(700, 300)

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
## A colour the second layer paints over one chunk, on the twelve bit grid so
## the save's rounding leaves it as it is.
const OVER := Color(0.25, 0.75, 0.5, 1.0)

static var working: String = SaDataRoot.path("test_working.sad")
static var before: String = SaDataRoot.path("test_before.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _opened: Array[SaEasel] = []


func before_each() -> void:
    SaSadSave.finish_all()
    _easel = SaEasel.create_default(SIZE)
    _doc = _easel.document
    var paint := SaLayer.new()
    paint.name = "paint"
    paint.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(paint)
    for y in 2:
        for x in 3:
            paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.125 * x + 0.25, 0.25 * y + 0.25, 0.5, 1.0))
    var over := SaLayer.new()
    over.name = "over"
    over.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(over)
    over.get_or_create_chunk(Vector2i(1, 0)).clear(OVER)
    _doc.active_layer = paint
    _composite()


func after_each() -> void:
    SaSadSave.finish_all()
    for easel in _opened:
        easel.free()
    _opened.clear()
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    for path: String in [working, working + "1", before, before + "1"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _composite() -> void:
    _easel.request_full_composite()
    _easel.process_pending_composite()


## One hard dab of *color* as a stroke of its own onto the active layer.
func _stroke(pos: Vector2, radius: float, color: Color) -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
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
    _doc.commit_stroke()


## Saves the document to *path* as Ctrl+S does, the preview taken on the card
## and the hashes asked for, and answers the save once it ended.
func _save_as_the_key_does(path: String) -> SaSadSave:
    _doc.modified = true
    var shot := SaExport.take_preview(_easel)
    assert_not_null(shot, "The preview is taken on the card")
    var save := SaSadFile.save_in_background(_doc, path, 0, shot, true, Callable(), true)
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    return save


## The file at *path* opened into a document of its own.
func _open(path: String) -> SaDocument:
    var easel := SaEasel.create_default(SIZE)
    _opened.append(easel)
    assert_eq(SaExport.load_sad(easel.document, path), OK, "The file %s opens" % path.get_file())
    return easel.document


## Every chunk of every layer of *doc* as the card holds it, by the layer's
## name, the place and the field.
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


## The keys whose texels differ between *a* and *b*, or that only one holds.
static func _differing(a: Dictionary[String, PackedByteArray], b: Dictionary[String, PackedByteArray]) -> Array[String]:
    var keys: Array[String] = []
    for key: String in a:
        if not b.has(key) or b[key] != a[key]:
            keys.append(key)
    for key: String in b:
        if not a.has(key):
            keys.append(key)
    return keys


func test_the_preview_read_over_frames_is_the_one_read_in_one_frame_to_the_byte() -> void:
    var at_once := SaExport.get_preview_image(_easel)
    var shot := SaExport.take_preview(_easel)
    assert_not_null(at_once, "The preview reads in one frame")
    assert_not_null(shot, "and is taken on the card")
    if at_once == null or shot == null:
        return
    assert_eq(shot.cells.size(), 6, "The picture is cut into the six cells of the export")
    var bytes: Array[PackedByteArray] = []
    var format := shot.picture.format
    for index in shot.cells.size():
        var scratch := shot.cell(index)
        assert_not_null(scratch, "Cell %d is put on a scratch of its own" % index)
        bytes.append(scratch.rd.texture_get_data(scratch.rid, 0) if scratch != null else PackedByteArray())
    shot.let_go()
    var over_frames := SaExport.PreviewShot.image_of(shot.size, shot.cells, format, bytes)
    assert_not_null(over_frames, "The cells' bytes make a picture")
    if over_frames == null:
        return
    assert_eq(over_frames.get_size(), at_once.get_size(), "of the canvas's size")
    assert_eq(over_frames.get_format(), at_once.get_format(), "at eight bits a channel")
    assert_true(over_frames.get_data() == at_once.get_data(), "and every byte of it is the read in one frame's")


func test_a_save_from_the_key_opens_as_the_document_stands_with_the_same_preview() -> void:
    # The save as it was before the snapshot frame was bounded, the preview read in its frame and the
    # walk at once, for the preview to compare with.
    _doc.modified = true
    var old := SaSadSave.start(_doc, before, 0, SaExport.get_preview_image(_easel), true, Callable(), true)
    assert_true(SaSadSave.finish_all(), "The save as it was ends")
    assert_eq(old.error, OK, "and writes its file")
    var save := _save_as_the_key_does(working)
    assert_false(_doc.modified, "The document is marked saved, since nothing changed after the walk")
    assert_eq(_doc.file_path, working, "as the file written")
    var opened := _open(working)
    var differing := _differing(_texels(_doc), _texels(opened))
    assert_eq(differing, [] as Array[String], "Every chunk of every layer opens as the document holds it")
    assert_eq(_texels(opened).size(), _texels(_doc).size(), "and no chunk is missing or more")
    var preview := SaSadFile.read_preview(working)
    var preview_before := SaSadFile.read_preview(before)
    assert_not_null(preview, "The file holds a preview")
    if preview != null and preview_before != null:
        assert_eq(preview.get_size(), preview_before.get_size(), "of the size the save before it was bounded wrote")
        assert_true(preview.get_data() == preview_before.get_data(), "and the same picture to the byte")
    assert_eq(save.error, OK, "The save from the key wrote no error")


func test_a_stroke_before_the_hashes_are_in_is_in_the_file_and_the_document_is_saved() -> void:
    _doc.modified = true
    var shot := SaExport.take_preview(_easel)
    # Not rounded, since the dab's soft edge is off the twelve bit grid and
    # the file is read against the document texel for texel.
    var save := SaSadFile.save_in_background(_doc, working, 0, shot, true, Callable(), false)
    assert_true(SaSadSave.is_running(), "The save waits for its hashes")
    var before_stroke := _texels(_doc)
    _stroke(Vector2(128.0, 128.0), 40.0, OVER)
    assert_false(_differing(before_stroke, _texels(_doc)).is_empty(), "The stroke changes the document")
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    var opened := _open(working)
    var differing := _differing(_texels(_doc), _texels(opened))
    assert_eq(differing, [] as Array[String], "The file holds the stroke, as the document did at the walk")
    assert_false(_doc.modified, "and the document is marked saved as it stands")
