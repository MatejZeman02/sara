## The 18 icons and the two cursors drawn for the interface are in the
## tree and load, but for the two taken away with the Wrap menu, they keep
## the set's rules, and the three top bar toggles that had no icon show theirs.
## Select Subject's tool reads its icon from its own module,
## whose suite checks it is the same drawing.
extends "res://tests/test_framework.gd"

## The twelve drawn again and the six new, every one under `assets/icons/`,
## less `wrap_all` and `wrap_sides`, which went with the Wrap menu.
const NAMES: Array[String] = [
    "bucket",
    "clear",
    "container",
    "double_resolution",
    "ellipse_select",
    "guivisibilityhidden",
    "infinite_canvas",
    "lasso",
    "liquify",
    "patch",
    "relief",
    "select_subject",
    "toolpan",
    "visualshadernodecomment",
    "wrap",
    "wrench",
]
const CURSORS := "res://assets/icons/"

var _host: Node = null
var _doc: SaDocument = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "U468IconsTestHost"
    EventBus.add_child(_host)
    _doc = SaDocument.new()


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    if _doc != null:
        _doc.free()
        _doc = null


func test_each_of_the_18_names_loads_from_the_icons_folder() -> void:
    assert_eq(NAMES.size(), 16, "18 icons were drawn, and two were taken away with the Wrap menu")
    for icon_name in NAMES:
        var path := "res://assets/icons/%s.svg" % icon_name
        assert_true(ResourceLoader.exists(path), "%s is in the tree" % path)
        assert_not_null(SaUI.get_icon(icon_name), "%s loads" % icon_name)


func test_each_drawing_keeps_the_sets_grid_and_its_one_fill() -> void:
    for icon_name in NAMES:
        var text := FileAccess.get_file_as_string("res://assets/icons/%s.svg" % icon_name)
        assert_true(text.contains('viewBox="0 0 16 16"'), "%s is drawn on the 16 grid" % icon_name)
        assert_true(text.contains('fill="#e0e0e0"'), "%s is filled #e0e0e0" % icon_name)
        assert_false(text.contains("#808080"), "%s is never dimmed, a dimmed control reads as disabled" % icon_name)


func test_the_two_cursors_are_in_the_tree_and_load_at_24_pixels() -> void:
    for cursor: String in ["arrow", "hand"]:
        var picture := load(CURSORS + cursor + ".png") as Texture2D
        assert_not_null(picture, "%s.png loads" % cursor)
        if picture != null:
            assert_eq(picture.get_size(), Vector2(24, 24), "%s.png is a 24 pixel cursor" % cursor)
        assert_not_null(load(CURSORS + cursor + ".svg") as Texture2D, "and %s.svg, its drawing, loads" % cursor)
    var arrow := FileAccess.get_file_as_bytes(CURSORS + "arrow.png")
    var hand := FileAccess.get_file_as_bytes(CURSORS + "hand.png")
    assert_false(arrow == hand, "The hand is a hand and no longer the arrow's bytes under a second name")


func test_double_resolution_shows_its_icon_and_keeps_its_name_in_the_tooltip() -> void:
    var button := SaTopBarDoubleResolution.make(_host, func() -> SaDocument: return _doc)
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_eq(button.icon, SaUI.get_icon(SaTopBarDoubleResolution.ICON), "The toggle shows its drawn icon")
    assert_eq(button.text, "", "and no label beside it")
    assert_true(button.tooltip_text.begins_with("Double Resolution"), "Its name opens the tooltip")


func test_the_wrap_icon_is_the_grid_of_nine_with_no_label() -> void:
    var button := SaTopBarPageEdges.make(_host, func() -> SaDocument: return _doc)
    SaTopBarPageEdges.follower_of(button).sync()
    assert_eq(button.icon, SaUI.get_icon("wrap"), "The icon is the grid of nine")
    assert_eq(button.text, "", "and no label beside it")
    assert_true(button.tooltip_text.begins_with("Page Edges"), "Its name opens the tooltip")
