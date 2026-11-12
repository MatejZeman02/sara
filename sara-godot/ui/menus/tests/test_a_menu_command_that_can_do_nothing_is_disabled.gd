## A menu row whose command can do
## nothing now is dimmed. Undo and Redo ask the document's history, Feather,
## Border, Deselect and Crop to Selection ask for a selection, and each row is
## read again when its menu opens, so a step taken a moment ago shows.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice, for the document the menus act on.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## Each menu's rows under test, label -> item id.
const ROWS := {
    "Edit": {"Undo": SaEditMenu.ID_UNDO, "Redo": SaEditMenu.ID_REDO},
    "Select": {"Deselect": SaSelectMenu.ID_NONE, "Feather": SaSelectMenu.ID_FEATHER, "Border": SaSelectMenu.ID_BORDER},
    "Image": {"Crop to Selection": SaImageMenu.ID_CROP_TO_SELECTION},
}


## A bar bound to every command a menu lists, the shortcut table's among them
## acting on *surface*'s document, the way main binds it. The canvas is held
## for the caller to free, and the shortcut table is held as the router holds
## it, because a command's handler and its check are bound to that object and a
## callable does not keep its object alive.
func _bar(surface: SaSurface) -> Array:
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel
    var registries := Fixtures.make_registries(surface)
    SaAppCommands.register_all(registries, func(_docker_id: StringName) -> void: pass)
    var table := SaShortcutCommands.new(Callable(), func() -> SaCanvas: return canvas, Callable(), null)
    table.register_into(registries.commands)
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    return [bar, canvas, registries, table]


## The rows of every menu in *labels* that are not *dimmed*, each menu opened
## afresh first the way a press on its title opens it.
func _rows_not(bar: TopMenuBar, labels: Array, dimmed: bool) -> Array:
    var wrong := []
    for menu_name: String in ROWS:
        var menu := bar.menu(menu_name)
        menu.populate()
        for label: String in ROWS[menu_name]:
            if label in labels and menu.popup.is_disabled(SaMenu.key(ROWS[menu_name][label])) != dimmed:
                wrong.append(label)
    return wrong


func _free(held: Array, surface: SaSurface) -> void:
    held[0].free()
    held[1].free()
    Fixtures.teardown(surface)


func test_a_new_document_dims_the_six_rows_and_a_step_and_a_selection_light_them() -> void:
    var surface := Fixtures.make_surface()
    var doc := surface.easel.document
    var held := _bar(surface)
    var bar: TopMenuBar = held[0]
    var registries: SaRegistries = held[2]
    var all := ["Undo", "Redo", "Deselect", "Feather", "Border", "Crop to Selection"]
    assert_false(doc.undo_redo.has_undo(), "a new document has no history")
    assert_false(doc.selection.active, "and no selection")
    assert_eq(_rows_not(bar, all, true), [], "every row dimmed on a new document")
    assert_true(registries.commands.execute(&"layer_new_paint"), "a new layer is a step")
    assert_true(doc.undo_redo.has_undo(), "and the history holds it")
    assert_eq(_rows_not(bar, ["Undo"], false), [], "Undo lit once there is a step")
    assert_eq(_rows_not(bar, ["Redo"], true), [], "Redo still dimmed, nothing was undone")
    assert_true(doc.undo(), "the step goes back")
    assert_eq(_rows_not(bar, ["Redo"], false), [], "Redo lit once a step was undone")
    doc.selection.select_rect(Rect2i(16, 16, 64, 64))
    assert_true(doc.selection.active, "a rectangle is a selection")
    assert_eq(
        _rows_not(bar, ["Deselect", "Feather", "Border", "Crop to Selection"], false),
        [],
        "the selection rows lit once there is one"
    )
    doc.selection.deselect()
    assert_eq(_rows_not(bar, ["Deselect", "Feather", "Border", "Crop to Selection"], true), [], "and dimmed once it is gone")
    _free(held, surface)


func test_a_dimmed_row_takes_no_press() -> void:
    var surface := Fixtures.make_surface()
    var held := _bar(surface)
    var bar: TopMenuBar = held[0]
    var menu := bar.menu("Image")
    menu.populate()
    var size_before := surface.easel.document.canvas_size
    assert_false(menu.popup.press_row(SaMenu.key(SaImageMenu.ID_CROP_TO_SELECTION)), "Crop to Selection refuses a press")
    assert_eq(surface.easel.document.canvas_size, size_before, "and the canvas is its size still")
    _free(held, surface)


## A shortcut table with no canvas behind it dims the rows rather than
## lighting a press that fails.
func test_no_document_dims_the_rows() -> void:
    var registries := Fixtures.make_registries()
    var table := SaShortcutCommands.new(Callable(), Callable(), Callable(), null)
    table.register_into(registries.commands)
    var bar := TopMenuBar.new()
    bar._ready()
    bar.bind_commands(registries.commands)
    assert_eq(_rows_not(bar, ["Undo", "Redo", "Feather", "Border"], true), [], "nothing to act on, nothing lit")
    bar.free()
