## New Document, Image Size and Canvas Size are declared pages in their windows:
## the plain controls are bound rows the page made, and a row moved as a hand
## moves it writes the window's own property and runs the window's own rule.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"


## The keys of a page's rows and the kind of each, in declaration order.
func _shape(page: SaPage) -> Array:
    return page.rows().map(func(entry: SaPageRow) -> String: return "%s:%s" % [entry.key, SaPageRow.KIND_NAMES[entry.kind]])


## The rows a dump prints for *page*, found the way the harness finds it: by the
## meta on the container it was realized into.
func _host_page(dialog: Window, host_name: String) -> SaPage:
    var host := dialog.find_child(host_name, true, false) as Container
    assert_not_null(host, "%s holds the page" % host_name)
    if host == null or not host.has_meta(SaPage.PAGE_META):
        return null
    return host.get_meta(SaPage.PAGE_META) as SaPage


func test_image_size_is_a_page_of_four_bound_rows() -> void:
    var dialog := SaImageSizeDialog.new()
    var page := _host_page(dialog, "ImageSizePage")
    assert_true(page == dialog.page, "the page the window holds is the one its container carries")
    var shape := ["width:number", "height:number", "lock:toggle", "filter:choice"]
    assert_eq(_shape(page), shape, "two numbers, the lock and the filter")
    for key: StringName in [&"width", &"height", &"lock", &"filter"]:
        assert_true(page.row(key).bound_to().begins_with("image_size_dialog."), "%s is bound to the window" % key)
    assert_true(dialog.find_child("WidthSpin", true, false) is SpinBox, "the width row is a spinbox under its old name")
    assert_true(dialog.find_child("LockCheck", true, false) is CheckButton, "the lock is a switch under its old name")
    assert_true(dialog.find_child("FilterOption", true, false) is SaChoiceButton, "the filter is Sara's dropdown")
    dialog.free()


func test_image_size_the_lock_fills_the_other_number() -> void:
    var dialog := SaImageSizeDialog.new()
    dialog.configure(Vector2i(1920, 1080))
    dialog.page.row(&"width").drive(3840)
    assert_eq(dialog.requested_size(), Vector2i(3840, 2160), "a width typed with the lock on fills the height in")
    assert_eq((dialog.find_child("HeightSpin", true, false) as SpinBox).value, 2160.0, "and the height spinbox shows it")
    assert_eq(
        (dialog.find_child("ScaleLabel", true, false) as Label).text,
        "200% × 200%, resampled with Bilinear.",
        "the line under the rows says what the numbers do"
    )
    dialog.page.row(&"lock").drive(false)
    dialog.page.row(&"height").drive(500)
    assert_eq(dialog.requested_size(), Vector2i(3840, 500), "with the lock off the width stays")
    dialog.page.row(&"filter").drive(1)
    assert_eq(dialog.selected_filter(), int(SaResampleKernel.Filter.NEAREST), "the second filter row is Nearest")
    assert_true(
        (dialog.find_child("ScaleLabel", true, false) as Label).text.ends_with("resampled with Nearest."), "and the line says so"
    )
    dialog.configure(Vector2i(800, 600))
    assert_eq(dialog.requested_size(), Vector2i(800, 600), "an open starts the numbers at the document again")
    assert_eq((dialog.find_child("WidthSpin", true, false) as SpinBox).value, 800.0, "and the spinbox follows the property")
    dialog.free()


func test_image_size_confirms_what_the_rows_hold() -> void:
    var dialog := SaImageSizeDialog.new()
    dialog.configure(Vector2i(1000, 500))
    var asked: Array = []
    dialog.resample_requested.connect(func(size: Vector2i, filter: int) -> void: asked.append([size, filter]))
    dialog.page.row(&"width").drive(2000)
    dialog.default_button.pressed.emit()
    assert_eq(asked, [[Vector2i(2000, 1000), int(SaResampleKernel.Filter.BILINEAR)]], "Scale sends the rows' size and filter")
    dialog.free()


func test_canvas_size_is_two_bound_numbers_and_the_anchor() -> void:
    var dialog := SaCanvasSizeDialog.new()
    var page := _host_page(dialog, "CanvasSizePage")
    assert_true(page == dialog.page, "the page the window holds is the one its container carries")
    assert_eq(_shape(page), ["width:number", "height:number", "anchor:custom"], "two numbers and the one custom row")
    assert_eq(page.row(&"width").bound_to(), "canvas_size_dialog.wanted_width", "the width is bound to the window")
    assert_true(page.row(&"anchor").control is GridContainer, "the custom row is the nine-cell grid")
    assert_eq(page.row(&"anchor").control.get_child_count(), 9, "of nine cells")
    assert_true((dialog.find_child("Anchor11", true, false) as Button).button_pressed, "and the centre is down")
    dialog.free()


func test_canvas_size_rows_reach_the_difference_line_and_the_request() -> void:
    var dialog := SaCanvasSizeDialog.new()
    dialog.configure(Vector2i(1920, 1080))
    var said := dialog.find_child("DifferenceLabel", true, false) as Label
    assert_eq(said.text, "Anchor: Centre. The canvas does not change.", "an untouched dialog changes nothing")
    dialog.page.row(&"width").drive(2560)
    assert_eq(dialog.requested_size(), Vector2i(2560, 1080), "the width row reaches the request")
    assert_true(said.text.begins_with("Anchor: Centre. The picture's top-left corner moves to 320, 0 px."), "and the line")
    (dialog.find_child("Anchor20", true, false) as Button).pressed.emit()
    assert_eq(dialog.anchor, Vector2i(2, 0), "a cell pressed is the anchor")
    var asked: Array = []
    dialog.resize_requested.connect(func(size: Vector2i, cell: Vector2i) -> void: asked.append([size, cell]))
    dialog.default_button.pressed.emit()
    assert_eq(asked, [[Vector2i(2560, 1080), Vector2i(2, 0)]], "Resize sends the rows' size and the anchor")
    dialog.configure(Vector2i(640, 480))
    assert_eq((dialog.find_child("HeightSpin", true, false) as SpinBox).value, 480.0, "an open starts the rows again")
    dialog.free()


func test_new_document_is_a_page_with_six_custom_rows() -> void:
    var dialog := NewDocumentDialog.new()
    var page := _host_page(dialog, "NewDocumentPage")
    assert_true(page == dialog.page, "the page the window holds is the one its container carries")
    var shape := ["template:choice", "save_template:custom"]
    shape.append_array(["size:choice", "width:number", "swap:action", "height:number", "dpi:number"])
    shape.append_array(["background:choice", "background_colour:colour", "details:toggle", "ground:choice", "memory:custom"])
    shape.append_array(["space:choice", "depth:choice", "gamut:choice", "primaries:custom", "white:choice"])
    shape.append_array(["white_xy:custom", "transfer:choice", "gamma:custom", "coordinates:choice", "save_space:custom"])
    var said := "three numbers, ten dropdowns, the background's swatch, the swap, the details switch"
    said += ", and the template's saving, memory, primaries, white xy, gamma and the space's saving held by hand"
    assert_eq(_shape(page), shape, said)
    for key: StringName in [&"width", &"height", &"dpi", &"space", &"gamut", &"transfer", &"coordinates", &"depth"]:
        assert_true(page.row(key).bound_to().begins_with("new_document_dialog."), "%s is bound to the window" % key)
    for node: String in ["WidthSpin", "HeightSpin", "DpiSpin"]:
        assert_true(dialog.find_child(node, true, false) is SpinBox, "%s keeps its name" % node)
    for node: String in ["SpaceOption", "GamutRowOption", "TransferOption", "CoordinatesOption", "DepthOption"]:
        assert_true(dialog.find_child(node, true, false) is SaChoiceButton, "%s keeps its name" % node)
    assert_true(dialog.find_child("GammaSlider", true, false) is HSlider, "the gamma slider sits in its custom row")
    # The white is a choice of its own, so a space can be the same lights at
    # another white.
    assert_true(dialog.row_option(&"white") is SaChoiceButton, "the white point is a dropdown of its own")
    dialog.free()


func test_new_document_rows_reach_the_request() -> void:
    var dialog := NewDocumentDialog.new()
    dialog.page.row(&"width").drive(640)
    dialog.page.row(&"height").drive(480)
    dialog.page.row(&"dpi").drive(150)
    assert_eq(dialog.selected_size(), Vector2i(640, 480), "the number rows are the size asked for")
    assert_eq(dialog.selected_dpi(), 150.0, "and the resolution")
    dialog.page.row(&"space").drive(0)
    var filled := dialog.selected_space()
    assert_eq(
        dialog.row_option(&"gamut").text, SaGamut.presets()[dialog.picker.gamut_row].display_name, "a preset fills the gamut row"
    )
    assert_eq(filled.primaries.size(), 3, "and the space the rows describe is whole")
    dialog.page.row(&"transfer").drive(SaTransferFunction.presets().size())
    assert_eq(dialog.picker.space_row, SaColorSpace.presets().size(), "a free gamma curve matches no preset and shows Custom")
    assert_eq(dialog.row_option(&"space").text, NewDocumentDialog.CUSTOM_LABEL, "and the dropdown follows the property")
    dialog.free()
