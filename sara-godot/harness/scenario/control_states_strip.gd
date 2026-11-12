## A row of buttons per control family, one in every state, for a scenario to
## photograph.
##
## A pointer cannot be parked over one button while another is held down and a
## third is disabled, so no single frame of the interface shows a family in all
## of its states. Each sample here draws the box its family really uses for one
## state, in every state of its own: the push button's is the one the shared
## theme holds, the very object a `Button` nobody styled resolves, and every
## other family's comes from the door its own control walks through in
## `SaTheme` or `SaThemeDefaults`. All of them are bound, so a palette edit
## repaints the strip the way it repaints the interface.
class_name SaControlStatesStrip
extends PanelContainer

const NAME := "G6ControlStates"

## Family -> the states shown, in the order the strip lays them out.
## `slider` is its parts rather than five states: the app's own slider draws a
## track and a fill, and the engine's draws a third, the fill under a grabber the
## pointer is on. `scrollbar` is the engine's own parts too, and
## no app control draws one.
const FAMILIES := {
    "button": ["normal", "hover", "pressed", "disabled"],
    "toggle": ["normal", "hover", "pressed", "disabled"],
    "switch": ["normal", "hover", "pressed", "disabled"],
    "dropdown": ["normal", "hover", "pressed", "focus", "disabled"],
    "slider": ["track", "handle", "hover"],
    "scrollbar": ["track", "grabber", "hover", "pressed"],
    "tab": ["unselected", "hovered", "selected", "disabled"],
    "menu_row": ["normal", "hover", "checked", "disabled"],
    "text_field": ["normal", "read_only", "focus"],
}

## Family -> what its row is headed. The family key is an identifier and a
## painter reads a heading.
const TITLES := {
    "button": "Push button",
    "toggle": "Toggle button",
    "switch": "Switch",
    "dropdown": "Dropdown",
    "slider": "Slider",
    "scrollbar": "Scroll bar",
    "tab": "Tab",
    "menu_row": "Menu row",
    "text_field": "Text field",
}

## Family -> state -> the word on the sample, for the families whose states are
## not the four words a button already uses.
const STATE_WORDS := {
    "slider": {"track": "Track", "handle": "Handle", "hover": "Hovered"},
    "scrollbar": {"track": "Track", "grabber": "Grabber"},
    "tab": {"unselected": "Unselected", "selected": "Selected"},
    "menu_row": {"checked": "Chosen"},
    "text_field": {"read_only": "Read only"},
}

## Family -> state -> the box each sample draws, kept so the report reads the
## colours the shot shows rather than asking the palette a second time.
var _boxes: Dictionary = {}


func _init() -> void:
    name = NAME
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    var panel := StyleBoxFlat.new()
    SaTheme.bind(panel, {"bg_color": "bg_primary", "border_color": "border_secondary"})
    panel.set_border_width_all(1)
    panel.set_content_margin_all(float(SaUI.px(10)))
    add_theme_stylebox_override("panel", panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", SaUI.px(8))
    add_child(column)
    for family: String in FAMILIES:
        column.add_child(_family_row(family))


func _family_row(family: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", SaUI.px(6))
    var title := Label.new()
    title.text = tr(String(TITLES.get(family, family)))
    title.custom_minimum_size = Vector2(SaUI.px(110), 0)
    row.add_child(title)
    _boxes[family] = {}
    for state: String in FAMILIES[family]:
        var box := _box(family, state)
        _boxes[family][state] = box
        var sample := Button.new()
        sample.name = "%s_%s" % [family.capitalize(), state.capitalize()]
        sample.text = _state_label(family, state)
        sample.focus_mode = Control.FOCUS_NONE
        sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
        sample.custom_minimum_size = Vector2(SaUI.px(96), SaUI.px(SaUI.BASE_BTN_H))
        for drawn: String in SaTheme.TOGGLE_STATES:
            sample.add_theme_stylebox_override(drawn, box)
        row.add_child(sample)
    return row


## The box *family* draws in *state*, the same object the interface draws.
static func _box(family: String, state: String) -> StyleBox:
    if family == "toggle":
        return SaTheme.make_toggle_style(state)
    if family == "switch" and SaUI.shared_theme != null:
        return SaUI.shared_theme.get_stylebox(state, "CheckButton")
    if family == "dropdown":
        return SaTheme.make_dropdown_style(state)
    if family == "slider":
        return SaTheme.make_slider_style(state)
    if family == "scrollbar":
        return SaThemeDefaults.make_scrollbar_style(state)
    if family == "tab":
        return SaTheme.make_tab_style("tab_" + state)
    if family == "menu_row":
        return SaTheme.make_menu_row_style(state)
    if family == "text_field":
        return SaThemeDefaults.make_field_style(state)
    if SaUI.shared_theme != null and SaUI.shared_theme.has_stylebox(state, "Button"):
        return SaUI.shared_theme.get_stylebox(state, "Button")
    return StyleBoxFlat.new()


func _state_label(family: String, state: String) -> String:
    var words: Dictionary = STATE_WORDS.get(family, {})
    if words.has(state):
        return tr(String(words[state]))
    match state:
        "hover":
            return tr("Hovered")
        "pressed":
            return tr("On") if family in ["toggle", "switch"] else tr("Pressed")
        "disabled":
            return tr("Disabled")
        "focus":
            return tr("Focused")
    return tr("Off") if family in ["toggle", "switch"] else tr("Normal")


## Family -> state -> `{field, hex, held}`: the palette field each ground reads,
## the ground the sample draws, and whether the painter set that field.
func report() -> Dictionary:
    var out := {}
    for family: String in _boxes:
        var states := {}
        for state: String in _boxes[family]:
            var flat := _boxes[family][state] as StyleBoxFlat
            var field := _field(family, state)
            states[state] = {
                "field": field,
                "hex": flat.bg_color.to_html() if flat != null else "",
                "held": SaTheme.palette.overridden_states.has(field),
            }
        out[family] = states
    return out


static func _field(family: String, state: String) -> String:
    return String(_table(family, state).get("bg_color", ""))


## The family's own box table for *state*, so a row names the field the palette
## derives it from and not the colour it happens to hold.
static func _table(family: String, state: String) -> Dictionary:
    match family:
        "toggle":
            return SaPalette.TOGGLE_BOXES.get(state, {}) as Dictionary
        "switch":
            return SaPalette.SWITCH_BOXES.get(state, {}) as Dictionary
        "dropdown":
            return SaPalette.DROPDOWN_BOXES.get(state, {}) as Dictionary
        "slider":
            return SaPalette.SLIDER_BOXES.get(state, {}) as Dictionary
        "scrollbar":
            return SaPalette.SCROLLBAR_BOXES.get(state, {}) as Dictionary
        "tab":
            return SaPalette.TAB_BOXES.get("tab_" + state, {}) as Dictionary
        "menu_row":
            return SaPalette.MENU_ROW_BOXES.get(state, {}) as Dictionary
        "text_field":
            return SaPalette.FIELD_BOXES.get(state, {}) as Dictionary
    return {"bg_color": SaPalette.BUTTON_GROUNDS.get(state, "")}


## Shows the control states strip: at the foot of the main window, or builds it
## again when one is already there, and prints every sample's ground with the
## field it reads, `{"control_states": {}}`. `{"control_states": {"close": true}}`
## takes it away.
##
## Built again rather than kept, so a scenario that switches palettes between
## two shots photographs the boxes of the palette it is on.
##
## Made through `load` and held untyped, because this file naming its own
## `class_name` inside a static function leaks the script, which cost 545 live
## objects when it happened.
static func capture_strip(tree: SceneTree, spec: Dictionary = {}) -> String:
    var old := tree.root.get_node_or_null(NAME)
    if old != null:
        tree.root.remove_child(old)
        old.queue_free()
    if bool(spec.get("close", false)):
        return "SaCapture: control states strip closed"
    var strip: Control = load("res://harness/scenario/control_states_strip.gd").new()
    tree.root.add_child(strip)
    # Bottom centre, the strip of canvas Preferences leaves uncovered, so one shot
    # holds a swatch set on the page and the boxes it moved.
    strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, SaUI.px(24))
    var parts: Array[String] = []
    var found: Dictionary = strip.call("report")
    for family: String in found:
        for state: String in found[family]:
            var entry: Dictionary = found[family][state]
            parts.append("%s.%s=%s%s" % [family, state, entry["hex"], " held" if entry["held"] else ""])
    return "SaCapture: control states of '%s': %s" % [SaTheme.palette.display_name, ", ".join(parts)]
