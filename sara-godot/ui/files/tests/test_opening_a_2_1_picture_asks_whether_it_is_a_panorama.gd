## Opening a picture exactly twice as wide as it is tall asks whether it is an
## equirectangular panorama, Assign or Keep Flat, and Assign is
## `SaProjection.assign`, one history step. A `.sad` never asks, and the
## preference turns it off.
##
## The flow is built with a canvas and never added to a tree, as the welcome
## window's suite builds it, so the depth question answers at once and the
## panorama question is made as the flow's child without a window on screen.
## The question on screen and a press on Assign there are
## `scenarios/opening-a-2-1-picture-asks-whether-it-is-a-panorama.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Opening a picture rebinds the easel's textures, which needs a RenderingDevice.
const REQUIRES_GPU := true

## 256 by 128 half floats, a sky over a ground with a sun in it.
const PANORAMA := "res://ui/files/tests/panorama.exr"
## The Radiance fixture, 256 by 128 as well.
const RADIANCE := "res://modules/sara-base-modules/image-formats/radiance/tests/sky.hdr"
## 300 by 200, three by two.
const THREE_BY_TWO := "res://tests/data/import_gradient.png"

static var scratch_sad: String = SaDataRoot.path("h9-a-panorama-saved.sad")

var _saved_recent: Array = []
var _asked_panorama: bool = true
var _asked_depth: bool = true
var _canvas: SaCanvas = null
var _files: SaDocumentFiles = null

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()
    _saved_recent = SaSettings.recent_files()
    _asked_panorama = SaSettings.ask_panorama
    _asked_depth = SaSettings.ask_when_opening
    SaSettings.ask_panorama = true
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(64, 64)
    _canvas.easel = SaEasel.create_default(Vector2i(64, 64))
    _canvas.add_child(_canvas.easel)
    _files = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)


func after_each() -> void:
    _files.free()
    _canvas.free()
    for path: String in [PANORAMA, RADIANCE, THREE_BY_TWO, scratch_sad]:
        SaSettings.remove_recent_file(path)
    DirAccess.remove_absolute(WelcomePreviewCache.cache_path(scratch_sad))
    DirAccess.remove_absolute(scratch_sad)
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    SaSettings.ask_panorama = _asked_panorama
    SaSettings.ask_when_opening = _asked_depth


func _question() -> SaMessage:
    return _files.get_node_or_null(NodePath(SaDocumentFiles.PanoramaQuestion.NODE_NAME)) as SaMessage


func _kind() -> StringName:
    return _canvas.document.projection.kind.id


func test_the_preference_is_on_for_a_bare_profile_and_has_a_place_in_the_file() -> void:
    var bare := SaSettingsImporting.new()
    assert_true(bare.ask_panorama, "A bare profile asks")
    bare.free()
    assert_eq(SaSettingsKeys.place_of(&"ask_panorama").size(), 2, "and the preference has a place in the file")


func test_a_2_1_picture_with_the_preference_off_opens_flat_and_asks_nothing() -> void:
    SaSettings.ask_panorama = false
    _files.open_path(PANORAMA)
    assert_eq(_canvas.document.canvas_size, Vector2i(256, 128), "The picture opened at its own size, two to one")
    assert_eq(_kind(), SaProjection.FLAT, "and reads flat")
    assert_null(_question(), "and nothing was asked")


func test_a_3_2_picture_asks_nothing() -> void:
    _files.open_path(THREE_BY_TWO)
    assert_eq(_canvas.document.canvas_size, Vector2i(300, 200), "The picture opened at three by two")
    assert_null(_question(), "and nothing was asked with the preference on")
    assert_eq(_kind(), SaProjection.FLAT, "and it reads flat")


func test_a_2_1_exr_asks_with_keep_flat_the_default_and_assign_assigns() -> void:
    _files.open_path(PANORAMA)
    var question := _question()
    assert_not_null(question, "A two to one EXR is asked about")
    if question == null:
        return
    var labels: Array = []
    for button: Button in question.buttons:
        labels.append(button.text)
    assert_eq(labels, ["Assign", "Keep Flat"], "with Assign and Keep Flat")
    assert_eq(question._default_index, SaDocumentFiles.PanoramaQuestion.KEEP_FLAT, "and Keep Flat is what Enter presses")
    assert_eq(question.cancel_index, SaDocumentFiles.PanoramaQuestion.KEEP_FLAT, "and what Escape answers")
    assert_eq(_kind(), SaProjection.FLAT, "Until it is answered the document is flat")

    question.buttons[SaDocumentFiles.PanoramaQuestion.ASSIGN].pressed.emit()
    assert_eq(_kind(), SaProjection.EQUIRECTANGULAR, "Assign reads it equirectangular")
    assert_eq(
        _canvas.document.projection.orientation.preset, SaProjection.Heading.BLENDER, "in Blender's orientation, the default"
    )
    assert_true(_canvas.document.undo_redo.has_undo(), "as one step to take back")
    _canvas.document.undo()
    assert_eq(_kind(), SaProjection.FLAT, "and undone it reads flat again")


func test_keep_flat_keeps_it_flat() -> void:
    _files.open_path(RADIANCE)
    var question := _question()
    assert_not_null(question, "A two to one Radiance file is asked about too")
    if question == null:
        return
    question.buttons[SaDocumentFiles.PanoramaQuestion.KEEP_FLAT].pressed.emit()
    assert_eq(_kind(), SaProjection.FLAT, "Keep Flat leaves it flat")
    assert_false(_canvas.document.undo_redo.has_undo(), "and leaves nothing to undo")


func test_a_sad_never_asks() -> void:
    SaSettings.ask_panorama = false
    _files.open_path(PANORAMA)
    assert_eq(SaExport.save_sad(_canvas.document, scratch_sad, 0), OK, "a two to one document is saved")
    SaSettings.ask_panorama = true
    _files.open_path(scratch_sad)
    assert_eq(_canvas.document.canvas_size, Vector2i(256, 128), "It opens two to one")
    assert_null(_question(), "and a .sad is never asked, since it says what it is")
    assert_false(
        SaDocumentFiles.PanoramaQuestion.due("a.sad", Vector2i(256, 128), null), "which is the rule and not the open's luck"
    )
    assert_true(SaDocumentFiles.PanoramaQuestion.due("a.exr", Vector2i(256, 128), null), "where a picture of that shape is due")
    assert_false(SaDocumentFiles.PanoramaQuestion.due("a.exr", Vector2i(256, 129), null), "and one a texel off is not")
