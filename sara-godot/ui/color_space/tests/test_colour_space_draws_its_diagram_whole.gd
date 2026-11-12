## Document Colour Space draws its diagram whole and says what Assign and
## Convert do.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The dialog clipped its own diagram:
## the drawing sat in a scroll about 200 tall inside the page's own scroll, with
## about 130 pixels of the dialog under it empty, and nothing on the row said
## what Assign and Convert do to the pixels. The browser now goes into the page
## with no scroll of its own, the page is the window's `scrolling_body`, and the
## window opens as tall as the drawing wants or as the host allows.
##
## The screen is a `SubViewport` of the size asked for with subwindows embedded in
## it, because an embedded window measures itself against its host viewport, and
## the layout is driven by hand, for the reason
## `test_the_about_window_fits_a_screen.gd` gives: a suite cannot await the frame
## the app fits on, so every container is sorted outside in before the fit reads
## a wrapping label and again before the rectangles are read.
extends "res://tests/test_framework.gd"

## The browser draws its gamut through the rendering device.
const REQUIRES_GPU := true

## The screen the Done paragraph names, and one too short for the whole drawing.
const FULL_HD := Vector2i(1920, 1080)
const LAPTOP := Vector2i(1280, 720)

## The host a 1280 by 800 screen leaves at an interface scale of 2, less the bar:
## shorter than the 430 the floor was a guess of, so the floor has to give.
const SMALL := Vector2i(640, 400)

const NOTE := "Assign keeps every pixel and reads it in the new space. Convert changes the pixels so they look the same."

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
    _host.name = "ColourSpaceWholeTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


func test_the_diagram_lies_inside_the_visible_page_at_1920_by_1080() -> void:
    var dialog := _opened_in(FULL_HD)
    var page := Rect2(dialog._page_scroll.global_position, dialog._page_scroll.size)
    var diagram := Rect2(dialog.browser.diagram.global_position, dialog.browser.diagram.size)
    assert_true(page.size.y > 0.0 and diagram.size.y > 0.0, "Both were laid out: the page %s, the diagram %s" % [page, diagram])
    assert_true(page.encloses(diagram), "The diagram at %s lies inside the visible page at %s" % [diagram, page])
    assert_true(
        diagram.size.y >= float(SaUI.px(SaChromaticityDiagram.MIN_HEIGHT)),
        "and is drawn at its own height, %d, not cut to a letterbox" % int(diagram.size.y)
    )
    assert_true(
        diagram.size.y > float(SaUI.px(200)), "which is more than the 200 the inner scroll left it: %d" % int(diagram.size.y)
    )
    var report := ColorSpaceDialog.capture_state(_host.get_tree().root)
    assert_eq(report.get("diagram_inside_page"), true, "and the dump says so in a word")


## The Target is the colour space picker, its rows beside the drawing, and at
## 1920 by 1080 every row of it and the drawing are in sight with no scrolling.
func test_the_picker_and_the_drawing_lie_side_by_side_inside_the_page_at_1920_by_1080() -> void:
    var dialog := _opened_in(FULL_HD)
    var page := Rect2(dialog._page_scroll.global_position, dialog._page_scroll.size)
    var rows := dialog.find_child("TargetRows", true, false) as Control
    var cut: Array[String] = []
    for node: Node in rows.find_children("*", "Control", true, false):
        var control := node as Control
        if control.is_visible_in_tree() and control.size.x > 0.0 and not page.grow(0.5).encloses(control.get_global_rect()):
            cut.append("%s at %s" % [control.name, control.get_global_rect()])
    assert_eq(cut, [] as Array[String], "every row of the picker lies inside the visible page at %s" % page)
    for node_name: String in ["SpaceOption", "PrimariesFields", "WhitePointXy", "GammaSlider", "SpaceSaver"]:
        var control := rows.find_child(node_name, true, false) as Control
        assert_true(control != null and control.is_visible_in_tree(), "%s is shown" % node_name)
    var diagram := dialog.browser.diagram.get_global_rect()
    assert_true(diagram.position.x >= rows.get_global_rect().end.x, "and the drawing stands beside the rows, not under them")


func test_the_browser_has_no_scroll_of_its_own() -> void:
    var dialog := _opened_in(FULL_HD)
    assert_eq(dialog.find_child("ColorSpaceScroll", true, false), null, "The inner scroll is gone")
    var between: Array[String] = []
    var up := dialog.browser.get_parent()
    while up != null and up != dialog._page_scroll:
        if up is ScrollContainer:
            between.append(String(up.name))
        up = up.get_parent()
    assert_eq(up, dialog._page_scroll, "The browser sits in the page the one scroll holds")
    assert_eq(between, [] as Array[String], "with no scroll between them")
    assert_eq(dialog.scrolling_body, dialog._page_scroll, "and that scroll is the window's scrolling body")


func test_the_window_opens_taller_than_the_default_and_the_floor_stays_low() -> void:
    var dialog := _opened_in(FULL_HD)
    assert_true(
        dialog.logical_size.y > ColorSpaceDialog.DEFAULT_SIZE.y,
        (
            "The window grew to the drawing: %d against the %d it was asked for"
            % [dialog.logical_size.y, ColorSpaceDialog.DEFAULT_SIZE.y]
        )
    )
    assert_eq(
        dialog.logical_min_size,
        dialog.content_minimum(),
        "while the floor is the measured one, so the window can still be dragged down"
    )
    assert_true(
        dialog.logical_min_size.y < dialog.logical_size.y,
        "which is under the height it opened at: %d under %d" % [dialog.logical_min_size.y, dialog.logical_size.y]
    )


## The floor the test above holds is one the window can really be dragged to:
## there the three buttons are inside it and the page scrolls.
##
## The floor came down to the measured one while the page kept the height the
## base fit had given it for the whole drawing, so the column still asked for
## that height, and the window dragged to its floor of 430 held its buttons at
## 922. The whole run's dialog suite read the same thing as a floor under what
## the content needs. The base fit now asks a scrolling body for no more than
## its own floor, which is what holds this.
func test_a_window_dragged_to_its_floor_keeps_its_buttons() -> void:
    var dialog := _opened_in(FULL_HD)
    assert_true(
        dialog.size.y > dialog.min_size.y, "It opened taller than its floor, %d over %d" % [dialog.size.y, dialog.min_size.y]
    )
    dialog.size = dialog.min_size
    _settle(dialog.content)
    var needed := dialog.content_minimum_size()
    assert_true(
        dialog.logical_min_size.y >= needed.y,
        "The floor of %d holds the %d the laid out column needs" % [dialog.logical_min_size.y, needed.y]
    )
    var report := ColorSpaceDialog.capture_state(_host.get_tree().root)
    assert_eq(report.get("buttons_inside"), true, "At %s the three buttons are inside the window" % dialog.size)
    assert_eq(report.get("page_scrolls"), true, "and the page scrolls to the rest of the drawing")


func test_the_line_that_says_what_assign_and_convert_do_stands_above_the_row() -> void:
    var dialog := _opened_in(FULL_HD)
    var note := dialog.find_child("NoteLabel", true, false) as Label
    assert_not_null(note, "The window carries a line about the two buttons")
    if note == null:
        return
    assert_eq(note.text, NOTE, "and it says what each does to the pixels")
    assert_true(note.is_visible_in_tree(), "It is shown")
    assert_false(
        dialog._page_scroll.is_ancestor_of(note), "and it is outside the scroll, so it is in sight whenever the buttons are"
    )
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    assert_true(frame.encloses(note.get_global_rect()), "inside the window at %s" % note.get_global_rect())
    var buttons_row := dialog.cancel_button.get_parent() as Control
    assert_true(note.get_global_rect().end.y <= buttons_row.get_global_rect().position.y + 0.5, "above the row of buttons")
    assert_true(note.has_theme_color_override("font_color"), "in the muted colour")


func test_the_row_reads_cancel_convert_assign_and_assign_is_the_default() -> void:
    var dialog := _opened_in(FULL_HD)
    var row := dialog.cancel_button.get_parent() as Container
    var names: Array[String] = []
    for child: Node in row.get_children():
        names.append((child as Button).text)
    assert_eq(names, ["Cancel", "Convert", "Assign"] as Array[String], "The way out first, the default last")
    assert_eq(dialog.default_button, dialog.assign_button, "and the default is still Assign, the reversible one")
    var rects: Array[Rect2] = []
    for button: Button in [dialog.cancel_button, dialog.convert_button, dialog.assign_button]:
        rects.append(button.get_global_rect())
    assert_true(
        rects[0].position.x < rects[1].position.x and rects[1].position.x < rects[2].position.x, "left to right in that order"
    )
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    for rect: Rect2 in rects:
        assert_true(frame.encloses(rect), "%s lies inside the window %s" % [rect, frame])


func test_enter_still_presses_assign() -> void:
    var dialog := _opened_in(FULL_HD)
    var asked: Array[String] = []
    dialog.assign_requested.connect(func(_space: SaColorSpace) -> void: asked.append("assign"))
    dialog.convert_requested.connect(func(_space: SaColorSpace) -> void: asked.append("convert"))
    dialog.gui_release_focus()
    dialog.push_input(_enter(true))
    dialog.push_input(_enter(false))
    assert_eq(asked, ["assign"] as Array[String], "Enter with the outline nowhere is Assign, not Convert")
    assert_false(dialog.visible, "and it shut the dialog")


func test_a_short_host_scrolls_the_page_and_keeps_the_rows_and_the_buttons() -> void:
    var dialog := _opened_in(LAPTOP)
    var page := dialog._page_scroll
    var wanted := ceili((page.get_child(0) as Control).get_combined_minimum_size().y)
    assert_true(
        float(wanted) > page.size.y, "The page is taller than the room it has: %d against %d" % [wanted, int(page.size.y)]
    )
    var report := ColorSpaceDialog.capture_state(_host.get_tree().root)
    assert_eq(report.get("page_scrolls"), true, "so it scrolls")
    assert_eq(report.get("buttons_inside"), true, "while the three buttons stay inside the window")
    var frame := Rect2(Vector2.ZERO, Vector2(dialog.size))
    assert_true(frame.encloses(dialog._status_label.get_global_rect()), "and so does the line that says why Convert is out")
    assert_true(
        Rect2(Vector2.ZERO, Vector2(LAPTOP)).encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))),
        "and the window lies inside the screen it was opened in"
    )


func test_a_host_shorter_than_the_old_floor_gets_a_window_that_fits_it() -> void:
    var dialog := _opened_in(SMALL)
    var screen := Rect2(Vector2.ZERO, Vector2(SMALL))
    assert_true(
        screen.encloses(Rect2(Vector2(dialog.position), Vector2(dialog.size))),
        "The window at %s, %s big, lies inside %s" % [dialog.position, dialog.size, SMALL]
    )
    assert_true(
        dialog.logical_min_size.y < ColorSpaceDialog.FLOOR_SIZE.y,
        "because the floor gave way to the room: %d" % dialog.logical_min_size.y
    )
    for button: Button in [dialog.cancel_button, dialog.convert_button, dialog.assign_button]:
        var rect := Rect2(Vector2(dialog.position) + button.get_global_rect().position, button.size)
        assert_true(screen.encloses(rect), "%s lies inside the screen at %s" % [button.text, rect])
    assert_eq(ColorSpaceDialog.capture_state(_host.get_tree().root).get("page_scrolls"), true, "and the page scrolls under them")


func test_the_reason_convert_is_out_is_read_beside_the_buttons() -> void:
    var dialog := _opened_in(LAPTOP)
    dialog.configure(
        SaColorSpace.unspecified(), func(_target: SaColorSpace) -> String: return "this document never declared a colour space"
    )
    assert_false(dialog._page_scroll.is_ancestor_of(dialog._status_label), "The status line is outside the scrolling page")
    assert_true(dialog._status_label.text.contains("never declared"), "and says the reason")
    assert_true(dialog.convert_button.disabled, "Convert is out for it")


## One edge of Enter, spelled with both keycode fields as a keyboard sends it.
static func _enter(pressed: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ENTER
    key.physical_keycode = KEY_ENTER
    key.pressed = pressed
    return key


## The dialog in a screen of *size*, opened the way the menu opens it, fitted,
## and laid out.
func _opened_in(size: Vector2i) -> ColorSpaceDialog:
    var screen := SubViewport.new()
    screen.size = size
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    var dialog := ColorSpaceDialog.new()
    screen.add_child(dialog)
    dialog.configure(SaColorSpace.srgb(), func(_target: SaColorSpace) -> String: return "")
    dialog.popup_centered()
    for _pass in 3:
        _settle(dialog.content)
        dialog.fit_opening_size()
    _settle(dialog.content)
    return dialog


## Every wrapping label asked again, then every container sorted, outside in.
##
## A wrapping `Label` keeps the minimum it measured when it was one character
## wide until it is told to measure again, and the page holds a dozen of them, so
## the page wanted five thousand units tall before the first frame. The app has
## frames for it and a suite has none, so it is asked for by hand, twice over
## because a label's answer moves the width the container above it sorts to.
func _settle(node: Node) -> void:
    for _round in 2:
        _remeasure_labels(node)
        _sort_children(node)


func _remeasure_labels(node: Node) -> void:
    for child: Node in node.get_children():
        var label := child as Label
        if label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
            label.update_minimum_size()
        _remeasure_labels(child)


func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)
