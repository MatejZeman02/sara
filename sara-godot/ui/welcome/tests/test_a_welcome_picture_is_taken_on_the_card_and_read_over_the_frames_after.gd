## A welcome picture is taken on the card and read over the
## frames after. A saved document with no preview of its own gets its card's
## picture as it closes, and the frame that closes it no longer waits for the
## read of the whole composite, which `SaExport` measured at a quarter of a
## second at 3840 by 2160. The copy on the card is the document as it stood,
## so the picture lands even though another document is in its place by then.
extends "res://tests/test_framework.gd"

## Needs the main RenderingDevice: the cells come back as frames are drawn.
const REQUIRES_GPU := true

## The size the review measured the blocking read at.
const SIZE := Vector2i(3840, 2160)

## The document that closes, written with no preview of its own.
static var scratch_closing: String = SaDataRoot.path("the-document-that-closes.sad")

var _saved_recent: Array = []
var _easel: SaEasel = null


func before_each() -> void:
    _saved_recent = SaSettings.recent_files()
    for path: String in _saved_recent:
        SaSettings.remove_recent_file(str(path))
    _easel = SaEasel.create_default(SIZE, null, SaColorSpace.oklab())
    _easel.document.fill_layer(Color.RED)
    _composite()
    assert_eq(SaExport.save_sad(_easel.document, scratch_closing, 0), OK, "the document is written with no preview")
    _easel.document.mark_saved(scratch_closing)
    SaSettings.add_recent_file(scratch_closing)
    WelcomePreviewCache.prune()


func after_each() -> void:
    WelcomePreviewCache.finish_all()
    DirAccess.remove_absolute(WelcomePreviewCache.cache_path(scratch_closing))
    SaSettings.remove_recent_file(scratch_closing)
    DirAccess.remove_absolute(scratch_closing)
    WelcomePreviewCache.prune()
    for i in range(_saved_recent.size() - 1, -1, -1):
        SaSettings.add_recent_file(str(_saved_recent[i]))
    _easel.free()
    _easel = null


func _composite() -> void:
    _easel.request_full_composite()
    _easel.process_pending_composite()


func test_the_close_is_shorter_than_a_blocking_read_and_the_picture_is_written() -> void:
    assert_null(SaSadFile.read_preview(scratch_closing), "the file carries no preview of its own")
    # Once first, so neither timing below pays for a kernel's first compile.
    assert_not_null(SaExport.get_preview_image(_easel), "the blocking read answers")
    var began := Time.get_ticks_usec()
    var blocking := SaExport.get_preview_image(_easel)
    var blocking_usec := Time.get_ticks_usec() - began
    assert_not_null(blocking, "the blocking read answers a second time")
    began = Time.get_ticks_usec()
    var taken := SaWelcomeWindow.keep_closing_picture(_easel)
    var closing_usec := Time.get_ticks_usec() - began
    assert_true(taken, "the close takes the picture")
    assert_true(WelcomePreviewCache.reading(scratch_closing), "which is on its way, not read in the frame")
    assert_null(WelcomePreviewCache.read(scratch_closing), "and not yet written")
    print("The close took %d us, a blocking read %d us" % [closing_usec, blocking_usec])
    assert_true(
        closing_usec < blocking_usec, "the close, %d us, is shorter than a blocking read, %d us" % [closing_usec, blocking_usec]
    )
    # Another document in its place before the picture lands, which is what
    # the close is for.
    _easel.document.fill_layer(Color.BLUE)
    _composite()
    assert_true(WelcomePreviewCache.finish_all(), "the picture lands")
    var picture := WelcomePreviewCache.read(scratch_closing)
    assert_not_null(picture, "and the welcome picture is written")
    if picture == null:
        return
    assert_eq(picture.get_size(), Vector2i(256, 144), "at a card's size: %s" % picture.get_size())
    var middle := picture.get_pixel(128, 72)
    assert_true(middle.r > 0.8 and middle.g < 0.2 and middle.b < 0.2, "of the document as it closed, red: %s" % middle)
    var at_once := SaSadFile.shrink(blocking, WelcomePreviewCache.LONG_SIDE)
    var held := at_once.get_pixel(128, 72)
    assert_true(absf(held.r - middle.r) < 0.02 and absf(held.b - middle.b) < 0.02, "as the blocking read sees it: %s" % held)


func test_a_second_close_while_the_picture_is_on_its_way_takes_none() -> void:
    assert_true(WelcomePreviewCache.keep_closing(_easel), "the first close takes a picture")
    assert_false(WelcomePreviewCache.keep_closing(_easel), "a second before it lands takes none")
    assert_true(WelcomePreviewCache.finish_all(), "the picture lands")
    assert_false(WelcomePreviewCache.keep_closing(_easel), "and one after it lands takes none either")


## A card drawn while the picture is on its way, the welcome window opened just
## after a tab closed, asks to be told when it lands, and is told once.
func test_a_card_drawn_before_the_picture_lands_is_told_when_it_does() -> void:
    var told: Array[int] = [0]
    var tell := func() -> void: told[0] += 1
    assert_false(WelcomePreviewCache.after(scratch_closing, tell), "nothing is on its way before the close")
    assert_true(WelcomePreviewCache.keep_closing(_easel), "the close takes a picture")
    assert_true(WelcomePreviewCache.after(scratch_closing, tell), "a card drawn now waits for it")
    assert_true(WelcomePreviewCache.after(scratch_closing, tell), "and asking twice")
    assert_true(WelcomePreviewCache.finish_all(), "the picture lands")
    assert_eq(told[0], 1, "is told once")
    assert_not_null(WelcomePreviewCache.read(scratch_closing), "and finds the picture written")
