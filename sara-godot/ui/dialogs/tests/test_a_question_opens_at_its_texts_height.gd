## The unsaved changes question opens at the height of its text, and a message of
## forty lines still fits the screen and scrolls.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## File, New on a changed document went through a mostly empty question, its
## three buttons under the text and blank below them. `SaMessage` opened at
## 520 by 240 and its scroll was not the window's `scrolling_body`, so the fit never sized it to what it said. Now the scroll is
## the body, the floor is below a line and a row of buttons, and the window is
## what its content needs.
##
## Built the way `test_the_about_window_fits_a_screen` builds About: a
## `SubViewport` of the asked size with subwindows embedded, and every container
## sorted by hand before the fit reads the text's height and again before the
## buttons are read, because a suite cannot await the frame the app fits on.
extends "res://tests/test_framework.gd"

const SCREEN := Vector2i(1920, 1080)
const SHORT := Vector2i(1280, 720)

## The sentence `SaDocumentFiles.confirm_discard` asks on File, New, with the
## name a new document has.
const QUESTION := "Save the changes to Untitled before creating a new document?"

var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    SaUI.user_scale = 1.0
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "QuestionFitTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_the_discard_question_is_no_taller_than_its_text_buttons_and_margins() -> void:
    var dialog := _asked_in(SCREEN, QUESTION)
    var scroll := dialog.scrolling_body
    assert_true(scroll != null, "The question declares the scroll its text sits in as its scrolling body")
    if scroll == null:
        return
    var text := _child_minimum(scroll)
    assert_true(
        scroll.custom_minimum_size.y >= text,
        "The whole question is shown, its scroll asks for the %d its text needs, not %d" % [text, scroll.custom_minimum_size.y]
    )
    var needed := SaUI.window_size_for(dialog, dialog.content_minimum_size())
    assert_true(
        dialog.size.y <= needed.y,
        "The question is %d high and its title, text, buttons and margins need %d" % [dialog.size.y, needed.y]
    )
    assert_true(
        dialog.size.y < SaUI.window_size_for(dialog, Vector2i(520, 240)).y,
        "The question opens lower than the 240 it used to open at, %d" % dialog.size.y
    )
    _assert_buttons_inside(dialog, SCREEN)
    var labels: Array[String] = []
    for button in dialog.buttons:
        labels.append(button.text)
    assert_eq(labels, ["Save", "Discard", "Cancel"], "The three verbs stay")


func test_a_message_of_forty_lines_fits_the_screen_and_scrolls() -> void:
    var lines := PackedStringArray()
    for i in 40:
        lines.append("Line %d of a long message, which scrolls inside the window." % (i + 1))
    var dialog := _asked_in(SHORT, "\n".join(lines))
    var rect := Rect2i(dialog.position, dialog.size)
    assert_true(Rect2i(Vector2i.ZERO, SHORT).encloses(rect), "The question at %s lies inside a screen of %s" % [rect, SHORT])
    var scroll := dialog.scrolling_body
    assert_not_null(scroll, "The question declares the scroll its text sits in as its scrolling body")
    if scroll == null:
        return
    var text := _child_minimum(scroll)
    assert_true(scroll.size.y < text, "The text scrolls: its scroll is %d high against %d of text" % [scroll.size.y, text])
    _assert_buttons_inside(dialog, SHORT)


## The question asked the way `SaDocumentFiles.confirm_discard` asks it, in a
## screen of *size*, and fitted.
func _asked_in(size: Vector2i, text: String) -> SaMessage:
    var screen := SubViewport.new()
    screen.size = size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var dialog := SaMessage.confirm(
        screen, "Unsaved changes", text, PackedStringArray(["Save", "Discard", "Cancel"]), func(_index: int) -> void: pass, 2, 0
    )
    _sort_children(dialog.content)
    dialog.fit_opening_size()
    _sort_children(dialog.content)
    return dialog


func _assert_buttons_inside(dialog: SaMessage, screen: Vector2i) -> void:
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    for button in dialog.buttons:
        var rect := button.get_global_rect()
        assert_true(frame.encloses(rect), "%s at %s lies inside the window %s" % [button.text, rect, frame])
        var on_screen := Rect2(Vector2(dialog.position) + rect.position, rect.size)
        assert_true(
            Rect2(Vector2.ZERO, Vector2(screen)).encloses(on_screen),
            "%s at %s lies inside the screen %s" % [button.text, on_screen, screen]
        )


func _child_minimum(scroll: ScrollContainer) -> int:
    return ceili((scroll.get_child(0) as Control).get_combined_minimum_size().y)


func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
