## The status line begins with the document's name as its tab reads it and the
## name of the tool in hand, and follows both, so a Liquify preset refused with the
## Bucket in hand by accident is explained by what the line says.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The runner is synchronous, so a change is followed by the reading it queued,
## taken by hand with `refresh()`. The running app with two documents and the
## Bucket is `scenarios/the-status-line-names-the-document-and-the-tool-in-hand.json`.
extends "res://tests/test_framework.gd"

## A real easel holds the document, and an easel needs a RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _host: Control = null
var _surface: SaSurface = null
var _other: SaSurface = null
var _front: SaSurface = null
var _machine: ToolMachine = null
var _line: SaStatusLine = null


func before_each() -> void:
    _host = Control.new()
    _host.name = "StatusLineNamesHost"
    _host.size = Vector2(1200.0, 40.0)
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _machine = Fixtures.make_bound_machine(_surface)
    _front = _surface
    _line = SaStatusLine.new(func() -> SaSurface: return _front)
    _host.add_child(_line)
    _line.refresh()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    Fixtures.teardown(_surface, _machine)
    if _other != null:
        Fixtures.teardown(_other)
    _surface = null
    _other = null
    _front = null
    _machine = null
    _line = null


func test_the_line_begins_with_the_document_and_the_tool() -> void:
    var words := _line.get_node("Words")
    assert_eq(words.get_child(0), _line.document_label, "The document's name is the first word")
    assert_eq(words.get_child(2), _line.tool_label, "and the tool's the second, after a separator")
    assert_eq(words.get_child(4), _line.zoom_label, "both before the zoom")
    assert_eq(_line.document_label.text, "Untitled", "A document never saved reads as its tab does")
    assert_eq(_line.tool_label.text, "Brush", "and the machine starts on the Brush")


func test_file_new_brings_its_untitled_document_onto_the_line() -> void:
    _surface.get_document().mark_saved("/probe/Portrait.sad")
    _line.refresh()
    assert_eq(_line.document_label.text, "Portrait.sad", "The saved document first")

    # File > New opens its document in a tab of its own, which comes in front.
    _other = Fixtures.make_surface(Vector2i(128, 128))
    _front = _other
    EventBus.active_document_changed.emit(_other)
    assert_true(_line._queued, "The new front queued a reading")
    _line.refresh()
    assert_eq(_line.document_label.text, "Untitled", "and the new document's name after File > New")


func test_a_save_under_a_new_name_and_its_star_are_read() -> void:
    var document := _surface.get_document()
    document.modified = true
    assert_true(_line._queued, "A change to the document queued a reading")
    _line.refresh()
    assert_eq(_line.document_label.text, "Untitled*", "An unsaved change carries the tab's star")

    document.mark_saved("/probe/Under a new name.sad")
    assert_true(_line._queued, "The save queued a reading")
    _line.refresh()
    assert_eq(_line.document_label.text, "Under a new name.sad", "The new name, with the star gone")


func test_a_switch_of_document_reads_the_one_in_front() -> void:
    _surface.get_document().mark_saved("/probe/First.sad")
    _other = Fixtures.make_surface(Vector2i(128, 128))
    _other.get_document().mark_saved("/probe/Second.sad")
    _line.refresh()
    assert_eq(_line.document_label.text, "First.sad", "The first document in front")

    _front = _other
    EventBus.active_document_changed.emit(_other)
    _line.refresh()
    assert_eq(_line.document_label.text, "Second.sad", "the second once it is in front")

    _surface.get_document().mark_saved("/probe/Renamed behind.sad")
    _line.refresh()
    assert_eq(_line.document_label.text, "Second.sad", "and a save of the one behind leaves the line alone")


func test_a_switch_of_tool_is_read() -> void:
    _machine.set_active_tool(&"bucket_fill")
    assert_true(_line._queued, "The machine's tool_changed queued a reading")
    _line.refresh()
    assert_eq(_line.tool_label.text, "Fill", "The Bucket reads as its toolbox button names it")
    assert_eq(_line.tool_label.tooltip_text, "Fill", "and its tooltip names it whole")


func test_a_quick_tool_shows_while_it_is_held() -> void:
    _machine.set_active_tool(&"brush")
    _key(KEY_SPACE, true)
    _machine._evaluate_tool()
    _line.refresh()
    assert_eq(_line.tool_label.text, "Pan", "A held Space shows the Pan")

    _key(KEY_SPACE, false)
    _machine._evaluate_tool()
    _line.refresh()
    assert_eq(_line.tool_label.text, "Brush", "and the Brush again once it is let go")


func test_a_name_of_200_characters_is_cut_and_whole_in_its_tooltip() -> void:
    var long_name := "A".repeat(196) + ".sad"
    assert_eq(long_name.length(), 200, "The name is 200 characters long")
    _surface.get_document().mark_saved("/probe/" + long_name)
    _line.refresh()

    var label := _line.document_label
    assert_eq(label.text, long_name, "The word holds the whole name")
    assert_eq(label.tooltip_text, long_name, "and so does its tooltip")
    assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "which the label cuts with an ellipsis")
    var whole := _width(label, long_name)
    assert_true(whole > _line.size.x, "200 characters are wider than the line")
    assert_true(label.custom_minimum_size.x < whole, "so the word is given less than the whole name")
    assert_true(label.custom_minimum_size.x > 0.0, "and still some of it")
    assert_eq(_line.tool_label.custom_minimum_size.x, _width(_line.tool_label, "Brush"), "The tool keeps its whole name")
    assert_true(_line.get_combined_minimum_size().x <= _line.size.x, "and the line stays inside the window")


func test_the_document_is_cut_before_the_tool() -> void:
    var shares := SaStatusLine.share_room(100.0, 300.0, 60.0, 10.0)
    assert_eq(shares, Vector2(40.0, 60.0), "The tool keeps its 60 and the document has the 40 left")
    shares = SaStatusLine.share_room(50.0, 300.0, 60.0, 10.0)
    assert_eq(shares, Vector2(10.0, 40.0), "With less room than the tool needs, the document keeps an ellipsis")
    shares = SaStatusLine.share_room(500.0, 300.0, 60.0, 10.0)
    assert_eq(shares, Vector2(300.0, 60.0), "and with room for both, both are whole")


func _width(label: Label, text: String) -> float:
    var font := label.get_theme_font("font")
    return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x


func _key(keycode: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    _machine._update_held_keys(event)
