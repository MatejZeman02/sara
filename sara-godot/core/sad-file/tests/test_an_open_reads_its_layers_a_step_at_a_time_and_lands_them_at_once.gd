## An open of a deep file reads its layers a step at a time,
## outside the document, and lands them in one go.
##
## The open read every layer, decoded every Zstd blob on the main thread and
## hashed every chunk in one call, a frame of three seconds on a
## painting of 308 layers. [SaSadOpening] reads the layers over frames
## with the blobs decoded on the pool, and the document sees none of it until
## the landing, so the window and the layers docker never meet a stack half
## read. The document lets go of its own layers before the first
## is read, so it stands empty until then rather than holding the old stack.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: a save reads chunks back and an open writes them.
const REQUIRES_GPU := true

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const SIZE := Vector2i(64, 64)
const SQUARE := Rect2i(4, 4, 8, 8)
const PAINTED := 5

var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


func _easel() -> SaEasel:
    var made := Bench.easel(SIZE)
    _easels.append(made)
    return made


## A file of the easel's two layers and [constant PAINTED] more, each holding
## a square of its own grey in its first chunk.
func _saved() -> String:
    var document := _easel().document
    for i in PAINTED:
        var layer := SaLayerOps.new(document).add(&"")
        layer.name = "Painted %d" % i
        var texture := layer.get_or_create_chunk(Vector2i(0, 0)).albedo()
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
        image.fill(Color(0.0, 0.0, 0.0, 0.0))
        image.fill_rect(SQUARE, _grey(i))
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
    var path := ProjectSettings.globalize_path(SaDataRoot.path("test_%d.sad" % _paths.size()))
    _paths.append(path)
    assert_eq(SaExport.save_sad(document, path), OK, "The file is written")
    return path


static func _grey(i: int) -> Color:
    var value := 0.25 + 0.125 * i
    return Color(value, value, value, 1.0)


## An open of *path* into *document*, its magic read as the reader does.
static func _opening(document: SaDocument, path: String) -> SaSadOpening:
    var file := FileAccess.open(path, FileAccess.READ)
    file.get_buffer(4)
    return SaSadOpening.new(document, file, path)


static func _names(document: SaDocument) -> Array[String]:
    var found: Array[String] = []
    for child in document.get_children():
        if child is SaLayer and child != document.stroke_layer:
            found.append(str(child.name))
    return found


func test_the_document_is_empty_until_the_open_lands_and_then_holds_the_file() -> void:
    var path := _saved()
    var target := _easel().document
    var opening := _opening(target, path)
    assert_eq(opening.error, OK, "The header is read")
    var before: Array[String] = []
    assert_eq(_names(target), before, "and the document has let go of its own layers")
    var steps := 1
    while not opening.step(0) and steps < 1000:
        steps += 1
        assert_eq(_names(target), before, "A step adds nothing to the document")
    assert_eq(steps, PAINTED + 2, "A step with no time to spare reads one layer, the file's seven in seven")
    assert_eq(_names(target), before, "Every layer read, and still none in the document")

    assert_eq(opening.land(), OK, "The open lands")
    var names := _names(target)
    assert_eq(names.size(), PAINTED + 2, "and the document holds the file's layers: %s" % [names])
    for i in PAINTED:
        var layer := target.get_node(NodePath("Painted %d" % i)) as SaLayer
        assert_not_null(layer, "Painted %d is there" % i)
        if layer != null:
            var texel := Bench.texel(layer.get_field(Vector2i(0, 0)), SQUARE.position)
            assert_true(texel.is_equal_approx(_grey(i)), "with its own grey: %s" % texel)
    assert_false(target.modified, "An opened file has nothing unsaved")


func test_the_zstd_blobs_are_decoded_on_the_pool() -> void:
    var path := _saved()
    var opening := _opening(_easel().document, path)
    assert_eq(opening.whole(), OK, "The open in one call lands")
    assert_true(opening._opening.pooled >= PAINTED, "Each painted chunk was decoded on the pool: %d" % opening._opening.pooled)


func test_a_dropped_open_leaves_the_document_empty_and_none_of_its_layers() -> void:
    var path := _saved()
    var target := _easel().document
    var opening := _opening(target, path)
    var before: Array[String] = []
    assert_false(opening.step(0), "One layer of seven is read")
    opening.drop()
    assert_eq(opening.error, ERR_SKIP, "The dropped open says so")
    assert_true(opening._built.is_empty(), "and the layers it made are let go")
    assert_eq(_names(target), before, "The document stays as empty as the open left it")


func test_an_open_over_frames_answers_once_with_the_file_in() -> void:
    var path := _saved()
    var target := _easel().document
    var answers: Array[Error] = []
    SaExport.open_sad(target, path, answers.append)
    for _i in 30:
        if not answers.is_empty():
            break
        await (Engine.get_main_loop() as SceneTree).process_frame
    assert_eq(answers, [OK] as Array[Error], "The answer comes once, and it is OK")
    assert_eq(_names(target).size(), PAINTED + 2, "with the file's layers in the document")
