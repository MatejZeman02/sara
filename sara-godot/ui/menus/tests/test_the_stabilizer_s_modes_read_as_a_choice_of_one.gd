## The Tools menu's Stabilizer section is a choice of one: no row carries a box,
## exactly one row wears the mark, the tool's current mode, and a pick moves the
## mark and the tool's setting while the menu stays open.
##
## Rows with check boxes read as three things that can each be on, while only
## one ever is. The press is made the way a pointer makes it, on the row's
## label, and the list is shown first so a pick that closed it would show.
##
## Built on a detached bar with a bound machine, the way `test_tools_menu.gd`
## builds it.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

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


## The Stabilizer rows as the state report reads them, in order.
func _stabilizer_rows(spec: SaOptionSpec) -> Array:
    var out: Array = []
    for row: Dictionary in _menu.popup.row_report():
        for index in spec.choices.size():
            if row["id"] == String(SaToolsMenu.key(SaToolsMenu.STABILIZER_ROW_BASE + index)):
                out.append(row)
    return out


## The labels of the rows that wear the mark.
func _marked(rows: Array) -> Array:
    var out: Array = []
    for row: Dictionary in rows:
        if bool(row["current"]):
            out.append(String(row["label"]))
    return out


func test_no_stabilizer_row_carries_a_box_and_only_the_current_mode_is_marked() -> void:
    var owner := SaToolsMenu.stabilizer_owner(_machine)
    assert_false(owner.is_empty(), "A registered tool declares a stabilizer")
    if owner.is_empty():
        return
    var spec: SaOptionSpec = owner["spec"]
    var rows := _stabilizer_rows(spec)
    assert_eq(rows.size(), spec.choices.size(), "The menu draws a row for every mode")
    for row: Dictionary in rows:
        assert_false(bool(row["checkable"]), "and %s carries no box" % row["label"])
    var current: Variant = ToolOptionControls.read_spec(spec, owner["tool"])
    var expected := ""
    for choice: Dictionary in spec.choices:
        if choice["id"] == current:
            expected = String(choice["label"])
    assert_eq(_marked(rows), [expected], "and the tool's own mode is the one row marked chosen")


func test_a_pick_moves_the_mark_and_the_setting_and_leaves_the_menu_open() -> void:
    var owner := SaToolsMenu.stabilizer_owner(_machine)
    assert_false(owner.is_empty(), "A registered tool declares a stabilizer")
    if owner.is_empty():
        return
    var spec: SaOptionSpec = owner["spec"]
    var before: Variant = ToolOptionControls.read_spec(spec, owner["tool"])
    var picked := 0 if spec.choices[1]["id"] == before else 1
    var row_key := SaToolsMenu.key(SaToolsMenu.STABILIZER_ROW_BASE + picked)
    _menu.popup.visible = true
    assert_true(_menu.popup.press_row(row_key), "The picked row takes a press")
    assert_eq(ToolOptionControls.read_spec(spec, owner["tool"]), spec.choices[picked]["id"], "The mode reached the tool")
    var label := String(spec.choices[picked]["label"])
    assert_eq(_marked(_stabilizer_rows(spec)), [label], "and the mark moved to that row and off every other")
    assert_true(_menu.popup.visible, "and the menu is still open")
    assert_true(_menu.is_choice_marked(SaToolsMenu.STABILIZER_ROW_BASE + picked), "and the menu says so itself")
