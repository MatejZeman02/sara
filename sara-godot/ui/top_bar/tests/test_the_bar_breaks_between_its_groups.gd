## The bar draws a break between its brush, stroke and view
## controls, and the rotation says what it turns.
##
## Without breaks the bar reads as one run of buttons that look alike, menus,
## brush options, the rotation and the stroke switches in one row with one
## separator, and the rotation as a chip that says 0 ° and nothing else. A group is
## declared by what owns the element, `SaOptionSpec.bar_group` for a tool's
## option and the element tables for the bar's own, and `SaTopBarRows` draws a
## gap and a rule between two shown neighbours whose groups differ.
##
## Built detached and `_ready()`ed by hand, the way `test_top_bar_rows.gd` does,
## on a bar wide enough that nothing goes to the overflow, so the order read is
## the shipped one whole. The running app at 1920 by 1080 and at 1280 by 800 is
## `scenarios/the-bar-groups-brush-stroke-and-view-and-names-the-rotation.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar's controls come from the tools' descriptors, and a machine with the
## built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

## Wide enough for every shown control of the shipped order on one row.
const ROOMY := 4000.0

const FIXTURE_TOOL := &"n115_fixture_tool"
const FIXTURE_ROW := "n115_fixture_row"

static var scratch_profile: String = SaDataRoot.path("test_n115_bar_groups.cfg")

var _saved_path: String = ""
var _saved_row: bool = false
var _row_saved: bool = false
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _bar: TopMenuBar = null


func before_each() -> void:
    if not _row_saved:
        _saved_row = SaSettings.second_row
        _row_saved = true
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    SaSettings.second_row = false


func after_each() -> void:
    if _bar != null:
        _bar.free()
        _bar = null
    if _machine != null and _machine.registry != null and _machine.registry.has(FIXTURE_TOOL):
        _machine.registry.unregister(FIXTURE_TOOL)
    SaSettings.unregister_layout_element("TopMenuBar", FIXTURE_ROW)
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    SaSettings.second_row = _saved_row
    if _machine != null:
        Fixtures.teardown(_surface, _machine)
        _surface = null
        _machine = null


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## A bar with its tool options, the way main builds them, detached and laid out
## at *width*. The anchors are pinned together for the reason
## `test_top_bar_rows.gd` gives, so the width written is the width that stays.
func _build(width: float = ROOMY) -> TopMenuBar:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    _bar = TopMenuBar.new()
    var options := ToolOptionsBar.new()
    options.target_tool_machine = _machine
    options._ready()
    _bar.add_tool_options(options)
    _bar._ready()
    _bar.set_anchor(SIDE_RIGHT, 0.0)
    _bar.size.x = width
    _bar.apply_layout_settings()
    return _bar


## The elements row 1 shows, in order, each with its group.
func _shown(rows: SaTopBarRows) -> Array:
    var element_of := {}
    var elements := rows.elements()
    for element: String in elements:
        element_of[elements[element]] = element
    var groups := rows.groups()
    var out: Array = []
    for child in rows.row_container(1).get_children():
        var node := child as Control
        if node != null and node.visible and element_of.has(node):
            out.append([element_of[node], String(groups.get(element_of[node], &""))])
    return out


## Each break as "left|right", the two elements it stands between.
func _between(rows: SaTopBarRows) -> Array[String]:
    var out: Array[String] = []
    for entry: Dictionary in rows.breaks_report(1):
        out.append("%s|%s" % [entry.get("after", ""), entry.get("before", "")])
    return out


## On the shipped order a break sits after the last brush control and before
## the first stroke control, and one sits wherever two shown neighbours'
## groups differ and are both set, and nowhere else.
func test_a_break_sits_between_the_brush_and_the_stroke_on_the_shipped_order() -> void:
    var rows := _build().rows
    var shown := _shown(rows)
    assert_false(rows.overflow.visible, "The bar is wide enough that nothing went to the overflow")
    var first_stroke := -1
    for index in shown.size():
        if shown[index][1] == String(SaOptionSpec.BAR_GROUP_STROKE):
            first_stroke = index
            break
    assert_true(first_stroke > 0, "The shipped order shows a stroke control after something: %s" % [shown])
    var last_brush := -1
    for index in first_stroke:
        if shown[index][1] == String(SaOptionSpec.BAR_GROUP_BRUSH):
            last_brush = index
    assert_true(last_brush >= 0, "and a brush control before it")
    var between := _between(rows)
    var spans := 0
    for index in range(last_brush, first_stroke):
        if between.has("%s|%s" % [shown[index][0], shown[index + 1][0]]):
            spans += 1
    assert_true(
        spans > 0,
        "A break sits between %s and %s: %s" % [shown[last_brush][0], shown[first_stroke][0], between],
    )

    var expected: Array[String] = []
    for index in range(1, shown.size()):
        var left: String = shown[index - 1][1]
        var right: String = shown[index][1]
        if left != right and not left.is_empty() and not right.is_empty():
            expected.append("%s|%s" % [shown[index - 1][0], shown[index][0]])
    assert_eq(between, expected, "A break stands between every two neighbours whose groups differ, and nowhere else")
    assert_true(
        between.has("radius|Double Resolution") and between.has("Reset Rotation|Mirror H"),
        "The view's three are broken off from the brush before it and the stroke after it: %s" % [between],
    )
    assert_true(
        rows.row_container(1).get_child(0) == rows.elements()[ToolOptionsBar.ELEMENT_PRESETS],
        "and the row opens on a control, never on a break",
    )


## Two neighbours whose groups differ with nothing between them: the pressure
## toggles, which a fresh bar hides, shown after Radius.
func test_a_shown_pressure_toggle_breaks_from_the_brush_before_it() -> void:
    SaSettings.set_element_visible("TopMenuBar", "size_by_pressure", true)
    var rows := _build().rows
    var between := _between(rows)
    assert_true(between.has("radius|size_by_pressure"), "Radius and the stroke's toggle are broken apart: %s" % [between])
    assert_false(between.has("radius|Double Resolution"), "and the break before the view moved with the toggle")
    assert_true(between.has("size_by_pressure|Double Resolution"), "to after it, where the stroke meets the view")


## A module's option that names no group draws no break on either side of it,
## so one between the brush and the view takes the break there away.
func test_a_module_option_with_no_group_draws_none() -> void:
    _register_fixture(&"")
    var rows := _build().rows
    assert_not_null(rows.elements().get(FIXTURE_ROW), "The fixture's option is on the bar")
    assert_true(rows.elements()[FIXTURE_ROW].visible, "and shown")
    for entry: String in _between(rows):
        assert_false(entry.split("|").has(FIXTURE_ROW), "No break stands beside the ungrouped option: %s" % entry)
    assert_false(_between(rows).has("radius|Double Resolution"), "so the brush and the view meet across it with none")


## The same option naming the brush's group joins it, through the door a module
## uses, and the break moves to after it.
func test_a_module_option_joins_a_group_it_names() -> void:
    _register_fixture(SaOptionSpec.BAR_GROUP_BRUSH)
    var between := _between(_build().rows)
    assert_false(between.has("radius|%s" % FIXTURE_ROW), "The option sits in the brush's group with no break before it")
    assert_true(between.has("%s|Double Resolution" % FIXTURE_ROW), "and the break to the view follows it: %s" % [between])


## A tool of a module that is not the base one, painting so its option has a
## place on the bar whatever tool is chosen, with one row after Radius in
## *group*.
func _register_fixture(group: StringName) -> void:
    if _machine == null:
        _surface = Fixtures.make_surface()
        _machine = Fixtures.make_bound_machine(_surface)
    var descriptor := Fixtures.make_tool_descriptor(FIXTURE_TOOL)
    descriptor.display_name = "Group Fixture"
    descriptor.is_painting = true
    var row := SaOptionSpec.make(StringName(FIXTURE_ROW), "Fixture", SaOptionSpec.Kind.BOOL)
    row.on_tool = true
    # After Radius, the brush's last row on a fresh bar, which sits to the right
    # of Opacity with no Flat or Environment button, so the view's group opens on Rotation.
    row.bar_after = "radius"
    row.bar_group = group
    descriptor.options = [row]
    assert_true(_machine.registry.register(descriptor, &"n115-fixture-module"), "The fixture tool registers")


## The rotation says what it turns: the icon set has no rotate icon, so the
## word goes ahead of the angle, and the pair sits in the view's group.
func test_the_rotation_reads_rotate_ahead_of_its_angle() -> void:
    var bar := _build()
    var slider := bar.rotation_row.slider
    assert_null(SaUI.get_icon("rotate"), "The shipped icon set has no rotate icon, which is why it is the word")
    assert_eq(slider.prefix, "Rotate: ", "The slider's label opens on the word")
    assert_eq(slider._label.text, "Rotate: 0 °", "and reads it ahead of the angle")
    assert_eq(bar.rows.groups().get(SaTopBarRotation.ELEMENT_SLIDER), SaOptionSpec.BAR_GROUP_VIEW, "in the view's group")
    assert_eq(bar.rows.groups().get(SaTopBarRotation.ELEMENT_RESET), SaOptionSpec.BAR_GROUP_VIEW, "with its reset")


## A break is a child of the row, so the row's spend counts it and the overflow
## cuts against it: a row with room shows them, and a row too short for even
## the brush's controls shows none.
func test_a_break_costs_its_row_and_leaves_with_its_reason() -> void:
    var rows := _build().rows
    var breaks := rows.breaks_report(1)
    assert_true(breaks.size() > 0, "A roomy row draws its breaks")
    var with_breaks := rows.row_spent(1)
    var rule := rows.row_container(1).get_node(NodePath(SaTopBarRows.BREAK_NAME + "0")) as Control
    var rule_width := rule.get_combined_minimum_size().x
    assert_true(rule_width > 0.0, "and each takes room: %d" % int(rule_width))
    _bar.size.x = 1280.0
    _bar.apply_layout_settings()
    for entry: Dictionary in rows.breaks_report(1):
        assert_true(entry.has("before"), "No break is left at the row's end once its neighbour left: %s" % [entry])
    assert_true(rows.row_spent(1) <= rows.row_budget(1), "and the short row fits its budget, breaks and all")
    assert_true(rows.row_spent(1) < with_breaks, "having given up controls and their breaks to the overflow")
