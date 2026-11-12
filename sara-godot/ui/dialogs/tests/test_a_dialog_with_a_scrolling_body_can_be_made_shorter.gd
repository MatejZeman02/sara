## About can be made shorter than its report, which then scrolls, and a dialog
## with nothing to scroll keeps the floor its content needs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## About must be draggable shorter, so that its report scrolls. On a 1280 by
## 1024 screen every drag of its corner upwards once left it 728 high.
## `_fit_scrolling_body` gave the scroll the whole
## height its text wanted, `fit_opening_size` raised the floor to the content
## that held it, and the engine refuses a window under its `min_size`. The scroll
## now asks for `SCROLLING_BODY_FLOOR` and the text's height goes into the size
## the dialog opens at.
##
## A drag is a write of `size` from outside the class, which is what the resizer
## and the window manager both make, and the engine holds it to `min_size` the
## same way. The screen and the hand-driven layout are those of
## `test_the_about_window_fits_a_screen`, for the reasons it gives. A tool
## script, because the stub dialog below extends one.
@tool
extends "res://tests/test_framework.gd"

## The screen size the fault was met on.
const SCREEN := Vector2i(1280, 1024)

## How much shorter the window is made, in pixels.
const SHORTER := 300

## The height About opened at on the screen above when the fault was met. Unfolded at
## the suite's font About opens 581 high, and 300 off 581 is under the 300 About
## declares as its floor, so the report is lengthened a line at a time until
## About opens this high, rather than the drag made shorter than the floor allows.
##
## A count of lines would not do. It was eight, measured alone,
## where the details are drawn at the engine's 16. In a whole run
## `test_dialog_font_scale.gd` has built the shared theme the app builds at
## boot, so they are drawn at Sara's 20, and after `test_boot_cover.gd` has run
## a boot as well the eight took About to 1002 on a screen that holds 976 of
## it, and the report was clamped to 770 of its 796.
const NOTE_HEIGHT := 728

## However tall a line is, About reaches that height long before this.
const MOST_EXTRA_LINES := 40


## A dialog of many fixed rows and no scrolling body, so its floor is the whole
## of what it shows.
class TallFixedDialog:
    extends SaDialogWindow

    func _init() -> void:
        _init_dialog("D13TallFixedDialog", "Tall", Vector2i(360, 240), Vector2i(300, 200))
        var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
        margin.set_anchors_preset(Control.PRESET_FULL_RECT)
        var column := SaMake.column(margin, "Column", SaTheme.GAP)
        for i in 16:
            SaMake.label(column, "Row%d" % i, "Row %d of a dialog that never scrolls" % (i + 1))
        SaMake.button(pinned_buttons(column), "DoneButton", "Done")


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
    _host.name = "D13ShorterTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_about_opens_showing_its_whole_report() -> void:
    var window := _about()
    var report := window.scrolling_body
    assert_true(
        report.size.y >= _child_minimum(report),
        "About opens with its whole report on show, %d of %d" % [report.size.y, _child_minimum(report)]
    )
    assert_true(
        window.min_size.y + SHORTER <= window.size.y,
        "Its floor of %d lets it lose %d of %d" % [window.min_size.y, SHORTER, window.size.y]
    )


func test_about_made_300_shorter_holds_its_height_its_buttons_and_scrolls() -> void:
    var window := _about()
    var opened := window.size
    var shorter := Vector2i(opened.x, opened.y - SHORTER)
    window.size = shorter
    _sort_children(window.content)
    assert_eq(window.size, shorter, "About held the height it was dragged to")
    assert_eq(window.logical_size, shorter, "and keeps it as the size it wants, at scale 1")
    var frame := Rect2(Vector2.ZERO, Vector2(window.size))
    for button_name: String in ["CopyButton", "CloseButton"]:
        var button := window.content.find_child(button_name, true, false) as BaseButton
        assert_not_null(button, "%s is in About" % button_name)
        if button != null:
            assert_true(
                frame.encloses(button.get_global_rect()),
                "%s at %s lies inside %s" % [button_name, button.get_global_rect(), frame]
            )
    var report := window.scrolling_body
    assert_true(
        report.size.y < _child_minimum(report),
        "The report is %d high against %d of text" % [report.size.y, _child_minimum(report)]
    )
    assert_true(report.get_v_scroll_bar().visible, "and its scroll bar shows")


func test_a_dialog_with_no_scrolling_body_keeps_its_floor() -> void:
    var screen := _screen()
    var window := TallFixedDialog.new()
    screen.add_child(window)
    window.popup_centered()
    _sort_children(window.content)
    window.fit_opening_size()
    _sort_children(window.content)
    var needed := window.content_minimum_size()
    assert_true(needed.y > 200, "The stub's rows need more than its declared floor, %d" % needed.y)
    assert_eq(window.min_size.y, needed.y, "Its floor is what its content needs")
    window.size = Vector2i(window.size.x, window.size.y - SHORTER)
    assert_eq(window.size.y, needed.y, "and a drag under it is held at it")


## About in the screen, opened the way the menu opens it, and fitted, with its
## licences unfolded and its details long enough that it opens `NOTE_HEIGHT`
## high. The fit only ever grows a window, so each line it is handed takes it
## one line taller.
func _about() -> SaAboutDialog:
    var window := SaAboutDialog.new()
    window.fold.folded = false
    _screen().add_child(window)
    window.refresh()
    window.popup_centered()
    _fit(window)
    var added := 0
    while window.size.y < NOTE_HEIGHT and added < MOST_EXTRA_LINES:
        added += 1
        window.details.text += "\nA further line of the machine's facts, %d" % added
        _fit(window)
    return window


func _fit(window: SaDialogWindow) -> void:
    _sort_children(window.content)
    window.fit_opening_size()
    _sort_children(window.content)


func _screen() -> SubViewport:
    var screen := SubViewport.new()
    screen.size = SCREEN
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    return screen


func _child_minimum(scroll: ScrollContainer) -> int:
    return ceili((scroll.get_child(0) as Control).get_combined_minimum_size().y)


func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
