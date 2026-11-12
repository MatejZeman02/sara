## A save of the seasons file holds no frame over a tenth of
## a second. A Ctrl+S sends its hashes in shares, `SaSadHashShares`, reads
## their words in a turn of their own and walks a share of the layers a turn,
## `SaSadWalk`, so the shares are lowered here to make a small document's save
## take many turns as the seasons file's does. The file such a save writes
## opens with every chunk of every layer as the document held it, a stroke
## between two shares of the walk drops the walk and is in the file, and a
## save at once asked in the middle of the walk ends it first and both files
## open as the document stands.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice: the save reads its copies and the
## preview's cells back as frames are drawn.
const REQUIRES_GPU := true

const SIZE := Vector2i(700, 300)
const LAYERS := 6
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")
## A colour on the twelve bit grid, so a save that rounds keeps it as it is.
const OVER := Color(0.25, 0.75, 0.5, 1.0)

static var working: String = SaDataRoot.path("test_working.sad")
static var at_once: String = SaDataRoot.path("test_at_once.sad")

var _easel: SaEasel = null
var _doc: SaDocument = null
var _opened: Array[SaEasel] = []
var _a_turn := 0
var _usec_a_turn := 0


func before_each() -> void:
    SaSadSave.finish_all()
    _a_turn = SaSadSnapshot.HashShares.a_turn
    _usec_a_turn = SaSadWalk.usec_a_turn
    SaSadSnapshot.HashShares.a_turn = 3
    SaSadWalk.usec_a_turn = 0
    _easel = SaEasel.create_default(SIZE)
    _doc = _easel.document
    for index in LAYERS:
        var layer := SaLayer.new()
        layer.name = "layer %d" % index
        layer.schema = SaFieldSpec.schema_for_space(_doc.color_space)
        _doc.add_child(layer)
        for x in 3:
            if (x + index) % 2 == 0 or x == 1:
                layer.get_or_create_chunk(Vector2i(x, index % 2)).clear(Color(0.125 * x + 0.25, 0.0625 * index, 0.5, 1.0))
        _doc.active_layer = layer
    _easel.request_full_composite()
    _easel.process_pending_composite()


func after_each() -> void:
    SaSadSave.finish_all()
    SaSadSnapshot.HashShares.a_turn = _a_turn
    SaSadWalk.usec_a_turn = _usec_a_turn
    for easel in _opened:
        easel.free()
    _opened.clear()
    if _easel != null:
        _easel.free()
    _easel = null
    _doc = null
    for path: String in [working, working + "1", at_once, at_once + "1"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Starts a save of the document to *path* as Ctrl+S does, the preview taken
## on the card, the hashes asked for and the colour rounded.
func _start_as_the_key_does(path: String) -> SaSadSave:
    _doc.modified = true
    var shot := SaExport.take_preview(_easel)
    assert_not_null(shot, "The preview is taken on the card")
    return SaSadFile.save_in_background(_doc, path, 0, shot, true, Callable(), true)


## Turns the loop until *save* walks in shares, and answers the turns taken,
## or -1 when it never did within a hundred.
func _turns_to_the_walk(save: SaSadSave) -> int:
    for turns in 100:
        if save._walk != null:
            return turns
        SaSadSave.turn()
        OS.delay_usec(500)
    return -1


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


## The largest difference between two chunks' texels read as floats, or one
## when they are not of one length.
static func _largest(a: PackedByteArray, b: PackedByteArray) -> float:
    if a.size() != b.size():
        return 1.0
    var fa := a.to_float32_array()
    var fb := b.to_float32_array()
    var largest := 0.0
    for index in fa.size():
        largest = maxf(largest, absf(fa[index] - fb[index]))
    return largest


## Asserts the file at *path* opens with every chunk of every layer as
## *expected* holds it, saying *what* the file is.
func _opens_as(path: String, expected: Dictionary[String, PackedByteArray], what: String) -> void:
    var opened := _texels(_open(path))
    var differing := _differing(expected, opened)
    assert_eq(differing, [] as Array[String], "%s opens with every chunk of every layer as the document held it" % what)
    assert_eq(opened.size(), expected.size(), "and no chunk is missing or more")


func test_a_save_from_the_key_over_many_turns_opens_as_the_document_was() -> void:
    var before := _texels(_doc)
    assert_true(before.size() > LAYERS * 2, "The document holds chunks on every layer, %d of them" % before.size())
    var save := _start_as_the_key_does(working)
    assert_true(_turns_to_the_walk(save) > 2, "The hashes go out over several turns before the walk")
    var turns := 0
    while save._walk != null and turns < 100:
        SaSadSave.turn()
        turns += 1
    assert_true(turns >= LAYERS - 1, "The walk takes a layer a turn, %d turns" % turns)
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    assert_false(_doc.modified, "The document is marked saved, since nothing changed")
    _opens_as(working, before, "The file a Ctrl+S wrote")


func test_a_stroke_in_the_middle_of_the_walk_drops_it_and_is_in_the_file() -> void:
    var save := _start_as_the_key_does(working)
    assert_true(_turns_to_the_walk(save) > 0, "The save comes to its walk")
    SaSadSave.turn()
    assert_not_null(save._walk, "and is in the middle of it")
    var before_stroke := _texels(_doc)
    _stroke(Vector2(128.0, 128.0), 40.0, OVER)
    var after_stroke := _texels(_doc)
    assert_false(_differing(before_stroke, after_stroke).is_empty(), "The stroke changes the document")
    SaSadSave.turn()
    assert_null(save._walk, "The walk is dropped at the next turn, the document having moved")
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(save.error, OK, "and writes the file")
    assert_false(_doc.modified, "The document is marked saved as it stands")
    # The save from the key rounds the colour to the twelve bit grid, and the
    # dab's soft edge is off it, so a texel moves by half a step at most.
    var opened := _texels(_open(working))
    assert_eq(opened.keys(), after_stroke.keys(), "The file holding the stroke has every chunk the document has")
    var largest := 0.0
    for key: String in after_stroke:
        largest = maxf(largest, _largest(after_stroke[key], opened.get(key, PackedByteArray())))
    var within := 0.5 / 4095.0 + 1e-6
    assert_true(largest <= within, "and every texel within half a step of the twelve bit grid, %f apart at most" % largest)
    var stroked := "layer 5/(0, 0)/albedo"
    var moved := _largest(before_stroke.get(stroked, PackedByteArray()), opened[stroked])
    assert_true(moved > 0.1, "The stroke is in the file")


func test_a_save_at_once_in_the_middle_of_the_walk_ends_the_walk_first() -> void:
    var before := _texels(_doc)
    var save := _start_as_the_key_does(working)
    assert_true(_turns_to_the_walk(save) > 0, "The save comes to its walk")
    SaSadSave.turn()
    assert_not_null(save._walk, "and is in the middle of it")
    assert_eq(SaExport.save_sad(_doc, at_once, 0, null, true), OK, "A save at once writes its file")
    assert_null(save._walk, "after the walk in shares was ended in its frame")
    assert_true(SaSadSave.finish_all(), "The save from the key ends")
    assert_eq(save.error, OK, "and writes its file")
    _opens_as(working, before, "The file the key wrote")
    _opens_as(at_once, before, "The file the save at once wrote")
