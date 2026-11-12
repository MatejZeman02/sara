## The Transform tool's Flip buttons mirror what is in the box.
##
## Before them the only flip was a handle dragged through the opposite edge or
## a width typed as minus a hundred. The buttons multiply the map by minus one
## on one axis about the box's centre, so the box stays put, the picture inside
## it is mirrored, and with a selection only what it holds moves. Read back as
## texels, because a mirrored square and a square are the same shot.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")
const StateTransformScript = preload("res://modules/sara-base-modules/base/transform/state_transform.gd")

const GREY := Color(0.4, 0.4, 0.4, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## The selection, and the mark near its left edge that tells left from right.
const BOX := Rect2i(100, 100, 100, 100)
const MARK := Rect2i(110, 110, 8, 8)


func _tool_on(surface: SaSurface) -> Array:
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    return [machine, machine.active_tool]


func _texel(document: SaDocument, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := document.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A grey layer with a red mark inside the box, and the box selected.
func _painted(document: SaDocument) -> void:
    document.active_layer.fill(GREY)
    document.selection.select_rect(MARK)
    document.fill_layer(RED)
    document.selection.select_rect(BOX)


func test_the_flip_buttons_are_options_of_the_tool() -> void:
    var descriptor := Fixtures.make_tool_registry().get_descriptor(&"transform")
    var found: Dictionary = {}
    for spec: SaOptionSpec in descriptor.options:
        found[spec.key] = spec
    for key: StringName in [&"transform_flip_horizontal", &"transform_flip_vertical"]:
        assert_true(found.has(key), "%s is a row" % key)
        if found.has(key):
            var spec: SaOptionSpec = found[key]
            assert_eq(spec.kind, SaOptionSpec.Kind.ACTION, "and a button")
            assert_false(spec.tooltip.is_empty(), "that says what it does")


func test_a_flip_mirrors_what_the_selection_holds_and_leaves_the_rest() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    var document := surface.get_document()
    _painted(document)

    tool.call("flip_horizontal")
    assert_true(tool.is_moving(), "The button lifts the selection, as a typed row does")
    var quad: PackedVector2Array = tool.call("pending_quad")
    for corner: Vector2 in [Vector2(100, 100), Vector2(200, 100), Vector2(200, 200), Vector2(100, 200)]:
        var kept := Array(quad).any(func(point: Vector2) -> bool: return point.distance_to(corner) < 0.01)
        assert_true(kept, "and the box stays where it was, corner %s" % corner)
    assert_true(tool.commit_move(), "Apply writes it down")

    # The mark's column 114 mirrors about the box's middle, 150, to 185.
    assert_true(_texel(document, Vector2i(185, 114)).is_equal_approx(RED), "The mark is on the right of the box now")
    assert_true(_texel(document, Vector2i(114, 114)).is_equal_approx(GREY), "and gone from the left")
    assert_true(_texel(document, Vector2i(50, 50)).is_equal_approx(GREY), "while outside the selection nothing moved")
    assert_true(document.selection.active, "and the selection is still there")
    Fixtures.teardown(surface, machine)


func test_a_vertical_flip_mirrors_top_to_bottom() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    var document := surface.get_document()
    _painted(document)

    tool.call("flip_vertical")
    assert_true(tool.commit_move(), "The flip is written down")
    assert_true(_texel(document, Vector2i(114, 185)).is_equal_approx(RED), "The mark is at the bottom of the box")
    assert_true(_texel(document, Vector2i(114, 114)).is_equal_approx(GREY), "and gone from the top")
    Fixtures.teardown(surface, machine)


func test_two_flips_in_the_air_are_no_move_at_all() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    _painted(surface.get_document())

    tool.call("flip_horizontal")
    assert_almost_eq(tool.scale_x * tool.scale_y, -1.0, 1e-4, "One flip reads as a mirrored map in the rows")
    tool.call("flip_horizontal")
    assert_true(tool.get("matrix").is_equal_approx(Transform2D.IDENTITY), "and a second one undoes it in the air")
    tool.set("angle_degrees", 30.0)
    var turned: PackedVector2Array = tool.call("pending_quad")
    tool.call("flip_vertical")
    assert_almost_eq(tool.angle_degrees, 30.0, 1e-2, "A turned picture flips along its own axis and stays turned")
    var flipped: PackedVector2Array = tool.call("pending_quad")
    for corner: Vector2 in turned:
        var kept := Array(flipped).any(func(point: Vector2) -> bool: return point.distance_to(corner) < 0.01)
        assert_true(kept, "and its box stays where it stood, corner %s" % corner)
    Fixtures.teardown(surface, machine)


## Perspective and Mirrored hold four corners and Freehand nine points rather
## than a matrix, so a flip there is the same points read in mirrored order. A
## small drag first gives each mode its points, the top left corner in the two
## and the middle of the grid in the third, and the mark still lands on the
## right.
func test_a_flip_in_perspective_and_freehand_mirrors_their_points() -> void:
    var grabs: Dictionary = {
        StateTransformScript.Mode.PERSPECTIVE: [Vector2(100, 100), Vector2(103, 102)],
        StateTransformScript.Mode.MIRRORED: [Vector2(100, 100), Vector2(103, 102)],
        StateTransformScript.Mode.FREEHAND: [Vector2(150, 150), Vector2(152, 151)],
    }
    for which: int in grabs:
        var surface := Fixtures.make_surface(Vector2i(512, 512))
        var built := _tool_on(surface)
        var machine: ToolMachine = built[0]
        var tool: StateTransformScript = built[1]
        var document := surface.get_document()
        _painted(document)
        tool.transform_mode = which
        var grab: Array = grabs[which]
        surface.view.mouse_position = grab[0]
        tool.handle_input(_button(true))
        surface.view.mouse_position = grab[1]
        tool.handle_input(InputEventMouseMotion.new())
        tool.handle_input(_button(false))
        var dragged := tool.pending_quad()

        tool.flip_horizontal()
        assert_eq(tool.transform_mode, which, "The flip keeps mode %d" % which)
        var flipped := tool.pending_quad()
        for corner: Vector2 in dragged:
            var kept := Array(flipped).any(func(point: Vector2) -> bool: return point.distance_to(corner) < 0.01)
            assert_true(kept, "and the box stays where the drag left it, corner %s" % corner)
        assert_true(tool.commit_move(), "Apply writes it down")
        assert_true(_texel(document, Vector2i(186, 114)).is_equal_approx(RED), "The mark crossed to the right in mode %d" % which)
        assert_true(_texel(document, Vector2i(114, 114)).is_equal_approx(GREY), "and left the left")
        Fixtures.teardown(surface, machine)
