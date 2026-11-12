## Rename Layer opened at 420 by 320 logical pixels, a fifth of the
## window, with a five-line Note box whether the layer had a note or not. It is
## as tall as what it holds now: the Name field, its label, a one-line note and
## the two buttons while the note is empty, and the lines the note needs, up to
## five, once it holds text or has been clicked.
##
## The dialog is opened from a Layers docker in a host that embeds, the way
## `test_rename_layer_opens_in_the_middle_of_the_main_window` does, because a
## `Window` added to the test runner's own tree hangs the run and an embedded
## one does not. The fit a frame after a show is run by hand, since the suite
## has no frame to wait for. The scenario
## `renaming-a-layer-is-a-small-dialog` shows the same in the running app.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document.
const REQUIRES_GPU := true

const LayersDockerScript = preload("res://ui/dockers/layers/layers_docker.gd")

## What the dialog stood at before this unit, in logical units.
const OLD_HEIGHT: int = 320

## Three fifths of it, which the dialog with no note is held to. It stands near
## half, 159 in the suite's font and 173 in the app's, and the font is not the
## test's to pin.
const ABOUT_HALF_OLD_HEIGHT: int = 192

var _host: SubViewport = null


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## The first case: no note, about half the old height or less.
func test_a_layer_with_no_note_opens_at_half_its_old_height_or_less() -> void:
    var dialog := _opened("")
    assert_true(
        dialog.size.y <= ABOUT_HALF_OLD_HEIGHT,
        "With no note the dialog is %d high where it was %d, so about half or less" % [dialog.size.y, OLD_HEIGHT]
    )
    assert_eq(_note(dialog).custom_minimum_size.y, _one_line(dialog), "and its note box is one line")
    assert_true(_name_edit(dialog).visible and _button(dialog, "OKButton").visible, "with the Name field and the buttons showing")
    assert_true(dialog.size.x >= 420, "and it keeps the 420 it was wide, which is %d" % dialog.size.x)


## A one-line note needs one line, so the note box and the dialog are no taller
## than they are empty. The box's line is a pixel or so higher once it holds
## text, which is the font's own measure, so the lines are counted and not the
## pixels.
func test_a_one_line_note_takes_one_line() -> void:
    var empty_rest := _rest(_opened(""))
    var dialog := _opened("the sky, too blue")
    assert_eq(_lines_shown(dialog), 1, "a note of a line shows one line")
    assert_eq(_rest(dialog), empty_rest, "and the dialog holds the rest of its content in the same height")
    assert_eq(_note(dialog).text, "the sky, too blue", "and the note is in the box")


## A note of several lines takes the height they need, and a longer one is held
## to five, the rest scrolling.
func test_a_longer_note_takes_the_height_it_needs_and_five_lines_at_most() -> void:
    var rest := _rest(_opened(""))
    var three := _opened("one\ntwo\nthree")
    assert_eq(_lines_shown(three), 3, "a note of three lines shows three")
    assert_eq(_rest(three), rest, "and the window is the note box's height and no more than it was")
    var five := _opened("1\n2\n3\n4\n5")
    assert_eq(_lines_shown(five), 5, "a note of five lines shows five")
    assert_eq(_rest(five), rest, "in a window that follows it")
    var nine := _opened("1\n2\n3\n4\n5\n6\n7\n8\n9")
    assert_eq(_lines_shown(nine), 5, "a note of nine is held to the five")
    assert_eq(_rest(nine), rest, "and the window with it")
    assert_true(nine.size.y < OLD_HEIGHT, "which is still shorter than the old dialog, %d against %d" % [nine.size.y, OLD_HEIGHT])


## A click opens an empty note out to room for three lines, and the room stays.
func test_a_click_in_an_empty_note_opens_it_out_and_it_stays_open() -> void:
    var dialog := _opened("")
    var closed := dialog.size.y
    var rest := _rest(dialog)
    _note(dialog).focus_entered.emit()
    assert_eq(_lines_shown(dialog), 3, "a click gives the empty note three lines")
    assert_true(dialog.size.y > closed, "and the window grows by them, to %d from %d" % [dialog.size.y, closed])
    assert_eq(_rest(dialog), rest, "by the box's growth and nothing else")
    var open := dialog.size.y
    _note(dialog).focus_exited.emit()
    assert_eq(dialog.size.y, open, "and leaving it takes nothing back, or Rename would move from under the pointer")


## Text typed into the note makes the window follow it, down as well as up, and
## the top edge stays where it was for a window that is already open.
func test_typing_makes_the_window_follow_the_note_and_keeps_its_top() -> void:
    var dialog := _opened("")
    var top := dialog.position.y
    var rest := _rest(dialog)
    _note(dialog).text = "a\nb\nc\nd"
    _note(dialog).text_changed.emit()
    assert_eq(_lines_shown(dialog), 4, "four lines typed show four")
    assert_eq(_rest(dialog), rest, "in a window that follows the box")
    assert_eq(dialog.position.y, top, "and the top edge did not move")
    _note(dialog).text = "a\nb"
    _note(dialog).text_changed.emit()
    assert_eq(_lines_shown(dialog), 2, "two lines show two, so the box gives height back")
    assert_eq(_rest(dialog), rest, "and the window with it")


## The size follows the layer it is opened on, so a tall note does not leave the
## next layer's dialog tall, which is what a window keeping its last size would do.
func test_the_next_layer_opens_at_its_own_height() -> void:
    var docker := _docker(Vector2i(1920, 1080))
    var layer := docker.target_canvas.document.active_layer
    layer.comment = "1\n2\n3\n4\n5"
    assert_true(docker.open_rename_dialog(), "the dialog opens on a layer with a five-line note")
    var dialog := _dialog(docker)
    dialog.fit_opening_size()
    var tall := dialog.size.y
    dialog.hide()
    layer.comment = ""
    assert_true(docker.open_rename_dialog(), "and again on a layer with none")
    dialog.fit_opening_size()
    assert_true(dialog.size.y < tall, "the second is shorter, %d against %d" % [dialog.size.y, tall])


## Enter in the Name field renames, as it did.
func test_enter_in_the_name_field_renames() -> void:
    var docker := _docker(Vector2i(1920, 1080))
    var layer := docker.target_canvas.document.active_layer
    layer.name = "Sky"
    assert_true(docker.open_rename_dialog(), "the dialog opens")
    var dialog := _dialog(docker)
    _name_edit(dialog).text = "Cloud"
    _name_edit(dialog).text_submitted.emit("Cloud")
    assert_eq(str(layer.name), "Cloud", "Enter in the name field gives the layer its new name")
    assert_false(dialog.visible, "and the dialog goes")


## It opens in the middle of the main window still, at its new
## height.
func test_it_still_opens_in_the_middle_of_the_main_window() -> void:
    var dialog := _opened("")
    var host := Rect2i(Vector2i.ZERO, _host.size)
    var off := (Rect2i(dialog.position, dialog.size).get_center() - host.get_center()).abs()
    assert_true(off.x <= 1 and off.y <= 1, "its middle is %s from the host's" % off)


## The least the window can be follows its content, which is under the old 240.
func test_the_floor_is_the_content_and_under_the_old_one() -> void:
    var dialog := _opened("")
    assert_true(dialog.min_size.y < 240, "the minimum height is %d, under the 240 it was" % dialog.min_size.y)
    assert_true(dialog.min_size.y <= dialog.size.y, "and no more than the window's own")


## Opens the dialog on the active layer holding *note*, in a host of 1920 by
## 1080, and runs the fit a frame after the show.
func _opened(note: String) -> SaLayerRenameDialog:
    if _host != null:
        _host.free()
        _host = null
    var docker := _docker(Vector2i(1920, 1080))
    docker.target_canvas.document.active_layer.comment = note
    assert_true(docker.open_rename_dialog(), "the docker opens the dialog")
    var dialog := _dialog(docker)
    dialog.fit_opening_size()
    return dialog


func _note(dialog: SaLayerRenameDialog) -> TextEdit:
    return dialog.find_child("NoteEdit", true, false) as TextEdit


func _name_edit(dialog: SaLayerRenameDialog) -> LineEdit:
    return dialog.find_child("NameEdit", true, false) as LineEdit


func _button(dialog: SaLayerRenameDialog, node_name: String) -> Button:
    return dialog.find_child(node_name, true, false) as Button


## The logical height of one line of the note box.
func _line_height(dialog: SaLayerRenameDialog) -> int:
    return _note(dialog).get_line_height()


## How many lines the note box has been given room for.
func _lines_shown(dialog: SaLayerRenameDialog) -> int:
    var chrome := _note(dialog).get_theme_stylebox("normal").get_minimum_size().y
    return roundi((_note(dialog).custom_minimum_size.y - chrome) / float(_line_height(dialog)))


## What the window is tall by beyond the note box, which is the same for every
## note when the window follows the box exactly.
func _rest(dialog: SaLayerRenameDialog) -> int:
    return dialog.size.y - int(_note(dialog).custom_minimum_size.y)


## The note box's minimum height with one line in it.
func _one_line(dialog: SaLayerRenameDialog) -> float:
    var chrome := _note(dialog).get_theme_stylebox("normal").get_minimum_size().y
    return ceilf(chrome + float(_line_height(dialog)))


## A host that embeds, with a layers docker in it at its right edge over a
## document with an active layer.
func _docker(host_size: Vector2i) -> LayersDocker:
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = SubViewport.new()
    _host.name = "N4Host"
    _host.size = host_size
    _host.gui_embed_subwindows = true
    _host.render_target_update_mode = SubViewport.UPDATE_DISABLED
    EventBus.add_child(_host)

    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(128, 128)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var docker: LayersDocker = LayersDockerScript.new()
    docker.name = "LayersDocker"
    docker.target_canvas = canvas
    canvas.add_child(docker)
    docker.size = Vector2i(310, 600)
    docker.position = Vector2i(host_size.x - 320, 120)
    docker.sync_layer_list()
    return docker


func _dialog(docker: LayersDocker) -> SaLayerRenameDialog:
    return docker.find_child("LayerRenameDialog", true, false) as SaLayerRenameDialog
