## An autosave is the background save File > Save runs. The
## tick returns with the save still running, a stroke painted meanwhile is in
## the document, and a copy never outlives a document that turned clean while
## it was being written. The autosave walks once its hashes are in,
## as a Ctrl+S does, so a stroke laid before that walk is in the copy too.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice: the save reads its copies back as frames
## are drawn, and off it the save is written at once.
const REQUIRES_GPU := true

## Several layers, each with a chunk of its own colour.
const LAYERS := 12

## What the stroke paints, which no layer holds before it.
const STROKE := Color(5.0, 0.25, 0.5, 1.0)

static var scratch: String = SaDataRoot.path("test_autosave.sad")

var _easel: SaEasel = null
var _autosave: SaAutosave = null
var _versions_kept := 1


func before_each() -> void:
    SaSadFile.finish_saves()
    _versions_kept = SaSettings.sad_versions
    _easel = SaEasel.create_default(Vector2i(256, 256))
    var doc := _easel.document
    var ops := SaLayerOps.new(doc)
    # Bounded, so a layer that cannot be added ends the loop and the count is
    # asserted where the document is used, rather than the run looping.
    var adds := 0
    while paint_layers(doc).size() < LAYERS and adds < LAYERS:
        ops.add()
        adds += 1
    assert_eq(paint_layers(doc).size(), LAYERS, "The document has its layers")
    var layers := paint_layers(doc)
    for index in layers.size():
        layers[index].get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).clear(colour_of(index))
    _autosave = SaAutosave.new()
    _autosave.follow_settings = false
    _autosave.interval_seconds = 60.0
    _autosave.attach(doc)
    _easel.add_child(_autosave)


func after_each() -> void:
    SaSadFile.finish_saves()
    _autosave.discard_recovery()
    SaSettings.sad_versions = _versions_kept
    _easel.free()
    for path: String in [scratch, scratch + "1", SaAutosave.recovery_path_for(scratch)]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The colour layer *index* is filled with.
static func colour_of(index: int) -> Color:
    return Color(index / 16.0, 1.0 - index / 16.0, 0.5 + index * 0.25, 1.0)


## Every layer of *doc* but the stroke buffer, bottom first.
static func paint_layers(doc: SaDocument) -> Array[SaLayer]:
    var found: Array[SaLayer] = []
    for child in doc.get_children():
        if child is SaLayer and child != doc.stroke_layer:
            found.append(child as SaLayer)
    return found


## The first texel of *layer*'s colour, or black when it holds no chunk.
static func texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i.ZERO, SaFieldSpec.ALBEDO)
    if texture == null:
        return Color(0, 0, 0, 0)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Color(bytes.decode_float(0), bytes.decode_float(4), bytes.decode_float(8), bytes.decode_float(12))


## Paints a stroke of [constant STROKE] over *layer*'s chunk, one undo step.
static func paint(doc: SaDocument, layer: SaLayer) -> void:
    doc.active_layer = layer
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).clear(STROKE)
    doc.commit_stroke()


## Saves the document as the painter's file at once, so it is clean.
func _saved_once() -> void:
    var doc := _easel.document
    assert_eq(SaExport.save_sad(doc, scratch, 0), OK, "Saved once")
    doc.mark_saved(scratch)
    assert_false(doc.modified, "and clean")


func test_the_tick_returns_with_the_save_running_and_a_stroke_before_its_walk_is_in_the_copy() -> void:
    var doc := _easel.document
    var layers := paint_layers(doc)
    assert_eq(layers.size(), LAYERS, "The document holds %d layers" % LAYERS)
    doc.modified = true
    _autosave.note_activity(0)
    assert_true(_autosave.tick(60.0, 1_000_000), "The interval passed and the painter rested, so the autosave is asked")
    assert_true(SaSadFile.saving(), "and the tick returned with the save still running")
    assert_eq(_autosave.last_written, "", "with no copy claimed before it is on disk")
    var copy := _autosave.recovery_path()
    assert_false(FileAccess.file_exists(copy), "and none written yet")
    assert_false(_autosave.tick(60.0, 2_000_000), "A tick while it runs asks for no second save")

    paint(doc, layers[0])
    assert_true(texel(layers[0]).is_equal_approx(STROKE), "A stroke lands on the bottom layer while the save runs")
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_eq(_autosave.last_written, copy, "and the copy is claimed once it is on disk")
    assert_true(texel(layers[0]).is_equal_approx(STROKE), "The stroke is in the document")
    assert_true(doc.modified, "which still has unsaved work")

    var reopened := SaDocument.new()
    assert_eq(SaExport.load_sad(reopened, copy, SaCompositor.new()), OK, "The copy opens whole")
    var back := paint_layers(reopened)
    assert_eq(back.size(), LAYERS, "with every layer")
    var same := 0
    for index in range(1, back.size()):
        if texel(back[index]).is_equal_approx(colour_of(index)):
            same += 1
    assert_eq(same, LAYERS - 1, "each layer above the stroke holding its own colour")
    assert_true(texel(back[0]).is_equal_approx(STROKE), "and the bottom one the stroke, laid before the walk")
    reopened.free()


func test_a_recovery_autosave_leaves_the_document_unsaved() -> void:
    var doc := _easel.document
    _saved_once()
    paint(doc, paint_layers(doc)[0])
    assert_eq(_autosave.save_now(), OK, "The recovery autosave is asked for")
    assert_true(SaSadFile.finish_saves(), "and ends")
    assert_true(FileAccess.file_exists(SaAutosave.recovery_path_for(scratch)), "The copy is beside the file")
    assert_true(doc.modified, "and the document is still unsaved, a copy claims nothing")
    assert_eq(doc.file_path, scratch, "and still the painter's file")


func test_a_working_file_autosave_marks_the_document_saved_and_keeps_the_file_before_it() -> void:
    var doc := _easel.document
    SaSettings.sad_versions = 1
    _saved_once()
    var before := FileAccess.get_file_as_bytes(scratch)
    paint(doc, paint_layers(doc)[0])
    _autosave.write_working_file = true
    var heard: Array[String] = []
    _autosave.saved.connect(func(path: String) -> void: heard.append(path))
    assert_eq(_autosave.save_now(), OK, "The working-file autosave is asked for")
    assert_true(doc.modified, "and the document is unsaved until the file is written")
    assert_eq(heard, [] as Array[String], "and nothing says saved yet")
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_false(doc.modified, "and marks the document saved")
    assert_eq(heard, [scratch] as Array[String], "said once, on disk")
    assert_eq(FileAccess.get_file_as_bytes(scratch + "1"), before, "The file before it is kept as .sad1")
    assert_false(FileAccess.file_exists(SaAutosave.recovery_path_for(scratch)), "and no recovery copy is written")


func test_a_save_while_the_copy_is_written_leaves_no_copy() -> void:
    var doc := _easel.document
    _saved_once()
    paint(doc, paint_layers(doc)[0])
    assert_eq(_autosave.save_now(), OK, "The recovery autosave is asked for")
    # File > Save, through the door `SaDocumentFiles.save_document` calls.
    SaSadFile.save_in_background(doc, scratch, 0, null, true)
    assert_true(SaSadFile.finish_saves(), "Both saves end")
    assert_false(doc.modified, "File > Save made the document clean")
    assert_false(FileAccess.file_exists(SaAutosave.recovery_path_for(scratch)), "and no recovery copy is left")
    assert_eq(_autosave.last_written, "", "nor one the autosave remembers")


func test_an_undo_to_the_saved_state_while_the_copy_is_written_leaves_no_copy() -> void:
    var doc := _easel.document
    _saved_once()
    paint(doc, paint_layers(doc)[0])
    assert_true(doc.modified, "The stroke left unsaved work")
    assert_eq(_autosave.save_now(), OK, "The recovery autosave is asked for")
    assert_true(doc.undo(), "An undo while it is written")
    assert_false(doc.modified, "brings the document back to the saved state")
    assert_true(SaSadFile.finish_saves(), "The save ends")
    assert_false(FileAccess.file_exists(SaAutosave.recovery_path_for(scratch)), "and no recovery copy is left")
    assert_eq(_autosave.last_written, "", "nor one the autosave remembers")
