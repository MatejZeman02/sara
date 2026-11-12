## Tests for StateEyedropper tool and colour picking functionality.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const StateEyedropperScript = preload("res://modules/sara-base-modules/base/tools/state_eyedropper.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")


func test_eyedropper_merged_sampling() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))

    var rd := GlobalShaderCompiler.get_rd()
    # Clear merged canvas texture to solid blue
    rd.texture_clear(surface.easel.output.rid, Color(0.1, 0.2, 0.8, 1.0), 0, 1, 0, 1)

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW

    var picked := eyedropper.pick_color_at_pos(Vector2(32, 32))
    assert_almost_eq(picked.r, 0.1, 0.01, "Picked R should be ~0.1")
    assert_almost_eq(picked.g, 0.2, 0.01, "Picked G should be ~0.2")
    assert_almost_eq(picked.b, 0.8, 0.01, "Picked B should be ~0.8")
    assert_almost_eq(picked.a, 1.0, 0.01, "Picked A should be ~1.0")

    surface.get_document().free()
    surface.easel.free()


func test_eyedropper_layer_sampling() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))

    var layer := surface.get_document().active_layer
    layer.fill(Color(0.9, 0.5, 0.1, 0.7))

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER

    var picked := eyedropper.pick_color_at_pos(Vector2(10, 10))
    assert_almost_eq(picked.r, 0.9, 0.01, "Layer picked R should be ~0.9")
    assert_almost_eq(picked.g, 0.5, 0.01, "Layer picked G should be ~0.5")
    assert_almost_eq(picked.b, 0.1, 0.01, "Layer picked B should be ~0.1")
    assert_almost_eq(picked.a, 0.7, 0.01, "Layer picked A should be ~0.7")

    surface.get_document().free()
    surface.easel.free()


func test_eyedropper_signal_updates_brush() -> void:
    # The module owns shared settings rather than tool instances now: the registry
    # creates one instance per surface, so a colour pick has to reach the settings
    # every instance shares, not a single tool the module holds.
    #
    # The module it has to reach is the stamp brush: the eyedropper is base's
    # and the brush is not, and this test is about the signal between them
    # rather than about either module's own tools.
    var mod := preload("res://modules/sara-base-modules/stamp-brush/module.gd").new()
    var brush := StateBrushScript.new()
    mod.brush_settings = brush.settings

    if not EventBus.color_picked.is_connected(mod._on_color_picked):
        EventBus.color_picked.connect(mod._on_color_picked)

    var test_color := Color(0.3, 0.6, 0.9, 1.0)
    EventBus.color_picked.emit(test_color)

    assert_eq(brush.settings.color, test_color, "Brush settings color should be updated via EventBus")


## An F16 document stores half floats, and a half is two bytes. Reading it with
## decode_float takes four, so channel 0 is two halves glued together, channel 2
## reads past the end of a one-texel readback, and the engine logs an
## out-of-bounds decode for every sample.
##
## Reported from a real session as three `p_offset > size - 4` errors, which is
## what an eyedropper click on an F16 canvas costs: two errors and a colour that
## is not the colour under the pointer.
func test_the_eyedropper_reads_an_f16_document_at_its_own_depth() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()

    # A merged sample reads the easel's output texture, so make that one F16.
    var f16 := SaTexture.new(Vector2i(64, 64), RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    rd.texture_clear(f16.rid, Color(0.25, 0.5, 0.75, 1.0), 0, 1, 0, 1)
    surface.easel.output = f16

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW

    var picked := eyedropper.pick_color_at_pos(Vector2(32, 32))

    assert_almost_eq(picked.r, 0.25, 0.001, "Red is what the half float holds")
    assert_almost_eq(picked.g, 0.5, 0.001, "and green")
    assert_almost_eq(picked.b, 0.75, 0.001, "and blue, which decode_float could not even reach")
    assert_almost_eq(picked.a, 1.0, 0.001, "and alpha")

    # Through the fixture, not document.free(): this test replaced the easel's
    # output texture, and the easel is what owns it.
    Fixtures.teardown(surface)


## A sample size averages the square around the pointer.
func test_a_sample_size_averages_the_square() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_clear(surface.easel.output.rid, Color(0.0, 0.0, 1.0, 1.0), 0, 1, 0, 1)
    # One red texel in a blue field, at the centre of the square.
    var dot := SaTexture.new(Vector2i.ONE, surface.easel.output.format)
    rd.texture_clear(dot.rid, Color(1.0, 0.0, 0.0, 1.0), 0, 1, 0, 1)
    rd.texture_copy(dot.rid, surface.easel.output.rid, Vector3.ZERO, Vector3(32, 32, 0), Vector3.ONE, 0, 0, 0, 0)

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    eyedropper.sample_size = 1
    assert_almost_eq(eyedropper.pick_color_at_pos(Vector2(32, 32)).r, 1.0, 0.01, "One texel is the red dot")

    eyedropper.sample_size = 3
    var picked := eyedropper.pick_color_at_pos(Vector2(32, 32))
    assert_almost_eq(picked.r, 1.0 / 9.0, 0.01, "Three by three is one red in nine")
    assert_almost_eq(picked.b, 8.0 / 9.0, 0.01, "and eight blues")
    assert_almost_eq(picked.a, 1.0, 0.01, "all opaque")

    eyedropper.sample_size = 9
    assert_almost_eq(eyedropper.pick_color_at_pos(Vector2(32, 32)).r, 1.0 / 81.0, 0.005, "Nine by nine is one in eighty-one")

    surface.get_document().free()
    surface.easel.free()


## The square stops at the canvas edge and averages only what is there.
func test_the_square_is_clipped_at_the_canvas_edge() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_clear(surface.easel.output.rid, Color(0.2, 0.4, 0.6, 1.0), 0, 1, 0, 1)

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.VIEW
    eyedropper.sample_size = 9
    var picked := eyedropper.pick_color_at_pos(Vector2(0, 0))
    assert_almost_eq(picked.g, 0.4, 0.01, "A corner sample is the corner's colour")
    assert_almost_eq(picked.a, 1.0, 0.01, "and not diluted by the texels outside the canvas")

    surface.get_document().free()
    surface.easel.free()


## On the active layer the square may cross a chunk edge, and both chunks
## count, the way the layer looks.
func test_a_layer_sample_spans_chunks() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var layer := surface.get_document().active_layer
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(1.0, 0.0, 0.0, 1.0))
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.0, 0.0, 1.0, 1.0))

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER
    eyedropper.sample_size = 3
    # Centred on the first texel of the second chunk: one red column, two blue.
    var picked := eyedropper.pick_color_at_pos(Vector2(256, 10))
    assert_almost_eq(picked.r, 1.0 / 3.0, 0.01, "A third red from the chunk on the left")
    assert_almost_eq(picked.b, 2.0 / 3.0, 0.01, "two thirds blue from the one on the right")

    # A chunk nobody painted is not a colour, so it is left out of the average.
    var lower := eyedropper.pick_color_at_pos(Vector2(10, 256))
    assert_almost_eq(lower.r, 1.0, 0.01, "Below the red chunk lies nothing, and nothing does not dilute it")

    surface.get_document().free()
    surface.easel.free()


## A pick outside the canvas leaves the colour alone.
##
## **The bug was not in the pick, it was in the emit.**
## `pick_color_at_pos` answers `Color.TRANSPARENT` off the canvas and has done
## since it was written, which is right: there is nothing there. What was wrong
## is that the tool then put that on the bus, so a painter who released the
## eyedropper over the grey beside their canvas had a transparent black
## foreground and had to go and find their colour again.
func test_a_pick_outside_the_canvas_has_nothing_to_sample() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface

    assert_true(eyedropper.has_sample_at(Vector2(32, 32)), "The middle of the canvas is a sample")
    assert_true(eyedropper.has_sample_at(Vector2(0, 0)), "so is its first texel")
    assert_true(eyedropper.has_sample_at(Vector2(63.9, 63.9)), "and so is its last")

    assert_false(eyedropper.has_sample_at(Vector2(-1, 32)), "A point left of the canvas is not")
    assert_false(eyedropper.has_sample_at(Vector2(64, 32)), "nor one past its right edge")
    assert_false(eyedropper.has_sample_at(Vector2(32, -1)), "nor one above it")
    assert_false(eyedropper.has_sample_at(Vector2(32, 64)), "nor one below it")
    assert_false(eyedropper.has_sample_at(Vector2(-500, -500)), "nor one nowhere near it")

    surface.get_document().free()
    surface.easel.free()


## A larger square hanging off the edge still picks, because part of it is over
## the canvas and the average already leaves out what is not there.
func test_a_square_that_overlaps_the_edge_still_picks() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_size = 9

    assert_true(eyedropper.has_sample_at(Vector2(0, 0)), "A nine square on the corner overlaps the canvas")
    assert_true(eyedropper.has_sample_at(Vector2(-3, 32)), "and so does one three texels off the left edge")
    assert_false(eyedropper.has_sample_at(Vector2(-5, 32)), "One five off it does not, so it picks nothing")
    assert_false(eyedropper.has_sample_at(Vector2(69, 32)), "and neither does one five past the right")

    surface.get_document().free()
    surface.easel.free()


## Transparent inside the canvas is still a sample, and the pick reads it as
## nothing painted. The tool then leaves the colour alone, which
## `test_an_empty_pick_changes_nothing.gd` holds.
func test_transparent_inside_the_canvas_is_still_a_sample() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface
    eyedropper.sample_from = StateEyedropperScript.SampleFrom.LAYER

    # A chunk nobody has painted, well inside the document.
    assert_true(eyedropper.has_sample_at(Vector2(300, 300)), "An unpainted chunk is inside the canvas")
    assert_almost_eq(eyedropper.pick_color_at_pos(Vector2(300, 300)).a, 0.0, 0.01, "and reads as nothing painted")

    surface.get_document().free()
    surface.easel.free()


## The drag samples because the tool remembers the press, not because the motion
## carries a button mask.
##
## **This is what makes the drag half provable.** A motion branch that read
## `event.button_mask` alone would never fire for a scenario, because
## `SaCaptureInput._inject_motion` fills in the position, the pressure and the
## tilt and never the mask. `state_brush.gd` tracks its own `is_drawing` from the
## press, and this is the same thing.
##
## A motion no longer samples on the spot: it records the pointer and sets a
## flag, and `tick` does the one sample the frame gets, so a motion this test
## drives has to be followed by a `tick` before it shows up on `seen`.
func test_the_drag_follows_the_press_rather_than_the_button_mask() -> void:
    var surface := Fixtures.make_surface(Vector2i(64, 64))
    var rd := GlobalShaderCompiler.get_rd()
    rd.texture_clear(surface.easel.output.rid, Color(0.1, 0.2, 0.8, 1.0), 0, 1, 0, 1)

    var eyedropper := StateEyedropperScript.new()
    eyedropper.surface = surface

    # The tool samples where the *pointer* is rather than where the event says,
    # so this is asserted first: an offscreen run whose pointer sat outside the
    # fixture would make every count below zero and say nothing about why.
    assert_true(
        eyedropper.has_sample_at(eyedropper.get_document_mouse_position()),
        "The pointer is over the fixture, at %s" % eyedropper.get_document_mouse_position()
    )

    var seen: Array[Color] = []
    var listener := func(color: Color) -> void: seen.append(color)
    EventBus.color_picked.connect(listener)

    # A motion with no button and no press before it is a hover, and a hover
    # picks nothing.
    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    assert_eq(seen.size(), 0, "A hover picks nothing")

    eyedropper.handle_input(_button(true))
    assert_eq(seen.size(), 1, "The press picks once")

    # A motion carrying no mask at all, which is every motion a scenario sends.
    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    assert_eq(seen.size(), 2, "and a motion after it picks again, mask or no mask")

    eyedropper.handle_input(_button(false))
    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    assert_eq(seen.size(), 2, "while a motion after the release is a hover again")

    # A tool swapped away mid-drag comes back with the button believed up, which
    # is what ALT does when it borrows the eyedropper.
    eyedropper.handle_input(_button(true))
    eyedropper.reset()
    eyedropper.handle_input(_motion())
    eyedropper.tick(0.016)
    assert_eq(seen.size(), 3, "A reset forgets the press, so the next motion is a hover")

    EventBus.color_picked.disconnect(listener)
    surface.get_document().free()
    surface.easel.free()


## A left press or release at the middle of the 64 by 64 fixture.
func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = Vector2(32, 32)
    return event


## A motion with **no button mask**, which is what the capture harness sends.
func _motion() -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = Vector2(32, 32)
    return event
