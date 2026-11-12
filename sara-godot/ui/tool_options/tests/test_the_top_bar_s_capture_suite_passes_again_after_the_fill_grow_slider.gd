## The fill's Grow row comes and goes with the fill, so the first row carries
## what the capture in `ui/top_bar/tests/test_top_bar_rows.gd` says it carries.
##
## The fill paints, and a painting tool's rows stay on the bar whatever tool is
## chosen so that the brush group does not vanish under the eyedropper, so
## without a rule the Grow slider would stand on the brush's bar, 146 px of a
## row that fills nothing while a brush is in hand.
##
## What is asserted here is the rule rather than the capture: `bar_own_tool` on
## the spec takes the fill's row out of that exception, and the brush group is
## still there with the fill in hand, which is the half the exception exists
## for. `scenarios/the-top-bar-s-capture-suite-passes-again-after-the-fill-grow-slider.json`
## is the same thing on the running app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## The bar builds from every registered tool's descriptor, which needs a
## machine, a surface and therefore a device.
const REQUIRES_GPU := true

## The row, and the tool whose descriptor declares it.
const ROW := "fill_grow"
const FILL := &"bucket_fill"

static var scratch_profile: String = SaDataRoot.path("test_fill_grow.cfg")

var _saved_path: String = ""
var _host: Node = null
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _host = Node.new()
    _host.name = "U342TestHost"
    EventBus.add_child(_host)
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _machine.set_active_tool(&"brush")
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _host.add_child(_bar)
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    _bar = null
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


## The fill is a painting tool, which is why its row needs the flag at all: the
## eyedropper's rows come and go without one.
func test_the_fill_paints_and_its_grow_row_is_on_the_bar() -> void:
    assert_true(_bar.painting_tool_ids().has(FILL), "The fill is one of the painting tools")
    assert_not_null(_bar.control_for(StringName(ROW)), "and the bar built a control for '%s'" % ROW)


func test_the_grow_row_shows_only_while_the_fill_is_in_hand() -> void:
    var grow := _bar.control_for(StringName(ROW))
    assert_not_null(grow, "The bar has a Grow control to ask about")
    if grow == null:
        return
    for id: StringName in [&"brush", &"eraser", &"eyedropper", &"gradient"]:
        _machine.set_active_tool(id)
        _bar.options.binding.follow(_machine)
        assert_false(_bar.shows_for_active_tool(grow), "Grow has no place on the bar with %s in hand" % id)
    _machine.set_active_tool(FILL)
    _bar.options.binding.follow(_machine)
    assert_true(_bar.shows_for_active_tool(grow), "and a place with the fill in hand")


## The exception the flag steps out of is still there for the rows it was
## written for, which is the half a fix could have broken without a word.
func test_the_brush_group_still_has_a_place_with_the_fill_in_hand() -> void:
    for id: StringName in [FILL, &"eyedropper", &"pan"]:
        _machine.set_active_tool(id)
        _bar.options.binding.follow(_machine)
        for key: StringName in [&"radius", &"opacity", &"blend_mode"]:
            var control := _bar.control_for(key)
            assert_not_null(control, "The bar built a control for %s" % key)
            assert_true(_bar.shows_for_active_tool(control), "%s has a place with %s in hand" % [key, id])


## A row that follows one tool is off a fresh bar and one tick away, which is
## what keeps a tool switch from refitting the
## bar on the shipped profile.
func test_a_fresh_profile_keeps_the_row_off_the_bar() -> void:
    assert_false(SaSettings.get_element_visible("TopMenuBar", ROW), "A fresh profile hides '%s'" % ROW)
    var grow := _bar.control_for(StringName(ROW))
    SaSettings.set_element_visible("TopMenuBar", ROW, true)
    assert_true(SaSettings.get_element_visible("TopMenuBar", ROW), "A tick in Preferences turns it on")
    _machine.set_active_tool(&"brush")
    _bar.options.binding.follow(_machine)
    assert_false(_bar.shows_for_active_tool(grow), "and the tick alone does not put it on the brush's bar")


## The declaration, so a reader of the spec finds the three flags together and
## a change to one of them fails here rather than in the capture.
func test_the_spec_says_what_the_rule_reads() -> void:
    var spec := _bar.options.spec_for(StringName(ROW), FILL)
    assert_not_null(spec, "The fill declares '%s'" % ROW)
    if spec == null:
        return
    assert_true(spec.bar, "The row is on the bar")
    assert_true(spec.bar_own_tool, "while its own tool is in hand")
    assert_true(spec.bar_hidden, "and off a fresh bar until Preferences says otherwise")
    assert_eq(spec.bar_group, SaOptionSpec.BAR_GROUP_BRUSH, "in the brush group, so the row keeps its break")
