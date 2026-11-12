## A save runs in the background, and the file holds the
## document as it was when the save was asked for. A stroke painted and a
## layer deleted while it runs are in the document and not in the file, and
## the document stays unsaved.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice: the save reads its copies back as frames
## are drawn.
const REQUIRES_GPU := true

## The layers the document holds, as the row asks.
const LAYERS := 60

## What the stroke paints, which no layer holds before it.
const STROKE := Color(5.0, 0.25, 0.5, 1.0)

static var scratch: String = SaDataRoot.path("test_snapshot.sad")


func before_each() -> void:
    SaSadSave.finish_all()


func after_each() -> void:
    SaSadSave.finish_all()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))


## The colour layer *index* is filled with.
static func colour_of(index: int) -> Color:
    return Color(index / 64.0, 1.0 - index / 64.0, 0.5 + index * 0.25, 1.0)


## A document of [constant LAYERS] paint layers, the layer at *index* from
## the bottom filled with [method colour_of] in its one chunk.
static func sixty_layers() -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), SaColorSpace.srgb())
    var ops := SaLayerOps.new(doc)
    # Bounded, so a layer that cannot be added ends the loop and the count is
    # asserted where the document is used, rather than the run looping.
    var adds := 0
    while paint_layers(doc).size() < LAYERS and adds < LAYERS:
        ops.add()
        adds += 1
    var layers := paint_layers(doc)
    for index in layers.size():
        layers[index].get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).clear(colour_of(index))
    return doc


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


## Paints a stroke of [constant STROKE] over *layer*'s chunk.
static func paint(doc: SaDocument, layer: SaLayer) -> void:
    doc.active_layer = layer
    doc.begin_stroke(1.0, &"normal")
    doc.stroke_layer.get_or_create_field(Vector2i.ZERO, SaFieldSpec.ALBEDO).clear(STROKE)
    doc.commit_stroke()


func test_a_stroke_and_a_deleted_layer_during_a_save_are_not_in_its_file() -> void:
    var doc := sixty_layers()
    assert_eq(paint_layers(doc).size(), LAYERS, "The document has its sixty layers")
    var layers := paint_layers(doc)
    assert_eq(layers.size(), LAYERS, "The document holds sixty layers")
    doc.modified = true
    var ended: Array[Error] = []
    var save := SaSadSave.start(doc, scratch, 0, null, true, func(err: Error) -> void: ended.append(err))
    assert_true(SaSadSave.is_running(), "The save runs in the background rather than at once")
    assert_false(FileAccess.file_exists(scratch), "and has written nothing yet")

    paint(doc, layers[0])
    assert_true(texel(layers[0]).is_equal_approx(STROKE), "The stroke lands on the bottom layer at once")
    assert_true(SaLayerOps.new(doc).remove(layers[LAYERS >> 1]), "A layer is deleted while the save runs")
    assert_eq(paint_layers(doc).size(), LAYERS - 1, "and goes from the document")
    assert_true(doc.undo(), "An undo runs during the save")
    assert_eq(paint_layers(doc).size(), LAYERS, "and brings the layer back")
    assert_true(doc.redo(), "and a redo deletes it again")
    doc.set_active_layer(layers[1])
    assert_eq(doc.active_layer, layers[1], "Switching layers goes on as well")
    assert_true(SaSadSave.is_running(), "while the save is still running")

    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_eq(ended, [OK] as Array[Error], "once, without an error")
    assert_eq(save.error, OK, "and says so")
    assert_true(doc.modified, "The document is still unsaved, since it changed after the snapshot")
    assert_eq(doc.file_path, scratch, "and its file is the one written")
    assert_false(FileAccess.file_exists(scratch + SaSadFile.SAD_TEMP_SUFFIX), "No side file is left")

    var reopened := SaDocument.new()
    assert_eq(SaExport.load_sad(reopened, scratch, SaCompositor.new()), OK, "The file opens")
    var back := paint_layers(reopened)
    assert_eq(back.size(), LAYERS, "with all sixty layers, the deleted one too")
    var same := 0
    for index in back.size():
        if texel(back[index]).is_equal_approx(colour_of(index)):
            same += 1
    assert_eq(same, LAYERS, "every layer holding its colour as at the snapshot, the stroke not on the bottom one")
    reopened.free()
    doc.free()


func test_a_save_with_nothing_changed_after_it_marks_the_document_saved_at_its_end() -> void:
    var doc := sixty_layers()
    assert_eq(paint_layers(doc).size(), LAYERS, "The document has its sixty layers")
    doc.modified = true
    # A preview as the painter's save passes one, which the worker shrinks and
    # encodes before the first chunk's bytes.
    var picture := Image.create(640, 320, false, Image.FORMAT_RGBA8)
    picture.fill(Color(0.8, 0.3, 0.2, 1.0))
    SaSadSave.start(doc, scratch, 0, picture)
    assert_true(doc.modified, "The document is unsaved while its save runs")
    assert_true(SaSadSave.finish_all(), "The save ends")
    assert_false(doc.modified, "and marks it saved, since nothing changed after the snapshot")
    assert_eq(doc.file_path, scratch, "as the file written")
    var thumbnail := SaSadFile.read_preview(scratch)
    assert_not_null(thumbnail, "The file holds the preview the worker encoded")
    if thumbnail != null:
        assert_eq(thumbnail.get_width(), SaSadFile.PREVIEW_LONG_SIDE, "shrunk to the preview's long side")
    var reopened := SaDocument.new()
    assert_eq(SaExport.load_sad(reopened, scratch, SaCompositor.new()), OK, "and the chunks after it read back")
    assert_eq(paint_layers(reopened).size(), LAYERS, "every layer")
    reopened.free()
    doc.free()
