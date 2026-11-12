## The top bar's Double Resolution toggle reads as on at a glance.
##
## On is the accent box every toggle on the bar takes from `SaTheme.make_toggle`,
## under the pointer as well, not the theme's plain pressed box a shade off the
## hover, and the tooltip opens by saying whether the switch is on.
extends "res://tests/test_framework.gd"

var _host: Node = null
var _first: SaDocument = null
var _second: SaDocument = null
var _front: SaDocument = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "DoubleResolutionLookTestHost"
    EventBus.add_child(_host)
    _first = SaDocument.new()
    _second = SaDocument.new()
    _front = _first


func after_each() -> void:
    _host.free()
    _host = null
    _first.free()
    _first = null
    _second.free()
    _second = null
    _front = null


func _make() -> Button:
    var button := SaTopBarDoubleResolution.make(_host, func() -> SaDocument: return _front)
    SaTopBarDoubleResolution.follower_of(button).sync()
    return button


## The box the button draws now, picked the way `Button` picks it.
func _drawn(button: Button, hovered: bool = false) -> StyleBoxFlat:
    var state := "normal"
    if button.disabled:
        state = "disabled"
    elif button.button_pressed:
        state = "hover_pressed" if hovered else "pressed"
    elif hovered:
        state = "hover"
    return button.get_theme_stylebox(state) as StyleBoxFlat


func _same(a: StyleBoxFlat, b: StyleBoxFlat) -> bool:
    return a != null and b != null and a.bg_color.is_equal_approx(b.bg_color) and a.border_color.is_equal_approx(b.border_color)


func test_on_draws_the_theme_s_on_box_and_off_its_ordinary_one() -> void:
    var button := _make()
    assert_false(button.button_pressed, "A fresh document's switch is off")
    assert_true(_same(_drawn(button), SaTheme.make_toggle_style("normal")), "and off draws the toggle's ordinary box")
    _first.double_resolution.turn(_first, true)
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_true(button.button_pressed, "The button follows the switch on")
    assert_true(_same(_drawn(button), SaTheme.make_toggle_style("pressed")), "and on draws the theme's on box")
    assert_true(_same(_drawn(button, true), SaTheme.make_toggle_style("pressed")), "and still does under the pointer")
    _first.double_resolution.turn(_first, false)
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_true(_same(_drawn(button), SaTheme.make_toggle_style("normal")), "Off again draws the ordinary box")


func test_on_differs_plainly_from_hover() -> void:
    var button := _make()
    var hover := _drawn(button, true)
    _first.double_resolution.turn(_first, true)
    SaTopBarDoubleResolution.follower_of(button).sync()
    var on := _drawn(button)
    var accent := SaTheme.palette.toggle_on
    assert_true(on.bg_color.is_equal_approx(accent), "On is the palette's toggle_on, drawn from the accent: %s" % on.bg_color)
    var gap := on.bg_color - hover.bg_color
    var apart := absf(gap.r) + absf(gap.g) + absf(gap.b)
    assert_true(apart > 0.3, "and stands well apart from the hover box, %.3f" % apart)


func test_it_follows_a_change_of_tab_to_a_document_whose_switch_differs() -> void:
    _second.double_resolution.turn(_second, true)
    var button := _make()
    assert_false(button.button_pressed, "The first tab's switch is off")
    _front = _second
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_true(button.button_pressed, "The second tab's is on, and the button follows it")
    assert_true(_same(_drawn(button), SaTheme.make_toggle_style("pressed")), "drawn as on")
    _front = _first
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_false(button.button_pressed, "and back on the first it is off again")


func test_a_docker_s_view_of_the_toggle_reads_the_same() -> void:
    var was_placeable := SaSettings.is_placeable(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT)
    var bar := _make()
    SaTopBarDoubleResolution.register(func() -> SaDocument: return _front)
    var view := SaSettings.build_element_view(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT) as Button
    assert_true(view != null, "A custom docker builds its own view of the toggle")
    _host.add_child(view)
    _first.double_resolution.turn(_first, true)
    SaTopBarDoubleResolution.follower_of(bar).sync()
    SaTopBarDoubleResolution.follower_of(view).sync()
    assert_true(_same(_drawn(view), _drawn(bar)), "and draws on as the bar's does")
    if was_placeable:
        SaTopBarDoubleResolution.register()
    else:
        SaSettings.unregister_layout_element(SaTopBarDoubleResolution.CATEGORY, SaTopBarDoubleResolution.ELEMENT)


func test_the_tooltip_says_on_or_off_before_what_it_does() -> void:
    var button := _make()
    assert_true(button.tooltip_text.begins_with("Double Resolution is off."), "Off is said first: %s" % button.tooltip_text)
    assert_true(button.tooltip_text.contains("four times the texels"), "with what it does")
    _first.double_resolution.turn(_first, true)
    SaTopBarDoubleResolution.follower_of(button).sync()
    assert_true(button.tooltip_text.begins_with("Double Resolution is on."), "and on when on: %s" % button.tooltip_text)
