## A document's card gets its picture when the document closes,
## so one opened and closed in a session that never built the welcome window
## still has a picture there the next time.
##
## The close is the document flow's own: `SaDocumentFiles.open_path` puts
## another file in place of the open one, which is File > Open, a recent row and
## a drop. File > New and a picture opened as a document make the same call.
## What the welcome window shows for it on the running app is
## `scenarios/a-recent-document-shows-its-picture-after-a-close.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, because the picture is a readback of the easel.
const REQUIRES_GPU := true

## The document the suite opens, paints and closes, written with no preview of
## its own, the shape every older `.sad` has.
static var scratch_fixture: String = SaDataRoot.path("n3-the-document-that-closes.sad")

## The document opened in its place, which is what closes the first.
static var scratch_next: String = SaDataRoot.path("n3-the-document-opened-next.sad")

## A file that carries its own preview, whose card never asks the cache.
static var scratch_with_preview: String = SaDataRoot.path("n3-a-file-with-its-own-preview.sad")

## A picture opened as a document, and the `.sad` its painting is
## saved to, since a picture document is nameless and Save asks where.
static var scratch_picture: String = SaDataRoot.path("n3-a-picture-opened-as-a-document.png")
static var scratch_picture_saved: String = SaDataRoot.path("n3-the-picture-saved-as-a-document.sad")

## A linear EXR of the same kind, whose small copy is encoded to sRGB.
static var scratch_picture_exr: String = SaDataRoot.path("n3-a-linear-picture.exr")

const SIZE := Vector2i(64, 64)

var _saved_recent: Array = []
var _canvas: SaCanvas = null
var _files: SaDocumentFiles = null


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = SaEasel.create_default(SIZE, null, SaColorSpace.oklab())
    _canvas.add_child(_canvas.easel)
    _composite()
    # Both files hold the grey background a fresh document opens on, and
    # neither carries a preview, so a card for either can only draw the cache.
    for path: String in [scratch_fixture, scratch_next]:
        assert_eq(SaExport.save_sad(_canvas.document, path, 0), OK, "the fixture %s is written" % path)
    _files = SaDocumentFiles.new(func() -> SaCanvas: return _canvas)
    WelcomePreviewCache.prune()


func after_each() -> void:
    for path: String in [
        scratch_fixture, scratch_next, scratch_with_preview, scratch_picture, scratch_picture_saved, scratch_picture_exr
    ]:
        DirAccess.remove_absolute(WelcomePreviewCache.cache_path(path))
        SaSettings.remove_recent_file(path)
        DirAccess.remove_absolute(path)
    WelcomePreviewCache.prune()
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    _files.free()
    _canvas.free()


## The gap: the document was open, no grid was built to take its picture at
## the open, and the close is the last moment it can be taken.
func test_a_document_opened_and_closed_with_no_welcome_window_has_a_picture() -> void:
    _open(scratch_fixture)
    assert_null(WelcomePreviewCache.read(scratch_fixture), "no grid was built, so the open took no picture")
    _open(scratch_next)
    var picture := WelcomePreviewCache.read(scratch_fixture)
    assert_not_null(picture, "the close took the picture of the document it closed")
    assert_null(WelcomePreviewCache.read(scratch_next), "and the document still open has none yet")
    if picture != null:
        # A 64 pixel document is never enlarged to the 256 a preview is shrunk to.
        assert_eq(picture.get_size(), SIZE, "of the whole document, at its own size: %s" % picture.get_size())


## The row's own case: a fixture is opened, painted, written to its file, and
## closed, and the cache holds a picture of the painting for its path.
##
## Written by `SaExport.save_sad` with no preview, which is the capture's own
## `save` step, because File > Save writes the file a preview of its own and a
## card draws that one instead of asking the cache.
func test_a_painted_document_closes_with_a_picture_of_its_paint() -> void:
    _open(scratch_fixture)
    _canvas.document.fill_layer(Color.RED)
    _composite()
    assert_true(_canvas.document.modified, "the paint is a change to the document")
    _save_without_preview(scratch_fixture)
    _open(scratch_next)
    var picture := WelcomePreviewCache.read(scratch_fixture)
    assert_not_null(picture, "the cache holds a picture for the painted document's path")
    if picture == null:
        return
    var middle := picture.get_pixel(picture.get_width() >> 1, picture.get_height() >> 1)
    assert_true(middle.r > 0.8 and middle.g < 0.2 and middle.b < 0.2, "and it is the red it was painted: %s" % middle)


## Discard is the one way a modified document reaches a close, since Save marks
## it saved before the close goes on, and the file holds none of what was thrown
## away. The picture it already had stays, rather than one of paint that is
## gone.
func test_a_discarded_painting_keeps_the_picture_the_file_already_had() -> void:
    _open(scratch_fixture)
    _open(scratch_next)
    var where := WelcomePreviewCache.cache_path(scratch_fixture)
    var before := FileAccess.get_file_as_bytes(where)
    assert_false(before.is_empty(), "the first close took the file's picture")
    _open(scratch_fixture)
    _canvas.document.fill_layer(Color.RED)
    _composite()
    assert_false(WelcomePreviewCache.keep_closing(_canvas.easel), "a modified document at a close takes no picture")
    _open(scratch_next)
    assert_eq(FileAccess.get_file_as_bytes(where), before, "so the picture is the one of the file as it stands")


## An unchanged document costs no second readback: the picture under the file's
## current name is the one it keeps.
func test_a_document_closed_without_a_change_keeps_its_picture() -> void:
    _open(scratch_fixture)
    assert_true(WelcomePreviewCache.keep_closing(_canvas.easel), "the first close takes a picture")
    assert_false(WelcomePreviewCache.keep_closing(_canvas.easel), "and a second close of the same file takes none")


func test_a_file_with_its_own_preview_and_a_nameless_document_take_none() -> void:
    _canvas.document.mark_saved("")
    assert_false(WelcomePreviewCache.keep_closing(_canvas.easel), "an untitled document has no card")
    var preview := SaExport.get_preview_image(_canvas.easel)
    assert_eq(SaExport.save_sad(_canvas.document, scratch_with_preview, 0, preview), OK, "a file with its own preview is written")
    _open(scratch_with_preview)
    assert_false(WelcomePreviewCache.keep_closing(_canvas.easel), "its card reads the file, so the cache is not asked")
    assert_null(WelcomePreviewCache.read(scratch_with_preview), "and nothing is stored for it")
    assert_false(WelcomePreviewCache.keep_closing(null), "and no easel is nothing to keep")


## A PNG opened as a document, painted on, saved and closed, in
## a session that never built the welcome window. The close takes no picture of
## a nameless modified document, so its card reads the PNG itself.
func test_a_picture_opened_painted_saved_and_closed_keeps_its_cards_picture() -> void:
    _write_png(Color.BLUE)
    var image := SaImageImport.read(scratch_picture)
    assert_not_null(
        SaDocumentFiles.open_picture_into(_canvas.document, scratch_picture, image, SaColorSpace.srgb()), "the PNG opens"
    )
    SaSettings.add_recent_file(scratch_picture)
    _composite()
    _canvas.document.fill_layer(Color.RED)
    _composite()
    _save_without_preview(scratch_picture_saved)
    _open(scratch_next)
    assert_null(WelcomePreviewCache.read(scratch_picture), "the close takes no picture for a picture document")
    var picture := WelcomePreviewCache.of_picture_file(scratch_picture)
    assert_not_null(picture, "the card reads the PNG itself")
    if picture == null:
        return
    var middle := picture.get_pixel(picture.get_width() >> 1, picture.get_height() >> 1)
    assert_true(middle.b > 0.8 and middle.r < 0.2, "and it is the file's blue, not the paint saved elsewhere: %s" % middle)
    assert_not_null(WelcomePreviewCache.read(scratch_picture), "and it is stored so the next card costs no decode")


## A PNG opened and closed with no Welcome window and no paint.
func test_a_picture_opened_and_closed_with_no_welcome_window_has_a_picture() -> void:
    _write_png(Color.GREEN)
    SaSettings.add_recent_file(scratch_picture)
    var picture := WelcomePreviewCache.of_picture_file(scratch_picture)
    assert_not_null(picture, "the card reads the PNG")
    if picture != null:
        assert_eq(picture.get_size(), SIZE, "at its own size: %s" % picture.get_size())
    assert_null(WelcomePreviewCache.of_picture_file(scratch_fixture), "a `.sad` is not a picture file")
    assert_null(WelcomePreviewCache.of_picture_file(SaDataRoot.path("n3-no-such-picture.png")), "nor is a file that is gone")


## An EXR's linear half grey is encoded as sRGB for the card, near 188 of 255.
func test_a_linear_exr_card_is_encoded_to_srgb() -> void:
    var linear := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBAF)
    linear.fill(Color(0.5, 0.5, 0.5, 1.0))
    assert_eq(linear.save_exr(scratch_picture_exr), OK, "the EXR is written")
    SaSettings.add_recent_file(scratch_picture_exr)
    var picture := WelcomePreviewCache.of_picture_file(scratch_picture_exr)
    assert_not_null(picture, "the card reads the EXR")
    if picture != null:
        var grey := picture.get_pixel(1, 1).r
        assert_true(absf(grey - 0.735) < 0.02, "the linear half is sRGB 0.735: %s" % grey)


func _write_png(colour: Color) -> void:
    var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
    image.fill(colour)
    assert_eq(image.save_png(scratch_picture), OK, "the PNG is written")


## The flow's own open, which closes the document open before it, and then the
## composite a frame would run, since the suite's canvas is not in a tree.
## Opens *path* in place of the open document, and waits out the picture its
## close took on the card.
func _open(path: String) -> void:
    _files.open_path(path)
    assert_true(WelcomePreviewCache.finish_all(), "the picture the close took lands")
    assert_eq(_canvas.document.file_path, path, "%s is the open document" % path)
    _composite()


func _composite() -> void:
    _canvas.easel.request_full_composite()
    _canvas.easel.process_pending_composite()


## What the capture's `save` step does: the file, with no preview, and the
## document marked as that file.
func _save_without_preview(path: String) -> void:
    assert_eq(SaExport.save_sad(_canvas.document, path, 0), OK, "%s is written again" % path)
    _canvas.document.mark_saved(path)
