## b4: a hovered switch is marked by a state field of its own family.
##
## A switch's hover read the raw key `bg_slider`, so editing the push button's
## hover moved nothing on it and nothing a painter could set moved it either.
## It reads `switch_hover` now, and the other three states read their own
## fields, so the box is a palette edit away like every other control's.
extends "res://tests/test_framework.gd"

## State -> the field the strip names for the switch, written out here so a
## table that changed would not carry this test's intent along with it.
const FIELDS := {
    "normal": "switch_normal",
    "hover": "switch_hover",
    "pressed": "switch_pressed",
    "disabled": "switch_disabled",
}


func _saved() -> Array:
    return [SaUI.shared_theme, SaTheme.palette_id]


func _restore(saved: Array) -> void:
    SaTheme.use_named(String(saved[1]))
    SaUI.shared_theme = saved[0] as Theme


func _host() -> Node:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var host := Node.new()
    host.name = "B4SwitchHost"
    EventBus.add_child(host)
    var root := Control.new()
    root.theme = SaUI.shared_theme
    host.add_child(root)
    return host


## Every state of the switch is grounded on its own field, and a field the
## painter sets moves the box in place while the push button's does not.
func test_a_switch_box_reads_its_own_field_and_follows_an_edit() -> void:
    var saved := _saved()
    var host := _host()
    var root := host.get_child(0) as Control
    var switch := CheckButton.new()
    var push := Button.new()
    root.add_child(switch)
    root.add_child(push)
    for state: String in FIELDS:
        var field := String(FIELDS[state])
        assert_true(SaPalette.STATE_BASES.has(field), "%s is a state field" % field)
        var flat := switch.get_theme_stylebox(state) as StyleBoxFlat
        assert_eq(flat.bg_color, SaTheme.palette.get(field), "the switch's %s is grounded on %s" % [state, field])
    var hover := switch.get_theme_stylebox("hover") as StyleBoxFlat
    var push_hover := push.get_theme_stylebox("hover") as StyleBoxFlat
    assert_eq(hover.bg_color, push_hover.bg_color, "at rest in a palette the two hovers are marked alike")
    assert_eq(hover.border_color, push_hover.border_color, "and carry the same rim")

    SaTheme.palette.set("switch_hover", Color("#336699"))
    SaTheme.palette.hold_state("switch_hover")
    SaTheme.use_named(SaTheme.palette_id)
    SaUI.shared_theme.changed.emit()
    assert_eq(hover.bg_color, Color("#336699"), "setting switch_hover moves the switch's hover box in place")
    assert_true(push_hover.bg_color != Color("#336699"), "and not the push button's")
    SaTheme.palette.overridden_states.erase("switch_hover")
    SaTheme.palette.derive_states()
    host.free()
    _restore(saved)


## The strip draws the switch in all four states and names the field of each.
func test_the_strip_names_the_switchs_fields() -> void:
    SaTheme.use_named("default")
    SaUI.init_global_theme(null)
    var strip := SaControlStatesStrip.new()
    var found: Dictionary = strip.report()
    assert_true(found.has("switch"), "the strip has a switch row")
    for state: String in FIELDS:
        var entry: Dictionary = (found.get("switch", {}) as Dictionary).get(state, {})
        assert_eq(String(entry.get("field", "")), String(FIELDS[state]), "%s names its field" % state)
    strip.free()
