## The colour theme's editor: the palette dropdown, and under it the palette's
## own colours. Changing a swatch on a shipped palette forks it into "<name>
## (custom)" in the settings folder, selects the fork and applies it at once.
## Save As names a fork, Delete asks first and then moves one into the `deleted`
## folder beside them, and a shipped palette cannot be deleted.
##
## **Not a page of the sidebar.** As one it put the one choice most painters
## make, the theme, at the top of 47 rows of swatches. The choice is a row of
## the Interface page, [ThemeChoice] below, with Edit colours… beside it, and
## this page is what that button opens, drawn in the page area with a Back row
## to the theme's row.
##
## The colours are laid out the way the palette declares them: a section per
## `@export_group`, and one row for each of `SaTheme.GROUPS`, holding the base,
## its shadow, its highlight and the further shades cut from the same cloth,
## with a link toggle at the end, rather than twenty-one swatches in one flat
## list. A colour that belongs to no group keeps a row of its own, and a field
## added to SaPalette still gets a swatch with no edit here.
##
## **The controls come first**. A painter looking for the toggle's pressed
## colour looks for the toggle, not for a ramp, so every section of the palette
## whose colours are all state fields is a control's and is built above the
## ramps: a row to try the control itself, then a row per state with the state
## spelled out, its swatch, and a sample drawn with the very box that state
## draws in the interface. The walk is the same one, so a family a palette adds
## later lands among the controls and gains its rows with no edit here. Its
## samples are the one thing that does need a line, because a sample is drawn
## with the family's own door: [method _box_tables] names the table and [method
## _state_box] the door, and the five later families are the second entry in
## each.
##
## Declared rather than built, and every row is a custom row: a swatch group, a
## state with its sample and a control to try are not kinds of the row layer and
## will not be. The declaration walks the same sections in the same order and
## hands each row its control or its box, named by its palette key or its group.
## The page never rebuilds: a new theme is a new entry in the dropdown, which
## [method _refresh_option] refills, and the rows are the palette's fields,
## which no theme changes.
class_name SaColorThemesPage
extends SaSettingsPage

## A lone colour's swatch, and a swatch inside a group row, in logical units.
## A group row carries up to seven of them beside a toggle, so they are narrow.
const SWATCH_WIDTH := 64
const GROUP_SWATCH_WIDTH := 38
## The sample beside a state's swatch, wide enough for the state's name.
const SAMPLE_WIDTH := 96

## The word a state field's name ends in, spelled out for its row, and what the
## state is. A word not listed is capitalised and says nothing more, so a state
## a palette adds later still reaches the page.
const STATE_WORDS := {
    "normal": ["Normal", "At rest, neither hovered nor held."],
    "hover": ["Hovered", "While the pointer is over it."],
    "pressed": ["Pressed", "While it is held down."],
    "disabled": ["Disabled", "While it cannot be used."],
    "off": ["Off", "Switched off and at rest."],
    "on": ["On", "A toggle that is on."],
    "bar": ["Title bar", "Behind the title of a docker and of a dialog."],
}

## The state fields no table's `bg_color` names, with the family and state whose
## box shows them: the rim a hovered toggle is drawn with, and the title bar.
const EDGE_READINGS := {"border_hover": ["rim", "hover"], "title_bar": ["bar", "normal"]}

## The word a palette field's first word stands for, which [method swatch_title]
## puts after the rest.
const FAMILY_WORDS := {"bg": "background", "border": "border", "accent": "accent", "text": "text"}
## The fields whose rest is what the family word belongs to, rather than the
## other way about: a text shadow is a shadow, not text.
const SWATCH_NAMES := {"text_shadow": "Text shadow"}

## The key the theme's row is named by, on the Interface page and here, so a
## door lands on it and the Back row returns to it.
const THEME_ROW := &"theme"

## The two answers to the Delete question, in the order the buttons are built.
## Cancel is first so that the safe one is both the default and the cancel
## index, which is what makes Enter and Escape leave the palette alone.
const DELETE_CANCEL: int = 0
const DELETE_CONFIRM: int = 1

var option: SaChoiceButton
var save_as_name: LineEdit
var save_as_button: Button
var delete_button: Button

var _ids: Array[String] = []
var _swatches: Dictionary = {}
var _links: Dictionary = {}
## State field -> the sample drawn beside its swatch.
var _samples: Dictionary = {}

## The colours a drag sent since the last frame, `{palette key: Color}`, the
## latest for each key. See [method drag_swatch].
var _dragged: Dictionary = {}
## The palette the dropdown was last filled for.
var _shown_id: String = ""
## What was built, in order: `{section, title, group, keys}` per row. The state
## dump reads the colours and the toggles back off the nodes, and this for the
## shape they were put in.
var _rows: Array[Dictionary] = []

## What the Back row at the top calls, or nothing for a page with no way back,
## which is the page a suite builds on its own.
var _back: Callable = Callable()


func _init(back: Callable = Callable()) -> void:
    _back = back
    # `super()` declares and realizes, so the dropdown exists to fill and the
    # rows exist to follow a theme change only after it.
    super()
    _refresh_option()
    EventBus.theme_changed.connect(_on_theme_changed)
    tree_exiting.connect(func() -> void: EventBus.theme_changed.disconnect(_on_theme_changed))
    # Replacing the page with another and quitting both take it out of the tree.
    tree_exiting.connect(save_swatches)
    visibility_changed.connect(_on_visibility_changed)


## The declaration: the "Theme" section, then a section per `@export_group`
## of the palette. Runs once, in `_init`.
func build(ui: SaPage) -> void:
    _ids.clear()
    _swatches.clear()
    _links.clear()
    _samples.clear()
    _rows.clear()
    if _back.is_valid():
        # No heading over it, the way a docker's part has none: the title above
        # already names the page.
        ui.section("").action(tr("Back to Interface"), _back).named(&"back").node("BackToInterface")
    var section := ui.section(tr("Theme"))

    # `SaChoiceButton` rather than the engine's dropdown, and the rows carry the
    # palette id, so the handler writes what it was handed instead of counting
    # into `_ids`.
    option = SaMake.choice(null, "ColorThemeOpt")
    option.choice_picked.connect(func(id: Variant) -> void: SaSettings.theme_name = String(id))
    section.custom(tr("Colour theme"), option).named(THEME_ROW).explain(
        tr("The palette these colours belong to, the one the interface is drawn with. Applies at once.")
    )

    var save_box := SaMake.row(null, "SaveBox", 6)
    # Set before the row is declared, because the builder gives a custom
    # control back the width it was handed over with.
    save_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_as_name = SaMake.line_edit(save_box, "SaveAsName", "", tr("Name"))
    save_as_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_as_button = SaMake.button(save_box, "SaveAsButton", tr("Save As"))
    save_as_button.pressed.connect(_on_save_as)
    delete_button = SaMake.button(save_box, "DeleteButton", tr("Delete"))
    delete_button.pressed.connect(_on_delete)
    section.custom(tr("Your palettes"), save_box).named(&"your_palettes").explain(
        tr("Save the current colours as a palette of your own. A built-in palette cannot be deleted.")
    )
    section.note(
        tr("Change any swatch and the palette becomes yours, applied as you pick. Editing a built-in palette makes a copy first.")
    )

    _build_sections(ui)


## A section per `@export_group` of SaPalette, the controls' first and the
## ramps' under them. The property list is walked rather than a list kept here,
## which is what keeps a new palette field from needing an edit in this file.
func _build_sections(ui: SaPage) -> void:
    var sections := _gather_sections()
    for section: Dictionary in sections:
        if _is_control_section(section["keys"]):
            _control_section(ui, String(section["title"]), section["keys"])
    var placed: Dictionary = {}
    for section: Dictionary in sections:
        if not _is_control_section(section["keys"]):
            _ramp_section(ui, String(section["title"]), section["keys"], placed)


## The palette's colours as `{title, keys}` per `@export_group`, in the order
## the palette declares them.
func _gather_sections() -> Array[Dictionary]:
    var sections: Array[Dictionary] = []
    var pending := "Colours"
    var current: Dictionary = {}
    for property: Dictionary in SaTheme.palette.get_property_list():
        var usage: int = property["usage"]
        var key := String(property["name"])
        if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY):
            # Named but not opened yet. Godot's own "Resource" category is in
            # this list too and holds no colour, and a section made the moment
            # its name went by was a heading with a rule under it and nothing
            # else.
            pending = key
            current = {}
            continue
        if property["type"] != TYPE_COLOR or not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
            continue
        if current.is_empty():
            current = {"title": pending, "keys": []}
            sections.append(current)
        (current["keys"] as Array).append(key)
    return sections


## A section is a control's when every colour in it is a state field, which is
## how a family the palette adds later is told from a ramp without naming it.
static func _is_control_section(keys: Array) -> bool:
    if keys.is_empty():
        return false
    for key: String in keys:
        if not SaPalette.STATE_BASES.has(key):
            return false
    return true


## A section of the palette's own ramps: a row per group and a row per colour
## that belongs to none. *placed* is shared between sections, because a group's
## row is built where its first member is met, and the section is opened where
## its first row is placed, so a section whose colours were all placed by an
## earlier one is no heading over nothing.
func _ramp_section(ui: SaPage, title: String, keys: Array, placed: Dictionary) -> void:
    var section: SaPageSection = null
    for key: String in keys:
        if placed.has(key):
            continue
        if section == null:
            section = ui.section(tr(title))
        var group := SaTheme.group_of(key)
        if group.is_empty():
            _lone_row(section, key)
            placed[key] = true
            continue
        for member: String in SaTheme.group_keys(group):
            placed[member] = true
        _group_row(section, group)


## A control's section: the control itself to try, then a row per state.
func _control_section(ui: SaPage, title: String, keys: Array) -> void:
    var section := ui.section(tr(title))
    var preview := _live_preview(keys)
    if preview != null:
        section.custom(tr("Preview"), preview).named(StringName(preview.name.to_snake_case())).explain(
            tr("The control itself, drawn the way the interface draws it. Hover it and press it.")
        )
    for key: String in keys:
        _state_row(section, key)


## One state: its name spelled out, what the state is, and beside the swatch a
## sample drawn with the box that state draws. Not a group, so no link.
func _state_row(section: SaPageSection, key: String) -> void:
    var word := _state_word(key)
    # A state the table lacks shows its key's own word, which no catalogue holds.
    var spelled: Array = STATE_WORDS.get(word, [])
    var title := tr(String(spelled[0])) if not spelled.is_empty() else word.capitalize()
    var controls: Array[Control] = [_swatch(key, SWATCH_WIDTH)]
    var box := _state_box(key)
    if box != null:
        controls.append(_sample(key, title, box))
    _lay_out(section, key, title, _state_hint(key, String(spelled[1]) if not spelled.is_empty() else ""), controls)
    _rows.append({"section": section.title, "title": title, "group": "", "keys": [key], "state": word})


## The part of a state field's name after the control's, `toggle_on` to `on`.
static func _state_word(key: String) -> String:
    return key.substr(key.find("_") + 1)


## What the state is, then the field's own name and the colour it follows until
## it is set. The field's name is in the text rather than only in a tooltip,
## because the file stores it and a Preferences search reads the label column.
## The colour it follows is named by [method swatch_title], the name its own
## swatch carries, because "it follows Bg Panel" names the palette's key and not
## anything on the page.
func _state_hint(key: String, sentence: String) -> String:
    var base := swatch_title(String(SaPalette.STATE_BASES[key]))
    var follows := tr("Saved as %s. Until you set it, it is the same as %s.") % [key.capitalize(), base]
    if sentence.is_empty():
        return follows
    return tr(sentence) + " " + follows


## `[family, state]` for a state field: which control's box reads it, and in
## which of the engine's states, or an empty pair for a field no box reads.
##
## The two oldest families are asked by name and the five later ones are walked
## from a table each, so a family a palette gains is one entry in [method
## _box_tables] and one branch in [method _state_box], and neither the rows
## built above nor the swatches beside them knows it happened.
static func _box_reading(key: String) -> Array:
    for state: String in SaPalette.BUTTON_GROUNDS:
        if String(SaPalette.BUTTON_GROUNDS[state]) == key:
            return ["button", state]
    for state: String in SaPalette.TOGGLE_BOXES:
        if String((SaPalette.TOGGLE_BOXES[state] as Dictionary)["bg_color"]) == key:
            return ["toggle", state]
    for entry: Array in _box_tables():
        var table: Dictionary = entry[1]
        for state: String in table:
            if String((table[state] as Dictionary).get("bg_color", "")) == key:
                return [String(entry[0]), state]
    return EDGE_READINGS.get(key, [])


## The later families, each with the table its box reads. A function rather than
## a `const`, because a const whose initializer names a global `class_name`
## breaks the class cache.
static func _box_tables() -> Array:
    return [
        ["switch", SaPalette.SWITCH_BOXES],
        ["dropdown", SaPalette.DROPDOWN_BOXES],
        ["slider", SaPalette.SLIDER_BOXES],
        ["scrollbar", SaPalette.SCROLLBAR_BOXES],
        ["tab", SaPalette.TAB_BOXES],
        ["menu_row", SaPalette.MENU_ROW_BOXES],
        ["text_field", SaPalette.FIELD_BOXES],
    ]


## The box the interface draws *key*'s state with, from the call that makes it
## there: the shared theme's own push button box, the object every unstyled
## button resolves, or the family's own door in `SaTheme` or `SaThemeDefaults`.
## All of them are bound, so a swatch set on this page repaints the sample in
## place. Null for a state no box reads, which keeps its swatch and no sample.
static func _state_box(key: String) -> StyleBox:
    var reading := _box_reading(key)
    if reading.is_empty():
        return null
    var state := String(reading[1])
    match String(reading[0]):
        "toggle", "rim":
            return SaTheme.make_toggle_style(state)
        "bar":
            return SaTheme.make_drag_bar_style()
        "switch":
            return SaUI.shared_theme.get_stylebox(state, "CheckButton") if SaUI.shared_theme != null else null
        "dropdown":
            return SaTheme.make_dropdown_style(state)
        "slider":
            return SaTheme.make_slider_style(state)
        "scrollbar":
            return SaThemeDefaults.make_scrollbar_style(state)
        "tab":
            return SaTheme.make_tab_style(state)
        "menu_row":
            return SaTheme.make_menu_row_style(state)
        "text_field":
            return SaThemeDefaults.make_field_style(state)
    if SaUI.shared_theme == null or not SaUI.shared_theme.has_stylebox(state, "Button"):
        return null
    return SaUI.shared_theme.get_stylebox(state, "Button")


## A button drawing *box* in every state it can be in, so it shows its one state
## however the pointer meets it.
func _sample(key: String, word: String, box: StyleBox) -> Button:
    var sample := SaMake.button(null, key.to_pascal_case() + "Sample", word)
    sample.focus_mode = Control.FOCUS_NONE
    sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
    sample.custom_minimum_size = Vector2(SaUI.px(SAMPLE_WIDTH), SaUI.px(SaUI.BASE_BTN_H))
    for drawn: String in SaTheme.TOGGLE_STATES:
        sample.add_theme_stylebox_override(drawn, box)
    # The box is the same in every state, but the words are the button's own,
    # so the Disabled sample is a disabled button to read in the grey a really
    # disabled one shows, and not in the white of an enabled one.
    sample.disabled = _state_word(key) == "disabled"
    _samples[key] = sample
    return sample


## The control a section's states belong to, for the painter to hover and press,
## made the way the interface makes it: a toggle through `SaTheme.make_toggle`,
## switched on so the pressed colour is the one showing, and a push button
## carrying the shared theme's own boxes. Null for a family this page cannot
## build, whose state rows still show.
func _live_preview(keys: Array) -> Button:
    var families: Dictionary = {}
    for key: String in keys:
        var reading := _box_reading(key)
        if not reading.is_empty():
            families[reading[0]] = true
    var button := Button.new()
    button.text = tr("Try it")
    button.custom_minimum_size = Vector2(SaUI.px(SAMPLE_WIDTH), SaUI.px(SaUI.BASE_BTN_H))
    if families.has("toggle"):
        button.name = "TogglePreview"
        button.toggle_mode = true
        button.set_pressed_no_signal(true)
        SaTheme.make_toggle(button)
        return button
    if families.has("button") and SaUI.shared_theme != null:
        button.name = "PushButtonPreview"
        for state: String in SaThemeDefaults.BOXES["Button"]["states"]:
            if SaUI.shared_theme.has_stylebox(state, "Button"):
                button.add_theme_stylebox_override(state, SaUI.shared_theme.get_stylebox(state, "Button"))
        return button
    button.free()
    return null


## A colour that follows nothing and that nothing follows.
func _lone_row(section: SaPageSection, key: String) -> void:
    var title := swatch_title(key)
    _lay_out(section, key, title, "", [_swatch(key, SWATCH_WIDTH)])
    _rows.append({"section": section.title, "title": title, "group": "", "keys": [key]})


## The name a palette field goes by on this page: its lone row's title, its
## swatch's tooltip, and what a state's hint says it is the same as. The word
## for the family goes last, so `bg_panel` is "Panel background" and
## `accent_gauge` "Gauge accent", which reads as what the colour is for rather
## than as the key the file stores. A field with no family word reads as its
## words, so one a palette adds later still has a name.
static func swatch_title(key: String) -> String:
    if SWATCH_NAMES.has(key):
        return SWATCH_NAMES[key]
    var words := Array(key.split("_"))
    if words.size() > 1 and FAMILY_WORDS.has(words[0]):
        words.append(FAMILY_WORDS[words.pop_front()])
    var named := " ".join(PackedStringArray(words))
    return named.left(1).to_upper() + named.substr(1)


## A group's row: the base, then every shade that follows it, then the toggle
## that says whether they follow it. The base is always the painter's to set,
## and a shade is only while the link is off, because a shade a painter can edit
## while it is following the base is a value the next slide of the base throws
## away.
func _group_row(section: SaPageSection, group: String) -> void:
    var keys := SaTheme.group_keys(group)
    var controls: Array[Control] = []
    for key: String in keys:
        controls.append(_swatch(key, GROUP_SWATCH_WIDTH))
    var link := CheckButton.new()
    link.name = String(SaTheme.GROUPS[group]["title"]) + "Link"
    link.set_pressed_no_signal(SaTheme.is_linked(group))
    link.tooltip_text = tr("Linked, the shades follow the base.")
    link.toggled.connect(func(on: bool) -> void: set_link(group, on))
    _links[group] = link
    controls.append(link)
    var title := tr(String(SaTheme.GROUPS[group]["title"]))
    _lay_out(section, group, title, _group_hint(group), controls)
    _rows.append({"section": section.title, "title": title, "group": group, "keys": keys})
    _apply_link_lock(group)


func _group_hint(group: String) -> String:
    var shades := SaTheme.group_members(group).size()
    if shades == 1:
        return tr("The base and the one shade cut from it. Linked, it follows.")
    return (
        tr_n(
            "The base and the %d shade cut from it. Linked, it follows.",
            "The base and the %d shades cut from it. Linked, they follow it.",
            shades
        )
        % shades
    )


## One custom row, named *key*, with the controls packed left to right when
## there is more than one. The row layer draws it, so it is a row to the search
## and to the dump the way every other page's rows are.
func _lay_out(section: SaPageSection, key: String, title: String, hint: String, controls: Array[Control]) -> void:
    var control: Control = controls[0]
    if controls.size() > 1:
        var box := SaMake.row(null, "Swatches", SaTheme.GAP_TIGHT)
        for packed: Control in controls:
            box.add_child(packed)
        control = box
    section.custom(title, control).named(StringName(key)).explain(hint)


func _swatch(key: String, width: int) -> ColorPickerButton:
    var picker := ColorPickerButton.new()
    picker.name = key.to_pascal_case() + "Swatch"
    picker.edit_alpha = true
    picker.color = SaTheme.palette.get(key)
    picker.tooltip_text = swatch_title(key)
    picker.custom_minimum_size = Vector2(SaUI.px(width), SaUI.px(SaUI.BASE_BTN_H))
    picker.color_changed.connect(func(color: Color) -> void: drag_swatch(key, color))
    picker.popup_closed.connect(save_swatches)
    _swatches[key] = picker
    return picker


## Writes *color* into *key*: a fork of the shipped palette first when the
## active one is shipped, then the swatch, applied and saved. What the picker
## calls, and what a scenario drives.
func set_swatch(key: String, color: Color) -> void:
    # The lock is on the page rather than only on the widget, so a scenario
    # driving this method proves the refusal instead of photographing a grey
    # square. A disabled picker cannot emit `color_changed` anyway.
    if not is_swatch_editable(key):
        return
    _fork_if_shipped()
    SaTheme.set_color(key, color)


## What the picker calls on every motion of a drag: *color* is held for *key*
## and applied once at the next frame, the motions of one frame folded into the
## last, and the palette file waits for [method save_swatches].
##
## Each application repaints every bound box and has every window take its
## theme again, a few milliseconds a window, and the picker sends a colour per
## pointer motion, so applying and saving each one held a frame for a second.
## Outside the tree there is no frame to wait for, and it applies at once.
func drag_swatch(key: String, color: Color) -> void:
    if not is_swatch_editable(key):
        return
    # Now rather than at the frame, so the fork's own recolour is not a second
    # one in the frame the drag is applied in.
    _fork_if_shipped()
    _dragged[key] = color
    if not is_inside_tree():
        _apply_dragged()
    elif not get_tree().process_frame.is_connected(_apply_dragged):
        get_tree().process_frame.connect(_apply_dragged, CONNECT_ONE_SHOT)


## Applies whatever the drag left held, then writes the palette file if an
## edit left it unwritten. What closing the picker, the page or Preferences runs.
func save_swatches() -> void:
    _apply_dragged()
    SaTheme.save_unsaved()


func _on_visibility_changed() -> void:
    if not is_visible_in_tree():
        save_swatches()


func _apply_dragged() -> void:
    if is_inside_tree() and get_tree().process_frame.is_connected(_apply_dragged):
        get_tree().process_frame.disconnect(_apply_dragged)
    if _dragged.is_empty():
        return
    _fork_if_shipped()
    var held := _dragged
    _dragged = {}
    for key: String in held:
        SaTheme.set_color(key, held[key], false)


## False for a shade whose group is linked, true for everything else: a base,
## a colour in an unlinked group, and a lone colour that belongs to no group.
func is_swatch_editable(key: String) -> bool:
    var group := SaTheme.group_of(key)
    if group.is_empty() or not SaTheme.group_members(group).has(key):
        return true
    return not SaTheme.is_linked(group)


## Links or unlinks *group*, forking a shipped palette first for the same
## reason a swatch does: a shipped file is never written.
func set_link(group: String, linked: bool) -> void:
    _fork_if_shipped()
    SaTheme.set_linked(group, linked)
    _apply_link_lock(group)


## Greys out the shades of *group* while its link is on, and hands them back
## when it is off.
##
## The base is never locked, and neither is a lone colour, which belongs to no
## group and so never reaches this. The tooltip changes with the state because
## a disabled swatch that says nothing reads as broken rather than as derived.
func _apply_link_lock(group: String) -> void:
    var linked := SaTheme.is_linked(group)
    for key: String in SaTheme.group_members(group):
        var picker := _swatches.get(key, null) as ColorPickerButton
        if picker == null:
            continue
        picker.disabled = linked
        if linked:
            picker.tooltip_text = tr("%s, cut from the base while the link is on.") % swatch_title(key)
        else:
            picker.tooltip_text = swatch_title(key)


func _fork_if_shipped() -> void:
    if not SaTheme.is_custom(SaTheme.palette_id):
        SaSettings.theme_name = SaTheme.fork(SaTheme.palette.display_name + SaTheme.CUSTOM_SUFFIX)


func _on_save_as() -> void:
    var palette_name := save_as_name.text.strip_edges()
    if palette_name.is_empty():
        palette_name = SaTheme.palette.display_name + SaTheme.CUSTOM_SUFFIX
    SaSettings.theme_name = SaTheme.fork(palette_name)
    save_as_name.text = ""


## Delete asks first, and the answer is what deletes.
##
## One press must not lose a painter's palette, so the question is one half of
## the guard and `SaTheme.delete_custom` keeping the file is the other.
##
## The palette's display name goes in the sentence rather than in the title,
## because "Delete this palette?" over a dropdown does not say which one was
## selected when the button was pressed. Hosted on the page, a node that is
## already in the tree by the time a button can be pressed and that outlives the
## answer. `SaMessage.confirm` frees the window on the answer.
func _on_delete() -> void:
    if not SaTheme.is_custom(SaTheme.palette_id):
        return
    SaMessage.confirm(
        self,
        tr("Delete palette"),
        tr("Delete '%s'? The file is kept under 'deleted' beside your palettes.") % SaTheme.palette.display_name,
        PackedStringArray([tr("Cancel"), tr("Delete")]),
        _on_delete_answered.bind(SaTheme.palette_id),
        DELETE_CANCEL,
        DELETE_CANCEL
    )


## The answer to the question above: index 1 is Delete and everything else,
## Escape included, is Cancel.
##
## *doomed* is bound rather than read again, because the answer arrives on a
## later frame and the painter can pick another palette on the dropdown while
## the question is up, which would otherwise send the wrong one to the deleted
## folder.
##
## The same later frame is why the profile is written only when *doomed* was
## still the live palette. A painter who picked Krita Grey under the question
## has already put it on screen and in the profile, and writing the default here
## regardless replaced a palette they had just chosen with one they had not.
## `SaTheme.delete_custom` falls back to the default on screen in the same case,
## so the two stay in step.
func _on_delete_answered(index: int, doomed: String) -> void:
    if index != DELETE_CONFIRM:
        return
    var was_live := SaTheme.palette_id == doomed
    if SaTheme.delete_custom(doomed) and was_live:
        SaSettings.theme_name = "default"


func _on_theme_changed(id: String) -> void:
    # The list changes with the active id only, and reading it again lists the
    # settings folder, which a drag's recolour every frame has no need of.
    if id != _shown_id:
        _refresh_option()
    for key: String in _swatches:
        var picker := _swatches[key] as ColorPickerButton
        var color: Color = SaTheme.palette.get(key)
        if picker.color != color:
            picker.color = color
    for group: String in _links:
        var link := _links[group] as CheckButton
        link.set_pressed_no_signal(SaTheme.is_linked(group))
        # A palette carries its own linked groups, so the locks follow the
        # switch rather than staying as the last palette left them.
        _apply_link_lock(group)


## The dropdown lists what SaTheme offers now, the active one selected, and
## Delete is offered only for the painter's own.
func _refresh_option() -> void:
    _shown_id = SaTheme.palette_id
    _ids.clear()
    for entry: Dictionary in fill_theme_choice(option):
        _ids.append(String(entry["id"]))
    delete_button.disabled = not SaTheme.is_custom(SaTheme.palette_id)


## Fills *choice* with every palette SaTheme offers now, the active one
## selected, and answers the choices, the one list this page and the Interface
## page's row both draw.
static func fill_theme_choice(choice: SaChoiceButton) -> Array:
    var choices: Array = []
    for entry: Dictionary in SaTheme.available():
        choices.append({"id": String(entry["id"]), "label": String(entry["name"])})
    choice.set_choices(choices)
    if not choice.select_value(SaTheme.palette_id) and not choices.is_empty():
        choice.select_value(choices[0]["id"])
    return choices


## What this page shows, one entry per row: its section, its title, whether a
## link holds it together, and every colour in it as its own swatch is showing
## it. The shape is what was built and the values come off the live nodes, so a
## slide that failed to reach a member is a wrong hex here.
##
## The state dump carries this, because twelve swatches in a screenshot cannot
## be read back as numbers and the whole claim is which colour sits in which
## row.
func theme_report() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for row: Dictionary in _rows:
        # An array rather than a dictionary keyed by colour, because
        # `JSON.stringify` sorts keys and the base being first is the point.
        var colors: Array[Dictionary] = []
        for key: Variant in row["keys"]:
            var picker := _swatches[key] as ColorPickerButton
            # Whether the swatch is the painter's to set, which is the whole
            # claim and cannot be read back off a screenshot of a grey square.
            colors.append({"key": key, "hex": picker.color.to_html(), "editable": not picker.disabled})
        var entry := {"section": row["section"], "title": row["title"], "colors": colors}
        if row.has("state"):
            # The ground the sample beside the swatch draws, read off its box,
            # so a dump says whether the page and the interface agree.
            entry["state"] = row["state"]
            var sample := _samples.get(row["keys"][0], null) as Button
            if sample != null:
                var flat := sample.get_theme_stylebox("normal") as StyleBoxFlat
                if flat != null:
                    entry["preview"] = flat.bg_color.to_html()
        if not String(row["group"]).is_empty():
            entry["group"] = row["group"]
            entry["base"] = SaTheme.GROUPS[row["group"]]["base"]
            entry["linked"] = (_links[row["group"]] as CheckButton).button_pressed
        out.append(entry)
    return out


## The one line the `theme_rows` step prints, for the run log.
func describe_theme_rows() -> String:
    var line := "SaCapture: %d colours in %d rows of '%s'" % [_swatches.size(), _rows.size(), SaTheme.palette.display_name]
    var states: Array[String] = []
    for entry: Dictionary in theme_report():
        if entry.has("preview"):
            var swatch: Dictionary = entry["colors"][0]
            states.append("%s=%s/%s" % [swatch["key"], swatch["hex"], entry["preview"]])
    if states.is_empty():
        return line
    return line + ", swatch/sample " + ", ".join(states)


## The page a scenario's drag found, so its later frames walk no tree.
static var _drag_page: WeakRef = null


## Reads the theme colours page: the one behind Interface's Edit colours…, which
## is how a scenario proves the grouping without reading a screenshot,
## `{"theme_rows": {}}`.
##
## `{"theme_rows": {"swatch": "bg_primary", "color": "#503038"}}` drags a
## swatch first and `{"theme_rows": {"link": "background", "on": false}}` the
## toggle, both through the methods the controls call, because a
## `ColorPickerButton` opens a popup an injected click cannot reach.
## `"drag": true` beside a swatch sends the colour, or each of `"colors"`, the
## motions of one frame, the way a motion in the open picker does, and answers
## without reading the rows, whose reading would weigh on the frame measured.
## `{"theme_rows": {"close": true}}` is the picker closing, which saves what the
## drag left.
##
## `{"theme_rows": {"save_as": "Sara Green"}}` types a name and presses the
## button, so a scenario can watch what the dropdown does with a name the
## shipped four already wear, and `{"theme_rows": {"delete": true}}` presses
## Delete on whatever is selected. The pair is what lets a scenario that makes
## forks leave the settings folder as it found it, which matters because the
## number a collision earns counts from what the folder already holds.
##
## Untyped on purpose. A cast to this file's own `class_name` inside a static
## function leaks the script, which leaks 545 live objects.
static func capture_rows(tree: SceneTree, spec: Dictionary = {}) -> String:
    if spec.has("swatch") and bool(spec.get("drag", false)):
        # A drag's frame is what is measured, so the page is found in one walk
        # kept for the drag's later frames, and the rows are not read.
        var found: Object = _drag_page.get_ref() if _drag_page != null else null
        if found == null or not (found as Node).is_inside_tree():
            var pages := tree.root.find_children("*", "SaColorThemesPage", true, false)
            if pages.is_empty():
                return "SaCapture: no open colour themes page to drag a swatch on"
            found = pages[0]
            _drag_page = weakref(found)
        for color: Variant in spec.get("colors", [spec.get("color", "#ffffff")]):
            found.drag_swatch(String(spec["swatch"]), Color(String(color)))
        return "SaCapture: dragged %s" % spec["swatch"]
    for node in tree.root.find_children("*", "Window", true, false):
        if not node.has_method("show_page"):
            continue
        for found in node.find_children("*", "VBoxContainer", true, false):
            if not found.has_method("describe_theme_rows"):
                continue
            elif spec.has("swatch"):
                found.set_swatch(String(spec["swatch"]), Color(String(spec.get("color", "#ffffff"))))
            if bool(spec.get("close", false)):
                found.save_swatches()
            if spec.has("link"):
                found.set_link(String(spec["link"]), bool(spec.get("on", true)))
            if spec.has("save_as"):
                found.save_as_name.text = String(spec["save_as"])
                found.save_as_button.emit_signal("pressed")
            if bool(spec.get("delete", false)):
                found.delete_button.emit_signal("pressed")
            return found.describe_theme_rows()
    return "SaCapture: no open colour themes page to read rows from"


## The active palette, and this page's rows when it is open, for the state dump.
## The palette is reported either way, so a capture that never opens Preferences
## still says which theme its screenshots were taken under.
##
## Untyped page on purpose, for the reason `capture_rows` gives: a cast to a
## `class_name` in a static function leaks the script.
static func capture_state(root: Window) -> Dictionary:
    var linked := Array(SaTheme.palette.linked_groups)
    linked.sort()
    # `offered` is the dropdown itself, name by name: the numbering a collision
    # with a shipped palette earns is a list of names, and no screenshot of a
    # closed OptionButton shows more than the selected one.
    var offered: Array[String] = []
    for entry: Dictionary in SaTheme.available():
        offered.append(String(entry["name"]))
    var out := {
        "palette": SaTheme.palette_id,
        "name": SaTheme.palette.display_name,
        "offered": offered,
        "linked": linked,
        "rows": [],
    }
    for node in root.find_children("*", "Window", true, false):
        if not node.has_method("show_page"):
            continue
        for settings_page in node.find_children("*", "VBoxContainer", true, false):
            if settings_page.has_method("theme_report"):
                out["rows"] = settings_page.theme_report()
                return out
    return out


## The Interface page's row about the theme: the palette in use, picked from the
## list this page's own dropdown draws, and Edit colours… beside it, which opens
## this page. One row where the Colour Themes page was a page, because picking
## a theme is what most painters do here and editing its colours is what few
## do.
##
## Its own page rather than a row of the Workspace page's, so the theme's code
## stays in this file and the Interface page is a list of parts, see
## `SaSettingsWindow.PageParts`.
class ThemeChoice:
    extends SaSettingsPage

    var option: SaChoiceButton
    var edit_button: Button

    ## What Edit colours… calls, or nothing for a row built with no window to
    ## draw the editor in, which leaves the button dimmed.
    var _edit: Callable = Callable()

    func _init(edit: Callable = Callable()) -> void:
        _edit = edit
        super()
        SaColorThemesPage.fill_theme_choice(option)
        EventBus.theme_changed.connect(_on_theme_changed)
        tree_exiting.connect(func() -> void: EventBus.theme_changed.disconnect(_on_theme_changed))

    func build(ui: SaPage) -> void:
        var section := ui.section(tr("Theme"))
        var box := SaMake.row(null, "ThemeBox", SaTheme.GAP)
        # Set before the row is declared, for the reason the editor's Save As
        # row gives.
        box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        option = SaMake.choice(box, "ColorThemeOpt")
        option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        option.choice_picked.connect(func(id: Variant) -> void: SaSettings.theme_name = String(id))
        edit_button = SaMake.button(
            box, "EditColoursButton", tr("Edit colours..."), tr("Every colour of this palette, and your own palettes")
        )
        edit_button.disabled = not _edit.is_valid()
        edit_button.pressed.connect(_on_edit_pressed)
        # The words a search finds the editor by sit in the hint, since the
        # editor is no page of the sidebar and the search reads pages.
        section.custom(tr("Colour theme"), box).named(SaColorThemesPage.THEME_ROW).explain(
            tr(
                (
                    "The palette the interface is drawn with. Applies at once. Edit colours... opens every colour of it, "
                    + "the backgrounds, the accent, the text and each control's states, and saves a palette of your own."
                )
            )
        )

    func _on_edit_pressed() -> void:
        if _edit.is_valid():
            _edit.call()

    ## A palette saved, deleted or switched to elsewhere, the editor's own
    ## dropdown or the welcome window's, shows here while the page is open.
    func _on_theme_changed(_id: String) -> void:
        SaColorThemesPage.fill_theme_choice(option)
