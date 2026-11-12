## The pop-up palette's picker takes the shape the Colour Picker docker shows,
## so the two stay in sync, where the docker on the OKHSL disc and the palette
## on the OKHSV wheel beside it would disagree.
##
## The ring is built bare under the app's theme, as the slot suites build it,
## and its picker is read for each of the seven shapes, set before the ring is
## built and again on a ring already built. The two shapes with a bar are laid
## out at the palette's smallest and default sizes, and the frame, the area and
## the bar are measured against every cell and the name line. Those
## rings stand in a viewport in the tree for the measuring, as the colour
## docker's suite stands its column, because the picker's own column follows
## its anchors only there, and a ring out of it reads the frame at its least
## size. The setting is put back after each test. The running app's proof is a
## scenario.
extends "res://tests/test_framework.gd"

## The ring's rectangle in the docker at its default 360 by 384, as
## `test_the_palettes_slots_show_each_name` reads it off the running app.
const RING_AT_DEFAULT := Vector2(360, 331)

## The ring's rectangle in the docker at its least size of 240 by 260, less
## the same 53 the drag bar, the column's gap and the foot take.
const RING_AT_SMALLEST := Vector2(240, 207)

var _shape_before: String = ""
var _kept_theme: Theme = null
var _kept_font_scale: float = 1.0


func before_each() -> void:
    _shape_before = SaSettings.color_picker_shape
    _kept_theme = SaUI.shared_theme
    _kept_font_scale = SaUI.user_font_scale
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)


func after_each() -> void:
    SaSettings.color_picker_shape = _shape_before
    SaUI.shared_theme = _kept_theme
    SaUI.user_font_scale = _kept_font_scale


func _ring(at_size: Vector2, in_tree: bool = false) -> PaletteSlotRing:
    var ring := PaletteSlotRing.new(Callable(), func() -> String: return "")
    ring.theme = SaUI.shared_theme
    if in_tree:
        var viewport := SubViewport.new()
        viewport.size = Vector2i(at_size)
        EventBus.add_child(viewport)
        viewport.add_child(ring)
    ring.size = at_size
    ring.lay_out()
    return ring


## *control*'s rectangle in the ring's space, summed up its parents, since a
## ring in no tree has no global transform to ask.
static func _in_ring(control: Control, ring: Control) -> Rect2:
    var at := Vector2.ZERO
    var node: Node = control
    while node != ring and node is Control:
        at += (node as Control).position
        node = node.get_parent()
    return Rect2(at, control.size)


func test_a_ring_built_after_the_setting_takes_its_shape() -> void:
    for key: String in SaPickerShape.KIND_KEYS:
        SaSettings.color_picker_shape = key
        var ring := _ring(RING_AT_DEFAULT)
        assert_eq(ring.wheel.kind, SaPickerShape.kind_of(key), "a ring built under %s shows it" % key)
        assert_eq(ring.wheel.kind_key(), key, "and names it %s" % key)
        ring.free()


func test_a_ring_already_built_follows_the_setting() -> void:
    SaSettings.color_picker_shape = "wheel"
    var ring := _ring(RING_AT_DEFAULT)
    var keys: Array[String] = SaPickerShape.KIND_KEYS.duplicate()
    keys.reverse()
    for key in keys:
        SaSettings.color_picker_shape = key
        assert_eq(ring.wheel.kind_key(), key, "the built ring turned to %s" % key)
    ring.free()


## The colour docker and the palette read one setting, so the docker's own
## picker and the ring agree on a change written the way its menu writes it.
func test_the_docker_s_step_moves_the_ring_too() -> void:
    SaSettings.color_picker_shape = "wheel"
    var ring := _ring(RING_AT_DEFAULT)
    for i in SaPickerShape.KIND_KEYS.size():
        var landed := SaColorPicker.step_shape_kind(1)
        assert_eq(ring.wheel.kind_key(), landed, "the ring followed the docker's step to %s" % landed)
    ring.free()


func test_a_shape_with_a_bar_stays_clear_of_every_slot() -> void:
    for key: String in ["okhsl", "hsl_square"]:
        for at_size: Vector2 in [RING_AT_SMALLEST, RING_AT_DEFAULT]:
            SaSettings.color_picker_shape = key
            var ring := _ring(at_size, true)
            var bar: Control = ring.wheel.lightness_bar if key == "okhsl" else ring.wheel.hue_bar
            assert_true(bar.visible, "%s shows its bar" % key)
            var parts := {
                "frame": _in_ring(ring.wheel.frame, ring),
                "area": _in_ring(ring.wheel.area_rect, ring),
                "bar": _in_ring(bar, ring),
            }
            var where := "%s at %s" % [key, at_size]
            var centre := at_size / 2.0
            for part: String in parts:
                var rect: Rect2 = parts[part]
                assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "%s: the %s has a size, %s" % [where, part, rect])
                assert_true(Rect2(Vector2.ZERO, at_size).encloses(rect), "%s: the %s is inside the ring" % [where, part])
                assert_true(rect.has_point(centre) or part == "bar", "%s: the %s holds the centre" % [where, part])
                for cell in ring.cells:
                    var cell_rect := Rect2(cell.position, cell.size)
                    var said := "%s: the %s %s clears %s %s" % [where, part, rect, cell.name, cell_rect]
                    assert_false(rect.intersects(cell_rect), said)
                var line_rect := Rect2(ring.name_line.position, ring.name_line.size)
                var strip := "%s: the %s clears the name line's strip %s" % [where, part, line_rect]
                assert_false(rect.intersects(line_rect), strip)
            ring.get_parent().free()


## The wheel with no bar keeps the side it always had, so the shapes drawn in
## a circle lose nothing to the two that are not.
func test_a_shape_with_no_bar_keeps_the_whole_centre() -> void:
    SaSettings.color_picker_shape = "wheel"
    var ring := _ring(RING_AT_DEFAULT)
    var wanted := minf(RING_AT_DEFAULT.x, RING_AT_DEFAULT.y) * PaletteSlotRing.WHEEL_SIDE
    assert_almost_eq(ring.wheel.size.x, wanted, 0.01, "the wheel's side")
    SaSettings.color_picker_shape = "okhsl"
    assert_true(ring.wheel.size.x < wanted, "the disc and its bar take less, %s" % ring.wheel.size.x)
    SaSettings.color_picker_shape = "triangle"
    assert_almost_eq(ring.wheel.size.x, wanted, 0.01, "and the triangle has it back")
    ring.free()


## A drag on the HSL square's hue bar counts as the ring, on its area as the
## square, and on the disc's lightness bar as a slider, as the colour docker
## counts them. The drags go in through each part's own input, so the suite
## writes nothing of the picker's.
func test_a_press_on_a_bar_counts_as_the_docker_counts_it() -> void:
    SaSettings.color_picker_shape = "hsl_square"
    var ring := _ring(RING_AT_DEFAULT, true)
    _drag(ring.wheel.hue_bar)
    assert_eq(ring._wheel_part, SaUsageTally.RING, "the hue bar is the ring")
    _drag(ring.wheel.frame)
    assert_eq(ring._wheel_part, SaUsageTally.SQUARE, "the area is the square")
    SaSettings.color_picker_shape = "okhsl"
    _drag(ring.wheel.lightness_bar)
    assert_eq(ring._wheel_part, SaUsageTally.SLIDER, "the disc's bar is a slider")
    ring.get_parent().free()


## A press, a motion and a release down the middle of *part*, handed to its
## own input as the viewport hands them.
static func _drag(part: Control) -> void:
    var from := part.size * Vector2(0.5, 0.3)
    var to := part.size * Vector2(0.5, 0.6)
    part.gui_input.emit(_button(from, true))
    var motion := InputEventMouseMotion.new()
    motion.position = to
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    part.gui_input.emit(motion)
    part.gui_input.emit(_button(to, false))


static func _button(at: Vector2, pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = at
    return event
