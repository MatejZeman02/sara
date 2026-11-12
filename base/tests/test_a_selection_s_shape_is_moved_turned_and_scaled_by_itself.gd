## Select > Transform Selection moves, turns and scales the
## selection's outline alone.
##
## A selection of a rotated square has to be possible. The case is a square
## selected and turned by 45 degrees, and each claim is read back as texels, the mask's and the layer's,
## because a
## turned outline and a turned picture under it are the same shot.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const GREY := Color(0.4, 0.4, 0.4, 1.0)
const RED := Color(1.0, 0.0, 0.0, 1.0)
## The square, centred on (256, 256). Turned by 45 degrees it reaches 141
## pixels from its centre along the axes and 100 along the diagonals.
const BOX := Rect2i(156, 156, 200, 200)
const CENTRE := Vector2i(256, 256)
## Inside the old square's top left corner, 135 pixels out along the diagonal,
## so the turned square misses it.
const OLD_CORNER := Vector2i(160, 160)
## Above the old square and inside the turned one's top point.
const NEW_POINT := Vector2i(256, 130)
## A red mark in the old corner, which a lift would have carried away.
const MARK := Rect2i(158, 158, 8, 8)

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _commands: SaCommandRegistry = null
var _module: SaModule = null
var _context: SaContext = null


func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(512, 512))
    _machine = Fixtures.make_bound_machine(_surface)
    _surface.tool_machine = _machine
    # The base module registered on a context that sees this surface, the way
    # the app's registers it, so the command is the module's own.
    _commands = SaCommandRegistry.new()
    var surface := _surface
    _context = SaContext.create(
        SaToolRegistry.new(),
        SaBlendModeRegistry.new(),
        _commands,
        SaLayerTypeRegistry.new(),
        SaUIRegistry.new(),
        null,
        Callable(),
        func() -> Array: return [surface],
        null,
        SaRoleRegistry.new()
    )
    _module = load("res://modules/sara-base-modules/base/module.gd").new()
    _module.register(_context.for_module(_module.get_id()))
    _machine.set_active_tool(&"marquee")
    var document := _surface.get_document()
    document.active_layer.fill(GREY)
    document.selection.select_rect(MARK)
    document.fill_layer(RED)
    document.selection.select_rect(BOX)


func after_each() -> void:
    _module.unregister(_context)
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null
    _commands = null
    _module = null
    _context = null


func _covered(at: Vector2i) -> float:
    var selection := _surface.get_document().selection
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := selection.texture_for(grid)
    if texture == null or not texture.rid.is_valid() or not selection.covers(grid):
        return 0.0
    var local := at - grid * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x).r


func _texel(at: Vector2i) -> Color:
    var document := _surface.get_document()
    var grid := Vector2i(floori(float(at.x) / SaChunk.SIZE), floori(float(at.y) / SaChunk.SIZE))
    var texture := document.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := at - grid * SaChunk.SIZE
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event


## Runs the command and turns the outline by 45 degrees through the tool's row.
func _turned() -> ToolState:
    assert_true(_commands.execute(&"select_transform"), "Select > Transform Selection runs")
    assert_eq(_machine.active_tool_name, &"transform", "and puts the transform tool in hand")
    var tool := _machine.active_tool
    assert_true(tool.call(&"is_moving"), "with a session open")
    var report: Dictionary = tool.call(&"capture_report", &"transform", true)["transform"]
    assert_true(report["selection_only"], "on the outline alone")
    assert_eq(report["target_box"], SaReportShapes.rect(Rect2(BOX)), "round the selection's bounds")
    tool.set(&"angle_degrees", 45.0)
    assert_almost_eq(float(tool.get(&"angle_degrees")), 45.0, 1e-3, "and the row turned it")
    return tool


func test_a_square_turned_by_45_degrees_selects_the_turned_square_over_untouched_paint() -> void:
    var tool := _turned()
    assert_almost_eq(_covered(OLD_CORNER), 1.0, 1e-2, "Nothing is selected anew before Enter")
    assert_true(_texel(MARK.position + Vector2i(2, 2)).is_equal_approx(RED), "and no hole is cut under the mark")
    var steps := _surface.get_document().undo_redo.get_history_count()

    tool.handle_input(_key(KEY_ENTER))
    assert_false(tool.call(&"is_moving"), "Enter ends the session")
    assert_eq(_surface.get_document().undo_redo.get_history_count(), steps + 1, "as one history step")
    assert_eq(_surface.get_document().undo_redo.get_current_action_name(), SaTransformShape.TITLE, "named for the command")
    assert_almost_eq(_covered(CENTRE), 1.0, 1e-2, "The turned square's centre is selected")
    assert_almost_eq(_covered(NEW_POINT), 1.0, 1e-2, "and its top point, above the old square")
    assert_almost_eq(_covered(OLD_CORNER), 0.0, 1e-2, "while the old square's corner is not")
    assert_true(_texel(MARK.position + Vector2i(2, 2)).is_equal_approx(RED), "The mark is where it was painted")
    assert_true(_texel(NEW_POINT).is_equal_approx(GREY), "and the grey under the new outline is untouched")
    assert_true(_texel(Vector2i(300, 300)).is_equal_approx(GREY), "as is the grey inside both")


func test_an_undo_brings_the_old_rectangle_back() -> void:
    var tool := _turned()
    tool.handle_input(_key(KEY_ENTER))
    assert_almost_eq(_covered(OLD_CORNER), 0.0, 1e-2, "The turn landed")

    assert_true(_surface.get_document().undo(), "Undo has the step to take")
    assert_almost_eq(_covered(OLD_CORNER), 1.0, 1e-2, "The old square's corner is selected again")
    assert_almost_eq(_covered(NEW_POINT), 0.0, 1e-2, "and the turned square's point is not")
    assert_eq(_surface.get_document().selection.bounds, BOX, "with the bounds it had")
    assert_true(_texel(MARK.position + Vector2i(2, 2)).is_equal_approx(RED), "and the paint is as it was")


func test_escape_puts_the_selection_back_and_writes_no_step() -> void:
    var tool := _turned()
    var steps := _surface.get_document().undo_redo.get_history_count()
    tool.handle_input(_key(KEY_ESCAPE))
    assert_false(tool.call(&"is_moving"), "Escape ends the session")
    assert_eq(_surface.get_document().undo_redo.get_history_count(), steps, "and writes no step")
    assert_almost_eq(_covered(OLD_CORNER), 1.0, 1e-2, "The selection is the square it was")
    assert_eq(_surface.get_document().selection.bounds, BOX, "at its bounds")
    var report: Dictionary = tool.call(&"capture_report", &"transform", true)["transform"]
    assert_false(report["selection_only"], "and the tool is the free transform again")


func test_a_drag_after_the_command_moves_the_outline_and_not_the_pixels() -> void:
    var tool := _turned()
    tool.set(&"angle_degrees", 0.0)
    tool.set(&"move_x", 150.0)
    tool.set(&"scale_y", 0.5)
    assert_true(tool.call(&"commit_move"), "A move and a squash commit")
    assert_almost_eq(_covered(Vector2i(400, 256)), 1.0, 1e-2, "The outline went right")
    assert_almost_eq(_covered(Vector2i(400, 200)), 0.0, 1e-2, "and was squashed to half its height")
    assert_almost_eq(_covered(OLD_CORNER), 0.0, 1e-2, "and left the old corner")
    assert_true(_texel(MARK.position + Vector2i(2, 2)).is_equal_approx(RED), "while the mark stayed")
    assert_true(_texel(Vector2i(310, 160)).is_equal_approx(GREY), "and nothing landed where the mark would have gone")


func test_the_command_is_on_the_select_menu_and_dims_with_no_selection() -> void:
    var descriptor := _commands.get_descriptor(&"select_transform")
    assert_not_null(descriptor, "The base module registers it")
    if descriptor == null:
        return
    assert_eq(descriptor.category, &"select", "under Select")
    assert_eq(descriptor.menu_label(), "Transform Selection", "in the words the menu uses")
    assert_true(descriptor.is_enabled(), "lit with a selection")
    _surface.get_document().selection.deselect()
    assert_false(descriptor.is_enabled(), "and dimmed without one")
    assert_false(_commands.execute(&"select_transform"), "where a press does nothing")
    assert_eq(_machine.active_tool_name, &"marquee", "and leaves the tool in hand")
