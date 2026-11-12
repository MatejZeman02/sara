## A stroke laid wholly outside an active selection tells the
## painter a selection is on.
##
## The maintainers ruled on 2026-10-17 that an empty selection paints everywhere, and
## that a painter whose stroke does nothing because of a selection they forgot
## should be told. These read the rule on a bare document: one notice per
## selection, none for a stroke that lands inside, a new selection arming it
## again, and none at all with nothing selected.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _heard: Array[String] = []


## Two by two chunks, room for a selection and a stroke well clear of it.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _doc = _surface.get_document()
    _heard.clear()
    SaStrokeNote.say("")
    EventBus.corner_notice.connect(_hear)


func after_each() -> void:
    EventBus.corner_notice.disconnect(_hear)
    SaStrokeNote.say("")
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _doc = null


func _hear(line: String) -> void:
    _heard.append(line)


func test_a_stroke_outside_tells_once_per_selection() -> void:
    var brush := _brush()
    _doc.selection.select_rect(Rect2i(400, 400, 60, 60))
    _stroke(brush, Vector2(100, 100))
    assert_eq(_heard.size(), 1, "A stroke wholly outside the selection is told about")
    assert_eq(_heard[0], SaSelectionReminder.line(), "with the reminder's line")
    _stroke(brush, Vector2(140, 120))
    assert_eq(_heard.size(), 1, "A second stroke outside the same selection says nothing more")
    _stroke(brush, Vector2(430, 430))
    assert_eq(_heard.size(), 1, "A stroke inside says nothing")
    _stroke(brush, Vector2(100, 140))
    assert_eq(_heard.size(), 1, "and does not arm it again")
    _doc.selection.select_rect(Rect2i(380, 60, 80, 80))
    _stroke(brush, Vector2(100, 400))
    assert_eq(_heard.size(), 2, "A new selection arms the reminder again")


func test_a_changed_selection_arms_it_again() -> void:
    var brush := _brush()
    _doc.selection.select_rect(Rect2i(400, 400, 60, 60))
    _stroke(brush, Vector2(100, 100))
    _doc.selection.select_rect(Rect2i(300, 300, 40, 40), SaSelection.Mode.ADD)
    _stroke(brush, Vector2(100, 100))
    assert_eq(_heard.size(), 2, "A selection added to is a changed one, and arms it")


func test_an_eraser_counts_as_a_stroke() -> void:
    var brush := _brush()
    brush.set(&"eraser_toggled", true)
    _doc.selection.select_rect(Rect2i(400, 400, 60, 60))
    _stroke(brush, Vector2(100, 100))
    assert_eq(_heard.size(), 1, "An erase stroke outside the selection is told about too")


func test_an_empty_selection_tells_nothing() -> void:
    var brush := _brush()
    assert_false(_doc.selection.active, "Nothing is selected")
    _stroke(brush, Vector2(100, 100))
    _stroke(brush, Vector2(300, 300))
    assert_eq(_heard.size(), 0, "and a stroke anywhere says nothing")


func test_the_line_names_select_none_and_its_key() -> void:
    var chords := SaShortcutStore.chords_for(SaSelectionReminder.SELECT_NONE)
    var line := SaSelectionReminder.line()
    assert_true(line.contains("Select None"), "The line names Select None: %s" % line)
    if not chords.is_empty():
        assert_true(line.contains(chords[0]), "and the key the store holds for it: %s" % line)


## The machine's brush, hard and opaque.
func _brush() -> ToolState:
    _machine.set_active_tool(&"brush")
    var brush := _machine.active_tool
    brush.set(&"eraser_toggled", false)
    return brush


## One press and one release at *at*, which is one dab and one stroke.
func _stroke(brush: ToolState, at: Vector2) -> void:
    (_surface.view as Fixtures.FakeView).mouse_position = at
    brush.handle_input(_button(true))
    brush.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
