## The canvas right-click menu of every tool with a selection Feather
## offers two rows under a Selection heading, the tool's own Feather and
## Select > Feather..., the second greyed until there is a selection, and the
## first writing through the bar. A tool without a Feather offers neither.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null
var _menu: ToolContextMenu = null
## Held, because the registry keeps only the handlers and a Callable does not
## keep its object alive.
var _menu_commands: SaMenuCommands = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
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


func test_every_tool_with_a_feather_offers_both_rows_under_the_selection_heading() -> void:
    for tool_id: StringName in [&"marquee", &"ellipse_select", &"lasso", &"polygonal_lasso", &"wand"]:
        _show(tool_id)
        assert_true(_menu.row_ids().has(ToolContextMenu.FEATHER_ROW), "%s's menu has its own Feather" % tool_id)
        assert_true(_menu.command_rows().has(&"select_feather"), "and Feather...")
        assert_true(_menu.section_titles().has("Selection"), "under the Selection heading")
        assert_true(_menu.is_disabled(&"cmd_select_feather"), "Feather... is greyed with no selection")


func test_the_brush_and_the_eyedropper_offer_neither() -> void:
    for tool_id: StringName in [&"brush", &"eyedropper"]:
        _show(tool_id)
        assert_false(_menu.row_ids().has(ToolContextMenu.FEATHER_ROW), "%s's menu has no Feather row" % tool_id)
        assert_false(_menu.command_rows().has(&"select_feather"), "and no Feather...")


func test_feather_lights_once_a_selection_stands() -> void:
    _show(&"marquee")
    assert_true(_menu.is_disabled(&"cmd_select_feather"), "Greyed before a selection")
    _surface.get_document().selection.select_rect(Rect2i(10, 10, 40, 40))
    _menu.rebuild()
    assert_false(_menu.is_disabled(&"cmd_select_feather"), "and lit once one stands")


func test_the_row_writes_the_tool_s_feather_in_pixels_and_reads_it_back() -> void:
    _show(&"marquee")
    _menu.write_feather_pixels(6)
    assert_eq(_menu.feather_pixels(), 6, "The row reads the 6 px it wrote")
    _menu.rebuild()
    assert_true(_menu.row_labels().has("Feather for the next selection: 6 px..."), "and says so on its label")
    var unit := _bar.canvas_min_dimension()
    assert_almost_eq(float(_bar.read_option(SelectionMenuRows.FEATHER_KEY)), 6.0 / unit, 0.0001, "through the bar")
