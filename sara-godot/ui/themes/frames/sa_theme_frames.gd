## The boxes a container draws behind what it holds, and the rules between
## things, written onto the shared `Theme` from the palette.
##
## A responsibility of its own beside `SaThemeDefaults`, which keeps the colours
## and the boxes of the controls that have states: these are the frames and the
## lines, found by sweeping every class Sara's UI makes against what the theme
## set.
class_name SaThemeFrames
extends Object

## Class -> box name -> `[role, margin]`, the boxes a container draws behind what
## it holds, or around the thing a keyboard has reached, that are still the
## engine's own after `BOXES`.
##
## Every class Sara's UI makes, read against what the theme sets. Left to the
## engine, such a box is `(0.1, 0.1, 0.1, 0.6)`, the same semi-transparent
## black every default box in Godot's theme is, and laid over a light palette's
## cream window it comes out a mid grey that muted descriptions on it cannot be
## read against. Under the dark palettes that black is close to the window's
## own colour, which hides it.
##
## A role is what the box is for, and `_frame_bindings` says which palette keys
## it reads: a `page` is the colour a page sits on, which is the window's own,
## so a pane is flush with the window the way a Preferences page is. The margin
## is the engine's own for that box. A box is never given less margin than its
## border is thick, so the content never sits under the rim, which moves the
## engine's margin of 0 to 1 on the classes whose box had none.
##
## What stays the engine's is in `test_a_tab_container_panel_is_drawn_from_the_palette.gd`
## beside the reason, because a list of exceptions is a list the suite can hold.
const FRAMES := {
    "TabContainer": {"panel": ["page", 0], "tab_focus": ["rim", 4]},
    "TabBar": {"tab_focus": ["rim", 4]},
    "PanelContainer": {"panel": ["panel", 0]},
    "Panel": {"panel": ["panel", 0]},
    "ItemList":
    {
        "panel": ["field", 4],
        "hovered": ["hover", 4],
        "selected": ["chosen", 4],
        "selected_focus": ["chosen", 4],
        "hovered_selected": ["chosen", 4],
        "hovered_selected_focus": ["chosen", 4],
        "focus": ["rim", 4],
        "cursor": ["rim", 4],
        "cursor_unfocused": ["rim", 4],
    },
    "FoldableContainer":
    {
        "panel": ["panel", 4],
        "title_panel": ["title", 4],
        "title_hover_panel": ["title_hover", 4],
        "title_collapsed_panel": ["title", 4],
        "title_collapsed_hover_panel": ["title_hover", 4],
        "focus": ["rim", 4],
    },
    "LinkButton": {"focus": ["rim", 4]},
    "RichTextLabel": {"focus": ["rim", 4]},
    "ScrollContainer": {"focus": ["rim", 4]},
    "ColorPicker": {"sample_focus": ["rim", 4], "picker_focus_rectangle": ["rim", 4], "picker_focus_circle": ["rim", 4]},
}

## Class -> the line boxes whose colour is the palette's rule colour. A rule is
## a `StyleBoxLine`, which has no ground and no margin to keep, only a colour,
## a thickness and how far it grows past its ends. So it is the engine's own box
## copied, with the colour alone bound: the engine's white at a low alpha is a
## rule on a dark ground and a smear on a light one.
const LINES := {
    "HSeparator": ["separator"],
    "VSeparator": ["separator"],
    "PopupMenu": ["separator", "labeled_separator_left", "labeled_separator_right"],
}


## Writes every frame and every rule onto *theme*, bound so that a later switch
## rewrites the same objects in place.
##
## Called once, from `SaThemeDefaults.paint`, when the shared theme is built.
static func paint(theme: Theme) -> void:
    for cls: String in FRAMES:
        var boxes: Dictionary = FRAMES[cls]
        for box_name: String in boxes:
            var spec: Array = boxes[box_name]
            theme.set_stylebox(box_name, cls, frame(String(spec[0]), int(spec[1])))
    for cls: String in LINES:
        for box_name: String in LINES[cls]:
            theme.set_stylebox(box_name, cls, _rule(cls, box_name))


## One box of `LINES`: the engine's line with its colour bound to the palette.
static func _rule(cls: String, box_name: String) -> StyleBoxLine:
    var line := ThemeDB.get_default_theme().get_stylebox(box_name, cls).duplicate() as StyleBoxLine
    SaTheme.bind(line, {"color": "border_secondary"})
    return line


## One box of `FRAMES`, bound so a theme switch rewrites it in place.
##
## Public so a container that wants the table's box with a margin of its own
## asks for it here: the Welcome window's tab panel keeps the window's margin
## and the other tab containers keep the engine's.
static func frame(role: String, margin: int) -> StyleBoxFlat:
    var bindings := _frame_bindings(role)
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, bindings)
    # A rim is drawn over what is under it, so it has no ground of its own.
    if not bindings.has("bg_color"):
        style.bg_color = Color(0, 0, 0, 0)
    var border := 2 if role == "rim" else 1
    style.set_border_width_all(border)
    style.set_corner_radius_all(3)
    style.set_content_margin_all(float(SaUI.px(maxi(margin, border))))
    return style


## The palette keys a role of `FRAMES` reads, taken from the tables the rest of
## the interface already draws from so that a box here is the same colour as the
## control of that kind elsewhere.
static func _frame_bindings(role: String) -> Dictionary:
    match role:
        # The colour a Preferences page sits on, which is the window's own.
        "page":
            return {"bg_color": "bg_primary", "border_color": "border_secondary"}
        "panel":
            return SaThemeDefaults.BOX_COLORS["panel"]
        # A list is a hole in the interface the way a text field is.
        "field":
            return SaPalette.FIELD_BOXES["normal"]
        "hover":
            return SaPalette.MENU_ROW_BOXES["hover"]
        "chosen":
            return SaPalette.MENU_ROW_BOXES["checked"]
        # A fold's title is a button, resting and hovered.
        "title":
            var resting: Dictionary = SaThemeDefaults.BOX_COLORS["normal"]
            return {"bg_color": SaPalette.BUTTON_GROUNDS["normal"], "border_color": resting["border_color"]}
        "title_hover":
            var hovered: Dictionary = SaThemeDefaults.BOX_COLORS["hover"]
            return {"bg_color": SaPalette.BUTTON_GROUNDS["hover"], "border_color": hovered["border_color"]}
        _:
            return SaThemeDefaults.BOX_COLORS["focus"]
