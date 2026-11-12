## The gradient tool's ramp, read back texel by texel.
##
## The claim under test is that the walk is Oklab, so
## the middle of a black to white ramp sits where Oklab puts it and not where
## either naive lerp would. The other three are the ones the maths could get
## wrong quietly: a chunk's own origin, the selection, and undo.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

var _easel: SaEasel = null
var _doc: SaDocument = null
var _ramp: SaGradient = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _ramp = SaGradient.new(_doc)


func after_each() -> void:
    _ramp = null
    _easel.free()
    _easel = null
    _doc = null


func _texel(x: int, y: int) -> Color:
    return _texel_of(_doc.active_layer, x, y)


## The texel at *x*, *y* of *layer*, or transparent where it holds no chunk.
func _texel_of(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )


## The ramp's value at *t* as this document stores it, worked out the long way
## round: Oklab's own midpoint, back through linear sRGB, back through the
## document's curve. The kernel is asked for the same number by a different
## road, which is the point of comparing them.
func _expected_grey(t: float) -> float:
    var lab := Vector3(t, 0.0, 0.0)
    var linear := SaOklab.to_linear_srgb(lab)
    return _doc.color_space.transfer.encode(linear.x)


## The drag runs from half a texel in to half a texel
## past the last column, so the centre of column 256 falls on t exactly 0.5.
func test_the_middle_of_a_black_to_white_ramp_is_oklab_s_middle() -> void:
    var laid := _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )
    assert_true(laid, "A drag lays a ramp")

    var middle := _texel(256, 100)
    assert_almost_eq(middle.r, _expected_grey(0.5), 2e-3, "The middle of the ramp is Oklab's middle")
    assert_almost_eq(middle.a, 1.0, 1e-4, "and it is opaque, both ends being opaque")
    assert_true(absf(middle.r - 0.5) > 0.05, "not the value a mix of the stored numbers gives")
    assert_true(absf(middle.r - _doc.color_space.transfer.encode(0.5)) > 0.05, "and not a mix in linear light")

    # The ends are read at the centres of the first and last columns, which sit
    # half a texel inside the drag, so each is a five-hundred-and-twelfth short
    # of the end colour rather than exactly on it.
    var start := _texel(0, 100)
    assert_almost_eq(start.r, _expected_grey(1.0 / 512.0), 2e-3, "The press end is the near colour")
    var finish := _texel(511, 100)
    assert_almost_eq(finish.r, _expected_grey(511.0 / 512.0), 2e-3, "and the release end is the far one")


## A chunk is dispatched with the drag in its own texel coordinates, so an
## origin dropped anywhere would show as a step at every 256th column and
## nowhere else. Read either side of the first boundary.
func test_the_ramp_does_not_step_at_a_chunk_boundary() -> void:
    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )
    var before := _texel(255, 40).r
    var after := _texel(256, 40).r
    assert_true(after > before, "The ramp still climbs across the boundary")
    assert_true(after - before < 0.01, "by one column's worth and not by a chunk's")


## Radial reads the drag as a radius: the press is the near colour and the
## circle through the release point is the far one, in every direction.
func test_a_radial_ramp_reads_the_drag_as_a_radius() -> void:
    _ramp.apply(
        _doc.active_layer,
        Vector2(256.0, 256.0),
        Vector2(356.0, 256.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.RADIAL,
        SaGradient.Repeat.NONE,
        true
    )
    assert_almost_eq(_texel(256, 256).r, 0.0, 5e-3, "The press is the near colour")
    assert_almost_eq(_texel(356, 256).r, 1.0, 5e-3, "the radius to the right is the far one")
    assert_almost_eq(_texel(256, 356).r, 1.0, 5e-3, "and so is the same radius downwards")


## A ramp under a selection is a ramp inside it, and the chunks the selection
## leaves out are not even allocated.
func test_the_selection_keeps_the_ramp_inside_it() -> void:
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    _doc.selection.select_rect(Rect2i(0, 0, 200, 200))

    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )
    assert_true(_texel(100, 100).r < 0.25, "Inside the selection the ramp landed")
    assert_almost_eq(_texel(300, 100).r, 0.25, 1e-4, "and outside it the fill is untouched")


## One drag is one history step, and it puts back a layer that had chunks as
## well as the emptiness of one that had none.
func test_undo_restores_what_the_ramp_covered() -> void:
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    var steps := _doc.history.step_count()

    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )
    assert_eq(_doc.history.step_count(), steps + 1, "A ramp is one step")
    assert_true(_doc.undo(), "which undoes")
    assert_almost_eq(_texel(256, 100).r, 0.25, 1e-4, "and the fill is back")


## The other half of undo: a layer that held nothing holds nothing again,
## rather than a grid of blank chunks the ramp allocated.
func test_undo_takes_back_the_chunks_the_ramp_allocated() -> void:
    _doc.active_layer.release_chunks()
    assert_eq(_doc.active_layer.chunks.size(), 0, "The layer starts empty")

    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )
    assert_true(_doc.active_layer.chunks.size() > 0, "the ramp allocates the grid")
    assert_true(_doc.undo(), "and the undo")
    assert_eq(_doc.active_layer.chunks.size(), 0, "leaves it as empty as it was")


## The snapshot is the ramp's rectangle and not the layer.
##
## A ramp under a small marquee reaches one chunk of a four-chunk layer, and
## what the history is charged says which of the two the snapshot walked. The
## whole-layer walk that stood here charged four, so a gradient the size of a
## postage stamp cost the history a layer.
func test_the_snapshot_covers_the_ramps_region_and_not_the_layer() -> void:
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    assert_eq(_doc.active_layer.chunks.size(), 4, "The layer holds the whole 512 by 512 grid")
    var one_chunk: int = (_doc.active_layer.chunks[Vector2i.ZERO] as SaChunk).byte_size()
    _doc.selection.select_rect(Rect2i(0, 0, 200, 200))
    var held := _doc.history.total_bytes()

    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )

    var charged := _doc.history.total_bytes() - held
    assert_eq(charged, one_chunk, "The step holds the one chunk the marquee reaches")
    assert_true(charged < one_chunk * 4, "and not the four the layer has")


## The other end of the same rule: a ramp with no selection is a whole-canvas
## write, so its snapshot is the whole grid and nothing is narrowed away.
func test_a_ramp_with_no_selection_still_snapshots_the_grid() -> void:
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    var one_chunk: int = (_doc.active_layer.chunks[Vector2i.ZERO] as SaChunk).byte_size()
    var held := _doc.history.total_bytes()

    _ramp.apply(
        _doc.active_layer,
        Vector2(0.5, 0.0),
        Vector2(512.5, 0.0),
        SaColorRamp.from_pair(Color.BLACK, Color.WHITE),
        SaGradient.Shape.LINEAR,
        SaGradient.Repeat.NONE,
        true
    )

    assert_eq(_doc.history.total_bytes() - held, one_chunk * 4, "Every chunk the ramp overwrites is in the step")


## A chunk the layer holds outside the canvas is a chunk the ramp can never
## reach, so it stays out of the step. Painting past the edge is allowed, which
## is how a layer comes to have one.
func test_a_chunk_past_the_canvas_edge_is_not_snapshotted() -> void:
    _doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    _doc.active_layer.get_or_create_chunk(Vector2i(4, 0))
    assert_eq(_doc.active_layer.chunks.size(), 5, "One chunk sits past the right edge")

    var recorded := _ramp._snapshot_of(_doc.active_layer)

    assert_eq(recorded.size(), 4, "The snapshot is the four the canvas covers")
    assert_false(recorded.has(Vector2i(4, 0)), "and not the one no ramp can write")


## The drag opens a stroke that nothing ever commits, deliberately, because the
## stroke buffer is only the preview's canvas. The check is that it swallows
## nothing: the release still leaves one history step and an empty buffer.
func test_the_uncommitted_stroke_leaves_the_step_alone() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool := machine.get_tool(&"gradient")
    var document: SaDocument = surface.get_document()
    document.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    var steps := document.history.step_count()

    var view: Fixtures.FakeView = surface.view
    view.mouse_position = Vector2(10.0, 10.0)
    tool.handle_input(_left_button(true))
    view.mouse_position = Vector2(200.0, 10.0)
    tool.handle_input(InputEventMouseMotion.new())
    tool.tick(0.016)
    assert_false(document.stroke_layer.chunks.is_empty(), "The preview is in the stroke buffer")
    view.mouse_position = Vector2(400.0, 10.0)
    tool.handle_input(_left_button(false))

    assert_true(document.stroke_layer.chunks.is_empty(), "The release drops the preview")
    assert_eq(document.history.step_count(), steps + 1, "and leaves the ramp as one step")
    assert_true(document.undo(), "which undoes")
    Fixtures.teardown(surface, machine)


## A press, a drag and a release over a default document whose active layer holds
## no chunk lay the ramp into that layer. A capture had shown the ramp on screen
## over an empty layer, and the cause was the capture's injected motion rather
## than this tool, so this is the half that rules the tool out: the pass
## allocates the chunks it walks and the release writes them.
func test_a_drag_over_an_empty_layer_lands_in_that_layer() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool := machine.get_tool(&"gradient")
    tool.ramp = SaColorRamp.from_pair(Color.BLACK, Color.WHITE)
    var document: SaDocument = surface.get_document()
    var layer := document.active_layer
    assert_true(layer.chunks.is_empty(), "The default document's active layer starts with no chunk")
    var steps := document.history.step_count()

    var view: Fixtures.FakeView = surface.view
    var width := document.canvas_size.x
    view.mouse_position = Vector2(0.0, 10.0)
    tool.handle_input(_left_button(true))
    for i in range(1, 5):
        view.mouse_position = Vector2(width * i / 4.0, 10.0)
        tool.handle_input(InputEventMouseMotion.new())
        tool.tick(0.016)
    assert_true(layer.chunks.is_empty(), "The drag previews in the stroke buffer and leaves the layer alone")
    tool.handle_input(_left_button(false))

    var near := _texel_of(layer, 0, 10)
    var far := _texel_of(layer, width - 1, 10)
    assert_false(layer.chunks.is_empty(), "The release allocates the layer's chunks")
    assert_almost_eq(near.a, 1.0, 0.001, "The press end is opaque")
    assert_true(near.r < 0.05, "and dark, %.3f" % near.r)
    assert_true(far.r > 0.95, "and the release end light, %.3f" % far.r)
    assert_true(document.stroke_layer.chunks.is_empty(), "The preview is gone")
    assert_eq(document.history.step_count(), steps + 1, "The ramp is one step")
    assert_true(document.modified, "and the document is modified")
    Fixtures.teardown(surface, machine)


## A drag's preview is dispatched once a frame and not once a motion event.
## The preview is the ramp over every chunk of the canvas, and a tablet's
## motion events came faster than the frames.
func test_two_motions_in_one_frame_preview_once() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool := machine.get_tool(&"gradient")
    var document: SaDocument = surface.get_document()
    # Through `handle_input`, the door the tool machine hands every event to,
    # rather than `_press` and `move_to`: the fixture's view answers
    # `get_document_mouse_position` with whatever the test puts there, which
    # is the one thing the tool reads off a motion.
    var view: Fixtures.FakeView = surface.view
    view.mouse_position = Vector2(10.0, 10.0)
    tool.handle_input(_left_button(true))
    var gradient_pass: SaGradient = tool._pass_for(document)
    view.mouse_position = Vector2(50.0, 10.0)
    tool.handle_input(InputEventMouseMotion.new())
    view.mouse_position = Vector2(90.0, 10.0)
    tool.handle_input(InputEventMouseMotion.new())
    assert_eq(gradient_pass.previews, 0, "Two motions dispatch nothing on their own")
    tool.tick(0.016)
    assert_eq(gradient_pass.previews, 1, "the frame dispatches one preview")
    tool.tick(0.016)
    assert_eq(gradient_pass.previews, 1, "and a frame with no motion dispatches none")
    tool.handle_input(_left_button(false))
    Fixtures.teardown(surface, machine)


## One left button event. The tool reads the pointer off its view, not off
## the event, so the event carries no position.
func _left_button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
