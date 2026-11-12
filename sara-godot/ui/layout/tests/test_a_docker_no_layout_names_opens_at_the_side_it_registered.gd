## A registered docker carries its default place.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaUIRegistry.register_docker` takes a side and an order, and a layout that
## has no section for the docker opens it there: beside the column the layout
## opens at that side, under the bar, two on one side stacked top down by
## order. The scenario of the same name shows it in each shipped layout, and
## this suite holds the arithmetic on a host of its own, with windows that are
## never shown.
extends "res://tests/test_framework.gd"

const HOST := Vector2i(1920, 1048)
const TOP := 79

var _windows: Array[Window] = []


func after_each() -> void:
    for win in _windows:
        win.free()
    _windows.clear()


func _window(size: Vector2i) -> Window:
    var win := Window.new()
    win.size = size
    _windows.append(win)
    return win


func _top() -> int:
    return TOP


## The default layout's columns at 1920 by 1048: the toolbox and the options at
## the left, the colour picker and the layers at the right.
func _default_columns() -> Dictionary:
    return {
        "ToolBoxDocker": Rect2i(0, 79, 60, 800),
        "ToolOptionsDocker": Rect2i(70, 79, 310, 420),
        "ColorDocker": Rect2i(1600, 79, 310, 393),
        "LayersDocker": Rect2i(1600, 482, 310, 527),
    }


func test_a_docker_opens_just_inside_the_column_of_its_side_under_the_bar() -> void:
    var places := SaDockerDefaultPlace.new(_default_columns(), _top)
    var right := places.entry_for(_window(Vector2i(220, 180)), &"right", HOST)
    var left := places.entry_for(_window(Vector2i(220, 180)), &"left", HOST)
    var gap := SaDockerDefaultPlace.GAP
    assert_eq(right["position"], Vector2i(1600 - gap - 220, TOP), "right of the painting, beside the colour picker")
    assert_eq(left["position"], Vector2i(380 + gap, TOP), "beside the options, which stand beside the toolbox")
    assert_true(bool(right["visible"]) and bool(left["visible"]), "both open")
    assert_eq(right["size"], Vector2i(220, 180), "at its own size")


func test_two_on_one_side_stack_by_order_and_one_past_the_foot_starts_a_column_further_in() -> void:
    var places := SaDockerDefaultPlace.new(_default_columns(), _top)
    var configs: Array = [
        {"id": "late", "order": 2, "node": _window(Vector2i(200, 500))},
        {"id": "first", "order": 0, "node": _window(Vector2i(200, 400))},
        {"id": "tied", "order": 2, "node": _window(Vector2i(200, 300))},
    ]
    var ordered := SaDockerDefaultPlace.in_order(configs)
    var ids := ordered.map(func(c: Dictionary) -> String: return c["id"])
    assert_eq(ids, ["first", "late", "tied"], "by order, a tie by registration")
    var first := places.entry_for(ordered[0]["node"], &"right", HOST)
    var late := places.entry_for(ordered[1]["node"], &"right", HOST)
    var tied := places.entry_for(ordered[2]["node"], &"right", HOST)
    var gap := SaDockerDefaultPlace.GAP
    assert_eq(first["position"], Vector2i(1600 - gap - 200, TOP), "the lowest order highest")
    assert_eq(late["position"], Vector2i(1600 - gap - 200, TOP + 400 + gap), "under it")
    assert_eq(tied["position"], Vector2i(1600 - 2 * (gap + 200), TOP), "no room under them, so a column further in")


func test_a_side_the_layout_opens_nothing_at_is_the_edge_of_the_host() -> void:
    var places := SaDockerDefaultPlace.new({}, _top)
    var right := places.entry_for(_window(Vector2i(220, 2000)), &"right", HOST)
    assert_eq(right["position"], Vector2i(HOST.x - SaDockerDefaultPlace.GAP - 220, TOP), "at the edge")
    assert_eq(right["size"], Vector2i(220, HOST.y - TOP), "no taller than the host under the bar")


func test_a_docker_off_the_column_or_below_the_bar_s_row_is_not_part_of_it() -> void:
    var opened := _default_columns()
    opened["MinimapDocker"] = Rect2i(390, 620, 300, 230)
    var places := SaDockerDefaultPlace.new(opened, _top)
    var left := places.entry_for(_window(Vector2i(220, 180)), &"left", HOST)
    var beside := Vector2i(380 + SaDockerDefaultPlace.GAP, TOP)
    assert_eq(left["position"], beside, "a floating docker lower down does not move the column")


func test_the_registry_keeps_the_place_and_refuses_a_side_it_does_not_know() -> void:
    var registry := SaUIRegistry.new()
    var factory := func() -> Window: return null
    assert_true(registry.register_docker(&"U633Right", "Right", factory, &"", &"fixture", "", &"right", 3), "a known side")
    var entry := registry.get_docker_entry(&"U633Right")
    assert_eq(entry["side"], &"right", "the side kept")
    assert_eq(entry["order"], 3, "the order kept")
    assert_true(registry.register_docker(&"U633None", "None", factory), "no side at all, as before")
    assert_eq(registry.get_docker_entry(&"U633None")["side"], &"", "no place")
    var refused := registry.register_docker(&"U633Up", "Up", factory, &"", &"fixture", "", &"top")
    assert_false(refused, "a side that is none of the two")
    assert_false(registry.has_docker(&"U633Up"), "and not registered")
