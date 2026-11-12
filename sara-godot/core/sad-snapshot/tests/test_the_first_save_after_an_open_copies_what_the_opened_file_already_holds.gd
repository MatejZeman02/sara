## The first save after an open copies what the opened file
## already holds. Opening a `.sad` leaves a record of the file for the document
## it made, each blob under the key the next save computes for the texture it
## filled, so that save copies every chunk unchanged since the open, writes
## only those a stroke touched, and saves whole when another writer changed the
## file in between.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The canvas, this many chunks a side.
const SIDE := 2
## Where a stroke on the paint layer lands, inside one chunk.
const STROKE_AT := Vector2(384.0, 128.0)

const HIDE := Color(0.0, 0.0, 0.0, 1.0)
const RED := Color(0.8, 0.1, 0.05, 1.0)

static var first: String = SaDataRoot.path("test_first.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _easels: Array[SaEasel] = []


## A paint layer holding colour over the whole canvas, at values twelve
## significant bits hold so a rounding save writes them as they are, and above
## it an adjustment layer whose own mask holds a hiding dab in three chunks.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _doc = _easel.document
    _paint = SaLayer.new()
    _paint.name = "paint"
    _paint.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(_paint)
    _fill(_paint, 0.0)
    var adjustment := SaLayer.new()
    adjustment.name = "masked"
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    _doc.add_child(adjustment)
    _doc.active_layer = adjustment
    _doc.mask_target = adjustment.add_mask()
    for at: Vector2 in [Vector2(128.0, 128.0), STROKE_AT, Vector2(128.0, 384.0)]:
        _stroke(_doc, at, 40.0, HIDE)


func after_each() -> void:
    SaSadFile.finish_saves()
    for easel in _easels:
        easel.free()
    _easels.clear()
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    DirAccess.remove_absolute(ProjectSettings.globalize_path(first))


## Clears every chunk of *layer* to a colour of its place, moved by *off*.
func _fill(layer: SaLayer, off: float) -> void:
    for y in SIDE:
        for x in SIDE:
            layer.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.25 * x + 0.125 + off, 0.25 * y + 0.25, 0.5, 1.0))


## One hard dab of *color* through *doc*'s paint context, as a stroke of its
## own, onto the mask it paints when one is targeted and else its active layer.
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


## Saves *doc* to [member first] in the background, rounding as File > Save
## does unless *rounds* is false, and answers the save once it ended.
func _save(doc: SaDocument, rounds := true) -> SaSadSave:
    var save := SaSadFile.save_in_background(doc, first, 0, null, true, Callable(), rounds)
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    return save


## The file at [member first] opened as File > Open opens it, into a document
## of its own: read, its history emptied and the path named.
func _open() -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _easels.append(easel)
    var doc := easel.document
    assert_eq(SaExport.load_sad(doc, first), OK, "The file opens")
    doc.undo_redo.clear_history()
    doc.history.reset()
    doc.mark_saved(first)
    return doc


## Every texture of *doc* as the card holds it, a layer's fields and an own
## mask's chunks, by the layer's name, the place and the field.
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
        if layer.mask != null and layer.mask.is_own():
            for grid_pos: Vector2i in layer.mask.grid_positions():
                var texture := layer.mask.texture_for(grid_pos)
                if texture != null and texture.rid.is_valid():
                    found["%s/mask/%s" % [layer.name, grid_pos]] = texture.rd.texture_get_data(texture.rid, 0)
    return found


## The keys of *after* new or holding other texels than in *before*.
static func _changed(before: Dictionary[String, PackedByteArray], after: Dictionary[String, PackedByteArray]) -> Array[String]:
    var found: Array[String] = []
    for key: String in after:
        if not before.has(key) or before[key] != after[key]:
            found.append(key)
    return found


## *bytes*, float32 words, each rounded as a save that rounds writes it.
static func _rounded(bytes: PackedByteArray) -> PackedByteArray:
    var out := bytes.duplicate()
    for at in range(0, out.size(), 4):
        out.encode_u32(at, SaSadSnapshot.round_bits(out.decode_u32(at)))
    return out


## Reads that the file reopens holding *wanted*, texture for texture and byte
## for byte.
func _reopens_as(wanted: Dictionary[String, PackedByteArray], how: String) -> void:
    var read := _texels(_open())
    var keys := read.keys()
    var expected := wanted.keys()
    keys.sort()
    expected.sort()
    assert_eq(keys, expected, "%s: the file holds the same textures" % how)
    assert_eq(_changed(wanted, read), [] as Array[String], "%s: each byte for byte" % how)


func test_the_first_save_after_an_open_copies_every_blob() -> void:
    var whole := _save(_doc)
    var blobs := whole.reuse.encoded
    assert_eq(whole.reuse.copied, 0, "The first document's save copies nothing")
    assert_true(blobs >= SIDE * SIDE + 3, "and writes the paint's chunks and the mask's, %d" % blobs)
    var opened := _open()
    var again := _save(opened)
    assert_eq(again.reuse.encoded, 0, "The first save after the open compresses no blob")
    assert_eq(again.reuse.copied, blobs, "and copies every one")
    assert_eq(again.taken, 0, "and its snapshot copies no texture")
    _reopens_as(_texels(_doc), "After the copying save")


func test_a_stroke_after_the_open_compresses_only_what_it_touched() -> void:
    var blobs := _save(_doc).reuse.encoded
    var opened := _open()
    var before := _texels(opened)
    for child in opened.get_children():
        if child is SaLayer and str(child.name) == "paint":
            opened.active_layer = child
    opened.mask_target = null
    _stroke(opened, STROKE_AT, 20.0, RED)
    var after_stroke := _texels(opened)
    var touched := _changed(before, after_stroke)
    assert_true(touched.size() >= 1, "The stroke changed a chunk, %s" % [touched])
    var after := _save(opened)
    assert_eq(after.reuse.encoded, touched.size(), "The save compresses only the chunks the stroke touched")
    assert_eq(after.reuse.copied, blobs - touched.size(), "and copies every other blob")
    # The stroke's colour is off the twelve bit grid, so the file holds it
    # rounded, as the save rounds it.
    for key: String in touched:
        after_stroke[key] = _rounded(after_stroke[key])
    _reopens_as(after_stroke, "After the stroke")


func test_a_file_changed_on_disk_after_the_open_is_saved_whole() -> void:
    var blobs := _save(_doc).reuse.encoded
    var opened := _open()
    # Another writer leaves the file a byte longer, which a reader of the
    # format never reaches but the record sees.
    var file := FileAccess.open(first, FileAccess.READ_WRITE)
    file.seek_end()
    file.store_8(0)
    file.close()
    var after := _save(opened)
    assert_eq(after.reuse.copied, 0, "The save copies nothing from the changed file")
    assert_eq(after.reuse.encoded, blobs, "and writes every blob afresh")
    _reopens_as(_texels(_doc), "After the whole save")


## A file a save that does not round wrote, colour off the twelve bit grid,
## gives a save that rounds nothing to copy for that colour, since its blobs
## are not what the rounding save writes. The rest is still copied.
func test_a_file_of_unrounded_colour_is_not_copied_where_the_save_rounds() -> void:
    _fill(_paint, 1.0 / 4099.0)
    var whole := _save(_doc, false)
    var blobs := whole.reuse.encoded
    var opened := _open()
    var again := _save(opened)
    assert_eq(again.reuse.encoded, SIDE * SIDE, "The rounding save writes the paint's four colour chunks")
    assert_eq(again.reuse.copied, blobs - SIDE * SIDE, "and copies the mask's")
    var opened_again := _open()
    var paint_texels := _texels(opened_again)
    var rounded := 0
    for key: String in paint_texels:
        if key.begins_with("paint/"):
            rounded += int(_rounded(paint_texels[key]) == paint_texels[key])
    assert_eq(rounded, SIDE * SIDE, "and the colour it wrote is rounded")
