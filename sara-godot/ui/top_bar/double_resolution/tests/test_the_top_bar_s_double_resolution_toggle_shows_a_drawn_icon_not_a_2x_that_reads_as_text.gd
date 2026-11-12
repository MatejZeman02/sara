## The top bar's Double Resolution toggle shows a drawn icon, not a 2x that
## reads as text.
##
## The button has a least size of its own, so the icon is not drawn into the 8
## pixels of its box's margins. It shows four squares at the bar's one size for
## an icon button.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _doc: SaDocument = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "U549DoubleResolutionTestHost"
    EventBus.add_child(_host)
    _doc = SaDocument.new()


func after_each() -> void:
    _host.free()
    _host = null
    _doc.free()
    _doc = null


func _make() -> Button:
    var button := SaTopBarDoubleResolution.make(_host, func() -> SaDocument: return _doc)
    SaTopBarDoubleResolution.follower_of(button).sync()
    return button


func test_make_sets_the_drawn_icon_and_leaves_the_text_empty() -> void:
    var button := _make()
    assert_true(button.icon != null, "The toggle carries an icon")
    assert_eq(button.icon, SaUI.get_icon("double_resolution_texels"), "and it is the four squares")
    assert_eq(button.text, "", "and no 2x beside it")


func test_the_icon_is_a_new_drawing_and_not_the_layers_docker_s_2x() -> void:
    var drawn_2x := SaUI.get_icon("double_resolution")
    assert_true(SaUI.get_icon(SaTopBarDoubleResolution.ICON) != drawn_2x, "The bar no longer shows the drawn 2x")


func test_the_button_is_as_large_as_the_bar_s_other_icon_buttons() -> void:
    var button := _make()
    var least := button.get_combined_minimum_size()
    assert_true(least.x >= SaUI.px(SaBarIconButton.WIDTH), "The toggle is as wide as Undo: %s" % least)
    assert_true(least.y >= SaUI.px(SaBarIconButton.HEIGHT), "and as tall: %s" % least)
    assert_true(button.has_meta(SaBarIconButton.META), "It is shaped where the bar's icon buttons are")


func test_the_tooltip_still_opens_with_its_name() -> void:
    var button := _make()
    assert_true(button.tooltip_text.begins_with("Double Resolution"), "Its name opens the tooltip: %s" % button.tooltip_text)
