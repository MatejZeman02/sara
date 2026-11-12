## Alt+F empties the search field that has the keyboard, as it does in Blender,
## and the list the field filters shows everything again.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The kinds of field are the ones a suite can build alone: Preferences' search,
## the choice lists' field and the Filters browser's. The search window's, the
## presets chooser's and the Keyboard page's are marked at the same line as
## their clear button, which the last test reads from the source so a new field
## cannot skip the mark.
extends "res://tests/test_framework.gd"

var _made: Array[Node] = []


func after_each() -> void:
    for node: Node in _made:
        if is_instance_valid(node):
            node.free()
    _made.clear()


static func _alt_f(alt: bool = true, pressed: bool = true) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_F
    key.physical_keycode = KEY_F
    key.alt_pressed = alt
    key.pressed = pressed
    return key


## Types *text* as a hand does, so the field announces it.
static func _type(field: LineEdit, text: String) -> void:
    field.text = text
    field.text_changed.emit(text)


func _page_of(category: String) -> Control:
    var page := VBoxContainer.new()
    SaSettingsRows.row(page, category, "", Control.new())
    return page


func test_alt_f_in_preferences_search_leaves_it_empty_and_every_page_shown() -> void:
    var scroll := ScrollContainer.new()
    _made.append(scroll)
    var titles := ["Canvas", "Keyboard", "Language"]
    var search := SaSettingsSearch.new(titles, scroll, _page_of)
    _made.append(search.field)
    _type(search.field, "keyb")
    assert_eq(search._shown.size(), 1, "typing narrowed the pages")
    search.field.gui_input.emit(_alt_f())
    assert_eq(search.field.text, "", "Alt+F emptied the field")
    assert_eq(search._shown.size(), titles.size(), "and every page is shown again")


func test_alt_f_in_a_choice_list_s_field_leaves_it_empty_and_announces_the_change() -> void:
    var column := VBoxContainer.new()
    _made.append(column)
    var field := SaChoiceSearch.new(column)
    _made.append(field)
    var heard: Array[String] = []
    field.text_changed.connect(func(text: String) -> void: heard.append(text))
    _type(field, "mul")
    field.gui_input.emit(_alt_f())
    assert_eq(field.text, "", "Alt+F emptied the field")
    assert_eq(heard, ["mul", ""], "and the listener the filtering hangs on heard the empty text")


func test_alt_f_in_the_filter_browser_s_field_leaves_it_empty_and_refreshes() -> void:
    var browser := SaFilterBrowser.new()
    _made.append(browser)
    var heard: Array[String] = []
    browser.search.text_changed.connect(func(text: String) -> void: heard.append(text))
    _type(browser.search, "blur")
    browser.search.gui_input.emit(_alt_f())
    assert_eq(browser.search.text, "", "Alt+F emptied the field")
    assert_eq(heard, ["blur", ""], "and the browser's own listener was told")


func test_only_alt_f_on_a_marked_field_clears_it() -> void:
    var marked := SaSearchField.mark(LineEdit.new())
    var plain := LineEdit.new()
    _made.append(marked)
    _made.append(plain)
    _type(marked, "word")
    marked.gui_input.emit(_alt_f(false))
    assert_eq(marked.text, "word", "F with no Alt types, it does not clear")
    marked.gui_input.emit(_alt_f(true, false))
    assert_eq(marked.text, "word", "the release of the key clears nothing")
    marked.gui_input.emit(_alt_f())
    assert_eq(marked.text, "", "the press does")
    assert_true(SaSearchField.keeps(marked, _alt_f()), "and the shortcut router leaves the key to the field")
    assert_true(ShortcutRouter.text_field_keeps(marked, _alt_f()), "through its own question about a text box")
    assert_false(SaSearchField.keeps(plain, _alt_f()), "a field that is not a search keeps nothing")


func test_every_search_field_with_a_clear_button_is_marked() -> void:
    var unmarked: Array[String] = []
    for path: String in _scripts("res://ui"):
        var source := FileAccess.get_file_as_string(path)
        if source.contains("clear_button_enabled = true") and not source.contains("SaSearchField.mark("):
            unmarked.append(path)
    assert_eq(unmarked, [], "a field with a clear button filters a list and takes Alt+F")


static func _scripts(dir: String) -> Array[String]:
    var out: Array[String] = []
    for file: String in DirAccess.get_files_at(dir):
        if file.ends_with(".gd"):
            out.append(dir.path_join(file))
    for sub: String in DirAccess.get_directories_at(dir):
        if sub != "tests":
            out.append_array(_scripts(dir.path_join(sub)))
    return out
