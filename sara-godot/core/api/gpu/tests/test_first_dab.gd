## The first stroke of a run paints.
##
## `StateBrush` opens a tablet stroke at the pressure a hover last reported, and
## fell back to 0.0 when none had. The first press of a process is exactly that
## case, `_analyze_pointer_type` learning a pressure only from a motion, so the
## press dab was a full-size dab at zero alpha: the history count went up and
## the canvas did not change. Every press after it read 1.0 off the stroke
## before it, which is why only the first one was lost and why a long stroke hid
## it, losing the first of twenty dabs being invisible.
##
## Measured on the running app before the fix: three two-pixel strokes, and
## the picture held one
## dab where the scenario asked for two. The instrumented run read
## `press raw_pressure=0.000` on the first and `1.000` on the two after it.
extends "res://tests/test_framework.gd"

## The proof is a texel, so this needs a real RenderingDevice.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


## One left press, which is the dab, and the release, which commits it. Kept
## apart because `reset()` on the release clears `last_pressure`, so the pressure
## the press chose can only be read between the two.
func _press(brush: Object) -> void:
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)


func _release(brush: Object) -> void:
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    brush.handle_input(release)


## The first texel of the active layer's first chunk, straight off the GPU, the
## way `core/api/document/tests/test_fill_commands.gd` reads one.
func _read_origin_texel(doc: SaDocument) -> Color:
    var chunk: SaTexture = doc.active_layer.get_or_create_field(Vector2i.ZERO)
    var data: PackedByteArray = GlobalShaderCompiler.get_rd().texture_get_data(chunk.rid, 0)
    if data.size() < 16:
        return Color(0, 0, 0, 0)
    return Color(data.decode_float(0), data.decode_float(4), data.decode_float(8), data.decode_float(12))


## The regression, and it is one dab into a document nothing has touched.
func test_the_first_dab_of_a_fresh_brush_lands() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool
    assert_not_null(brush, "The brush is one of the built-in tools")
    assert_true(brush.is_tablet, "and opens believing it is a tablet, which is the branch this is about")
    assert_eq(brush.last_pressure, 0.0, "with no pressure reported yet")

    var was := SaColors.foreground
    SaColors.foreground = Color(1.0, 1.0, 1.0, 1.0)
    surface.view.mouse_position = Vector2.ZERO
    _press(brush)
    _release(brush)
    SaColors.foreground = was

    var texel := _read_origin_texel(surface.easel.document)
    assert_true(texel.a > 0.0, "The dab under the press has alpha, %f" % texel.a)
    Fixtures.teardown(surface, machine)


## The mechanism, so a later change that reintroduces the zero fails here rather
## than in a texel nobody can attribute.
func test_a_press_with_nothing_to_read_does_not_open_at_zero_pressure() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool

    surface.view.mouse_position = Vector2.ZERO
    _press(brush)
    assert_true(brush.last_pressure > 0.0, "The press chose a pressure a dab can be seen at")
    _release(brush)
    Fixtures.teardown(surface, machine)


## The hover still wins where there is one, which is the case the fallback is a
## fallback to.
func test_a_hover_pressure_is_still_what_the_press_uses() -> void:
    var surface := Fixtures.make_surface(Vector2i(128, 128))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var brush: Object = machine.active_tool

    var hover := InputEventMouseMotion.new()
    hover.pressure = 0.25
    brush.handle_input(hover)
    assert_almost_eq(brush.last_pressure, 0.25, 1e-6, "The hover's pressure is remembered")

    surface.view.mouse_position = Vector2.ZERO
    _press(brush)
    assert_almost_eq(brush.last_pressure, 0.25, 1e-6, "and the press opens at it rather than at the fallback")
    _release(brush)
    Fixtures.teardown(surface, machine)
