## The autosave copies what its last autosave already wrote.
## An autosave keeps a record of its path as a Ctrl+S does, so an autosave with
## nothing changed since the last compresses no blob, and one after a stroke
## compresses only the chunks the stroke touched. An autosave rounds
## full precision colour as a Ctrl+S does, so a Ctrl+S after an autosave and an
## autosave after a Ctrl+S copy every blob the other wrote.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save hashes and reads chunks back and a load
## writes them.
const REQUIRES_GPU := true

const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

## The canvas, this many chunks a side.
const SIDE := 2
## Where a stroke on the paint layer lands, inside one chunk.
const STROKE_AT := Vector2(384.0, 128.0)
## Moves the paint's colour off the twelve bit grid, so a file written lossless
## would read back otherwise than the rounded one an autosave writes.
const OFF_GRID := 1.0 / 4099.0

const HIDE := Color(0.0, 0.0, 0.0, 1.0)
const RED := Color(0.8, 0.1, 0.05, 1.0)

static var working: String = SaDataRoot.path("test_working.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _autosave: SaAutosave = null
var _opened: Array[SaEasel] = []


## A full precision paint layer holding colour off the twelve bit grid over
## the whole canvas, and above it an adjustment layer whose own mask holds a
## hiding dab in three chunks, watched by an autosave that follows no setting.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(SIDE, SIDE) * SaChunk.SIZE)
    _doc = _easel.document
    _paint = SaLayer.new()
    _paint.name = "paint"
    _paint.schema = SaFieldSpec.schema_for_space(_doc.color_space)
    _doc.add_child(_paint)
    for y in SIDE:
        for x in SIDE:
            var colour := Color(0.25 * x + 0.125 + OFF_GRID, 0.25 * y + 0.25 + OFF_GRID, 0.5 + OFF_GRID, 1.0)
            _paint.get_or_create_chunk(Vector2i(x, y)).clear(colour)
    var adjustment := SaLayer.new()
    adjustment.name = "masked"
    adjustment.input = SaLayerTypeDescriptor.INPUT_BELOW
    _doc.add_child(adjustment)
    _doc.active_layer = adjustment
    _doc.mask_target = adjustment.add_mask()
    for at: Vector2 in [Vector2(128.0, 128.0), STROKE_AT, Vector2(128.0, 384.0)]:
        _stroke(at, 40.0, HIDE)
    _doc.active_layer = _paint
    _doc.mask_target = null
    _doc.file_path = working
    _autosave = SaAutosave.new()
    _autosave.follow_settings = false
    _autosave.attach(_doc)


func after_each() -> void:
    SaSadFile.finish_saves()
    _autosave.discard_recovery()
    _autosave.free()
    _autosave = null
    for easel in _opened:
        easel.free()
    _opened.clear()
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    for path: String in [working, working + "1", SaAutosave.recovery_path_for(working)]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## One hard dab of *color* through the document's paint context, as a stroke
## of its own, onto the mask it paints when one is targeted and else its
## active layer.
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


## Runs the autosave once, to the working file when *to_working_file* holds
## and otherwise to the recovery copy, and answers its save once it ended.
func _autosave_now(to_working_file: bool) -> SaSadSave:
    _autosave.write_working_file = to_working_file
    _doc.modified = true
    assert_eq(_autosave.save_now(), OK, "The autosave is asked for")
    var save: SaSadSave = SaSadSave._saves.back() if not SaSadSave._saves.is_empty() else null
    assert_true(SaSadFile.finish_saves(), "and it ends")
    assert_true(save != null and save.error == OK and save.rounds, "and writes the file rounding its colour")
    return save


## Saves as File > Save does, in the background and rounding, to the working
## file, and answers the save once it ended.
func _ctrl_s() -> SaSadSave:
    var save := SaSadFile.save_in_background(_doc, working, 0, null, true, Callable(), true)
    assert_true(SaSadFile.finish_saves(), "The Ctrl+S ends")
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


## *bytes*, float32 words, each rounded as a save that rounds writes it.
static func _rounded(bytes: PackedByteArray) -> PackedByteArray:
    var out := bytes.duplicate()
    for at in range(0, out.size(), 4):
        out.encode_u32(at, SaSadSnapshot.round_bits(out.decode_u32(at)))
    return out


## Reads that the file at *path* reopens holding *wanted*, texture for texture
## and byte for byte.
func _reopens_as(path: String, wanted: Dictionary[String, PackedByteArray], how: String) -> void:
    var read := _texels(_open(path))
    var keys := read.keys()
    var expected := wanted.keys()
    keys.sort()
    expected.sort()
    assert_eq(keys, expected, "%s: the file holds the same textures" % how)
    assert_eq(_changed(wanted, read), [] as Array[String], "%s: each byte for byte" % how)


## *texels* as a rounding save writes them, every colour texture rounded.
static func _as_saved(texels: Dictionary[String, PackedByteArray]) -> Dictionary[String, PackedByteArray]:
    var out := texels.duplicate()
    for key in _colour_keys(texels):
        out[key] = _rounded(texels[key])
    return out


## The colour textures in *texels*, every layer's, which a rounding save
## writes under a rounded key whatever they hold, the background's white as
## well as the paint's colour off the twelve bit grid.
static func _colour_keys(texels: Dictionary[String, PackedByteArray]) -> Array[String]:
    var found: Array[String] = []
    for key: String in texels:
        if key.ends_with("/albedo"):
            found.append(key)
    return found


func test_a_second_autosave_with_no_change_copies_every_blob() -> void:
    for to_working_file: bool in [false, true]:
        var where := "the working file" if to_working_file else "the recovery copy"
        var whole := _autosave_now(to_working_file)
        var blobs := whole.reuse.encoded
        var said := "The first autosave to %s writes the paint's and the mask's chunks, %d" % [where, blobs]
        assert_true(blobs >= SIDE * SIDE + 3, said)
        var again := _autosave_now(to_working_file)
        assert_eq(again.reuse.encoded, 0, "The second autosave to %s compresses no blob" % where)
        assert_eq(again.reuse.copied, blobs, "and copies every one")
        assert_eq(again.taken, 0, "and its snapshot copies no texture")
        var path := working if to_working_file else SaAutosave.recovery_path_for(working)
        _reopens_as(path, _as_saved(_texels(_doc)), "After the copying autosave to %s" % where)


func test_a_stroke_between_two_autosaves_compresses_only_what_it_touched() -> void:
    var blobs := _autosave_now(false).reuse.encoded
    var before := _texels(_doc)
    _stroke(STROKE_AT, 20.0, RED)
    var after_stroke := _texels(_doc)
    var touched := _changed(before, after_stroke)
    assert_true(touched.size() >= 1, "The stroke changed a chunk, %s" % [touched])
    var after := _autosave_now(false)
    assert_eq(after.reuse.encoded, touched.size(), "The autosave compresses only the chunks the stroke touched")
    assert_eq(after.reuse.copied, blobs - touched.size(), "and copies every other blob")
    var recovery := SaAutosave.recovery_path_for(working)
    _reopens_as(recovery, _as_saved(after_stroke), "The autosave after the stroke, its colour rounded")


func test_a_ctrl_s_after_an_autosave_and_the_next_autosave_copy_every_blob() -> void:
    var blobs := _autosave_now(true).reuse.encoded
    var texels := _texels(_doc)
    var colour := _colour_keys(texels)
    var said := "The background and the paint hold colour in every chunk, %s" % [colour]
    assert_eq(colour.size(), 2 * SIDE * SIDE, said)
    for key in colour:
        if key.begins_with("paint/"):
            assert_true(_rounded(texels[key]) != texels[key], "The colour of %s is off the twelve bit grid" % key)
    var ctrl_s := _ctrl_s()
    assert_eq(ctrl_s.reuse.encoded, 0, "The Ctrl+S after the autosave compresses nothing, the colour already rounded")
    assert_eq(ctrl_s.reuse.copied, blobs, "and copies every blob")
    _reopens_as(working, _as_saved(texels), "After the Ctrl+S, the colour rounded")
    var autosave := _autosave_now(true)
    assert_eq(autosave.reuse.encoded, 0, "The autosave after the Ctrl+S compresses nothing")
    assert_eq(autosave.reuse.copied, blobs, "and copies every blob")
    _reopens_as(working, _as_saved(texels), "After the autosave, the colour rounded")
