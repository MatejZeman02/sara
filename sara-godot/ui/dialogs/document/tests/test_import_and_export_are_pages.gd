## Export and the import dialog are declared pages in their windows: the plain
## controls are rows the page made, a row moved as a hand moves it writes the
## window's own property, and each window still holds its rows and its buttons.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


## The keys of a page's rows and the kind of each, in declaration order.
func _shape(page: SaPage) -> Array:
    return page.rows().map(func(entry: SaPageRow) -> String: return "%s:%s" % [entry.key, SaPageRow.KIND_NAMES[entry.kind]])


## The page a dump prints for *dialog*, found the way the harness finds it: by
## the meta on the container it was realized into.
func _host_page(dialog: Window, host_name: String) -> SaPage:
    var host := dialog.find_child(host_name, true, false) as Container
    assert_not_null(host, "%s holds the page" % host_name)
    if host == null or not host.has_meta(SaPage.PAGE_META):
        return null
    return host.get_meta(SaPage.PAGE_META) as SaPage


func test_export_is_a_page_of_its_options_and_its_result() -> void:
    var dialog := SaExportDialog.new()
    var page := _host_page(dialog, "ExportPage")
    assert_true(page == dialog.page, "the page the window holds is the one its container carries")
    var shape := [
        "format:choice",
        "quality:custom",
        "flatten:custom",
        "half:toggle",
        "depth:choice",
        "dither:toggle",
        "rolloff:toggle",
        "note:custom",
        "relief:toggle",
        "format_line:custom",
        "gamut_line:custom",
        "gamut_help:custom",
        "size_line:custom",
        "loss:custom",
    ]
    assert_eq(
        _shape(page),
        shape,
        "the format, one row per format, the dither, the rolloff with its sentence, the impasto row, and the Result"
    )
    for key: StringName in [&"format", &"half"]:
        assert_true(page.row(key).bound_to().begins_with("export_dialog."), "%s is bound to the window" % key)
    assert_eq(page.row(&"depth").bound_to(), "itself", "the depth is kept per format, so it is not bound")
    assert_eq(page.row(&"rolloff").bound_to(), "itself", "and the rolloff is the private member the export reads")
    assert_eq(page.row(&"dither").bound_to(), "itself", "and so is the dither, kept from one opening to the next")
    assert_true(dialog.find_child("FormatOption", true, false) is SaChoiceButton, "the format is Sara's dropdown")
    var quality := dialog.find_child("QualitySlider", true, false) as FactorSlider
    assert_not_null(quality, "the quality is the custom row's typed slider, under its old name")
    if quality != null:
        assert_eq(quality.decimal_places, 2, "reading two decimals")
    assert_true(dialog.find_child("HalfCheck", true, false) is CheckButton, "the half row is a switch under its old name")
    assert_true(dialog.find_child("RolloffCheck", true, false) is CheckButton, "and so is the rolloff")
    dialog.free()


func test_export_rows_follow_the_format() -> void:
    var dialog := SaExportDialog.new()
    assert_true(dialog.shows(&"depth"), "PNG asks for a depth")
    assert_false(dialog.shows(&"quality"), "and not for a quality")
    dialog.page.row(&"format").drive(SaExportDialog.format_ids().find(&"jpg"))
    assert_eq(dialog.format, &"jpg", "the format row writes the window's format")
    assert_true(dialog.shows(&"quality"), "JPG asks for a quality")
    assert_false(dialog.shows(&"depth"), "and has no depth to ask about")
    # As a hand moves it: the setter is silent, and a drag or a typed number
    # emits the signal after it.
    var slider := dialog.page.row(&"quality").control as FactorSlider
    slider.value = 0.5
    slider.value_changed.emit(0.5)
    assert_almost_eq(dialog.quality, 0.5, 0.001, "the quality slider writes the window's quality")
    dialog.page.row(&"format").drive(SaExportDialog.format_ids().find(&"exr"))
    assert_true(dialog.shows(&"half"), "EXR asks about half precision")
    dialog.page.row(&"half").drive(true)
    assert_true(dialog.half, "and the row writes it")
    dialog.page.row(&"format").drive(SaExportDialog.format_ids().find(&"tiff"))
    assert_true(dialog.shows(&"depth"), "TIFF asks for a depth again")
    var labels: Array = dialog.page.row(&"depth").choices.map(func(choice: Dictionary) -> String: return choice["label"])
    assert_true(labels.has("16-bit integer"), "from TIFF's own list")
    dialog.free()


func test_the_import_dialog_is_a_page_of_five_bound_rows() -> void:
    var dialog := SaImportFitDialog.new()
    var page := _host_page(dialog, "ImportFitPage")
    assert_true(page == dialog.page, "the page the window holds is the one its container carries")
    assert_eq(
        _shape(page),
        ["space:choice", "fit:choice", "depth:choice", "remember:toggle", "show_next_time:toggle"],
        "three choices and two boxes"
    )
    for key: StringName in [&"space", &"fit", &"depth", &"remember", &"show_next_time"]:
        assert_true(page.row(key).bound_to().begins_with("import_fit_dialog."), "%s is bound to the window" % key)
    for name: String in ["InputSpaceOption", "FitOption", "DepthOption"]:
        assert_true(dialog.find_child(name, true, false) is SaChoiceButton, "%s is Sara's dropdown under its old name" % name)
    assert_true(dialog.find_child("RememberCheck", true, false) is CheckButton, "and the box is a switch")
    dialog.free()


func test_the_import_rows_write_the_window() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(300, 150), Vector2i(200, 200))
    assert_eq(dialog.chosen_fit(), SaImageImport.Fit.INSIDE, "a picture wider than the canvas starts inside")
    var hint := dialog.find_child("FitHint", true, false) as Label
    assert_not_null(hint, "the fit row's sentence keeps its old name")
    var ids := SaImportFitDialog.CHOICES.map(func(choice: Array) -> int: return int(choice[0]))
    var stretch := ids.find(SaImageImport.Fit.STRETCH)
    dialog.page.row(&"fit").drive(stretch)
    assert_eq(dialog.chosen_fit(), SaImageImport.Fit.STRETCH, "the fit row writes the window's fit")
    if hint != null:
        assert_eq(hint.text, tr(SaImportFitDialog.CHOICES[stretch][2]), "and the sentence under it follows")
    dialog.page.row(&"remember").drive(true)
    assert_true(dialog.remembers(), "the box writes the window's answer")
    assert_true(dialog.select_space(&"display_p3"), "a space the list holds is chosen")
    assert_eq(dialog.chosen_space().id, &"display_p3", "and the window reads it back")
    dialog.free()


func test_the_import_dialog_swaps_its_rows_for_the_open_question() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure_open(Vector2i(100, 50), null, SaColorSpace.Depth.F16)
    assert_false(dialog.page.row(&"fit").line.visible, "the open question has no fit")
    assert_false(dialog.page.row(&"remember").line.visible, "and no box")
    assert_true(dialog.page.row(&"depth").line.visible, "it asks the depth")
    assert_eq(dialog.chosen_depth(), int(SaColorSpace.Depth.F16), "starting at the file's own")
    dialog.configure(Vector2i(100, 50), Vector2i(100, 50))
    assert_true(dialog.page.row(&"fit").line.visible, "the fit question has its fit back")
    assert_false(dialog.page.row(&"depth").line.visible, "and no depth")
    dialog.free()


## Both windows, in each of their questions, hold what their page builds at
## their smallest, measured as `test_windows_open` measures the colour dialogs.
func test_each_window_holds_its_rows_at_its_minimum() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This test needs the real scene tree, for the theme a Label measures against")
    if tree == null:
        return
    var previous_embedding: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "L10FitTestHost"
    EventBus.add_child(host)

    for mode: String in ["export png", "export jpg", "import fit", "import open"]:
        var window: Window = null
        if mode.begins_with("export"):
            window = SaExportDialog.new()
        else:
            window = SaImportFitDialog.new()
        host.add_child(window)
        window.show()
        if mode == "export jpg":
            (window as SaExportDialog).page.row(&"format").drive(SaExportDialog.format_ids().find(&"jpg"))
        elif mode == "import fit":
            (window as SaImportFitDialog).configure(Vector2i(1600, 900), Vector2i(1920, 1200))
        elif mode == "import open":
            (window as SaImportFitDialog).configure_open(Vector2i(1600, 900))
        var root_container := _outermost_container(window.content)
        if root_container != null:
            _lay_out(root_container, Vector2(window.min_size))
            var needed: float = root_container.get_combined_minimum_size().y
            assert_true(
                needed <= float(window.min_size.y),
                "%s is at least %d tall and its layout needs %d" % [mode, window.min_size.y, int(needed)]
            )
        window.free()

    host.free()
    tree.root.gui_embed_subwindows = previous_embedding


## Gives *root* a size and sorts every container under it twice, the pass the
## next frame would make, so a wrapping label asks for the lines its width
## gives it.
func _lay_out(root: Container, size: Vector2) -> void:
    root.size = size
    for _pass in 2:
        _sort(root)


func _sort(node: Node) -> void:
    if node is Container:
        node.notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child in node.get_children():
        _sort(child)
    if node is Control:
        (node as Control).update_minimum_size()


## The first Container under *node*, which is the one whose minimum is the
## whole window's.
func _outermost_container(node: Node) -> Container:
    if node == null:
        return null
    for child in node.get_children():
        if child is Container:
            return child as Container
        var found := _outermost_container(child)
        if found != null:
            return found
    return null
