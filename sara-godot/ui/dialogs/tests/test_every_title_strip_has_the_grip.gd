## Every dialog's title strip begins with the grip, whatever retitled it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "The grip" is not the text "::  " written before the words, but the six dots
## `SaGrip` draws over the left of the title label, which holds the words alone.
## This suite
## finds the grip on every dialog, before and after its retitle, finds no
## source under `ui` writing the old text, and finds the grip draws no text.
##
## Three title strips once lost the "::" that every other strip carries.
## `SaDialogWindow` writes
## it when it builds the strip, and Feather and Border (`configure`) and Colour
## Range (`retitle`) wrote the bare title over it when they were opened.
##
## Preferences keeps the grip it was built with and keeps its minimise and
## maximise on purpose, which is held below. The walk finds the dialogs the way
## `test_every_dialog_opens_inside_the_window_at_every_size_and_scale` does, so
## a dialog added tomorrow is held to the same rule, and a second walk over the
## sources catches a title strip written to by a method this suite does not
## call. The running app is
## `scenarios/every-dialogs-title-strip-has-the-grip-and-the-same-buttons.json`.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Where the dialog classes live, walked whole.
const UI_DIR := "res://ui"

## How few dialog classes the walk may find before it is the walk that broke,
## the number the sibling suite keeps.
const FLOOR := 17

## The text the grip once was, which no title may carry and no source write.
const OLD_GRIP := "::"

var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A dialog that joins the tree visible would map a real OS window and block
    # the run, so the root embeds.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N105TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _kept_embedding


## Every dialog as it is built, and again after the call that retitles it where
## it has one.
func test_every_dialog_title_strip_begins_with_the_grip() -> void:
    var paths := _dialog_scripts()
    assert_true(paths.size() >= FLOOR, "Found %d dialog classes under %s" % [paths.size(), UI_DIR])
    for path: String in paths:
        var window := _built(path)
        if window == null:
            assert_true(false, "%s could not be built" % path.get_file())
            continue
        assert_true(_has_grip(window), "%s is built with the grip before '%s'" % [path.get_file(), _strip(window)])
        assert_false(_strip(window).contains(OLD_GRIP), "%s holds no colons in '%s'" % [path.get_file(), _strip(window)])
        if window.has_method("retitle"):
            window.call("retitle", "Another title")
            assert_eq(_strip(window), "Another title", "%s writes the words alone when retitled" % path.get_file())
            assert_true(_has_grip(window), "%s keeps the grip when retitled" % path.get_file())


## Feather and Border are one dialog retitled for each, and it is `configure`
## that writes the word.
func test_feather_and_border_keep_the_grip_when_the_menu_opens_them() -> void:
    var dialog := SaRadiusDialog.new()
    _host.add_child(dialog)
    for word: String in ["Feather", "Border", "Feather"]:
        dialog.configure(word, 5)
        assert_eq(_strip(dialog), word, "%s opens with its word alone" % word)
        assert_true(_has_grip(dialog), "and the grip before it")


## Colour Range is retitled for a selection and for a filter's mask by `open`.
func test_colour_range_keeps_the_grip_for_the_selection_and_for_the_mask() -> void:
    var dialog := SaColorRangeDialog.new()
    _host.add_child(dialog)
    dialog.retitle(tr("Colour Range"))
    assert_eq(_strip(dialog), "Colour Range", "the selection's strip")
    assert_true(_has_grip(dialog), "keeps its grip")
    dialog.retitle(tr("Mask from Colour Range"))
    assert_eq(_strip(dialog), "Mask from Colour Range", "the mask's strip")
    assert_true(_has_grip(dialog), "and again")


## Preferences carries the grip and the two buttons its frame shows beside Close,
## and a question like Radius shows the close alone. The maximise every dialog
## builds is hidden there, and only the Brush Editor shows it as well.
func test_preferences_keeps_its_grip_and_its_two_buttons() -> void:
    var window := SaSettingsWindow.new()
    _host.add_child(window)
    assert_eq(_strip(window), "Preferences", "Preferences is built with its word alone")
    assert_true(_has_grip(window), "and the grip before it")
    var row := window.drag_handle.find_child("Row", true, false) as Control
    var buttons: PackedStringArray = []
    for child: Node in row.get_children():
        if child is Button:
            buttons.append(child.name)
    assert_eq(buttons.size(), 3, "its strip holds the minimise, the maximise and the close: %s" % ", ".join(buttons))
    assert_true(buttons.has("CloseButton"), "and the close is one of them")
    var other := SaRadiusDialog.new()
    _host.add_child(other)
    var other_row := other.drag_handle.find_child("Row", true, false) as Control
    var other_buttons := 0
    for child: Node in other_row.get_children():
        if child is Button and (child as Button).visible:
            other_buttons += 1
    assert_eq(other_buttons, 1, "where another dialog's strip holds the close alone")


## No source under `ui` writes the old grip as text: a title strip is the words
## alone, and the dots are `SaGrip`'s. The sources that write a strip name the
## label `TitleLabel`, and each of them is held to hand it no `"::  %s"`.
func test_no_source_writes_the_old_grip_as_text() -> void:
    var writers := 0
    var old_text := '"' + OLD_GRIP + '  %s"'
    for path: String in _all_scripts(UI_DIR):
        var text := FileAccess.get_file_as_string(path)
        if text.contains('"TitleLabel"'):
            writers += 1
        assert_false(text.contains(old_text), "%s writes %s" % [path, old_text])
    assert_true(writers >= 1, "The walk found %d scripts that write a title strip" % writers)


## The grip draws no text, so no font can turn it into a box: the class is a
## control rather than a label, its source calls no text drawing and names no
## U+283F, and its dots are drawn with the same call at both scales.
func test_the_grip_draws_no_text() -> void:
    var path := "res://ui/widgets/grip/sa_grip.gd"
    var text := FileAccess.get_file_as_string(path)
    assert_false(text.is_empty(), "the grip's source is found")
    for needle: String in ["draw_string", "draw_multiline_string", "draw_char", "TextServer"]:
        assert_false(text.contains(needle), "the grip's source calls no %s" % needle)
    assert_false(text.contains(String.chr(0x283F)), "and holds no braille dot glyph")
    var grip := SaGrip.new()
    assert_eq(grip.get_class(), "Control", "it is a plain control, not a label")
    assert_false("text" in grip, "and has no text property")
    grip.free()
    # A label's text with the glyph in it would be the font's to draw.
    for window_path: String in _dialog_scripts():
        var window := _built(window_path)
        if window != null:
            assert_false(_strip(window).contains(String.chr(0x283F)), "%s writes no braille glyph" % window_path.get_file())


## Six dots, each as large as `SaUI` says, in a palette key that exists.
func test_the_grip_is_six_dots_sized_by_the_ui_and_coloured_from_the_palette() -> void:
    assert_eq(SaGrip.COLUMNS * SaGrip.ROWS, 6, "two columns of three rows")
    assert_eq(SaGrip.dots_width(), SaUI.px(SaGrip.PITCH) + SaUI.px(SaGrip.DOT), "its width follows the interface units")
    assert_eq(SaGrip.dots_height(), 2 * SaUI.px(SaGrip.PITCH) + SaUI.px(SaGrip.DOT), "and its height")
    assert_true(SaTheme.palette.get(SaGrip.COLOR_KEY) is Color, "its colour is a palette key")
    var kept := SaTheme.palette.text_primary
    SaTheme.palette.text_primary = Color.RED
    assert_eq(SaGrip.color(), Color.RED, "a palette that changes recolours it")
    SaTheme.palette.text_primary = kept


func _built(path: String) -> SaDialogWindow:
    var script := load(path) as GDScript
    if script == null or not script.can_instantiate():
        return null
    var window := script.new() as SaDialogWindow
    if window == null:
        return null
    _host.add_child(window)
    return window


## Whether the strip's title label has the grip laid over it.
func _has_grip(window: SaDialogWindow) -> bool:
    if window.drag_handle == null:
        return false
    var label := window.drag_handle.find_child("TitleLabel", true, false) as Label
    return label != null and label.get_node_or_null(SaGrip.NODE_NAME) is SaGrip


## The text of the title strip's label, or "" for a window that has none.
func _strip(window: SaDialogWindow) -> String:
    if window.drag_handle == null:
        return ""
    var label := window.drag_handle.find_child("TitleLabel", true, false) as Label
    return label.text if label != null else ""


## Every script under `res://ui/` that says it extends the dialog window, but a
## suite, the walk the sibling suite makes.
func _dialog_scripts() -> Array[String]:
    var paths: Array[String] = []
    for path: String in _all_scripts(UI_DIR):
        if _extends_dialog_window(path):
            paths.append(path)
    paths.sort()
    return paths


## Every script under *dir_path*, but those in a `tests` folder.
func _all_scripts(dir_path: String) -> Array[String]:
    var found: Array[String] = []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return found
    for entry: String in dir.get_files():
        if entry.ends_with(".gd"):
            found.append(dir_path.path_join(entry))
    for sub: String in dir.get_directories():
        if sub != "tests":
            found.append_array(_all_scripts(dir_path.path_join(sub)))
    return found


func _extends_dialog_window(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    for line: String in file.get_as_text().split("\n"):
        var text := line.strip_edges()
        if text.begins_with("extends SaDialogWindow") or text.begins_with('extends "res://ui/dialogs/sa_dialog_window.gd"'):
            return true
        if text.begins_with("func ") or text.begins_with("var ") or text.begins_with("const "):
            return false
    return false
