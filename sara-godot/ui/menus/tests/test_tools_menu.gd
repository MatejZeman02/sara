## The Tools menu lists every registered tool with its chord, and switches
## the stabilizer the Tool Options docker shows.
##
## Tools are reachable by chord or by the toolbox, and a painter who does not
## know the letters would have the toolbox and nothing else.
##
## The menu is built on a detached bar and handed a bound machine, the way
## `test_menu_module_names.gd` builds its bar: a popup is a `Window`, and a bar in
## the tree hangs a headless run. What is asserted is one row per registered tool, a chord where the
## tool's action carries one, and a tool a module registers arriving without an edit to the menu's own
## file, plus the two presses the scenario makes on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## The five permanent tool switches this suite names. Every tool's chord comes
## off its own descriptor through the generic loop, and this suite's claim is
## about exactly these five actions -> tool id.
const FIVE_TOOL_ACTIONS: Dictionary = {
    "tool_brush": "brush",
    "tool_bucket_fill": "bucket_fill",
    "tool_eyedropper": "eyedropper",
    "tool_pan": "pan",
    "tool_zoom": "zoom",
}

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: TopMenuBar = null
var _menu: SaToolsMenu = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _bar = TopMenuBar.new()
    _bar._ready()
    _menu = _bar.menu("Tools") as SaToolsMenu
    if _menu != null:
        _menu.machine = _machine
        _menu.populate()


func after_each() -> void:
    _menu = null
    if _bar != null:
        _bar.free()
        _bar = null
    Fixtures.teardown(_surface, _machine)
    _surface = null
    _machine = null


func _rows() -> Array:
    return _menu.popup.row_report()


func test_the_bar_has_a_tools_menu() -> void:
    assert_not_null(_menu, "The top bar builds a Tools menu")
    assert_true(TopMenuBar.MENU_NAMES.has("Tools"), "named among the bar's menus")
    assert_true(SaSettingsLayout.DEFAULT_ORDERS["TopMenuBar"].has("Tools"), "and in the bar's default order")


func test_one_row_per_registered_tool() -> void:
    var registered := _machine.registry.list_tools()
    assert_true(registered.size() > 5, "The fixture machine carries more than five tools: %d" % registered.size())
    var labels := {}
    for row: Dictionary in _rows():
        labels[String(row["label"])] = true
    for descriptor: SaToolDescriptor in registered:
        var name := descriptor.display_name if not descriptor.display_name.is_empty() else String(descriptor.id).capitalize()
        assert_true(labels.has(name), "'%s' has a row" % name)


func test_each_tool_with_keys_shows_them() -> void:
    var hints := {}
    for row: Dictionary in _rows():
        hints[String(row["label"])] = String(row["hint"])
    var shown := 0
    for descriptor: SaToolDescriptor in _machine.registry.list_tools():
        var chord := SaToolsMenu.chord_for(descriptor)
        var name := descriptor.display_name if not descriptor.display_name.is_empty() else String(descriptor.id).capitalize()
        assert_eq(hints.get(name, "<no row>"), chord, "'%s' shows the keys its action has: '%s'" % [name, chord])
        if not chord.is_empty():
            shown += 1
    assert_true(shown >= 5, "At least the five tool switches the router names carry a chord: %d do" % shown)


## A chord is printed for each of the five that have one, and the five are not
## all five with a key. `tool_zoom` and `tool_bucket_fill` ship with an empty
## event list in `project.godot`, the fill's Shift+G having become the fill
## family's step, so on a default profile neither tool has a chord to print and
## its row shows none. What this asserts is the rule rather than a count: each
## of the five shows exactly what its action carries, and the ones that carry
## keys show them.
func test_the_five_permanent_switches_show_the_chord_their_action_carries() -> void:
    var with_keys := 0
    for action: String in FIVE_TOOL_ACTIONS:
        var tool_id := StringName(FIVE_TOOL_ACTIONS[action])
        var descriptor := _machine.get_descriptor(tool_id)
        assert_not_null(descriptor, "'%s' is registered" % tool_id)
        if descriptor == null:
            continue
        var carried := SaCommandRegistry.format_events(InputMap.action_get_events(StringName(action)), 1)
        assert_eq(SaToolsMenu.chord_for(descriptor), carried, "'%s' shows what %s carries: '%s'" % [tool_id, action, carried])
        if not carried.is_empty():
            with_keys += 1
    assert_eq(with_keys, 3, "Three of the five carry a key on a default profile, and the fill and zoom are the two that do not")


## The claim that makes this a registry menu rather than a list: a tool that did
## not exist when the menu was written is in it the next time it opens.
func test_a_module_tool_arrives_without_editing_the_menu() -> void:
    var descriptor := SaToolDescriptor.new()
    descriptor.id = &"g5_fixture_tool"
    descriptor.display_name = "G5 Fixture Tool"
    # A descriptor needs a script to be valid, which is what a module hands over,
    # and the registry refuses one without it.
    descriptor.tool_script = Fixtures.FakeTool
    assert_true(_machine.registry.register(descriptor, &"g5-fixture-module"), "The fixture tool registers")
    _menu.populate()
    var found := false
    for row: Dictionary in _rows():
        if String(row["label"]) == "G5 Fixture Tool":
            found = true
    assert_true(found, "A tool registered after the menu was built has a row on the next open")
    _machine.registry.unregister(&"g5_fixture_tool")
    _menu.populate()
    var gone := true
    for row: Dictionary in _rows():
        if String(row["label"]) == "G5 Fixture Tool":
            gone = false
    assert_true(gone, "and leaves with its tool")


func test_choosing_a_tool_makes_it_the_active_one() -> void:
    var target: StringName = &"eyedropper"
    var row_id := -1
    var index := 0
    for descriptor: SaToolDescriptor in _machine.registry.list_tools():
        if descriptor.id == target:
            row_id = SaToolsMenu.TOOL_ROW_BASE + index
        index += 1
    assert_true(row_id >= 0, "The eyedropper has a row")
    _menu.on_id_pressed(row_id)
    assert_eq(_machine.default_tool_name, target, "and pressing it switches the machine to it")


func test_a_stabilizer_row_writes_the_setting_the_docker_shows() -> void:
    var owner := SaToolsMenu.stabilizer_owner(_machine)
    assert_false(owner.is_empty(), "A registered tool declares a stabilizer")
    if owner.is_empty():
        return
    var spec: SaOptionSpec = owner["spec"]
    var moved := [0]
    var count_moves := func() -> void: moved[0] += 1
    EventBus.tool_options_moved.connect(count_moves)
    _menu.on_id_pressed(SaToolsMenu.STABILIZER_ROW_BASE + 2)
    EventBus.tool_options_moved.disconnect(count_moves)
    assert_eq(ToolOptionControls.read_spec(spec, owner["tool"]), spec.choices[2]["id"], "The third mode is on the tool")
    assert_eq(moved[0], 1, "and the docker and the bar are told once")
    _menu.populate()
    var marked: Array = []
    for row: Dictionary in _rows():
        if bool(row["current"]):
            marked.append(String(row["label"]))
    assert_eq(marked, [String(spec.choices[2]["label"])], "and the menu marks that mode and no other")


## `owner_of`'s rule, from the menu's side: with the eyedropper active the rows
## still move the brush's stabilizer, which is the one the bar shows.
func test_the_stabilizer_follows_the_brush_while_another_tool_is_active() -> void:
    _machine.set_active_tool(&"eyedropper")
    var owner := SaToolsMenu.stabilizer_owner(_machine)
    assert_false(owner.is_empty(), "The menu still finds a stabilizer")
    if not owner.is_empty():
        assert_eq(owner["id"], &"brush", "and it is the brush's")
