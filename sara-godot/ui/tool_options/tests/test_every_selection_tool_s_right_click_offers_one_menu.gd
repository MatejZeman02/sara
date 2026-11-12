## Every selection tool's right click offers one menu, the same rows in
## the same order, Transform Selection among them, each command dimmed until a
## selection stands for it to act on. A module's tool that makes a selection
## the way the built-in ones do gets the same menu without naming itself
## anywhere, and the Patch, which only acts on a selection, keeps its own.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Transform Selection is the base modules' command, reached by its path
## because no script of the skeleton names a module's class.
const TRANSFORM_SHAPE := "res://modules/sara-base-modules/base/transform/selection/sa_transform_shape.gd"

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

## The rows every selection tool's menu shows, in order.
const ROWS: Array[StringName] = [
    &"selection_mode_0",
    &"selection_mode_1",
    &"selection_mode_2",
    &"selection_mode_3",
    &"feather_option",
    &"cmd_select_transform",
    &"cmd_select_feather",
    &"cmd_select_invert",
    &"cmd_select_none",
    &"cmd_layer_via_copy",
    &"cmd_layer_via_cut",
    &"cmd_layer_via_seamless_cut",
]

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null
var _menu: ToolContextMenu = null
## Held, because the registry keeps only the handlers.
var _menu_commands: SaMenuCommands = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    load(TRANSFORM_SHAPE).register(_registries.context.for_module(&"sara-base-modules"))
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)
    var document := func() -> SaDocument: return _surface.get_document()
    _menu_commands = SaMenuCommands.new(Callable(), Callable(), Callable(), Callable(), document)
    _menu_commands.register_into(_registries.commands)
    _menu = ToolContextMenu.new()
    _menu.bar = _bar
    _menu.commands = _registries.commands


func after_each() -> void:
    _menu.free()
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _menu_commands = null


func _show(tool_id: StringName) -> void:
    _machine.default_tool_name = tool_id
    _machine.set_active_tool(tool_id)
    _menu.rebuild()


## A stranger's selection tool with nothing of the built-in ones' options, as
## Select Subject is: the `select` category, Shift and Alt read on its press,
## and one switch of its own.
func _register_a_stranger() -> void:
    var tool := Fixtures.make_tool_descriptor(&"stranger_select")
    tool.category = &"select"
    tool.reads_keys = [KEY_SHIFT, KEY_ALT]
    tool.options = [SaOptionSpec.make(&"stranger_merged", "Sample merged", SaOptionSpec.Kind.BOOL, {"on_tool": true})]
    _machine.registry.register(tool)
    _machine.register_tool(&"stranger_select", Fixtures.FakeTool.new())


## Every tool the machine holds that makes a selection.
func _selection_tools() -> Array[StringName]:
    var out: Array[StringName] = []
    for tool_id: StringName in _machine.registered_tools:
        if SelectionMenuRows.makes_a_selection(_machine.get_descriptor(tool_id)):
            out.append(tool_id)
    return out


func test_every_selection_tool_shows_the_same_rows_in_the_same_order() -> void:
    _register_a_stranger()
    var tools := _selection_tools()
    for built_in: StringName in [&"marquee", &"ellipse_select", &"lasso", &"polygonal_lasso", &"wand", &"stranger_select"]:
        assert_true(tools.has(built_in), "%s is a selection tool" % built_in)
    assert_false(tools.has(&"patch"), "and the Patch, which only acts on a selection, is not")
    for tool_id: StringName in tools:
        _show(tool_id)
        assert_eq(_menu.row_ids(), ROWS, "%s's menu is the shared rows in their order" % tool_id)
        assert_eq(_menu.section_titles(), ["Selection"], "under the one heading")


func test_a_tool_s_own_switch_stays_off_the_menu() -> void:
    _register_a_stranger()
    for tool_id: StringName in [&"ellipse_select", &"lasso", &"wand", &"stranger_select"]:
        _show(tool_id)
        for row: Dictionary in _menu.option_rows():
            assert_eq(row["key"], SelectionMenuRows.MODE_KEY, "%s's menu offers the mode and no switch of its own" % tool_id)


func test_a_row_the_tool_has_nothing_behind_is_dimmed_and_still_there() -> void:
    _register_a_stranger()
    _show(&"stranger_select")
    assert_true(_menu.is_disabled(&"selection_mode_1"), "A tool with no mode shows Add dimmed")
    assert_true(_menu.is_disabled(ToolContextMenu.FEATHER_ROW), "and a Feather it does not have dimmed")
    _show(&"marquee")
    assert_false(_menu.is_disabled(&"selection_mode_1"), "The Marquee's Add is lit")
    assert_false(_menu.is_disabled(ToolContextMenu.FEATHER_ROW), "and its Feather")


func test_every_command_is_dimmed_until_a_selection_stands() -> void:
    for tool_id: StringName in [&"marquee", &"lasso", &"wand"]:
        _show(tool_id)
        for row_id: StringName in ROWS.slice(5):
            assert_true(_menu.is_disabled(row_id), "%s on %s is dimmed with no selection" % [row_id, tool_id])
    _surface.get_document().selection.select_rect(Rect2i(10, 10, 40, 40))
    for tool_id: StringName in [&"marquee", &"lasso", &"wand"]:
        _show(tool_id)
        for row_id: StringName in ROWS.slice(5):
            assert_false(_menu.is_disabled(row_id), "%s on %s is lit once one stands" % [row_id, tool_id])


func test_a_mode_row_writes_the_tool_s_mode() -> void:
    _show(&"lasso")
    _menu._on_row_chosen(&"selection_mode_1")
    assert_eq(int(_bar.read_option(SelectionMenuRows.MODE_KEY)), SaSelection.Mode.ADD, "Add is the lasso's mode")
    _menu.rebuild()
    assert_true(_menu.is_marked(&"selection_mode_1"), "and the row is marked")


func test_transform_selection_from_the_menu_moves_the_outline_alone_and_enter_hands_back() -> void:
    var document := _surface.get_document()
    document.selection.select_rect(Rect2i(10, 10, 40, 40))
    _show(&"marquee")
    _menu._on_row_chosen(&"cmd_select_transform")
    assert_eq(_machine.default_tool_name, &"transform", "The transform is in hand")
    var tool: Variant = _machine.get_tool(&"transform")
    assert_true(tool.is_moving(), "open on the selection's outline")
    tool.move_x = 30.0
    var enter := InputEventKey.new()
    enter.keycode = KEY_ENTER
    enter.pressed = true
    tool.handle_input(enter)
    assert_eq(_machine.default_tool_name, &"marquee", "Enter puts the Marquee back in hand")
    assert_eq(document.selection.measure_bounds(), Rect2i(40, 10, 40, 40), "and the outline moved 30 px to the right")


## The transform's own rule for a tool picked mid-move, `reset`: the box goes
## back, since a painter who reaches for another tool has not said yes to it.
func test_picking_the_selection_tool_again_puts_it_in_hand_and_the_outline_back() -> void:
    var document := _surface.get_document()
    document.selection.select_rect(Rect2i(10, 10, 40, 40))
    _show(&"lasso")
    _menu._on_row_chosen(&"cmd_select_transform")
    var tool: Variant = _machine.get_tool(&"transform")
    tool.move_y = 20.0
    _machine.set_active_tool(&"lasso")
    assert_eq(_machine.default_tool_name, &"lasso", "The Lasso is in hand again")
    assert_false(tool.is_moving(), "the box is put down")
    assert_eq(document.selection.measure_bounds(), Rect2i(10, 10, 40, 40), "and the outline is where it stood")
