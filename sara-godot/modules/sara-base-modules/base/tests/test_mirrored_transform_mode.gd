## Mirrored, the fifth transform mode: a corner drag moves the diagonally
## opposite corner by the same displacement the other way, a side drag moves
## the opposite side the same way, and what commits is the picture under the
## homography Perspective would build for the same four corners.
##
## Editing a corner point changes the opposite corner point as well. Perspective
## is the other mode that does it, and the last test holds it with Shift held,
## which makes it the one corner.
##
## The pictures are `scenarios/a-transform-mode-where-a-corner-drag-moves-its-opposite-corner-too.json`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

## The selection every gesture is made over: corners (400, 384), (900, 384),
## (900, 784) and (400, 784), so the centre is (650, 584).
const BOX := Rect2i(400, 384, 500, 400)
const CANVAS := Vector2i(1024, 1024)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A document whose active layer carries a picture with no symmetry of its own
## over the box, so two maps that differ anywhere land different texels.
func _tool() -> Array:
    var surface := Fixtures.make_surface(CANVAS)
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    var layer := document.active_layer
    for gy in range(1, 4):
        for gx in range(1, 4):
            var grid_pos := Vector2i(gx, gy)
            var chunk := layer.get_or_create_chunk(grid_pos)
            var texture := chunk.albedo()
            var edge := chunk.pixel_size()
            var image := Image.create_empty(edge, edge, false, _image_format(texture))
            for y in edge:
                for x in edge:
                    var at := Vector2(grid_pos * edge) + Vector2(x, y)
                    image.set_pixel(
                        x, y, Color(fmod(at.x, 97.0) / 97.0, fmod(at.y, 61.0) / 61.0, fmod(at.x + at.y, 43.0) / 43.0, 1.0)
                    )
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
            layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())
    document.selection.select_rect(BOX)
    machine.set_active_tool(&"transform")
    return [surface, machine, machine.active_tool]


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## A press at *from*, a motion to *to* and the release, with Shift on the
## press when *shift*.
func _drag(parts: Array, from: Vector2, to: Vector2, shift: bool = false) -> void:
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    surface.view.mouse_position = from
    var press := _button(true)
    press.shift_pressed = shift
    tool.handle_input(press)
    surface.view.mouse_position = to
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


## Every chunk of the active layer as floats, keyed by its grid position.
func _layer(parts: Array) -> Dictionary:
    var layer: SaLayer = (parts[0] as SaSurface).get_document().active_layer
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), bytes)
        image.convert(Image.FORMAT_RGBAF)
        out[grid_pos] = image
    return out


func _assert_quad(got: PackedVector2Array, wanted: Array, what: String) -> void:
    assert_eq(got.size(), 4, "%s: a quad" % what)
    if got.size() != 4:
        return
    for index in 4:
        assert_almost_eq(
            (got[index] - (wanted[index] as Vector2)).length(), 0.0, 1.0, "%s: corner %d at %s" % [what, index, got[index]]
        )


# --- The gestures -----------------------------------------------------------------


## The top left corner dragged by (40, 30) takes the bottom right by (-40, -30),
## the diagonal through them keeps its midpoint, and the other two stay.
func test_a_corner_drag_moves_the_opposite_corner_the_other_way() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.MIRRORED
    _drag(parts, Vector2(400, 384), Vector2(440, 414))
    var quad: PackedVector2Array = tool.pending_quad()
    _assert_quad(quad, [Vector2(440, 414), Vector2(900, 384), Vector2(860, 754), Vector2(400, 784)], "Mirrored corner")
    if quad.size() == 4:
        assert_almost_eq(((quad[0] + quad[2]) * 0.5 - Vector2(650, 584)).length(), 0.0, 1.0, "The centre held")
    assert_false(tool.preview_shape().has("ants"), "and the map is a homography, as Perspective's is")

    # A second corner, the top right, carries the bottom left and leaves the
    # pair the first drag placed.
    _drag(parts, Vector2(900, 384), Vector2(880, 350))
    _assert_quad(
        tool.pending_quad(), [Vector2(440, 414), Vector2(880, 350), Vector2(860, 754), Vector2(420, 818)], "Second corner"
    )
    Fixtures.teardown(parts[0], parts[1])


## The top side dragged down by 40 takes the bottom side up by 40.
func test_a_side_drag_moves_the_opposite_side_the_other_way() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.MIRRORED
    _drag(parts, Vector2(650, 384), Vector2(650, 424))
    _assert_quad(
        tool.pending_quad(), [Vector2(400, 424), Vector2(900, 424), Vector2(900, 744), Vector2(400, 744)], "Mirrored side"
    )
    Fixtures.teardown(parts[0], parts[1])


## The committed layer is the one Perspective commits for the same quad, placed
## there by two corner drags with Shift, one step in history either way.
func test_the_commit_is_perspectives_homography_for_the_same_quad() -> void:
    var mirrored := _tool()
    var tool: StateTransformScript = mirrored[2]
    var document := (mirrored[0] as SaSurface).get_document()
    var steps_before: int = document.history.step_count()
    tool.transform_mode = StateTransformScript.Mode.MIRRORED
    _drag(mirrored, Vector2(400, 384), Vector2(440, 414))
    assert_true(tool.commit_move(), "Enter commits the mirrored quad")
    assert_eq(document.history.step_count(), steps_before + 1, "as one step")
    var got := _layer(mirrored)

    var perspective := _tool()
    var plain: StateTransformScript = perspective[2]
    plain.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    _drag(perspective, Vector2(400, 384), Vector2(440, 414), true)
    _drag(perspective, Vector2(900, 784), Vector2(860, 754), true)
    _assert_quad(
        plain.pending_quad(), [Vector2(440, 414), Vector2(900, 384), Vector2(860, 754), Vector2(400, 784)], "Perspective"
    )
    assert_true(plain.commit_move(), "Perspective commits the same quad")
    var wanted := _layer(perspective)

    assert_eq(got.keys().size(), wanted.keys().size(), "The same chunks are painted")
    var worst := 0.0
    for grid_pos: Vector2i in wanted:
        if not got.has(grid_pos):
            assert_true(false, "chunk %s is missing" % grid_pos)
            continue
        var a: Image = got[grid_pos]
        var b: Image = wanted[grid_pos]
        for y in a.get_height():
            for x in a.get_width():
                var p := a.get_pixel(x, y)
                var q := b.get_pixel(x, y)
                worst = maxf(worst, maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))))
    assert_almost_eq(worst, 0.0, 1e-3, "and every texel is Perspective's, the worst differing by %f" % worst)
    Fixtures.teardown(mirrored[0], mirrored[1])
    Fixtures.teardown(perspective[0], perspective[1])


## Perspective with Shift still moves the grabbed corner alone, and a side
## there still moves that edge alone, which is where Perspective differs from
## Mirrored. Without Shift its corner takes a neighbour, which another suite reads.
func test_perspective_still_moves_one_corner_and_one_side() -> void:
    var parts := _tool()
    var tool: StateTransformScript = parts[2]
    tool.transform_mode = StateTransformScript.Mode.PERSPECTIVE
    _drag(parts, Vector2(400, 384), Vector2(440, 414), true)
    _assert_quad(
        tool.pending_quad(), [Vector2(440, 414), Vector2(900, 384), Vector2(900, 784), Vector2(400, 784)], "Perspective corner"
    )
    _drag(parts, Vector2(650, 784), Vector2(650, 744))
    _assert_quad(
        tool.pending_quad(), [Vector2(440, 414), Vector2(900, 384), Vector2(900, 744), Vector2(400, 744)], "Perspective side"
    )
    Fixtures.teardown(parts[0], parts[1])


# --- The controls -----------------------------------------------------------------


## The fifth cell of the strip is Mirrored, a press on it picks the mode, and
## leaving the mode drops the corners it placed as leaving Perspective does.
func test_the_strip_has_a_fifth_cell_and_it_picks_mirrored() -> void:
    var parts := _tool()
    var surface: SaSurface = parts[0]
    var tool: StateTransformScript = parts[2]
    assert_eq(SaTransformModeStrip.MODE_COUNT, StateTransformScript.Mode.size(), "One cell per mode")
    var cells := SaTransformModeStrip.boxes(SaHomography.corners_of(BOX), 1.0)
    assert_eq(cells.size(), StateTransformScript.Mode.size(), "one for each mode, Cage the sixth")
    surface.view.mouse_position = cells[4].get_center()
    tool.handle_input(_button(true))
    tool.handle_input(_button(false))
    assert_eq(tool.mode, StateTransformScript.Mode.MIRRORED, "The fifth cell picks Mirrored")
    var glyphs: Array = SaTransformModeStrip.cells(SaHomography.corners_of(BOX), tool.transform_mode, 1.0)
    assert_true(bool((glyphs[4] as Dictionary)["on"]), "and the strip marks it")
    assert_eq(((glyphs[4] as Dictionary)["glyph"] as Array).size(), 2, "drawn as its outline and its diagonal")
    Fixtures.teardown(parts[0], parts[1])
