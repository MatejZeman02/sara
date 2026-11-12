## The open question and the fit question give every size in pixels.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The size was once shown with no unit and the phrase
## "becomes the document" was odd. The dialog here is detached because a `Window`
## added to the tree in a headless run hangs, so the sentence is read off the
## label it drew. `scenarios/the-open-picture-question-gives-the-size-in-pixels-and-reads-plainly.json`
## shows the same two windows over the running app.
extends "res://tests/test_framework.gd"


func _text_of(dialog: SaImportFitDialog) -> String:
    return dialog._size_label.text


func test_the_open_question_gives_its_size_in_pixels_and_says_it_is_a_new_document() -> void:
    for named_depth: int in [-1, SaColorSpace.Depth.F32]:
        var dialog := SaImportFitDialog.new()
        dialog.configure_open(Vector2i(300, 200), null, named_depth)
        var text := _text_of(dialog)
        assert_true(text.contains("300 × 200 px"), "The size carries its unit: %s" % text)
        assert_true(text.contains("opens as a new document"), "and says plainly what opening does: %s" % text)
        assert_false(text.contains("becomes the document"), "and the odd phrase is gone: %s" % text)
        dialog.free()


func test_the_fit_question_gives_both_sizes_in_pixels() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(300, 200), Vector2i(1920, 1080))
    var text := _text_of(dialog)
    assert_true(text.contains("300 × 200 px"), "The picture's size carries its unit: %s" % text)
    assert_true(text.contains("1920 × 1080 px"), "and so does the canvas's: %s" % text)
    dialog.free()
