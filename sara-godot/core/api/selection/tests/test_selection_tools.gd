## The selection beyond a rectangle: the ellipse and
## the polygon kernels, the three modes, invert, feather and border across a
## chunk seam, the Select menu's commands, and the quick mask that turns the
## brush into a way of painting the mask itself.
##
## Everything reads pixels back, because a mask written through the wrong
## kernel returns plausible numbers rather than an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

var _easel: SaEasel = null
var _doc: SaDocument = null


## Two by two chunks, so a shape can cross a seam and leave chunks out.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## The mask's coverage at a document pixel, 0 where no chunk is.
func _coverage(x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.selection.chunks.get(grid, null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)
    return bytes.decode_float((local.y * texture.size.x + local.x) * 4)


func _layer_texel(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + x - grid.x * SaChunk.SIZE
    )


## One hard white dab through the paint context, the way the brush lands one.
func _dab(pos: Vector2, radius: float, color: Color = Color.WHITE) -> void:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, false)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, color, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()


func test_an_ellipse_covers_its_centre_and_not_its_corners() -> void:
    _doc.selection.select_ellipse(Rect2i(100, 100, 200, 100))
    assert_almost_eq(_coverage(200, 150), 1.0, 0.001, "The centre is inside")
    assert_almost_eq(_coverage(102, 102), 0.0, 0.001, "The box's corner is outside the ellipse")
    assert_almost_eq(_coverage(299, 150), 1.0, 0.001, "The rightmost point on the axis is inside")
    assert_almost_eq(_coverage(50, 50), 0.0, 0.001, "and so is nothing beyond the box")
    assert_eq(_doc.selection.chunks.size(), 2, "A box over one seam touches two chunks")
    assert_eq(_doc.selection.bounds, Rect2i(100, 100, 200, 100), "and the bounds are the box")


## A pentagram is inside at its points and, by even-odd winding, outside at
## its centre, where the outline winds twice.
func test_a_polygon_is_filled_by_even_odd_winding() -> void:
    var points := PackedVector2Array()
    var centre := Vector2(128, 128)
    for i in 5:
        var angle := -PI / 2.0 + TAU * float(i * 2) / 5.0
        points.append(centre + Vector2(cos(angle), sin(angle)) * 100.0)
    _doc.selection.select_polygon(points)
    assert_almost_eq(_coverage(128, 128), 0.0, 0.001, "The centre of a pentagram winds twice and is out")
    assert_almost_eq(_coverage(128, 40), 1.0, 0.001, "The top point is in")
    assert_almost_eq(_coverage(10, 10), 0.0, 0.001, "and the corner of the box is out")
    assert_eq(_doc.selection.chunks.size(), 1, "The polygon's box is one chunk, so one chunk was touched")
    var box := _doc.selection.bounds
    assert_true(box.position.x >= 28 and box.end.x <= 229, "and the bounds are its box, not the canvas")


func test_add_and_subtract_change_only_the_shape() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(0, 0, 100, 100))
    selection.select_rect(Rect2i(300, 300, 100, 100), SaSelection.Mode.ADD)
    assert_almost_eq(_coverage(50, 50), 1.0, 0.001, "The first rectangle stays")
    assert_almost_eq(_coverage(350, 350), 1.0, 0.001, "and the second joins it")
    assert_eq(selection.bounds, Rect2i(0, 0, 400, 400), "with the bounds around both")

    selection.select_ellipse(Rect2i(20, 20, 40, 40), SaSelection.Mode.SUBTRACT)
    assert_almost_eq(_coverage(40, 40), 0.0, 0.001, "Subtracting takes the ellipse out")
    assert_almost_eq(_coverage(5, 5), 1.0, 0.001, "and leaves the corner")
    assert_almost_eq(_coverage(350, 350), 1.0, 0.001, "and the other rectangle")
    assert_true(selection.active, "The selection stays active")

    selection.select_rect(Rect2i(0, 0, 10, 10), true)
    assert_almost_eq(_coverage(350, 350), 1.0, 0.001, "An older caller's bare true still adds")

    selection.deselect()
    selection.select_rect(Rect2i(0, 0, 10, 10), SaSelection.Mode.SUBTRACT)
    assert_false(selection.active, "Subtracting from no selection changes nothing")


func test_invert_flips_the_canvas() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(0, 0, 100, 100))
    SaSelectionFilters.invert(selection, _doc.canvas_size)
    assert_almost_eq(_coverage(50, 50), 0.0, 0.001, "Inside the rectangle is out now")
    assert_almost_eq(_coverage(200, 50), 1.0, 0.001, "The rest of its chunk is in")
    assert_almost_eq(_coverage(400, 400), 1.0, 0.001, "and so is a chunk that had none")
    assert_eq(selection.chunks.size(), 4, "over the whole canvas")
    assert_eq(selection.bounds, Rect2i(0, 0, 512, 512), "which the bounds say")

    # What inverts to nothing is no selection, so inverting
    # everything leaves everything selected rather than an active nothing.
    selection.deselect()
    SaSelectionFilters.invert(selection, _doc.canvas_size)
    assert_false(selection.active, "Inverting everything changes nothing")
    assert_eq(selection.chunks.size(), 0, "and holds no chunk")


## A feather softens the edge over the radius, across a chunk seam as well as
## inside a chunk, and reaches no further than the radius.
func test_a_feather_softens_the_edge_across_a_seam() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(128, 128, 256, 256))
    SaSelectionFilters.feather(selection, 16, _doc.canvas_size)
    var at_edge := _coverage(128, 256)
    assert_true(at_edge > 0.35 and at_edge < 0.65, "On the edge the coverage is about a half: %f" % at_edge)
    assert_almost_eq(_coverage(256, 256), 1.0, 0.001, "Deep inside, on the seam, it is still full")
    assert_almost_eq(_coverage(250, 200), 1.0, 0.001, "and so is a texel whose window crosses the seam")
    assert_almost_eq(_coverage(100, 256), 0.0, 0.001, "Past the radius outside it is nothing")
    var just_out := _coverage(120, 256)
    assert_true(just_out > 0.0 and just_out < 0.5, "and just outside it is faint: %f" % just_out)
    assert_eq(selection.bounds, Rect2i(112, 112, 288, 288), "The bounds grew by the radius")


## Feather at 7 reaches seven pixels either way.
func test_feather_at_seven_gives_a_seven_pixel_edge() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(128, 128, 256, 256))
    SaSelectionFilters.feather(selection, 7, _doc.canvas_size)
    var at_edge := _coverage(128, 256)
    assert_true(at_edge > 0.35 and at_edge < 0.65, "On the edge the coverage is about a half: %f" % at_edge)
    assert_almost_eq(_coverage(142, 256), 1.0, 0.001, "Two radii inside, it is full")
    assert_almost_eq(_coverage(118, 256), 0.0, 0.001, "Past the radius outside, it is nothing")
    var just_out := _coverage(125, 256)
    assert_true(just_out > 0.0 and just_out < 0.5, "and just outside it is faint: %f" % just_out)
    assert_eq(selection.bounds, Rect2i(121, 121, 270, 270), "The bounds grew by exactly seven")


func test_a_border_is_a_band_around_the_edge() -> void:
    var selection := _doc.selection
    selection.select_rect(Rect2i(128, 128, 256, 256))
    SaSelectionFilters.border(selection, 8, _doc.canvas_size)
    assert_almost_eq(_coverage(128, 256), 1.0, 0.001, "On the edge the band is full")
    assert_almost_eq(_coverage(133, 256), 1.0, 0.001, "and just inside")
    assert_almost_eq(_coverage(123, 256), 1.0, 0.001, "and just outside, across the seam of the chunk before")
    assert_almost_eq(_coverage(256, 256), 0.0, 0.001, "Deep inside is out of the band")
    assert_almost_eq(_coverage(100, 256), 0.0, 0.001, "and so is far outside")


## With the quick mask on, a dab writes coverage into the selection and
## nothing into the layer, and undoes nothing.
func test_the_quick_mask_paints_the_selection_rather_than_the_layer() -> void:
    var selection := _doc.selection
    var layer := _doc.active_layer
    var steps := _doc.undo_redo.get_history_count()
    selection.editing = true
    assert_true(selection.active, "Turning the quick mask on makes a selection to paint")
    _dab(Vector2(300, 300), 20.0)
    assert_almost_eq(_coverage(300, 300), 1.0, 0.01, "The dab selected where it landed")
    assert_almost_eq(_coverage(100, 100), 0.0, 0.001, "and nowhere else")
    assert_eq(layer.chunks.size(), 0, "The layer got no chunk")
    assert_eq(_doc.undo_redo.get_history_count(), steps, "and history no step")

    _dab(Vector2(300, 300), 20.0, Color.BLACK)
    assert_almost_eq(_coverage(300, 300), 0.0, 0.01, "A black dab takes the selection away again")

    selection.editing = false
    _dab(Vector2(100, 100), 10.0, Color.RED)
    assert_eq(layer.chunks.size(), 0, "With the mask off, a dab outside the selection writes nothing, as before")
    _doc.stroke_layer.chunks.clear()


## The four commands the skeleton registers reach the primary document.
func test_the_select_commands_reach_the_document() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var commands := registries.commands
    for id: StringName in [&"select_all", &"select_none", &"select_invert", &"select_quick_mask"]:
        assert_true(commands.has(id), "%s is registered" % id)
    var doc := surface.get_document()
    assert_true(commands.execute(&"select_all"), "Select all runs")
    assert_eq(doc.selection.chunks.size(), 1, "and covers the 256 canvas")
    assert_true(commands.execute(&"select_invert"), "Invert runs")
    assert_almost_eq(_coverage_of(doc, 10, 10), 0.0, 0.001, "and leaves nothing selected")
    assert_true(commands.execute(&"select_quick_mask"), "The quick mask toggles")
    assert_true(doc.selection.editing, "on")
    assert_true(commands.execute(&"select_none"), "Deselect runs")
    assert_false(doc.selection.active, "and drops it")
    assert_false(doc.selection.editing, "quick mask included")
    Fixtures.teardown(surface)


func _coverage_of(doc: SaDocument, x: int, y: int) -> float:
    @warning_ignore("integer_division")
    var chunk: SaChunk = doc.selection.chunks.get(Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return bytes.decode_float(((y % SaChunk.SIZE) * texture.size.x + x % SaChunk.SIZE) * 4)


## The two tools register with their options and their keys, through the
## same door as the six before them.
func test_the_selection_tools_are_registered_with_their_options() -> void:
    var registry := Fixtures.make_tool_registry()
    for id: StringName in [&"marquee", &"lasso"]:
        assert_true(registry.has(id), "%s is a registered tool" % id)
    var marquee := registry.get_descriptor(&"marquee")
    assert_eq(marquee.activate_action, &"tool_marquee", "with its key")
    assert_true(InputMap.has_action(&"tool_marquee"), "which the input map holds")
    assert_true(InputMap.has_action(&"tool_lasso"), "and the lasso's too")
    var keys: Array = []
    for spec: SaOptionSpec in marquee.options:
        keys.append(spec.key)
    assert_eq(keys, [&"selection_mode", &"feather"], "The marquee declares the shared mode and its own feather, and no shape")
    keys.clear()
    for spec: SaOptionSpec in registry.get_descriptor(&"lasso").options:
        keys.append(spec.key)
    assert_eq(keys, [&"selection_mode", &"feather", &"lasso_anti_alias"], "and the lasso those and its edge, and no shape")
    keys.clear()
    for spec: SaOptionSpec in registry.get_descriptor(&"polygonal_lasso").options:
        keys.append(spec.key)
    assert_eq(keys, [&"selection_mode", &"feather", &"lasso_anti_alias"], "and the Polygonal Lasso the lasso's own")
    assert_true(InputMap.has_action(&"tool_polygonal_lasso"), "under an action of its own")


## A marquee drag selects the box between the press and the release, an
## ellipse when the shape says so, and a click alone deselects.
func test_the_marquee_selects_what_was_dragged() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    machine.set_active_tool(&"marquee")
    var tool := machine.active_tool
    var view := surface.view

    view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(300, 200)
    tool.handle_input(InputEventMouseMotion.new())
    assert_eq(tool.preview_shape().get("rect"), Rect2(100, 100, 200, 100), "The overlay is told the box while dragging")
    tool.handle_input(_button(false))
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 200, 100), "The release selects the box")
    assert_almost_eq(_coverage_of(doc, 150, 150), 1.0, 0.001, "inside")
    assert_almost_eq(_coverage_of(doc, 50, 50), 0.0, 0.001, "and not outside")

    tool.shape = 1
    view.mouse_position = Vector2(0, 0)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(200, 100)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_almost_eq(_coverage_of(doc, 100, 50), 1.0, 0.001, "An ellipse holds its centre")
    assert_almost_eq(_coverage_of(doc, 2, 2), 0.0, 0.001, "and not the box's corner")
    assert_almost_eq(_coverage_of(doc, 150, 150), 0.0, 0.001, "The first box is gone, because the mode replaces")

    var shift := _button(true)
    shift.shift_pressed = true
    view.mouse_position = Vector2(400, 400)
    tool.handle_input(shift)
    view.mouse_position = Vector2(450, 450)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    assert_almost_eq(_coverage_of(doc, 100, 50), 1.0, 0.001, "Shift on the press adds, so the ellipse stays")
    assert_almost_eq(_coverage_of(doc, 425, 425), 1.0, 0.001, "and the new box joins it")

    view.mouse_position = Vector2(10, 10)
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    assert_false(doc.selection.active, "A click without a drag deselects")
    Fixtures.teardown(surface, machine)


## A freehand lasso closes on release, and the Polygonal Lasso on a click back
## onto its first point.
func test_the_lasso_selects_the_outline() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    machine.set_active_tool(&"lasso")
    var tool := machine.active_tool
    var view := surface.view

    view.mouse_position = Vector2(50, 50)
    tool.handle_input(_button(true))
    for at: Vector2 in [Vector2(250, 50), Vector2(250, 250), Vector2(50, 250)]:
        view.mouse_position = at
        tool.handle_input(InputEventMouseMotion.new())
    assert_eq((tool.preview_shape().get("points") as PackedVector2Array).size(), 4, "The overlay sees the points so far")
    tool.handle_input(_button(false))
    assert_almost_eq(_coverage_of(doc, 150, 150), 1.0, 0.001, "The square lasso holds its middle")
    assert_almost_eq(_coverage_of(doc, 300, 300), 0.0, 0.001, "and not the outside")

    machine.set_active_tool(&"polygonal_lasso")
    tool = machine.active_tool
    for at: Vector2 in [Vector2(300, 300), Vector2(500, 300), Vector2(400, 500)]:
        view.mouse_position = at
        tool.handle_input(_button(true))
        tool.handle_input(_button(false))
    assert_false(tool.preview_shape().get("closed", true), "A polygon waits for its next click")
    view.mouse_position = Vector2(302, 301)
    tool.handle_input(_button(true))
    assert_almost_eq(_coverage_of(doc, 400, 350), 1.0, 0.001, "A click back on the first point closes the triangle")
    assert_almost_eq(_coverage_of(doc, 150, 150), 0.0, 0.001, "which replaced the lasso")
    assert_true(tool.preview_shape().is_empty(), "and the points are spent")
    Fixtures.teardown(surface, machine)


## An outline that encloses nothing used to clear a replace and leave an
## active selection holding no pixel, so the next stroke laid no paint. It now
## leaves the selection as it was and says so once on the route that is not a
## refusal, while a click in replace mode is still the plain deselect.
func test_a_lasso_that_closes_around_no_area_says_so_and_changes_nothing() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    machine.set_active_tool(&"lasso")
    var tool := machine.active_tool
    doc.selection.select_rect(Rect2i(100, 100, 100, 100))

    var two := _said(func() -> void: _drag_lasso(surface, tool, [Vector2(50, 300), Vector2(250, 300)]))
    assert_eq(two.size(), 1, "Two points say one line")
    assert_true(two[0].contains("no area"), "and that the lasso closed around no area: %s" % [two])
    assert_true(two[0].contains("did not change"), "and that the selection stayed")
    assert_true(doc.selection.active, "The selection is still there")
    assert_almost_eq(_coverage_of(doc, 150, 150), 1.0, 0.001, "and still holds its square")

    var line := _said(func() -> void: _drag_lasso(surface, tool, [Vector2(50, 300), Vector2(150, 300), Vector2(250, 300)]))
    assert_eq(line.size(), 1, "Three points on a line say one line")
    assert_true(doc.selection.active, "and leave the selection active")
    assert_almost_eq(_coverage_of(doc, 150, 150), 1.0, 0.001, "holding its square")
    assert_eq(doc.selection.bounds, Rect2i(100, 100, 100, 100), "whose bounds did not move")

    var shift_click := _said(func() -> void: _drag_lasso(surface, tool, [Vector2(400, 400)], true))
    assert_eq(shift_click.size(), 1, "A click that adds holds no area either, and says so")
    assert_almost_eq(_coverage_of(doc, 150, 150), 1.0, 0.001, "with the square kept")

    var sliver := _said(func() -> void: _drag_lasso(surface, tool, [Vector2(300, 300), Vector2(400, 300), Vector2(400, 302)]))
    assert_eq(sliver, [], "A thin triangle of a hundred square pixels is an area and says nothing")
    assert_almost_eq(_coverage_of(doc, 150, 150), 0.0, 0.001, "and it replaced the square")

    doc.selection.select_rect(Rect2i(100, 100, 100, 100))
    var click := _said(func() -> void: _drag_lasso(surface, tool, [Vector2(400, 400)]))
    assert_eq(click, [], "A click in replace mode says nothing")
    assert_false(doc.selection.active, "and deselects, as Krita's does")
    Fixtures.teardown(surface, machine)


## The tool option is a fraction of the smaller dimension, so the pixels a
## pass takes follow the document rather than the number the painter typed.
func test_a_feather_fraction_becomes_the_pixels_of_this_canvas() -> void:
    assert_eq(SaSelectionFilters.feather_radius(0.02, 1080.0), 22, "Two percent of 1080 is 22 pixels")
    assert_eq(
        SaSelectionFilters.feather_radius(0.02, 2160.0),
        43,
        "and the same setting is 43 on the 4K the document was upgraded to, so the softness is the same fraction of it"
    )
    assert_eq(SaSelectionFilters.feather_radius(0.0, 1080.0), 0, "Zero is still a hard edge")
    assert_eq(
        SaSelectionFilters.feather_radius(SaSettings.MAX_SELECTION_FEATHER, 8000.0),
        SaSelectionFilters.MAX_RADIUS,
        "and past the kernel's reach the clamp takes over, which is a limit of the blur and not a preference"
    )


## The three selection tools show one Feather, because the value is the
## setting and not a field on any of them.
func test_the_three_selection_tools_share_one_remembered_feather() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var was := SaSettings.selection_feather

    machine.set_active_tool(&"marquee")
    machine.active_tool.feather = 0.03
    assert_almost_eq(SaSettings.selection_feather, 0.03, 0.0001, "The marquee wrote the setting")
    machine.set_active_tool(&"lasso")
    assert_almost_eq(machine.active_tool.feather, 0.03, 0.0001, "and the lasso reads it back")
    machine.set_active_tool(&"wand")
    assert_almost_eq(machine.active_tool.feather, 0.03, 0.0001, "and so does the wand")

    machine.active_tool.feather = 5.0
    assert_almost_eq(
        SaSettings.selection_feather,
        SaSettings.MAX_SELECTION_FEATHER,
        0.0001,
        "A value past the ceiling is clamped by the setting, so no tool can store one the slider cannot show"
    )

    SaSettings.selection_feather = was
    Fixtures.teardown(surface, machine)


## The same setting on two documents, measured on the mask rather than argued:
## the bounds a marquee grows by are the radius the canvas earned.
func test_the_same_feather_softens_twice_as_far_on_twice_the_canvas() -> void:
    var was := SaSettings.selection_feather
    SaSettings.selection_feather = 0.02
    assert_eq(_marquee_growth(Vector2i(512, 512)), 10, "Two percent of 512 is ten pixels each way")
    assert_eq(_marquee_growth(Vector2i(1024, 1024)), 20, "and twenty on twice the canvas, which is the same softness")
    SaSettings.selection_feather = was


## How far a marquee drag's feather grew the selection past the box, on a
## document of *size*. The box is a quarter of the canvas, centred.
func _marquee_growth(size: Vector2i) -> int:
    var surface := Fixtures.make_surface(size)
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    machine.set_active_tool(&"marquee")
    var tool := machine.active_tool
    var view := surface.view
    @warning_ignore("integer_division")
    var box := Rect2i(size / 4, size / 2)
    view.mouse_position = Vector2(box.position)
    tool.handle_input(_button(true))
    view.mouse_position = Vector2(box.end)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    var grown: int = box.position.x - doc.selection.bounds.position.x
    Fixtures.teardown(surface, machine)
    return grown


## What *action* said on the corner's route, in order.
func _said(action: Callable) -> Array[String]:
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.corner_notice.connect(ear)
    action.call()
    EventBus.corner_notice.disconnect(ear)
    return said


## A freehand lasso drag through *path*, pressed on its first point and released
## on its last, with Shift on the press when *adding*.
func _drag_lasso(surface: SaSurface, tool: ToolState, path: Array, adding: bool = false) -> void:
    var press := _button(true)
    press.shift_pressed = adding
    surface.view.mouse_position = path[0]
    tool.handle_input(press)
    for i in range(1, path.size()):
        surface.view.mouse_position = path[i]
        tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event
