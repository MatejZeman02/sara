## A save copies an unchanged mask instead of compressing it
## again. The snapshot's hash takes in the chunks of every mask of its own a
## save writes, so a mask chunk unchanged since the last save to the same path
## is copied from the file it replaces, and a chunk a stroke touched, allocated
## or emptied is written or left out as a whole save would.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The canvas, this many chunks a side.
const SIDE := 2
## The chunk a mask stroke lands in alone, and a document pixel at its middle.
const STROKED := Vector2i(1, 0)
const STROKED_AT := Vector2(384.0, 128.0)
## A chunk the first mask strokes leave alone, and a pixel at its middle.
const LATER := Vector2i(1, 1)
const LATER_AT := Vector2(384.0, 384.0)

const RED := Color(0.8, 0.1, 0.05, 1.0)
const HIDE := Color(0.0, 0.0, 0.0, 1.0)
const GREY := Color(0.4, 0.4, 0.4, 1.0)
const SHOW := Color(1.0, 1.0, 1.0, 1.0)

static var first: String = SaDataRoot.path("test_first.sad")
static var other: String = SaDataRoot.path("test_other.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _adjustment: SaLayer = null
var _opened: Array[SaDocument] = []


## A paint layer holding colour over the whole canvas, and above it an
## adjustment layer whose own mask holds a hiding dab in three of the four
## chunks, [constant LATER] left empty.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _doc = _easel.document
    var paint := SaLayer.new()
    paint.name = "paint"
    paint.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(paint)
    for y in SIDE:
        for x in SIDE:
            paint.get_or_create_chunk(Vector2i(x, y)).clear(Color(0.2 * x + 0.1, 0.3 * y + 0.2, 0.5, 1.0))
    _adjustment = SaLayer.new()
    _adjustment.name = "masked"
    _adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    _doc.add_child(_adjustment)
    _doc.active_layer = _adjustment
    _doc.mask_target = _adjustment.add_mask()
    for at: Vector2 in [Vector2(128.0, 128.0), STROKED_AT, Vector2(128.0, 384.0)]:
        _stroke(at, 40.0, HIDE)


func after_each() -> void:
    SaSadFile.finish_saves()
    for doc in _opened:
        doc.free()
    _opened.clear()
    _easel.free()
    _easel = null
    _doc = null
    _adjustment = null
    for path: String in [first, other]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## One hard dab of *color* through the paint context, as a stroke of its own,
## onto the mask the document paints when one is targeted.
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


## Saves as File > Save does, in the background and rounding, and answers the
## save once it ended.
func _save() -> SaSadSave:
    var save := SaSadFile.save_in_background(_doc, first, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    return save


## Every chunk of *mask* as the card holds it, by position.
static func _mask_texels(mask: SaMask) -> Dictionary[Vector2i, PackedByteArray]:
    var found: Dictionary[Vector2i, PackedByteArray] = {}
    for grid_pos: Vector2i in mask.grid_positions():
        var texture := mask.texture_for(grid_pos)
        if texture != null and texture.rid.is_valid():
            found[grid_pos] = texture.rd.texture_get_data(texture.rid, 0)
    return found


## The positions of *after* new or holding other texels than in *before*.
static func _changed(
    before: Dictionary[Vector2i, PackedByteArray], after: Dictionary[Vector2i, PackedByteArray]
) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    for grid_pos: Vector2i in after:
        if not before.has(grid_pos) or before[grid_pos] != after[grid_pos]:
            found.append(grid_pos)
    return found


## Reads that the file reopens with the adjustment layer's mask equal to the
## document's, chunk for chunk and texel for texel.
func _reads_as_document(how: String) -> void:
    var doc := SaDocument.new()
    _opened.append(doc)
    assert_eq(SaExport.load_sad(doc, first, SaCompositor.new()), OK, "%s: the file opens" % how)
    var back: SaLayer = null
    for child in doc.get_children():
        if child is SaLayer and str(child.name) == "masked":
            back = child
    assert_true(back != null and back.mask != null, "%s: with the adjustment layer and its mask" % how)
    if back == null or back.mask == null:
        return
    var live := _mask_texels(_adjustment.mask)
    var read := _mask_texels(back.mask)
    assert_eq(read.keys(), live.keys(), "%s: the file holds the mask's chunks and no other" % how)
    var differ := 0
    for grid_pos: Vector2i in live:
        if read.get(grid_pos, PackedByteArray()) != live[grid_pos]:
            differ += 1
    assert_eq(differ, 0, "%s: every mask chunk reopens as the document holds it" % how)


func test_a_second_save_with_nothing_changed_compresses_no_blob() -> void:
    var whole := _save()
    assert_eq(_mask_texels(_adjustment.mask).size(), 3, "The mask holds three chunks")
    assert_eq(whole.reuse.copied, 0, "The first save copies nothing")
    var blobs := whole.reuse.encoded
    assert_true(blobs >= SIDE * SIDE + 3, "and writes the paint's chunks and the mask's, %d" % blobs)
    var again := _save()
    assert_eq(again.reuse.encoded, 0, "The second save compresses no blob")
    assert_eq(again.reuse.copied, blobs, "and copies every one")
    assert_eq(again.taken, 0, "and its snapshot copies no texture")
    _reads_as_document("After the copying save")


func test_a_stroke_on_the_mask_compresses_only_the_chunk_it_touched() -> void:
    var blobs := _save().reuse.encoded
    var before := _mask_texels(_adjustment.mask)
    _stroke(STROKED_AT, 20.0, GREY)
    var touched := _changed(before, _mask_texels(_adjustment.mask))
    assert_eq(touched, [STROKED] as Array[Vector2i], "The stroke changed the one mask chunk it landed in")
    var after := _save()
    assert_eq(after.reuse.encoded, touched.size(), "The save compresses only the touched mask chunk")
    assert_eq(after.reuse.copied, blobs - touched.size(), "and copies every other blob")
    _reads_as_document("After the stroke")


func test_a_mask_chunk_allocated_or_emptied_is_written_or_left_out() -> void:
    var blobs := _save().reuse.encoded
    _stroke(LATER_AT, 30.0, HIDE)
    assert_true(LATER in _adjustment.mask.grid_positions(), "A stroke where the mask held nothing allocates a chunk")
    var grown := _save()
    assert_eq(grown.reuse.encoded, 1, "The save compresses the new chunk alone")
    assert_eq(grown.reuse.copied, blobs, "and copies every blob it had")
    _reads_as_document("After the allocation")
    # Shown whole again in that chunk alone, as an eraser that covers it would
    # leave it, written on the card as the door's writes are.
    _adjustment.mask.texture_for(STROKED).clear(SHOW)
    var shrunk := _save()
    assert_false(STROKED in _adjustment.mask.grid_positions(), "A chunk shown whole again is let go")
    # The emptied chunk changed, so the walk takes it as it takes any changed
    # chunk, and the sweep on its copy then leaves it out of the header.
    assert_eq(shrunk.reuse.encoded, 1, "The save takes the emptied chunk alone")
    assert_eq(shrunk.reuse.copied, blobs, "and copies every other blob")
    _reads_as_document("After the emptying")
    var listed := _mask_listed(first)
    assert_false(STROKED in listed, "The file lists no mask chunk where it was emptied")
    var whole := SaSadFile.save_in_background(_doc, other, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves() and whole.error == OK, "A whole save to another path lands")
    assert_eq(whole.reuse.copied, 0, "copying nothing")
    var wanted := _mask_listed(other)
    listed.sort()
    wanted.sort()
    assert_eq(listed, wanted, "and lists the mask chunks the copying save listed")


## The positions the header of the file at *path* lists for the adjustment
## layer's mask.
static func _mask_listed(path: String) -> Array[Vector2i]:
    var found: Array[Vector2i] = []
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return found
    file.get_buffer(4)
    file.get_32()
    var packed := file.get_32()
    var raw := file.get_32()
    var text := file.get_buffer(packed).decompress(raw, SaSadFile.SAD_BLOB_COMPRESS).get_string_from_utf8()
    var header := SaTyped.strings(JSON.parse_string(text))
    for entry: Variant in header.get("layers", []):
        var layer := SaTyped.strings(entry)
        if str(layer.get("name", "")) != "masked":
            continue
        for slot: Variant in SaTyped.strings(layer.get("mask", {})).get("chunks", []):
            var at := SaTyped.strings(slot)
            found.append(Vector2i(SaTyped.int_at(at, "x", 0), SaTyped.int_at(at, "y", 0)))
    return found
