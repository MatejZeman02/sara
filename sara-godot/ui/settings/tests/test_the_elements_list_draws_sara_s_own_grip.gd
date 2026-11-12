## The Elements list on Layouts and dockers draws the docker bars' grip.
##
## The six-dot grip is Sara's own `SaGrip`, as on the bars, not " :: " as text or
## a dash on a row that cannot be dragged. A row that can be picked up carries
## an `SaGrip` under its title, and one that cannot, the top bar's sentinel and a
## docker's Drag Handle and Resizer, carries none and keeps the grip's room, so
## every title starts in one column. The proof on the running app is
## `scenarios/the-elements-list-draws-sara-s-own-grip.json`.
extends "res://tests/test_framework.gd"


func _grip_of(row: SaLayoutPage.DragRow) -> SaGrip:
    var title := row.find_child("Title", true, false) as Label
    return title.get_node_or_null(SaGrip.NODE_NAME) as SaGrip


func _title_left_margin(row: SaLayoutPage.DragRow) -> float:
    var title := row.find_child("Title", true, false) as Label
    return title.get_theme_stylebox("normal").content_margin_left


func test_a_row_that_can_be_dragged_has_the_grip_under_its_title() -> void:
    var page := SaLayoutPage.new("TopMenuBar")
    var row := page.row_for("File")
    assert_true(row.can_drag(), "File is a row the painter can pick up")
    assert_not_null(_grip_of(row), "and its title carries the six dots")
    assert_null(row.find_child("DragHandle", true, false), "The text grip is gone")
    var title := row.find_child("Title", true, false) as Label
    assert_eq(title.mouse_default_cursor_shape, Control.CURSOR_DRAG, "The drag cursor the text grip asked for is the title's")
    page.free()


func test_the_sentinel_has_no_grip() -> void:
    var page := SaLayoutPage.new("TopMenuBar")
    var row := page.row_for(SaSettings.ROW_SENTINEL)
    assert_false(row.can_drag(), "The sentinel is never dragged")
    assert_null(_grip_of(row), "so its title carries no grip")
    var title := row.find_child("Title", true, false) as Label
    assert_eq(title.mouse_default_cursor_shape, Control.CURSOR_ARROW, "and asks for the arrow its dash asked for")
    page.free()


func test_the_pinned_pair_has_no_grip() -> void:
    var page := SaLayoutPage.new("LayersDocker")
    for element: String in ["Drag Handle", "Resizer"]:
        var row := page.row_for(element)
        assert_false(row.can_drag(), "%s is pinned" % element)
        assert_null(_grip_of(row), "and %s's title carries no grip" % element)
    assert_not_null(_grip_of(page.row_for("Layer List")), "while Layer List's does")
    page.free()


## The grip lays its room on the title when it enters the tree, so the page is
## put in one for the reading, and every title then keeps the same left margin.
func test_every_title_starts_in_one_column() -> void:
    var host := Node.new()
    host.name = "GripColumnTestHost"
    EventBus.add_child(host)
    var page := SaLayoutPage.new("TopMenuBar")
    host.add_child(page)
    var dragged := _title_left_margin(page.row_for("File"))
    assert_almost_eq(dragged, float(SaGrip.room()), 0.001, "A dragged row's title keeps the grip's room")
    assert_almost_eq(_title_left_margin(page.row_for(SaSettings.ROW_SENTINEL)), dragged, 0.001, "and the sentinel's the same")
    EventBus.remove_child(host)
    host.free()
