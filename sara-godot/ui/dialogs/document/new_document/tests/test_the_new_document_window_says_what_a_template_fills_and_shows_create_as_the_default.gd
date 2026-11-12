## The New Document window says what a template fills and shows Create as the
## default.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter did not know that picking a Template fills every
## row below it, and Cancel and Create looked alike, so the action Enter takes
## was not clear. The window is opened embedded, so no OS window maps, the way
## `test_enter_presses_the_button_the_outline_is_on.gd` opens its dialogs, and
## Enter goes in through `push_input` as a keyboard sends it.
extends "res://tests/test_framework.gd"

## The dialog builds a colour space browser, which draws a gamut.
const REQUIRES_GPU := true

## The words under the Template row's title.
const HINT := "Fills every row below it."

var _host: Node = null
var _kept_embedding: bool = true
var _kept_last: String = ""
var _requested: Array = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _kept_last = SaSettings.last_template
    _host = Node.new()
    _host.name = "TemplateHintTestHost"
    EventBus.add_child(_host)
    _requested = []


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    SaSettings.last_template = _kept_last
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


func _opened() -> NewDocumentDialog:
    var dialog := NewDocumentDialog.new()
    _host.add_child(dialog)
    dialog.show()
    return dialog


## Every label drawn on *line*, its title and its hint among them.
static func _label_texts(line: Node) -> Array[String]:
    var out: Array[String] = []
    for child: Node in line.find_children("*", "Label", true, false):
        out.append((child as Label).text)
    return out


## One edge of Enter, spelled with both keycode fields as a keyboard sends it.
static func _enter(pressed: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ENTER
    key.physical_keycode = KEY_ENTER
    key.pressed = pressed
    return key


func _on_requested(size: Vector2i, _space: SaColorSpace, _dpi: float, _background: Dictionary) -> void:
    _requested.append(size)


func test_the_template_row_says_it_fills_the_rows_below() -> void:
    var dialog := _opened()
    var row := dialog.page.row(&"template")
    assert_eq(row.explanation, HINT, "The Template row carries the hint")
    var texts := _label_texts(row.line)
    assert_true(texts.has(HINT), "and draws it on its own line, under the title: %s" % [texts])
    assert_true(texts.find(HINT) > texts.find("Template"), "after the title rather than before it")
    assert_true(row.line.is_visible_in_tree(), "and the line is shown with the details closed")


func test_create_is_drawn_in_the_accent_and_cancel_plainly() -> void:
    var dialog := _opened()
    var create := dialog.find_child("CreateButton", true, false) as Button
    var cancel := dialog.find_child("CancelButton", true, false) as Button
    assert_true(create != null and cancel != null, "Both buttons are there")
    var accent := SaTheme.make_toggle_style("pressed").bg_color
    for state: String in NewDocumentDialog.DEFAULT_STATES:
        var box := create.get_theme_stylebox(state) as StyleBoxFlat
        assert_true(box != null, "Create has a box for %s" % state)
        assert_eq(box.bg_color, accent, "and it is the accent, the toggle's on box, in %s" % state)
    var plain := cancel.get_theme_stylebox("normal")
    assert_false(cancel.has_theme_stylebox_override("normal"), "Cancel keeps the plain button's box")
    var plain_colour: Variant = null
    if plain is StyleBoxFlat:
        plain_colour = (plain as StyleBoxFlat).bg_color
    assert_true(plain_colour != accent, "which is not the accent, so the two read apart")
    assert_eq(dialog.default_button, create, "and Create is the button Enter takes")


func test_enter_creates_the_document() -> void:
    var dialog := _opened()
    dialog.document_requested.connect(_on_requested)
    dialog.gui_release_focus()
    dialog.push_input(_enter(true))
    dialog.push_input(_enter(false))
    assert_eq(_requested.size(), 1, "Enter asks for one document")
    if _requested.size() == 1:
        assert_eq(_requested[0], dialog.selected_size(), "the size the window shows")
    assert_false(dialog.visible, "and the window closes, as a press of Create does")
