## Every colour the interface is drawn with, as one resource.
##
## The eleven constants and thirty-two literals across five files were one
## palette spread thin, and the theme dropdown in Preferences wrote a setting
## nothing read. A theme is now a `.tres` of this, under ui/themes/palettes, and
## `SaTheme` reads the active one. A resource rather than a branch, so a widget
## skin can take these as uniforms without a second copy.
##
## The defaults are Sara Green, so a script that makes one and sets nothing
## gets the shipped look.
class_name SaPalette
extends Resource

## What `preview_ground` tests `bg_input` against, and the grey it gives.
const PREVIEW_GROUND_MAX_LIGHTNESS := 0.3
const PREVIEW_GROUND_MAX_CHROMA := 0.045
const PREVIEW_GROUND_LIGHTNESS := 0.21

## The ground of a push button in each state it draws, as the state field it
## reads. `focus` is absent because Godot draws the focus box over the state box
## rather than instead of it, so it has no ground to give. `hover_pressed` is
## absent because no theme Sara builds defines one, and a button with none falls
## through to `pressed`, which was measured rather than assumed.
const BUTTON_GROUNDS := {
    "normal": "button_normal",
    "hover": "button_hover",
    "pressed": "button_pressed",
    "disabled": "button_disabled",
}

## A toggle's box in each state: the ground is the palette's state field and the
## rim a border colour, bound the way `SaTheme.make_dropdown_style` binds its
## own. Focus reads the ground of a toggle that is off.
const TOGGLE_BOXES := {
    "normal": {"bg_color": "toggle_off", "border_color": "border_secondary"},
    "hover": {"bg_color": "toggle_hover", "border_color": "border_hover"},
    "pressed": {"bg_color": "toggle_on", "border_color": "border_selected"},
    "focus": {"bg_color": "toggle_off", "border_color": "border_selected"},
    "disabled": {"bg_color": "toggle_disabled", "border_color": "border_secondary"},
}

## A switch's box in each state: a ground from the switch family's own state
## fields and a rim, bound the way `TOGGLE_BOXES` is. Its focus box stays the
## rim-only one the whole table gives every class.
const SWITCH_BOXES := {
    "normal": {"bg_color": "switch_normal", "border_color": "border_primary"},
    "hover": {"bg_color": "switch_hover", "border_color": "border_hover"},
    "pressed": {"bg_color": "switch_pressed", "border_color": "border_selected"},
    "disabled": {"bg_color": "switch_disabled", "border_color": "border_secondary"},
}

## A dropdown's box in each state it draws: the ground is the palette's state
## field and the rim a border colour, the shape `TOGGLE_BOXES` already has. The
## five states and their bases are the colours the dropdown is drawn from, so a
## palette file that sets none of them, as one saved before the fields does,
## draws the dropdown its bases give.
const DROPDOWN_BOXES := {
    "normal": {"bg_color": "dropdown_normal", "border_color": "border_primary"},
    "hover": {"bg_color": "dropdown_hover", "border_color": "border_hover"},
    "pressed": {"bg_color": "dropdown_pressed", "border_color": "border_selected"},
    "focus": {"bg_color": "dropdown_focus", "border_color": "border_selected"},
    "disabled": {"bg_color": "dropdown_disabled", "border_color": "border_secondary"},
}

## A slider's three parts. `SaTheme.make_slider_style` is the door, and the app's
## own slider, `FactorSlider`, reads the track and the handle. The engine's
## `HSlider`, `VSlider` and `ProgressBar` read the same fields, through
## `SaThemeDefaults`, and `hover` is the fill under a grabber the pointer is on,
## which only the engine's slider draws.
const SLIDER_BOXES := {
    "track": {"bg_color": "slider_track", "border_color": "border_primary"},
    "handle": {"bg_color": "slider_handle"},
    "hover": {"bg_color": "slider_hover"},
}

## A scroll bar's track and its grabber, at rest, hovered and pressed. Its own
## table rather than a row of `SLIDER_BOXES`, because a scroll bar is the
## engine's own control with no app-drawn counterpart, unlike a slider's track
## and handle, which `FactorSlider` draws too.
const SCROLLBAR_BOXES := {
    "track": {"bg_color": "scrollbar_track"},
    "grabber": {"bg_color": "scrollbar_grabber"},
    "hover": {"bg_color": "scrollbar_hover"},
    "pressed": {"bg_color": "scrollbar_pressed"},
}

## A tab in each state it draws, keyed by the engine's own stylebox name so
## `SaThemeDefaults` binds a `TabBar` or a `TabContainer` without a second
## translation table. Nothing in the tree builds a tab today, so these fields
## exist for the first one a module or a page adds, and the ramps they start
## from are the ones the interface already draws control faces with.
const TAB_BOXES := {
    "tab_unselected": {"bg_color": "tab_unselected", "border_color": "border_secondary"},
    "tab_hovered": {"bg_color": "tab_hovered", "border_color": "border_hover"},
    "tab_selected": {"bg_color": "tab_selected", "border_color": "border_selected"},
    "tab_disabled": {"bg_color": "tab_disabled", "border_color": "border_secondary"},
}

## A row of a list: the `SaChoicePopup` row's own button, and the `PopupMenu`
## hover box beside it. `normal` starts at `bg_panel` because a row rests on the
## popup's panel, and the other three start at the push button's ramp colours,
## which is what a row's button resolves today through the shared theme.
const MENU_ROW_BOXES := {
    "normal": {"bg_color": "menu_normal", "border_color": "border_secondary"},
    "hover": {"bg_color": "menu_hover", "border_color": "border_hover"},
    "checked": {"bg_color": "menu_checked", "border_color": "border_selected"},
    "disabled": {"bg_color": "menu_disabled", "border_color": "border_secondary"},
}

## A text field's box in each state it draws. The ground half is the one
## `SaThemeDefaults` once special-cased by class: a field is a hole in the
## interface and a button is a raised part of it. `focus` has no ground, because
## Godot draws the focus box over the state box rather than instead of it.
const FIELD_BOXES := {
    "normal": {"bg_color": "field_normal", "border_color": "border_primary"},
    "read_only": {"bg_color": "field_read_only", "border_color": "border_secondary"},
    "focus": {"border_color": "border_selected"},
}

## Every state field, and the colour it takes while nobody has set it.
##
## A state is a derivation from a base, so the states are not one more colour a
## painter has to fill in for every palette: a palette that sets none of them
## draws its controls from its ramps, and so does a palette file saved before
## the states were fields. The bases are the colours the boxes read by name.
const STATE_BASES := {
    "button_normal": "bg_panel",
    "button_hover": "bg_slider",
    "button_pressed": "bg_secondary",
    "button_disabled": "bg_primary",
    "toggle_off": "bg_input",
    "toggle_hover": "bg_slider",
    "toggle_on": "accent_primary",
    "toggle_disabled": "bg_primary",
    "switch_normal": "bg_panel",
    "switch_hover": "bg_slider",
    # On, which a check button draws as its pressed box, is the accent the toggle
    # button's On already is, so the word means one look wherever it is drawn.
    "switch_pressed": "accent_primary",
    "switch_disabled": "bg_primary",
    "dropdown_normal": "bg_input",
    "dropdown_hover": "bg_slider",
    "dropdown_pressed": "bg_secondary",
    "dropdown_focus": "bg_input",
    "dropdown_disabled": "bg_primary",
    "slider_track": "bg_slider",
    # The gauge rather than the orange fill, so orange on a slider does not
    # claim to mean on, and white on Sara Green's gauge clears 4.5 to 1, which
    # white on the orange does not.
    "slider_handle": "accent_gauge",
    # The engine's slider draws this over the handle's colour whenever the
    # pointer is inside it, so the primary accent flashed orange over the green.
    # A hover still shows on the grabber, which takes `border_selected`.
    "slider_hover": "accent_gauge",
    "scrollbar_track": "bg_secondary",
    "scrollbar_grabber": "text_muted",
    "scrollbar_hover": "scrollbar_grabber",
    "scrollbar_pressed": "scrollbar_grabber",
    "border_hover": "border_primary",
    "title_bar": "accent_primary",
    "tab_unselected": "bg_panel",
    "tab_hovered": "bg_slider",
    "tab_selected": "bg_secondary",
    "tab_disabled": "bg_primary",
    "menu_normal": "bg_panel",
    "menu_hover": "bg_slider",
    "menu_checked": "bg_secondary",
    "menu_disabled": "bg_primary",
    "field_normal": "bg_input",
    "field_read_only": "bg_secondary",
}

## Oklab lightness a hover state sits away from its resting colour, toward the
## text: lighter on a dark ground, darker on a light one. A step of 0.06 left a
## hover at 1.2 to 1 from rest on Paper White, which a painter does not see.
const HOVER_STEP := 0.10

## Which resting state each hover state steps away from.
const HOVER_FROM := {
    "button_hover": "button_normal",
    "toggle_hover": "toggle_off",
    "switch_hover": "switch_normal",
    "dropdown_hover": "dropdown_normal",
    "tab_hovered": "tab_unselected",
    "menu_hover": "menu_normal",
    "border_hover": "border_primary",
    "scrollbar_hover": "scrollbar_grabber",
}

## Oklab lightness a pressed state keeps under its hover state at the least, so
## the two never read as one colour whatever the palette set for the ramp.
const PRESS_GAP := 0.06

## Which hover state each pressed state has to sit under.
const PRESSED_UNDER := {
    "button_pressed": "button_hover",
    "dropdown_pressed": "dropdown_hover",
}

## A state that goes one `HOVER_STEP` further from rest than its hover does, so a
## scroll bar's grabber is one hue in three steps: rest, hovered, held.
const PRESSED_BEYOND := {"scrollbar_pressed": "scrollbar_hover"}

## The contrast `text_primary` has to hold on a colour that carries it.
const TEXT_CONTRAST := 4.5

## The states that draw text over an accent, and so are moved until it reads.
## The slider's handle and hover are not here: they are the gauge, and
## `slider_handle` is pinned to it by `test_engine_sliders`.
const TEXT_GROUNDS := ["toggle_on", "switch_pressed", "title_bar"]

## The contrast a slider's fill holds on its empty track, so the value reads at
## a glance. The fill is the gauge and stays, so the track is what moves.
const SLIDER_CONTRAST := 3.0

## The states a slider's track has to stand apart from: the fill, and the fill
## the engine's slider draws while the pointer is on it.
const SLIDER_FILLS := ["slider_handle", "slider_hover"]

@export var display_name: String = "Sara Green"

## The groups of `SaTheme.GROUPS` whose members follow their base. A palette is
## a few ramps rather than twenty-one free colours, and this is which of them
## are still ramps. Linked is the shipped state, because every shipped palette
## is built as one.
@export var linked_groups: PackedStringArray = ["background", "border", "text"]

## The state fields a painter has set, which [method derive_states] leaves where
## they are. Empty on every shipped palette, so a shipped palette's states are
## its ramps'.
@export var overridden_states: PackedStringArray = []

@export_group("Backgrounds")
@export var bg_primary: Color = Color("#202421")
@export var bg_secondary: Color = Color("#191C1A")
@export var bg_slider: Color = Color("#1A1D1B")
@export var bg_input: Color = Color("#121513")
@export var bg_panel: Color = Color("#2F3431")
@export var bg_sidebar: Color = Color("#1F2320")
@export var bg_track: Color = Color("#161917")

@export_group("Borders")
@export var border_primary: Color = Color("#35704B")
@export var border_secondary: Color = Color("#3B473F")
@export var border_selected: Color = Color("#5EB37E")
@export var border_drag: Color = Color("#F39C12")

@export_group("Accents")
@export var accent_primary: Color = Color("#D2561C")
@export var accent_fill: Color = Color("#DE8055")
@export var accent_gauge: Color = Color("#547A62")
@export var accent_ceiling: Color = Color("#E0B64A")

## The second trace on the Tablet page's pressure pad: the pressure Sara sends
## the brush, over the hardware reading `accent_gauge` draws.
##
## Its own key rather than a shade of anything, for the reason the group's own
## note gives about `accent_gauge`: that one is a green in Sara Green, a blue in
## Photoshop Dark and Krita Grey and a cyan in Solarized, so there is no palette
## in which "a lighter accent" would be reliably telling. What this has to be is
## a hue the gauge is not, and each palette answers that for itself.
@export var accent_stroke: Color = Color("#5A82C8")

@export_group("Text")
@export var text_primary: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var text_muted: Color = Color("#8B978F")
@export var text_shadow: Color = Color(0, 0, 0, 0.7)

@export_group("Depth")
@export var shadow: Color = Color(0, 0, 0, 0.55)
@export var grip_light: Color = Color(0.95, 0.95, 1.0, 0.9)
@export var grip_dark: Color = Color(0.1, 0.1, 0.15, 0.7)

## The push button's grounds. The defaults are Sara Green's bases from
## `STATE_BASES`, so a palette made in a script agrees with itself before
## anything derives it.
@export_group("Push button")
@export var button_normal: Color = Color("#2F3431")
@export var button_hover: Color = Color("#1A1D1B")
@export var button_pressed: Color = Color("#191C1A")
@export var button_disabled: Color = Color("#202421")

## The toggle's grounds: off, hovered while off, on, and disabled.
@export_group("Toggle button")
@export var toggle_off: Color = Color("#121513")
@export var toggle_hover: Color = Color("#1A1D1B")
@export var toggle_on: Color = Color("#D2561C")
@export var toggle_disabled: Color = Color("#202421")

## A switch's grounds, which a check button reads rather than the panel keys.
@export_group("Switch")
@export var switch_normal: Color = Color("#2F3431")
@export var switch_hover: Color = Color("#1A1D1B")
@export var switch_pressed: Color = Color("#D2561C")
@export var switch_disabled: Color = Color("#202421")

## A dropdown's box in each of the five states `DROPDOWN_BOXES` names.
@export_group("Dropdown")
@export var dropdown_normal: Color = Color("#121513")
@export var dropdown_hover: Color = Color("#1A1D1B")
@export var dropdown_pressed: Color = Color("#191C1A")
@export var dropdown_focus: Color = Color("#121513")
@export var dropdown_disabled: Color = Color("#202421")

## The slider's track, the fill under its handle, and that fill while the
## pointer is on an engine slider's grabber.
@export_group("Slider")
@export var slider_track: Color = Color("#1A1D1B")
@export var slider_handle: Color = Color("#547A62")
@export var slider_hover: Color = Color("#547A62")

## The engine's scroll bar: its track, its grabber at rest, hovered and pressed.
## No app control draws one, so these ground the engine's `HScrollBar` and
## `VScrollBar` alone.
@export_group("Scroll bar")
@export var scrollbar_track: Color = Color("#191C1A")
@export var scrollbar_grabber: Color = Color("#8B978F")
@export var scrollbar_hover: Color = Color("#8B978F")
@export var scrollbar_pressed: Color = Color("#8B978F")

## A tab, unselected, hovered, selected and disabled.
@export_group("Tab")
@export var tab_unselected: Color = Color("#2F3431")
@export var tab_hovered: Color = Color("#1A1D1B")
@export var tab_selected: Color = Color("#191C1A")
@export var tab_disabled: Color = Color("#202421")

## A row of a menu or of a `SaChoicePopup`: at rest, hovered, the row the list
## has chosen, and the row a painter cannot press.
@export_group("Menu row")
@export var menu_normal: Color = Color("#2F3431")
@export var menu_hover: Color = Color("#1A1D1B")
@export var menu_checked: Color = Color("#191C1A")
@export var menu_disabled: Color = Color("#202421")

## A text field's ground, at rest and read-only. The focus box has no ground to
## give, which is what the engine draws it for.
@export_group("Text field")
@export var field_normal: Color = Color("#121513")
@export var field_read_only: Color = Color("#191C1A")

## The rim of a control the pointer is over, one step brighter than
## `border_primary`, so a hover and a keyboard focus (`border_selected`, drawn
## wider) are never the same rim.
@export_group("Hover rim")
@export var border_hover: Color = Color("#35704B")

## The docker title bar and the dialog drag bar, `accent_primary` moved until the
## title on it reads.
@export_group("Title bar")
@export var title_bar: Color = Color("#D2561C")

## The ground a picture is previewed on: `bg_input`, unless that is both lighter
## than `PREVIEW_GROUND_MAX_LIGHTNESS` and more chromatic than
## `PREVIEW_GROUND_MAX_CHROMA`, as Pink's is (Oklab 0.49 and 0.086), and then a
## dark grey. Paper White's near white is nearly grey and stays. Derived, so no
## palette file carries it, and read by name through `SaTheme.bind`.
var preview_ground: Color:
    get:
        var lch := OkhslConversions.srgb_to_oklch(bg_input)
        if lch.z > PREVIEW_GROUND_MAX_LIGHTNESS and lch.y > PREVIEW_GROUND_MAX_CHROMA:
            return OkhslConversions.oklch_to_srgb(0.0, 0.0, PREVIEW_GROUND_LIGHTNESS)
        return bg_input


## Keeps the derived `preview_ground` out of the property list the Colour Themes
## page reads for the colours a painter sets.
func _validate_property(property: Dictionary) -> void:
    if property["name"] == "preview_ground":
        property["usage"] = PROPERTY_USAGE_NONE


## Writes every state field nobody has set from its base again.
##
## `SaTheme.use` calls it before it repaints, so a base the painter moves is
## a state that moves with it, and a state they set stays where they set it.
func derive_states() -> void:
    for key: String in STATE_BASES:
        if not overridden_states.has(key):
            set(key, get(String(STATE_BASES[key])))
    for key: String in HOVER_FROM:
        if not overridden_states.has(key):
            set(key, stepped(get(String(HOVER_FROM[key])), text_primary, HOVER_STEP))
    for key: String in PRESSED_UNDER:
        if not overridden_states.has(key):
            set(key, below(get(key), get(String(PRESSED_UNDER[key])), PRESS_GAP))
    for key: String in PRESSED_BEYOND:
        if not overridden_states.has(key):
            set(key, stepped(get(String(PRESSED_BEYOND[key])), text_primary, HOVER_STEP))
    for key: String in TEXT_GROUNDS:
        if not overridden_states.has(key):
            set(key, with_contrast(get(key), text_primary, TEXT_CONTRAST))
    if not overridden_states.has("slider_track"):
        for fill: String in SLIDER_FILLS:
            slider_track = apart_from(slider_track, get(fill), SLIDER_CONTRAST)


## *color* moved *step* of Oklab lightness toward *toward*.
static func stepped(color: Color, toward: Color, step: float) -> Color:
    var lch := OkhslConversions.srgb_to_oklch(color)
    var direction := 1.0 if OkhslConversions.srgb_to_oklch(toward).z > lch.z else -1.0
    return OkhslConversions.oklch_to_srgb(lch.x, lch.y, lch.z + direction * step)


## *color* lowered in Oklab lightness until it sits *gap* under *above*. A colour
## already that far under is returned as it is.
static func below(color: Color, above: Color, gap: float) -> Color:
    var lch := OkhslConversions.srgb_to_oklch(color)
    var limit := OkhslConversions.srgb_to_oklch(above).z - gap
    if lch.z <= limit:
        return color
    return OkhslConversions.oklch_to_srgb(lch.x, lch.y, limit)


## *ground* moved in Oklab lightness, away from *text*, until *text* holds
## *target* contrast on it. A ground that already does is returned as it is.
static func with_contrast(ground: Color, text: Color, target: float) -> Color:
    if contrast_ratio(text, ground) >= target:
        return ground
    var lch := OkhslConversions.srgb_to_oklch(ground)
    var direction := -1.0 if OkhslConversions.srgb_to_oklch(text).z > lch.z else 1.0
    var lightness := lch.z
    var moved := ground
    for _i in 200:
        lightness += direction * 0.005
        moved = OkhslConversions.oklch_to_srgb(lch.x, lch.y, lightness)
        if contrast_ratio(text, moved) >= target or lightness <= 0.0 or lightness >= 1.0:
            break
    return moved


## *ground* moved in Oklab lightness until *fill* holds *target* contrast on it,
## away from *fill* on the side it stands. A ground that already does is
## returned as it is. A fill in the middle of the scale can leave no colour on
## one side far enough from it, and then the ground crosses to the other.
static func apart_from(ground: Color, fill: Color, target: float) -> Color:
    if contrast_ratio(fill, ground) >= target:
        return ground
    var lch := OkhslConversions.srgb_to_oklch(ground)
    var away := -1.0 if OkhslConversions.srgb_to_oklch(fill).z > lch.z else 1.0
    for direction: float in [away, -away]:
        var lightness := lch.z
        for _i in 200:
            lightness += direction * 0.005
            if lightness < 0.0 or lightness > 1.0:
                break
            var moved := OkhslConversions.oklch_to_srgb(lch.x, lch.y, lightness)
            if contrast_ratio(fill, moved) >= target:
                return moved
    return ground


## WCAG contrast ratio of two colours.
static func contrast_ratio(a: Color, b: Color) -> float:
    var la := _relative_luminance(a)
    var lb := _relative_luminance(b)
    return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _relative_luminance(color: Color) -> float:
    var lin := OkhsvConversions.srgb_transfer_function_inv(Vector3(color.r, color.g, color.b))
    return 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z


## Keeps state *key* where it was set rather than deriving it again. A key that
## is not a state is left alone, so a caller that writes any colour need not
## ask first.
func hold_state(key: String) -> void:
    if STATE_BASES.has(key) and not overridden_states.has(key):
        overridden_states.append(key)
