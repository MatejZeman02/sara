## The top bar's Wrap is one icon whose edges and middle choose the wrap,
## which is Page Edges, whose middle steps through Grows as well. Real
## presses on the left column, the top row, a corner, the right column, the
## bottom row and the middle, from each of the four modes, leave the mode the
## region names, a hover over each region says what its press does, and there
## is no arrow or menu.
extends "res://tests/test_framework.gd"

const FIXED := SaTopBarPageEdges.Mode.FIXED
const GROWS := SaTopBarPageEdges.Mode.GROWS
const SIDES := SaTopBarPageEdges.Mode.WRAPS_SIDES
const ALL := SaTopBarPageEdges.Mode.WRAPS_ALL

## Each region the wrap distinguishes, as the column and row of the grid of nine the
## press lands on.
const REGIONS := {
    "the left column": Vector2i(0, 1),
    "the top row": Vector2i(1, 0),
    "the top left corner": Vector2i(0, 0),
    "the bottom right corner": Vector2i(2, 2),
    "the right column": Vector2i(2, 1),
    "the bottom row": Vector2i(1, 2),
    "the middle": Vector2i(1, 1),
}

## The expected modes, written out: from each mode, what a press on each region leaves.
const RULED := {
    FIXED:
    {
        "the left column": SIDES,
        "the top row": ALL,
        "the top left corner": ALL,
        "the bottom right corner": ALL,
        "the right column": SIDES,
        "the bottom row": ALL,
        "the middle": GROWS,
    },
    GROWS:
    {
        "the left column": SIDES,
        "the top row": ALL,
        "the top left corner": ALL,
        "the bottom right corner": ALL,
        "the right column": SIDES,
        "the bottom row": ALL,
        "the middle": SIDES,
    },
    SIDES:
    {
        "the left column": FIXED,
        "the top row": ALL,
        "the top left corner": ALL,
        "the bottom right corner": ALL,
        "the right column": FIXED,
        "the bottom row": ALL,
        "the middle": ALL,
    },
    ALL:
    {
        "the left column": SIDES,
        "the top row": FIXED,
        "the top left corner": FIXED,
        "the bottom right corner": FIXED,
        "the right column": SIDES,
        "the bottom row": FIXED,
        "the middle": FIXED,
    },
}

var _viewport: SubViewport = null
var _host: Control = null
var _doc: SaDocument = null
var _button: Button = null
var _was_placeable: bool = false


func before_each() -> void:
    _was_placeable = SaSettings.is_placeable(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    _doc = SaDocument.new()
    _host = Control.new()
    _host.name = "U582WrapHost"
    _host.size = Vector2(400, 200)
    _viewport = SubViewport.new()
    _viewport.size = Vector2i(400, 200)
    _viewport.add_child(_host)
    EventBus.add_child(_viewport)
    # A viewport the pointer never entered sends a motion to no control, which
    # is what a hover needs, so the pointer is said to be over it.
    _viewport.notification(Viewport.NOTIFICATION_VP_MOUSE_ENTER)
    _button = SaTopBarPageEdges.home(_host, func() -> SaDocument: return _doc)[SaTopBarPageEdges.ELEMENT] as Button
    _button.position = Vector2(100, 60)
    _button.size = Vector2(44, 44)


func after_each() -> void:
    if _was_placeable:
        SaTopBarPageEdges.register()
    else:
        SaSettings.unregister_layout_element(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    if _viewport != null:
        _viewport.free()
    _viewport = null
    _host = null
    _button = null
    if _doc != null:
        _doc.free()
        _doc = null


## The middle of *cell* of the grid of nine, in the viewport's space.
func _point(cell: Vector2i) -> Vector2:
    var grid := SaTopBarPageEdges.follower_of(_button).grid_rect()
    return _button.get_global_rect().position + grid.position + grid.size * (Vector2(cell) + Vector2(0.5, 0.5)) / 3.0


func _move(at: Vector2) -> void:
    var over := InputEventMouseMotion.new()
    over.position = at
    over.global_position = at
    _viewport.push_input(over)


## A real press and release at *at*, after a motion over it.
func _click(at: Vector2) -> void:
    _move(at)
    for pressed: bool in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.position = at
        event.global_position = at
        _viewport.push_input(event)


func _name(mode: SaTopBarPageEdges.Mode) -> String:
    return {FIXED: "Fixed", GROWS: "Grows", SIDES: "Wraps Sides", ALL: "Wraps All Edges"}[mode]


func test_a_press_on_each_region_from_each_mode_leaves_the_mode_ruled() -> void:
    assert_true(_button.is_visible_in_tree() and _button.size.x > 0.0, "The icon is drawn and can be pressed")
    for start: SaTopBarPageEdges.Mode in [FIXED, GROWS, SIDES, ALL]:
        for region: String in REGIONS:
            SaTopBarPageEdges.choose(_doc, start)
            SaTopBarPageEdges.follower_of(_button).sync()
            _click(_point(REGIONS[region]))
            var wanted: SaTopBarPageEdges.Mode = RULED[start][region]
            assert_eq(
                SaTopBarPageEdges.mode_of(_doc),
                wanted,
                "From %s, a press on %s leaves %s" % [_name(start), region, _name(wanted)],
            )
            assert_eq(_button.button_pressed, wanted != FIXED, "and the icon reads it pressed only while it is not Fixed")


func test_the_middle_steps_fixed_grows_sides_all_and_fixed_again() -> void:
    var seen: Array = []
    for _press in range(5):
        _click(_point(REGIONS["the middle"]))
        seen.append(SaTopBarPageEdges.mode_of(_doc))
    assert_eq(seen, [GROWS, SIDES, ALL, FIXED, GROWS], "Five presses on the middle step the mode round its cycle")


func test_a_hover_over_each_region_says_what_its_press_does() -> void:
    var follower := SaTopBarPageEdges.follower_of(_button)
    for start: SaTopBarPageEdges.Mode in [FIXED, GROWS, SIDES, ALL]:
        SaTopBarPageEdges.choose(_doc, start)
        for region: String in REGIONS:
            _move(_point(REGIONS[region]))
            follower.sync()
            var wanted: SaTopBarPageEdges.Mode = RULED[start][region]
            var tip := _button.tooltip_text
            var says := SaTopBarPageEdges.describe(wanted)
            assert_true(
                tip.begins_with(says),
                "From %s, the tooltip over %s says %s: %s" % [_name(start), region, says, tip],
            )
            assert_eq(tip.contains("\n"), region == "the middle", "and only the middle adds the round it steps")
            assert_eq(follower._hovered >= 0, true, "with a region hovered")
            assert_eq(SaTopBarPageEdges.mode_of(_doc), start, "and a hover alone leaves the mode")
    _move(Vector2(5, 5))
    assert_eq(follower._hovered, -1, "The pointer away, no region is hovered")


func test_the_cells_drawn_are_the_ones_each_wrap_fills() -> void:
    assert_eq(SaTopBarPageEdges.cells_of(FIXED), [] as Array[Vector2i], "Fixed fills nothing")
    assert_eq(SaTopBarPageEdges.cells_of(GROWS), [] as Array[Vector2i], "nor does Grows, which draws arrows")
    var sides := SaTopBarPageEdges.cells_of(SIDES)
    assert_eq(sides.size(), 6, "Wraps Sides fills the two side columns")
    for cell in sides:
        assert_true(cell.x != 1, "and no cell of the middle column")
    var edges := SaTopBarPageEdges.cells_of(ALL)
    assert_eq(edges.size(), 8, "Wraps All Edges fills every edge cell")
    assert_false(edges.has(Vector2i(1, 1)), "and never the middle")


func test_the_arrow_and_its_menu_are_gone_from_every_view() -> void:
    var docker := Control.new()
    _host.add_child(docker)
    var placed := SaSettings.build_element_view(SaTopBarPageEdges.CATEGORY, SaTopBarPageEdges.ELEMENT)
    docker.add_child(placed)
    for view: Control in [_button, placed]:
        assert_true(view is Button, "The element is the one icon's button")
        assert_eq(view.name, StringName(SaTopBarPageEdges.NODE_NAME), "named PageEdgesToggle")
    for gone: String in ["WrapMenuArrow", "WrapMenu", "WrapSwitch", "InfiniteCanvasToggle"]:
        assert_null(_host.find_child(gone, true, false), "%s is gone" % gone)
    assert_false(SaTopBarPageEdges.new().has_method("remembered"), "and no last choice is kept")
    var follower := SaTopBarPageEdges.Follower.new()
    assert_false(follower.has_method("open_menu"), "nor a menu opened")
    follower.free()


func test_a_panorama_greys_the_icon_and_a_press_leaves_its_wrap() -> void:
    _doc.projection = SaProjection.new(SaProjection.Equirectangular.new())
    SaTopBarPageEdges.follower_of(_button).sync()
    assert_true(_button.disabled, "A panorama greys the icon")
    assert_true(_button.button_pressed, "and shows its kind's wrap")
    assert_true(_button.tooltip_text.contains("projection"), "and the tooltip says the projection sets it")
    _click(_point(REGIONS["the top row"]))
    assert_eq(_doc.projection.wrapping, SaProjection.Wrap.X, "and a press leaves the panorama's wrap")


func test_a_wrap_chosen_while_the_page_grows_stops_the_growth() -> void:
    SaTopBarPageEdges.choose(_doc, GROWS)
    _click(_point(REGIONS["the left column"]))
    assert_eq(_doc.projection.wrapping, SaProjection.Wrap.X, "A press on the left column wraps the sides")
    assert_false(_doc.infinite_canvas.on, "and the page stops growing")
