## The transform tool's handles drive the active layer's live transform.
##
## With nothing selected the tool opens on a smart layer's own transform: a
## drag draws the layer through a new map and never touches a texel, Enter puts
## the map as one history step, and Escape draws the one the session opened on.
## A selection keeps the lift that resamples at Enter, and the corner says so.
##
## A layer is smart when it carries a live transform, and
## an ordinary layer's transform bakes at Enter, which
## `core/layers/transform/tests/test_a_transform_bakes_into_the_layer_when_it_is_confirmed.gd`
## reads. So the rig here makes its layer smart with an identity map, the one
## step it writes before a test counts, and a test of an ordinary layer asks
## for one.
##
## The pictures are taken by
## `scenarios/the-transform-tool-s-handles-drive-the-active-layer-s-live-transform.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const CANVAS := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
const STROKE := Rect2i(300, 300, 200, 160)


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


## A surface, its machine and the transform tool on it, over a layer painted
## over `STROKE`, made smart by an identity map unless *smart* is false.
func _rig(smart: bool = true) -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    _paint(document, STROKE)
    if smart:
        SaLiveTransform.put(document, document.active_layer, Basis.IDENTITY)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *rect*, in document pixels, painted on the active layer through an upload.
static func _paint(document: SaDocument, rect: Rect2i) -> void:
    var layer := document.active_layer
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), PAINT)
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())


## Every chunk's colour bytes, by grid position.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


## The alpha of the layer's own texel at *at*, zero where it has no chunk.
static func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var texel := Rect2i(at, Vector2i.ONE)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(texel):
        if not layer.chunks.has(grid_pos):
            return 0.0
        var texture: SaTexture = layer.chunks[grid_pos].albedo()
        var edge: int = layer.chunks[grid_pos].pixel_size()
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), data)
        return image.get_pixelv(SaChunkWalk.local_rect(grid_pos, texel, edge).position).a
    return 0.0


## A press at *from*, a motion to *to* and a release, then the frame's tick.
func _drag(surface: SaSurface, tool: StateTransformScript, from: Vector2, to: Vector2) -> void:
    surface.view.mouse_position = from
    tool.handle_input(_button(true))
    surface.view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    tool.tick(0.0)


## Whether *layer* is drawn where it was painted, under no map or the identity.
static func _unmoved(layer: SaLayer) -> bool:
    var live := SaLiveTransform.of(layer)
    return live == null or live.matrix.is_equal_approx(Basis.IDENTITY)


## Whether the tool's session is a live one, as its capture report says.
func _held(tool: StateTransformScript) -> bool:
    var report: Dictionary = tool.capture_report(&"transform", true).get("transform", {})
    return report.get("live", false)


func _same_texels(before: Dictionary, after: Dictionary, what: String) -> void:
    assert_eq(after.keys().size(), before.keys().size(), "%s: the layer has the chunks it had" % what)
    for grid_pos: Vector2i in before:
        assert_eq(after.get(grid_pos, PackedByteArray()), before[grid_pos], "%s: chunk %s texel for texel" % [what, grid_pos])


## The clause the note is about: a perspective drag with nothing selected
## leaves the layer a perspective map and its chunks as they were painted. The
## drag goes on past the horizon, which the layer's transform refuses, so the
## map drawn last is the one Enter puts.
func test_a_perspective_drag_is_the_layer_s_map_and_no_texel_moves() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var before := _texels(layer)
    var steps := document.history.step_count()

    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    surface.view.mouse_position = Vector2(STROKE.position)
    tool.handle_input(_button(true))
    surface.view.mouse_position = Vector2(STROKE.position) + Vector2(-30, -20)
    tool.handle_input(InputEventMouseMotion.new())
    tool.tick(0.0)
    var drawn: Basis = SaLiveTransform.of(layer).matrix if SaLiveTransform.of(layer) != null else Basis.IDENTITY
    # Pulled in this far the quad's horizon crosses the canvas.
    surface.view.mouse_position = Vector2(STROKE.position) + Vector2(60, 40)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))
    tool.tick(0.0)
    assert_true(tool.is_moving(), "The drag opened a session")
    assert_true(_held(tool), "and the report calls it live")
    assert_not_null(SaLiveTransform.of(layer), "The layer is drawn through the map while the hand moves")
    if SaLiveTransform.of(layer) != null:
        var held := SaLiveTransform.of(layer).matrix.is_equal_approx(drawn)
        assert_true(held, "and a map past the horizon leaves the last one drawn")
    assert_eq(document.history.step_count(), steps, "and no step is written before Enter")

    tool.handle_input(_key(KEY_ENTER))
    assert_false(tool.is_moving(), "Enter ends the session")
    assert_eq(document.history.step_count(), steps + 1, "as one history step")
    var live := SaLiveTransform.of(layer)
    assert_not_null(live, "The layer keeps a live transform")
    if live != null:
        var h := live.floats()
        assert_true(not is_zero_approx(h[6]) or not is_zero_approx(h[7]), "and it is a perspective, %s" % [h])
        var at := live.map_point(Vector2(STROKE.position))
        var wanted := Vector2(STROKE.position) + Vector2(-30, -20)
        assert_almost_eq((at - wanted).length(), 0.0, 1.0, "with the corner where the hand left it, %s" % at)
    _same_texels(before, _texels(layer), "Enter")

    assert_true(document.undo(), "The step undoes")
    assert_true(_unmoved(layer), "back to a layer drawn where it was painted")
    _same_texels(before, _texels(layer), "Undo")
    Fixtures.teardown(surface, parts[1])


## A move and then a scale in one session are still one step, and the map is
## the two composed.
func test_two_gestures_and_enter_are_one_step() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var steps := document.history.step_count()

    var centre := Vector2(STROKE.get_center())
    _drag(surface, tool, centre, centre + Vector2(40, 20))
    var corner := Vector2(STROKE.end) + Vector2(40, 20)
    _drag(surface, tool, corner, corner + Vector2(100, 80))
    assert_eq(document.history.step_count(), steps, "Two gestures write nothing")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(document.history.step_count(), steps + 1, "and Enter writes one step")
    var live := SaLiveTransform.of(layer)
    assert_not_null(live, "The layer is transformed")
    if live != null:
        var landed := live.map_point(Vector2(STROKE.position))
        var off := (landed - (Vector2(STROKE.position) + Vector2(40, 20))).length()
        assert_almost_eq(off, 0.0, 1.0, "The top left corner stayed where the move put it, %s" % landed)
        var far := live.map_point(Vector2(STROKE.end))
        var miss := (far - (corner + Vector2(100, 80))).length()
        assert_almost_eq(miss, 0.0, 1.0, "and the dragged one is under the hand, %s" % far)
    assert_eq(tool.pending_box(), Rect2i(340, 320, 300, 240), "The box stands where the layer is drawn")
    assert_true(document.undo(), "One undo")
    assert_true(_unmoved(layer), "takes both gestures back")
    Fixtures.teardown(surface, parts[1])


## An edge handle and the rotate ring rewrite the layer's map as they go, like
## the body and a corner, and leave its texels as they were painted.
func test_an_edge_and_the_ring_turn_the_layer_s_map() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var before := _texels(layer)
    var steps := document.history.step_count()

    var right := Vector2(STROKE.end.x, STROKE.get_center().y)
    _drag(surface, tool, right, right + Vector2(60, 0))
    var live := SaLiveTransform.of(layer)
    assert_not_null(live, "The edge drew a map")
    if live != null:
        var edge := live.map_point(Vector2(STROKE.end)) - live.map_point(Vector2(STROKE.position))
        assert_almost_eq(edge.x, 260.0, 1.0, "The right edge drew the layer wider, %s" % edge)
        assert_almost_eq(edge.y, 160.0, 1.0, "and no taller")

    var centre := Vector2(STROKE.get_center()) + Vector2(30, 0)
    var ring := Vector2(STROKE.end.x + 60, STROKE.position.y) + Vector2(16, -16)
    var from_centre := ring - centre
    _drag(surface, tool, ring, centre + Vector2(-from_centre.y, from_centre.x))
    live = SaLiveTransform.of(layer)
    assert_not_null(live, "The ring drew a map")
    if live != null:
        var top := live.map_point(Vector2(STROKE.end.x, STROKE.position.y)) - live.map_point(Vector2(STROKE.position))
        assert_true(absf(top.x) < 30.0, "The ring turned the top edge upright, %s" % top)
        assert_true(absf(top.y) > 230.0, "and kept its length")
    assert_eq(document.history.step_count(), steps, "Neither drag wrote a step")
    _same_texels(before, _texels(layer), "Edge and ring")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(document.history.step_count(), steps + 1, "and Enter writes one")
    Fixtures.teardown(surface, parts[1])


## Escape draws the layer at the map the session opened on and writes nothing.
func test_escape_puts_the_transform_back_as_it_was() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var opened: Basis = SaLiveTransform.map_of([1.0, 0.0, 30.0, 0.0, 1.0, -10.0, 0.0, 0.0, 1.0])
    assert_true(SaLiveTransform.put(document, layer, opened), "The layer starts transformed")
    var steps := document.history.step_count()

    var centre := Vector2(STROKE.get_center()) + Vector2(30, -10)
    _drag(surface, tool, centre, centre + Vector2(-90, 50))
    assert_false((SaLiveTransform.of(layer).matrix as Basis).is_equal_approx(opened), "The drag drew a new map")
    tool.handle_input(_key(KEY_ESCAPE))
    assert_false(tool.is_moving(), "Escape ends the session")
    assert_true(SaLiveTransform.of(layer).matrix.is_equal_approx(opened), "and the layer is drawn through the map it had")
    assert_eq(document.history.step_count(), steps, "with nothing written")
    Fixtures.teardown(surface, parts[1])


## A layer that carries a transform shows its handles where the transform put
## them, and dragging them back to the paint takes the transform off.
func test_the_handles_stand_where_the_transform_put_the_layer() -> void:
    var parts := _rig(false)
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var moved: Variant = SaLiveTransform.map_of([1.0, 0.0, 40.0, 0.0, 1.0, 20.0, 0.0, 0.0, 1.0])
    assert_true(SaLiveTransform.put(document, layer, moved), "A moved layer")

    var quad: PackedVector2Array = tool.pending_quad()
    var painted := SaHomography.corners_of(STROKE)
    assert_eq(quad.size(), 4, "The box is a quad")
    for i in quad.size():
        var off := (quad[i] - painted[i] - Vector2(40, 20)).length()
        assert_almost_eq(off, 0.0, 0.01, "Corner %d stands where the transform put it" % i)
    assert_eq(tool.pending_box(), Rect2i(STROKE.position + Vector2i(40, 20), STROKE.size), "and so does the box")
    assert_true(tool.preview_shape().has("quad"), "The overlay is handed the quad")
    assert_almost_eq(tool.move_x, 40.0, 0.01, "and the rows read the layer's map")

    var centre := Vector2(STROKE.get_center()) + Vector2(40, 20)
    _drag(surface, tool, centre, centre - Vector2(40, 20))
    tool.handle_input(_key(KEY_ENTER))
    assert_null(SaLiveTransform.of(layer), "Dragged back onto its paint, the layer is drawn where it was painted")
    assert_true(document.undo(), "and an undo")
    assert_not_null(SaLiveTransform.of(layer), "moves it again")
    Fixtures.teardown(surface, parts[1])


## A selection keeps the lift that resamples at Enter, and the corner says so.
func test_a_selection_is_lifted_and_resampled_as_before() -> void:
    var parts := _rig(false)
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var layer := document.active_layer
    var before := _texels(layer)
    var lines: Array[String] = []
    var heard := func(line: String) -> void: lines.append(line)
    EventBus.corner_notice.connect(heard)

    document.selection.select_rect(Rect2i(300, 300, 100, 100))
    _drag(surface, tool, Vector2(350, 350), Vector2(450, 600))
    assert_false(_held(tool), "A selection is lifted rather than held")
    tool.handle_input(_key(KEY_ENTER))
    EventBus.corner_notice.disconnect(heard)

    assert_null(SaLiveTransform.of(layer), "The layer takes no transform")
    var after := _texels(layer)
    var moved := after.keys().size() != before.keys().size()
    for grid_pos: Vector2i in before:
        moved = moved or after.get(grid_pos, PackedByteArray()) != before[grid_pos]
    assert_true(moved, "and its texels are resampled where the selection went")
    assert_almost_eq(_alpha_at(layer, Vector2i(350, 350)), 0.0, 0.01, "The lift left its place clear")
    assert_almost_eq(_alpha_at(layer, Vector2i(450, 600)), 1.0, 0.01, "and the paint stands where the drag put it")
    assert_almost_eq(_alpha_at(layer, Vector2i(450, 350)), 1.0, 0.01, "while the paint outside the selection stayed")
    var said := lines.any(func(line: String) -> bool: return line.contains("resampled"))
    assert_true(said, "The corner says the selection is resampled, %s" % [lines])
    Fixtures.teardown(surface, parts[1])


## Freehand's mesh is no 3 by 3 map, so Freehand lifts with nothing selected
## and the corner says so.
func test_freehand_lifts_and_says_so() -> void:
    var parts := _rig(false)
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var lines: Array[String] = []
    var heard := func(line: String) -> void: lines.append(line)
    EventBus.corner_notice.connect(heard)

    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    _drag(surface, tool, Vector2(STROKE.get_center()), Vector2(STROKE.get_center()) + Vector2(30, 30))
    EventBus.corner_notice.disconnect(heard)
    assert_true(tool.is_moving(), "Freehand opened a session")
    assert_false(_held(tool), "and it is a lift")
    var said := lines.any(func(line: String) -> bool: return line.begins_with("Freehand"))
    assert_true(said, "The corner names Freehand, %s" % [lines])
    tool.handle_input(_key(KEY_ESCAPE))
    assert_null(SaLiveTransform.of(document.active_layer), "and the layer takes no transform")
    Fixtures.teardown(surface, parts[1])


## Switching to Freehand in a live session puts the map first, since the mesh
## cannot carry it.
func test_freehand_puts_a_live_session_first() -> void:
    var parts := _rig()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    var document := surface.get_document()
    var steps := document.history.step_count()
    _drag(surface, tool, Vector2(STROKE.get_center()), Vector2(STROKE.get_center()) + Vector2(50, 0))
    tool.transform_mode = StateTransformScript.Mode.FREEHAND
    assert_false(tool.is_moving(), "The session ended")
    assert_eq(document.history.step_count(), steps + 1, "as one step")
    assert_not_null(SaLiveTransform.of(document.active_layer), "and the layer keeps the map")
    Fixtures.teardown(surface, parts[1])
