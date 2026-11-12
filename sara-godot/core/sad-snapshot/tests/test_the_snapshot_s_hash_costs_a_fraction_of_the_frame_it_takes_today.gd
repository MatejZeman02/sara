## The snapshot's hash costs a fraction of the frame it takes
## today. `SaSadHash` records every texture's hash into one compute list and
## keeps a descriptor set a texture, and the hash is still taken afresh of the
## texels at every save. So a save after a stroke, after its undo and after
## another stroke compresses exactly the chunks the step changed, and the file
## reopens as the document stands. An open hashes its textures and their
## rounded copies the same way, through a ring of copies the list outlives.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The canvas, this many chunks a side, more chunks of one shape than the ring
## of rounded copies holds.
const SIDE := 4
## Where the two strokes land, each inside chunks of its own.
const FIRST_AT := Vector2(384.0, 128.0)
const SECOND_AT := Vector2(640.0, 896.0)
## Moves the paint's colour off the twelve bit grid, so a hash of a rounded
## copy and of the texture differ.
const OFF_GRID := 1.0 / 4099.0

const HIDE := Color(0.0, 0.0, 0.0, 1.0)
const RED := Color(0.8, 0.1, 0.05, 1.0)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)

static var working: String = SaDataRoot.path("test_working.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _opened: Array[SaEasel] = []


## A full precision paint layer holding a colour of its own in every chunk,
## off the twelve bit grid when *off_grid* holds, and above it an adjustment
## layer whose own mask holds a dab, so the hash meets textures of two formats
## in one list.
func _make(off_grid: bool) -> void:
    _easel = SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _doc = _easel.document
    _paint = SaLayer.new()
    _paint.name = "paint"
    _paint.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(_paint)
    var off := OFF_GRID if off_grid else 0.0
    for y in SIDE:
        for x in SIDE:
            var colour := Color(0.125 * x + 0.125 + off, 0.125 * y + 0.25 + off, 0.5 + off, 1.0)
            _paint.get_or_create_chunk(Vector2i(x, y)).clear(colour)
    var adjustment := SaLayer.new()
    adjustment.name = "masked"
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    _doc.add_child(adjustment)
    _doc.active_layer = adjustment
    _doc.mask_target = adjustment.add_mask()
    _stroke(Vector2(128.0, 128.0), 40.0, HIDE)
    _doc.mask_target = null
    _doc.active_layer = _paint
    _doc.file_path = working


func after_each() -> void:
    SaSadFile.finish_saves()
    for easel in _opened:
        easel.free()
    _opened.clear()
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    _paint = null
    for path: String in [working, working + "1"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## One hard dab of *color* as a stroke of its own, onto the mask it paints
## when one is targeted and else the active layer.
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


## Saves *doc* in the background to the working file, rounding when *rounds*
## holds, and answers the save once it ended.
func _save(doc: SaDocument, rounds: bool) -> SaSadSave:
    doc.modified = true
    var save := SaSadFile.save_in_background(doc, working, 0, null, true, Callable(), rounds)
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    return save


## The file at *path* opened into a document of its own.
func _open(path: String) -> SaDocument:
    var easel := SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _opened.append(easel)
    assert_eq(SaExport.load_sad(easel.document, path), OK, "The file %s opens" % path.get_file())
    return easel.document


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


## Reads that the working file reopens holding *wanted*, texture for texture
## and byte for byte.
func _reopens_as(wanted: Dictionary[String, PackedByteArray], how: String) -> void:
    var read := _texels(_open(working))
    var keys := read.keys()
    var expected := wanted.keys()
    keys.sort()
    expected.sort()
    assert_eq(keys, expected, "%s: the file holds the same textures" % how)
    assert_eq(_changed(wanted, read), [] as Array[String], "%s: each byte for byte" % how)


## Saves and reads that the save compressed exactly the textures that differ
## from *saved*, what the last save wrote, copied the rest of *blobs* and
## reopens as the document stands. Answers what the document holds now.
func _save_reads(saved: Dictionary[String, PackedByteArray], blobs: int, step: String) -> Dictionary[String, PackedByteArray]:
    var now := _texels(_doc)
    var changed := _changed(saved, now)
    assert_true(changed.size() >= 1, "%s changed a chunk, %s" % [step, changed])
    assert_true(changed.size() < blobs, "and left others as they were")
    var save := _save(_doc, false)
    assert_eq(save.reuse.encoded, changed.size(), "The save after %s compresses exactly the chunks it changed" % step)
    assert_eq(save.reuse.copied, blobs - changed.size(), "and copies every other blob")
    _reopens_as(now, "After %s" % step)
    return now


func test_a_stroke_its_undo_and_another_stroke_each_save_exactly_what_they_changed() -> void:
    _make(true)
    var whole := _save(_doc, false)
    var blobs := whole.reuse.encoded
    var said := "The first save writes the background's, the paint's and the mask's chunks, %d" % blobs
    assert_true(blobs >= 2 * SIDE * SIDE + 1, said)
    var again := _save(_doc, false)
    assert_eq(again.reuse.encoded, 0, "A save with nothing changed compresses no blob")
    assert_eq(again.reuse.copied, blobs, "and copies every one")
    var saved := _texels(_doc)
    var before_stroke := saved
    _stroke(FIRST_AT, 20.0, RED)
    saved = _save_reads(saved, blobs, "the first stroke")
    assert_true(_doc.undo(), "The stroke undoes")
    saved = _save_reads(saved, blobs, "the undo")
    assert_eq(_changed(before_stroke, saved), [] as Array[String], "The undo gave back the texels before the stroke")
    _stroke(SECOND_AT, 20.0, BLUE)
    _save_reads(saved, blobs, "the second stroke")


func test_the_first_rounding_save_after_an_open_copies_colour_the_rounding_leaves_as_it_is() -> void:
    _make(false)
    var blobs := _save(_doc, false).reuse.encoded
    var texels := _texels(_doc)
    var opened := _open(working)
    var first := _save(opened, true)
    assert_eq(first.reuse.encoded, 0, "The rounding save after the open compresses nothing, its colour on the grid")
    assert_eq(first.reuse.copied, blobs, "and copies every blob the open hashed, each rounded copy's hash its own")
    _reopens_as(texels, "After the rounding save of the opened file")


func test_an_open_of_colour_off_the_grid_writes_the_colour_a_rounding_save_rounds() -> void:
    _make(true)
    var blobs := _save(_doc, false).reuse.encoded
    var opened := _open(working)
    var first := _save(opened, true)
    assert_eq(first.reuse.encoded, SIDE * SIDE, "The rounding save after the open compresses the paint's colour")
    assert_eq(first.reuse.copied, blobs - SIDE * SIDE, "and copies the background and the mask, which rounding leaves alone")
