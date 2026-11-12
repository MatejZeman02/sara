## The transform box fits the paint and its handles can be reached.
##
## The `canvas` sweep's F4: with no selection the box was the union of the
## layer's chunks, 1792 by 1024 from the origin, so the handles stood far from
## the strokes and the right middle one started under the Minimap docker,
## where a press lands on the docker. The box is measured on the GPU now, by a
## reduction that reads four ints back, and a box that opens with a
## handle outside the room between the dockers, or under a docker floating in
## the middle, pans the view by the least that brings it in. A gesture's
## release does not pan, and the suite that reads the view reads it left where
## it was.
##
## The pictures are taken by `scenarios/the-transform-box-fits-the-paint-and-its-handles-can-be-reached.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const CANVAS := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


func _key(keycode: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = true
    return event


## A surface, its machine and the transform tool on it, over an empty layer.
func _rig() -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *rect*, in document pixels, painted *colour* on the active layer, chunk by
## chunk through an upload, at the layer's own resolution or at *scale*.
static func _paint(document: SaDocument, rect: Rect2i, colour: Color = PAINT, scale: float = 0.0) -> void:
    var layer := document.active_layer
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos, scale)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), colour)
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())


## Every chunk's colour bytes, by grid position.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


func test_a_stroke_in_one_corner_of_a_chunk_gives_its_own_bounds() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var stroke := Rect2i(259, 262, 31, 12)
    _paint(surface.get_document(), stroke)

    assert_eq(tool.pending_box(), stroke, "The box is the stroke's own, and not the chunk at (256, 256) it sits in")
    assert_eq(tool.target_box(), stroke, "and so is what a transform would take")
    Fixtures.teardown(surface, parts[1])


func test_paint_across_a_seam_gives_the_union_of_both_sides() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    _paint(document, Rect2i(240, 100, 30, 8))
    _paint(document, Rect2i(500, 600, 4, 4))

    assert_eq(
        tool.pending_box(),
        Rect2i(240, 100, 264, 504),
        "A stroke across a seam and one two chunks below it give the box round both"
    )
    Fixtures.teardown(surface, parts[1])


func test_an_empty_layer_gives_the_empty_box() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var layer := surface.get_document().active_layer

    assert_eq(tool.pending_box(), Rect2i(), "A layer with no chunk has no box")
    layer.get_or_create_chunk(Vector2i(1, 1))
    layer.get_or_create_chunk(Vector2i(2, 1))
    assert_eq(tool.pending_box(), Rect2i(), "and nor has one whose chunks hold nothing, which must not give 512 by 256")
    assert_true(tool.preview_shape().is_empty(), "so the overlay is asked to draw nothing")
    Fixtures.teardown(surface, parts[1])


func test_a_texel_that_is_not_fully_transparent_counts() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    _paint(document, Rect2i(300, 300, 10, 10))
    _paint(document, Rect2i(320, 330, 2, 2), Color(0.8, 0.3, 0.1, 0.02))
    _paint(document, Rect2i(400, 400, 2, 2), Color(0.8, 0.3, 0.1, 0.0))

    assert_eq(
        tool.pending_box(), Rect2i(300, 300, 22, 32), "A faint texel is paint, and a transparent one with a colour in it is not"
    )
    Fixtures.teardown(surface, parts[1])


## A height can stand under a colour of no alpha, which Apply Mask leaves when
## it multiplies the colour alone, and the lift carries it, so the box counts it.
func test_a_height_under_no_alpha_counts() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    _paint(document, Rect2i(300, 300, 10, 10))
    SaHeightOps.new(document).gain(layer)
    _paint(document, Rect2i(600, 280, 8, 6), Color(0.8, 0.3, 0.1, 0.0))
    var texture := layer.get_or_create_field(Vector2i(2, 1), SaFieldSpec.HEIGHT)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    for y in range(280 - 256, 286 - 256):
        for x in range(600 - 512, 608 - 512):
            bytes.encode_half((y * texture.size.x + x) * 2, 2.5)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)

    assert_eq(tool.pending_box(), Rect2i(300, 280, 308, 30), "The relief under no alpha is in the box with the stroke")
    Fixtures.teardown(surface, parts[1])


func test_a_double_resolution_layer_answers_in_document_pixels() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var stroke := Rect2i(10, 5, 20, 10)
    _paint(surface.get_document(), stroke, PAINT, 2.0)

    assert_eq(surface.get_document().active_layer.chunks[Vector2i.ZERO].pixel_size(), 512, "The chunk holds 512 texels across")
    assert_eq(tool.pending_box(), stroke, "and the box is in the document's pixels and not in its texels")
    Fixtures.teardown(surface, parts[1])


func test_the_box_is_measured_once_until_the_layer_moves() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    _paint(document, Rect2i(100, 100, 20, 20))
    assert_eq(tool.pending_box(), Rect2i(100, 100, 20, 20), "The box of the first stroke")

    var before := SaCompute.dispatches
    for _frame in 5:
        tool.pending_box()
        tool.preview_shape()
        tool.capture_report(&"transform", true)
    assert_eq(SaCompute.dispatches, before, "Asked on five more frames, the box is not measured again")

    _paint(document, Rect2i(700, 700, 10, 10))
    assert_eq(tool.pending_box(), Rect2i(100, 100, 610, 610), "and a chunk the layer did not hold measures it again")
    assert_true(SaCompute.dispatches > before, "by a dispatch")
    Fixtures.teardown(surface, parts[1])


func test_a_move_commits_and_an_undo_restores_every_texel() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    var document := surface.get_document()
    var stroke := Rect2i(259, 262, 60, 40)
    _paint(document, stroke)
    var before := _texels(document.active_layer)
    assert_eq(tool.pending_box(), stroke, "The box hugs the stroke")

    view.mouse_position = Vector2(289, 282)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(329, 302)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    tool.tick(0.0)
    assert_eq(tool.pending_box(), Rect2i(299, 282, 60, 40), "and travels with the drag")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(tool.pending_box(), Rect2i(299, 282, 60, 40), "Enter lands it, and the box stands where it landed")
    assert_eq(tool.target_box(), Rect2i(299, 282, 60, 40), "on the paint, which Enter wrote where it landed")

    assert_true(document.undo(), "The move is a step")
    var after := _texels(document.active_layer)
    for grid_pos: Vector2i in before:
        assert_eq(
            after.get(grid_pos, PackedByteArray()),
            before[grid_pos],
            "and the undo gives chunk %s back texel for texel" % grid_pos
        )
    for grid_pos: Vector2i in after:
        if not before.has(grid_pos):
            var bytes: PackedByteArray = after[grid_pos]
            assert_eq(bytes.count(0), bytes.size(), "and a chunk the move made holds nothing, at %s" % grid_pos)
    assert_eq(tool.pending_box(), stroke, "so the box is the stroke's again")
    Fixtures.teardown(surface, parts[1])


func test_escape_restores_every_texel_of_a_tight_lift() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    var document := surface.get_document()
    _paint(document, Rect2i(500, 500, 40, 40))
    var before := _texels(document.active_layer)

    view.mouse_position = Vector2(520, 520)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(400, 450)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    tool.handle_input(_key(KEY_ESCAPE))

    assert_false(tool.is_moving(), "Escape puts the move back")
    var after := _texels(document.active_layer)
    for grid_pos: Vector2i in before:
        assert_eq(after.get(grid_pos, PackedByteArray()), before[grid_pos], "texel for texel, at %s" % grid_pos)
    Fixtures.teardown(surface, parts[1])


func test_opening_on_a_handle_outside_the_visible_rect_pans_it_in() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    view.viewport_size = Vector2(800, 600)
    _paint(surface.get_document(), Rect2i(640, 300, 180, 50))

    tool.tick(0.0)
    var reach := StateTransformScript.HANDLE_REACH
    assert_eq(
        view.pan,
        Vector2(800.0 - reach - 820.0, 0.0),
        "The right handles stood at 820 of 800, and the view moves left by the least"
    )
    assert_eq(
        view.document_to_screen(Vector2(820, 325)), Vector2(800.0 - reach, 325.0), "so the right middle handle is a reach inside"
    )
    for cell: Rect2 in SaTransformModeStrip.boxes(tool.pending_quad(), 1.0):
        assert_true(
            view.get_free_rect().has_point(view.document_to_screen(cell.get_center())), "and so is every cell of the mode strip"
        )
    tool.tick(0.0)
    assert_eq(view.pan, Vector2(800.0 - reach - 820.0, 0.0), "and a frame after it moves nothing")
    Fixtures.teardown(surface, parts[1])


func test_a_box_at_the_top_brings_its_mode_strip_down() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    view.viewport_size = Vector2(800, 600)
    _paint(surface.get_document(), Rect2i(300, 20, 200, 40))

    tool.tick(0.0)
    var strip := SaTransformModeStrip.boxes(tool.pending_quad(), 1.0)
    var reach := StateTransformScript.HANDLE_REACH
    assert_true(strip[0].position.y < 0.0, "The strip floats above the box, off the top of the view")
    assert_eq(
        view.pan, Vector2(0.0, reach - strip[0].position.y), "and the view moves down by the least that brings it a reach inside"
    )
    Fixtures.teardown(surface, parts[1])


func test_a_click_that_moves_nothing_leaves_the_view_where_the_painter_put_it() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    view.viewport_size = Vector2(800, 600)
    _paint(surface.get_document(), Rect2i(300, 300, 100, 50))
    tool.tick(0.0)
    view.set_pan(Vector2(450.0, 0.0))

    view.mouse_position = Vector2(350, 325)
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    tool.tick(0.0)
    assert_eq(view.pan, Vector2(450.0, 0.0), "A click inside the box moves nothing, so the view the painter panned stays")
    Fixtures.teardown(surface, parts[1])


func test_an_axis_the_handles_cannot_fit_across_is_left_alone() -> void:
    var room := Rect2(0, 0, 800, 600)
    var wide := PackedVector2Array([Vector2(-100, 650), Vector2(900, 700)])
    assert_eq(
        SaTransformHandles.reach_shift(wide, room, 10.0), Vector2(0.0, -110.0), "Wider than the room: x stays and y comes in"
    )
    var inside := PackedVector2Array([Vector2(20, 20), Vector2(780, 580)])
    assert_eq(SaTransformHandles.reach_shift(inside, room, 10.0), Vector2.ZERO, "Inside by more than the reach: nothing")
    var left := PackedVector2Array([Vector2(-40, 100), Vector2(60, 200)])
    assert_eq(SaTransformHandles.reach_shift(left, room, 10.0), Vector2(50.0, 0.0), "Off the left: the least to the right")


func test_a_handle_under_a_cover_in_the_middle_goes_out_past_its_nearest_side() -> void:
    var room := Rect2(0, 0, 800, 600)
    var box := PackedVector2Array()
    for x: float in [100.0, 225.0, 350.0]:
        for y: float in [200.0, 230.0, 260.0]:
            box.append(Vector2(x, y))
    var floating: Array[Rect2] = [Rect2(300, 100, 200, 300)]
    assert_eq(SaTransformHandles.reach_shift(box, room, 10.0), Vector2.ZERO, "The room alone has the box inside it")
    assert_eq(
        SaTransformHandles.clear_shift(box, room, floating, 10.0),
        Vector2(-60.0, 0.0),
        "The right handles stood 50 inside a cover in the middle, so the least move takes them a reach out of its left side"
    )
    var nothing: Array[Rect2] = []
    assert_eq(SaTransformHandles.clear_shift(box, room, nothing, 10.0), Vector2.ZERO, "With no cover it is the room's move")
    var everywhere: Array[Rect2] = [Rect2(-50, -50, 900, 700)]
    assert_eq(
        SaTransformHandles.clear_shift(box, room, everywhere, 10.0), Vector2.ZERO, "A cover no pan clears leaves the room's move"
    )


func test_opening_with_a_handle_under_a_floating_window_pans_it_out() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var kept_embedding := tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var view := surface.view as Fixtures.FakeView
    view.viewport_size = Vector2(800, 600)
    _paint(surface.get_document(), Rect2i(300, 300, 100, 50))

    # A docker dragged into the middle of the canvas, which the free rectangle
    # leaves in because it would take more than half the width. Under the
    # bus, the way the dialog suites host theirs, since the root is still
    # setting up its children while the suites run.
    var floating := Window.new()
    floating.position = Vector2i(380, 315)
    floating.size = Vector2i(150, 125)
    EventBus.add_child(floating)
    floating.show()
    assert_true(tree.root.get_embedded_subwindows().has(floating), "The window stands over the canvas, embedded")
    assert_eq(view.get_free_rect(), Rect2(0, 0, 800, 600), "and the room is still the whole view")

    # The open's own reach, which is the only one.
    tool.tick(0.0)

    var reach := StateTransformScript.HANDLE_REACH
    assert_eq(
        view.pan,
        Vector2(380.0 - reach - 400.0, 0.0),
        "The right handles open at 400, under the window from 380, and the view moves left by the least"
    )
    var cover := Rect2(Vector2(floating.position), Vector2(floating.size)).grow(reach)
    for corner: Vector2i in SaTransformHandles.HANDLE_CORNERS:
        var handle := view.document_to_screen(SaTransformHandles.point_on(tool.pending_quad(), corner))
        assert_false(
            handle.x > cover.position.x and handle.x < cover.end.x and handle.y > cover.position.y and handle.y < cover.end.y,
            "so the handle at %s is a reach clear of the window" % corner
        )
    floating.free()
    tree.root.gui_embed_subwindows = kept_embedding
    Fixtures.teardown(surface, parts[1])
