## A stroke that lands near an active selection brings no
## notice.
##
## A reasonable area is kept clear of the notice: "make some reasonable area
## around selection where there is no notice. It could be annoying." These read
## the margin on a bare document: a stroke wholly outside the selection but
## within the margin says nothing and leaves the reminder armed, one past it
## brings the notice once, and one canvas distance falls inside the margin at a
## low zoom and outside it at a high one.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The selection every case draws, its left edge at 400.
const SQUARE := Rect2i(400, 100, 60, 60)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _doc: SaDocument = null
var _heard: Array[String] = []


## Four by two chunks, room for a stroke near the square and one far from it.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(1024, 512))
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


func test_a_stroke_within_the_margin_says_nothing_and_one_past_it_tells_once() -> void:
    var brush := _brush()
    _doc.selection.select_rect(SQUARE)
    var near := SaSelectionReminder.margin(1.0, brush.get_cursor_radius() * 2.0)
    var least := SaSelectionReminder.NEAR_ON_SCREEN
    assert_true(near >= least, "At zoom 1 the margin is at least %d pixels: %.1f" % [least, near])
    _stroke(brush, Vector2(SQUARE.position.x - 40, 130))
    var outside := TranslationServer.translate(SaStrokeNote.OUTSIDE_SELECTION)
    assert_eq(SaStrokeNote._said, outside, "The stroke 40 pixels left of the square fell wholly outside it")
    assert_eq(_heard.size(), 0, "and, inside the margin, brings no notice")
    _stroke(brush, Vector2(130, 400))
    assert_eq(_heard.size(), 1, "A stroke far from the square still brings the notice, the near one left it armed")
    _stroke(brush, Vector2(900, 400))
    assert_eq(_heard.size(), 1, "and a second far one brings no second notice")


func test_one_canvas_distance_is_near_at_a_low_zoom_and_far_at_a_high_one() -> void:
    var brush := _brush()
    _doc.selection.select_rect(SQUARE)
    # A one dab region whose right edge lies 120 document pixels left of the
    # square. At zoom 0.5 the margin is 192 pixels, at zoom 4 it is 24 or the
    # brush's diameter, whichever is larger.
    var dab := Rect2i(SQUARE.position.x - 120 - 16, 120, 16, 16)
    var diameter := brush.get_cursor_radius() * 2.0
    assert_true(diameter < 120.0, "The brush is narrower than the gap: %.1f" % diameter)
    _view().zoom = 0.5
    _commit(dab, brush)
    assert_eq(_heard.size(), 0, "At zoom 0.5 the 120 pixel gap is inside the margin")
    _view().zoom = 4.0
    _commit(dab, brush)
    assert_eq(_heard.size(), 1, "and at zoom 4 the same gap is outside it")


func test_the_margin_is_the_larger_of_the_screen_distance_and_the_brush() -> void:
    assert_almost_eq(SaSelectionReminder.margin(1.0, 10.0), 96.0, 0.001, "96 screen pixels at zoom 1")
    assert_almost_eq(SaSelectionReminder.margin(2.0, 10.0), 48.0, 0.001, "half as many document pixels at zoom 2")
    assert_almost_eq(SaSelectionReminder.margin(2.0, 300.0), 300.0, 0.001, "and a broad brush's diameter where it is larger")


func test_the_gap_is_measured_between_the_two_rectangles() -> void:
    assert_almost_eq(SaSelectionReminder.distance(Rect2i(0, 0, 10, 10), Rect2i(20, 0, 10, 10)), 10.0, 0.001, "Side by side")
    var corner := SaSelectionReminder.distance(Rect2i(0, 0, 10, 10), Rect2i(13, 14, 10, 10))
    assert_almost_eq(corner, 5.0, 0.001, "corner to corner")
    assert_almost_eq(SaSelectionReminder.distance(Rect2i(0, 0, 10, 10), Rect2i(5, 5, 10, 10)), 0.0, 0.001, "overlapping")
    var nothing := SaSelectionReminder.distance(Rect2i(), Rect2i(5, 5, 10, 10))
    assert_eq(nothing, INF, "and a stroke that painted nothing is never near")


## The machine's brush, hard and opaque.
func _brush() -> ToolState:
    _machine.set_active_tool(&"brush")
    var brush := _machine.active_tool
    brush.set(&"eraser_toggled", false)
    return brush


func _view() -> Fixtures.FakeView:
    return _surface.view as Fixtures.FakeView


## One press and one release at *at*, which is one dab and one stroke.
func _stroke(brush: ToolState, at: Vector2) -> void:
    _view().mouse_position = at
    brush.handle_input(_button(true))
    brush.handle_input(_button(false))


## A stroke whose one dab covered *dab* in document pixels, committed by *tool*
## through the note, so the margin is read from the fake view's zoom.
func _commit(dab: Rect2i, tool: ToolState) -> void:
    _doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    var grid := Vector2i((Vector2(dab.position) / SaLayer.CHUNK_SIZE).floor())
    _doc.stroke_transaction.note_region(grid, Rect2i(dab.position - grid * SaLayer.CHUNK_SIZE, dab.size))
    SaStrokeNote.commit(_doc, false, tool)


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
