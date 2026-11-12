## No button the tool options bar builds keeps the keyboard past its click.
##
## The second row's blend mode dropdown opened on the space bar when it was the
## last selected, and the space bar is the pan key, so the buttons must not take
## focus and be triggered through it. A focused `Button` answers Space itself, as `ui_accept`, before
## the shortcut router sees it. The bar's own buttons said `FOCUS_NONE` one at
## a time, and every row built from a spec said nothing.
##
## The bar is built the way `test_brush_controls_on_the_bar.gd` builds it,
## with the stamp brush registered, so the walk below covers the rows the brush
## declares, the blend dropdown and the bar's own group at once. The two
## dropdown classes are also asked bare, because a docker that reuses them
## builds no bar.
##
## `scenarios/the-bars-buttons-take-no-focus-so-space-pans.json` is the
## running app: the blend list opened by a click, closed, and Space held for a
## drag that pans with no list coming back.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A machine holding the built-in tools needs a surface, which needs a device.
const REQUIRES_GPU := true

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null


func test_no_button_on_the_bar_takes_focus() -> void:
    var buttons := _buttons_outside_lists(_bar)
    assert_true(buttons.size() > 5, "The bar built its buttons, %d of them" % buttons.size())
    var blend := _bar.control_for(ToolOptionsBar.BLEND_KEY)
    assert_true(buttons.has(blend), "and the blend dropdown is one of them")
    for node in buttons:
        var button := node as BaseButton
        assert_eq(
            button.focus_mode,
            Control.FOCUS_NONE,
            "%s takes no focus, so a click on it leaves Space to the router" % _where(button)
        )


## Every `BaseButton` under *node* that is not inside a list. A list is a
## `Window` of its own and its rows do take the keyboard, on purpose: the list
## holds it while open and hands it back when it closes, which is the half of
## the rule's other half.
static func _buttons_outside_lists(node: Node) -> Array[BaseButton]:
    var out: Array[BaseButton] = []
    for child in node.get_children():
        if child is Window:
            continue
        if child is BaseButton:
            out.append(child as BaseButton)
        out.append_array(_buttons_outside_lists(child))
    return out


## A detached node has no path, so the name and the classes above it stand in.
static func _where(node: Node) -> String:
    var names: Array[String] = []
    var at := node
    while at != null:
        names.push_front("%s(%s)" % [at.name, at.get_class()])
        at = at.get_parent()
    return "/".join(names)


## The rule is on the two classes and not on the bar, so a docker that reuses
## a dropdown gets it without a line of its own.
func test_the_two_dropdown_classes_refuse_focus_bare() -> void:
    var choice := SaChoiceButton.new()
    assert_eq(choice.focus_mode, Control.FOCUS_NONE, "A bare SaChoiceButton takes no focus")
    var blend := BlendModeButton.new()
    assert_eq(blend.focus_mode, Control.FOCUS_NONE, "and neither does a bare BlendModeButton")
    assert_eq(SaChoiceButton.open_lists(choice).size(), 0, "A list that was never opened is not reported open")
    choice.free()
    blend.free()
