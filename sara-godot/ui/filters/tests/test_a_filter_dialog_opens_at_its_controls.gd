## A filter dialog opens at the size of its controls, with the
## controls first and every number named.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One window serves every filter, so it has to shrink after a tall one
## rather than stay 660 by 640 whatever it holds. Gaussian Blur's picture
## sits over its slider as the adjust filters, Levels and Curves have it, and
## the numbers under Levels' bars are named, with a preview strip that has a
## frame and a caption.
##
## A test cannot await a frame, so the fit the window asks for on the frame
## after it is shown is called here by hand, the way
## `test_the_browser_opens_at_a_size_its_content_fits.gd` calls it. The running
## app is `scenarios/the-filter-dialogs-are-sized-to-their-controls-in-one-order.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"

## The five captions, in the order the fields sit.
const CAPTIONS := ["Black", "Midtone", "White", "Output black", "Output white"]

var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _window: SaFilterDialogWindow = null
var _host: Node = null
var _registry: SaFilterRegistry = null
var _was_embedding: bool = false

var _curves: SaFilter = null
var _blur: SaFilter = null
var _hue: SaFilter = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _was_embedding = tree.root.gui_embed_subwindows
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N99TestHost"
    EventBus.add_child(_host)

    _easel = Bench.easel(Vector2i(256, 256))
    _canvas = SaCanvas.new()
    _canvas.easel = _easel

    _registry = SaFilterRegistry.new()
    _curves = SaCurvesFilter.new()
    _blur = SaGaussianBlurFilter.new()
    _hue = SaHueSaturationLightnessFilter.new()
    for filter: SaFilter in [_curves, _blur, _hue]:
        _registry.register(filter, OWNER)
    _easel.compositor.filter_chain.registry = _registry

    _window = SaFilterDialogWindow.new()
    _window.target_canvas = _canvas
    _window.watch(_registry)
    _host.add_child(_window)


func after_each() -> void:
    Teardown.free_nodes([_window, _canvas, _easel])
    _window = null
    _canvas = null
    _easel = null
    _registry = null
    _curves = null
    _blur = null
    _hue = null
    if _host != null:
        _host.free()
        _host = null
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _was_embedding


## Opens *filter* and runs the fit its first frame would, answering the size
## the window itself stands at after it. The window's own and not its
## `logical_size`, because a floor raised by the tall page can hold the first
## where it was while the second resets, and a suite that read `logical_size`
## would pass over a window still Curves' height.
##
## Laid out before the fit, as the app's first frames lay it out. A titled
## row's label wraps at the width its column hands it, and unsorted it had none,
## so the Preview switch's words read one letter a line and Gaussian Blur
## measured 858 high. Sorted and asked again twice, the way
## `test_the_browser_opens_at_a_size_its_content_fits.gd` settles its window,
## because the label measures its new width only once asked again.
func _open(filter: SaFilter) -> Vector2i:
    _window.open_filter(SaFilterRegistry.key_for(OWNER, filter))
    for _pass in range(2):
        _sort_children(_window)
        _ask_again(_window)
    _window.fit_opening_size()
    return _window.size


## Sorts every container under *node*, outside in, so the rectangles below it are
## the ones the running app would draw.
func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Every control under *node* asked for its minimum again, inside out.
func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


func _frame() -> SaFilterDialogFrame:
    return _window.find_child("FilterFrame", true, false) as SaFilterDialogFrame


func test_both_windows_are_built_narrow_and_hand_the_fit_their_scroll() -> void:
    assert_eq(_window.logical_min_size, SaFilterDialogFrame.FLOOR, "the one-shot window keeps the floor it had")
    assert_eq(_window.scrolling_body, _frame().scroll, "and the fit measures the page through the scroll")
    var editor := SaFilterEditWindow.new()
    assert_eq(editor.logical_size, SaFilterDialogFrame.OPENING_SIZE, "the attached filter's window is built at the same size")
    var editor_frame := editor.find_child("FilterFrame", true, false) as SaFilterDialogFrame
    assert_eq(editor.scrolling_body, editor_frame.scroll, "and fits the same way")
    editor.free()
    assert_eq(SaFilterDialogFrame.OPENING_SIZE.x, 520, "520 across, the width of the opening size")
    assert_eq(SaFilterDialogFrame.OPENING_SIZE.y, SaFilterDialogFrame.FLOOR.y, "and the floor's height, so the page decides it")


func test_a_short_filter_after_a_tall_one_opens_short() -> void:
    var tall := _open(_curves)
    var short := _open(_blur)
    assert_true(short.y < tall.y, "Gaussian Blur opens at %d after Curves at %d, not at Curves' height" % [short.y, tall.y])
    assert_true(short.y < 640, "and under the 640 every filter once opened at, at %d" % short.y)


func test_the_window_opens_at_the_height_its_page_asks_for() -> void:
    var opened := _open(_blur)
    # The scroll asks only for its floor, so the window's
    # whole height is its content with the page in place of that floor.
    var scroll := _frame().scroll
    var page := ceili((scroll.get_child(0) as Control).get_combined_minimum_size().y)
    var needed := _window.content_minimum_size().y - roundi(scroll.custom_minimum_size.y) + page
    var wanted := SaUI.window_size_for(_window, Vector2i(0, maxi(needed, SaFilterDialogFrame.FLOOR.y)))
    assert_eq(opened.y, wanted.y, "the window is as tall as its page and its buttons")
    assert_eq(_window.logical_size.y, maxi(needed, SaFilterDialogFrame.FLOOR.y), "and says so in logical units")
    _sort_children(_window)
    assert_true(scroll.size.y >= page, "and the scroll is laid out at the page's height, %d of %d" % [scroll.size.y, page])


func test_gaussian_blurs_first_row_is_its_radius() -> void:
    _open(_blur)
    var dialog := _window.dialog
    var names := dialog.rows().map(func(one: SaPageRow) -> String: return dialog.widget_name(one.key))
    assert_eq(
        names, ["slider", "canvas_preview", "thumbnail", "apply_cancel"], "the slider first, the switch and the picture after it"
    )
    var first: SaPageRow = dialog.rows()[0]
    assert_eq(first.key, &"radius", "and the slider is the Radius")
    assert_eq(first.suffix, " px", "which says it is in pixels")


func test_the_five_levels_fields_carry_their_captions() -> void:
    var panel := SaLevelsPanel.new()
    var found: Array[String] = []
    for row: Dictionary in SaLevelsPanel.ROWS:
        var named := String(row["key"]).capitalize().replace(" ", "")
        var caption := panel.find_child(named + "Caption", true, false) as Label
        var field := panel.find_child(named + "Field", true, false) as SpinBox
        assert_not_null(caption, "the %s field has a caption" % row["key"])
        assert_not_null(field, "and the field is still there")
        if caption == null or field == null:
            continue
        found.append(caption.text)
        assert_eq(caption.get_parent(), field.get_parent(), "%s sits with its own field" % caption.text)
        assert_true(caption.get_index() < field.get_index(), "and above it")
        assert_eq(caption.get_theme_color("font_color"), SaTheme.palette.text_muted, "in the muted colour")
    assert_eq(found, CAPTIONS, "the five captions")
    panel.free()


func test_the_preview_strip_has_a_caption_and_a_frame() -> void:
    var preview := SaFilterPreview.new()
    assert_eq(preview.caption.text, "Preview", "the strip says what it is")
    assert_true(preview.caption.get_index() < preview.frame.get_index(), "over the picture")
    var box := preview.frame.get_theme_stylebox("panel") as StyleBoxFlat
    assert_not_null(box, "the picture has a frame")
    assert_eq(box.border_color, SaTheme.palette.border_primary, "in the theme's border colour")
    assert_eq(box.border_width_top, 1, "one pixel wide")
    assert_eq(preview.frame.size_flags_vertical, Control.SIZE_EXPAND_FILL, "and any height the preview is given is the picture's")
    preview.free()


func test_the_picture_takes_the_free_height() -> void:
    _open(_hue)
    var picture: Control = _window.dialog.preview_control
    var rows := _frame().rows
    assert_true(rows.is_ancestor_of(picture), "the picture is on the page")
    assert_eq(rows.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the page fills a scroll taller than itself")
    var node: Node = picture
    while node != rows:
        assert_eq(
            (node as Control).size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s hands the picture its spare height" % node.name
        )
        node = node.get_parent()
