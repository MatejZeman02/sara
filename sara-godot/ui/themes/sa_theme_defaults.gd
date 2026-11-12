## The colour a control nobody styled is drawn in: the active palette written
## onto the shared `Theme`, by class name and by theme colour name.
##
## `SaTheme.bind_font` is opt-in. A `Label`, `Button` or `LineEdit` no caller
## reached would keep Godot's own theme, whose text is white and whose fields are
## a mid grey: right under the four dark palettes by accident, and white text on
## paper under Paper White.
##
## A default rather than a sweep of call sites. A control that overrides its own
## colour still wins, so nothing already styled moves, and a control that never
## asked is right without asking. `bind_font` stays for the cases that want a
## key other than the class's default, the `text_muted` on a Preferences hint
## line among them.
##
## Every class and every key below is one Godot's own default theme defines,
## read off `ThemeDB.get_default_theme()` rather than guessed. Class names and
## not type variations, because a variation declared on a `Window.theme` is
## registered and never resolved, as `SaTheme.make_dropdown` explains.
class_name SaThemeDefaults
extends Object

## Class -> theme colour name -> palette key. The whole of the fix.
##
## An icon is in the table for the same reason its label is: Godot modulates a
## button icon by `icon_normal_color`, whose default is white, so a glyph drawn
## in `#e0e0e0` (which is all but one of the thirty-two under `assets/icons/`)
## comes out white and lands invisible on paper. `text_primary` is white in the
## four dark palettes, so the multiply is the identity there and only the light
## one moves.
##
## Read it as three rules. Text a painter is meant to read is `text_primary`,
## whatever state its control is in, because a hover that also dims the words
## is two signals for one event. Text the interface is telling them not to use
## is `text_muted`: disabled rows, a placeholder, an accelerator. A tab that is
## not the chosen one is live, so it is `text_primary` too: dimmed is disabled
## in this app, and the chosen tab is marked by its box rather than by
## greying out the others.
const COLORS := {
    "Label": {"font_color": "text_primary"},
    "TooltipLabel": {"font_color": "text_primary"},
    "RichTextLabel": {"default_color": "text_primary"},
    "ProgressBar": {"font_color": "text_primary"},
    "Button":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_hover_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
        "icon_normal_color": "text_primary",
        "icon_hover_color": "text_primary",
        "icon_pressed_color": "text_primary",
        "icon_hover_pressed_color": "text_primary",
        "icon_focus_color": "text_primary",
        "icon_disabled_color": "text_muted",
    },
    "SpinBox":
    {
        "up_icon_modulate": "text_primary",
        "up_hover_icon_modulate": "text_primary",
        "up_pressed_icon_modulate": "text_primary",
        "up_disabled_icon_modulate": "text_muted",
        "down_icon_modulate": "text_primary",
        "down_hover_icon_modulate": "text_primary",
        "down_pressed_icon_modulate": "text_primary",
        "down_disabled_icon_modulate": "text_muted",
    },
    "OptionButton":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_hover_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
    },
    "MenuButton":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
    },
    "MenuBar":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_hover_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
    },
    "CheckBox":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_hover_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
        "checkbox_checked_color": "text_primary",
        "checkbox_unchecked_color": "text_muted",
    },
    "CheckButton":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_hover_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
        "font_disabled_color": "text_muted",
        "button_checked_color": "text_primary",
        "button_unchecked_color": "text_muted",
    },
    "LinkButton":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_pressed_color": "text_primary",
        "font_focus_color": "text_primary",
    },
    "PopupMenu":
    {
        "font_color": "text_primary",
        "font_hover_color": "text_primary",
        "font_accelerator_color": "text_muted",
        "font_separator_color": "text_muted",
        "font_disabled_color": "text_muted",
    },
    "LineEdit":
    {
        "font_color": "text_primary",
        "font_selected_color": "text_primary",
        "caret_color": "text_primary",
        "font_placeholder_color": "text_muted",
        "font_uneditable_color": "text_muted",
        "clear_button_color": "text_muted",
        "clear_button_color_pressed": "text_primary",
    },
    "TextEdit":
    {
        "font_color": "text_primary",
        "font_selected_color": "text_primary",
        "caret_color": "text_primary",
        "background_color": "bg_input",
        "font_placeholder_color": "text_muted",
        "font_readonly_color": "text_muted",
    },
    "Tree":
    {
        "font_color": "text_primary",
        "font_hovered_color": "text_primary",
        "font_hovered_selected_color": "text_primary",
        "font_selected_color": "text_primary",
        "title_button_color": "text_primary",
        "font_disabled_color": "text_muted",
    },
    "ItemList":
    {
        "font_color": "text_primary",
        "font_hovered_color": "text_primary",
        "font_hovered_selected_color": "text_primary",
        "font_selected_color": "text_primary",
    },
    "TabBar":
    {
        "font_selected_color": "text_primary",
        "font_hovered_color": "text_primary",
        "font_unselected_color": "text_primary",
        "font_disabled_color": "text_muted",
        "icon_selected_color": "text_primary",
        "icon_hovered_color": "text_primary",
        "icon_unselected_color": "text_primary",
        "icon_disabled_color": "text_muted",
    },
    "TabContainer":
    {
        "font_selected_color": "text_primary",
        "font_hovered_color": "text_primary",
        "font_unselected_color": "text_primary",
        "font_disabled_color": "text_muted",
        "icon_selected_color": "text_primary",
        "icon_hovered_color": "text_primary",
        "icon_unselected_color": "text_primary",
        "icon_disabled_color": "text_muted",
    },
    # The title of a fold is the engine's off-white, three greys of it, on a
    # title box `SaThemeFrames` now grounds in the palette.
    "FoldableContainer":
    {
        "font_color": "text_primary",
        "hover_font_color": "text_primary",
        "collapsed_font_color": "text_primary",
    },
}

## Class -> the states whose box comes from the palette, and the horizontal
## margin the engine's own box for that class carries.
##
## Every default button box in Godot's theme is a semi-transparent black,
## `(0.1, 0.1, 0.1, 0.6)` at rest, which is the same dark theme the text half
## of this file is about: over a light ground it composites to a mid grey that
## near-black words then have to fight. So a button's ground is painted here
## for the same reason its text is.
##
## `CheckBox` and `CheckButton` are here although their state boxes are
## `StyleBoxEmpty` in Godot's default theme, which reads as though there were
## no engine dark to replace. That is true of the default theme and not of what
## the control resolves: Godot walks every type of the control's list before it
## reaches that theme, a `CheckBox`'s list is `CheckBox` and then `Button`, and
## the shared theme's `Button` box answers first, the very object
## `get_stylebox("normal", "Button")` holds. Without the two entries below,
## setting the push button's ground would repaint every checkbox and every
## switch with it, and with them the check box family reads none of the push
## button's fields.
##
## The margins are the engine's own, kept, because a control that suddenly
## padded differently would move every row it sits in.
const BOXES := {
    "Button": {"states": ["normal", "hover", "pressed", "disabled", "focus"], "margin_x": 4},
    # `hover_pressed` is the box of a check box or a switch that is on while the
    # pointer is over it. The engine holds an empty box under that name for the
    # two, which a theme with none of its own leaves drawing nothing, so a switch
    # that is on lost its ground the moment it was hovered. A `Button` holds no
    # such name and falls through to `pressed`, so it is not listed.
    "CheckBox": {"states": ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"], "margin_x": 4},
    "CheckButton": {"states": ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"], "margin_x": 4},
    "OptionButton": {"states": ["normal", "hover", "pressed", "disabled", "focus"], "margin_x": 8},
    "MenuButton": {"states": ["normal", "hover", "pressed", "disabled", "focus"], "margin_x": 4},
    "MenuBar": {"states": ["normal", "hover", "pressed", "disabled"], "margin_x": 4},
    "LineEdit": {"states": ["normal", "read_only", "focus"], "margin_x": 4},
    "TextEdit": {"states": ["normal", "read_only", "focus"], "margin_x": 4},
    "PopupMenu": {"states": ["panel", "hover"], "margin_x": 4},
    "TooltipPanel": {"states": ["panel"], "margin_x": 8},
    # Every popup panel, which is what a colour swatch's picker opens in. The
    # engine's own box is a ground of alpha 0.6, and a popup is a transparent
    # window by default, so the docker behind it read through the lower half of
    # the picker, where nothing of its own is drawn.
    "PopupPanel": {"states": ["panel"], "margin_x": 4},
    # The tab, whose boxes the palette grounds. Nothing in the tree builds a
    # `TabBar` today, so these two entries draw nothing on their own: they are
    # what the first tab a module adds resolves.
    "TabBar": {"states": ["tab_unselected", "tab_hovered", "tab_selected", "tab_disabled"], "margin_x": 8},
    "TabContainer": {"states": ["tab_unselected", "tab_hovered", "tab_selected", "tab_disabled"], "margin_x": 8},
}

## The vertical margin every box above carries, which is the engine's.
const MARGIN_Y := 4

## Every state a `Button` modulates its icon in, so a control holding a picture
## rather than a glyph can put them all back to white in one loop.
## `brush_presets_chooser.gd` is the one that does.
const ICON_STATES: Array[String] = [
    "icon_normal_color",
    "icon_hover_color",
    "icon_pressed_color",
    "icon_hover_pressed_color",
    "icon_focus_color",
    "icon_disabled_color",
]

## The ground and the rim of each state, as palette keys. `focus` is the one
## with no ground: Godot draws it over the state box rather than instead of it,
## so a filled focus box would repaint a pressed button as a resting one.
const BOX_COLORS := {
    "normal": {"bg_color": "bg_panel", "border_color": "border_primary"},
    "hover": {"bg_color": "bg_slider", "border_color": "border_hover"},
    "pressed": {"bg_color": "bg_secondary", "border_color": "border_selected"},
    "hover_pressed": {"bg_color": "bg_secondary", "border_color": "border_selected"},
    "disabled": {"bg_color": "bg_primary", "border_color": "border_secondary"},
    "read_only": {"bg_color": "bg_secondary", "border_color": "border_secondary"},
    "panel": {"bg_color": "bg_panel", "border_color": "border_secondary"},
    "focus": {"border_color": "border_selected"},
}

## The classes whose boxes the palette's switch family grounds.
const SWITCH_CLASSES: Array[String] = ["CheckBox", "CheckButton"]

## The states whose ground is the field colour rather than the panel colour: a
## text field is a hole in the interface and a button is a raised part of it,
## and one palette key each is what says so.
const FIELD_CLASSES: Array[String] = ["LineEdit", "TextEdit"]

## The classes whose boxes the palette's tab states ground. The engine asks a
## `TabBar` and a `TabContainer` for their boxes under the same four names, so
## one table covers both, which is why they are a list here rather than an entry
## in each.
const TAB_CLASSES: Array[String] = ["TabBar", "TabContainer"]

## The engine's slider classes, each of its boxes as the part of the palette's
## slider family it draws, and the content margin the engine's own box carries.
## Its own table rather than rows of `BOXES`, because these are parts of one
## control and not states of it, and because the margin is the same on all four
## sides: a slider's track is as thick as its box's margins make it, so 4 is an
## 8 unit track and a progress bar's 2 leaves the bar its text's height. Both
## numbers are read off `ThemeDB.get_default_theme()`, and the suite holds them
## against it.
##
## Nothing in the tree builds a `ProgressBar` today, so its entry is for the
## first one, the way the tab's was written.
const SLIDER_CLASSES := {
    "HSlider": {"margin": 4, "parts": {"slider": "track", "grabber_area": "handle", "grabber_area_highlight": "hover"}},
    "VSlider": {"margin": 4, "parts": {"slider": "track", "grabber_area": "handle", "grabber_area_highlight": "hover"}},
    "ProgressBar": {"margin": 2, "parts": {"background": "track", "fill": "handle"}},
}

## The engine's grabber icon -> the palette colour its disc is drawn in. At rest
## it is the colour of the words beside it, which is the one colour every palette
## guarantees against its own grounds, highlighted it is the rim every hovered
## control already takes, and disabled it is muted like a disabled label.
const SLIDER_DISCS := {
    "grabber": "text_primary",
    "grabber_highlight": "border_selected",
    "grabber_disabled": "text_muted",
}

## The grabber's side in logical units, which is the engine's.
const SLIDER_DISC_SIZE := 16

## The engine's scroll bar classes, each of its boxes as the part of the
## palette's scroll bar family it draws, and which axis its bar runs along. A
## scroll bar's track fills its own length and carries a margin only across its
## thickness, unlike a slider's, which is the same four on every side, so the
## axis decides which pair of sides that margin falls on. Read off
## `ThemeDB.get_default_theme()`, and held against it by the suite.
const SCROLLBAR_CLASSES := {
    "HScrollBar":
    {
        "axis": "horizontal",
        "parts": {"scroll": "track", "grabber": "grabber", "grabber_highlight": "hover", "grabber_pressed": "pressed"}
    },
    "VScrollBar":
    {
        "axis": "vertical",
        "parts": {"scroll": "track", "grabber": "grabber", "grabber_highlight": "hover", "grabber_pressed": "pressed"}
    },
}

## The margin the focus rim carries on every side, which is the engine's own
## number.
const SCROLLBAR_MARGIN := 4

## A scroll bar's thickness in logical pixels, twice the engine's eight. The
## engine's bar was too thin to hit with a pen, so a press aimed at it landed
## beside it. The track's margin across its thickness is half of this on each
## side, which is what makes the engine lay the bar out this wide.
const SCROLLBAR_THICKNESS := 16

## How far in from each long side of the bar the grabber is drawn, in logical
## pixels. The grabber's box is the bar's full thickness, so the whole width
## takes a press, and a border of no colour this wide leaves a drawn grabber
## of ten that sits clear of the track's edges and reads as the thing to take.
const SCROLLBAR_GRABBER_INSET := 3

## The clear room between a scroll container's vertical bar and its own right
## side, in logical pixels, as the right margin of the container's empty panel,
## which the engine lays the bar inside of. A docker's right edge is a resize
## strip `SaDockerEdges.THICKNESS` wide laid over its content, and a scroll
## pinned to that side had its bar's outer half under the strip, so a pen
## aimed at the bar resized the docker. Ten is the strip's four and six of
## nothing between it and the bar.
const SCROLLBAR_EDGE_GAP := 10

## The shortest a grabber is drawn along its bar, in logical pixels. A long
## list shrank the engine's grabber to a sliver a pen could not find.
const SCROLLBAR_GRABBER_LENGTH := 32

## A spin box's two arrows, and the two engine box names each state fills. Godot
## names these boxes by which arrow they belong to rather than by state, unlike
## every class `BOXES` holds, which is why this table and `_spinbox_box` sit
## apart from it. `up_background`, `up_background_disabled`, `down_background`
## and `down_background_disabled` are the four Godot's own theme leaves as
## `StyleBoxEmpty`, and stay that way: an arrow at rest or disabled draws no
## ground, which is the engine's own choice.
const SPINBOX_BOXES := {
    "hover": ["up_background_hovered", "down_background_hovered"],
    "pressed": ["up_background_pressed", "down_background_pressed"],
}


## Writes the palette onto *theme*: the colours, and the boxes bound so that a
## later switch rewrites the same objects in place.
##
## Called once, when the shared theme is built. The colours are redone on every
## switch through [method paint_colors], the boxes never are.
static func paint(theme: Theme) -> void:
    if theme == null:
        return
    paint_colors(theme)
    for cls: String in BOXES:
        var spec: Dictionary = BOXES[cls]
        for state: String in spec["states"]:
            theme.set_stylebox(state, cls, _box(cls, state, int(spec["margin_x"])))
    SaThemeFrames.paint(theme)
    for cls: String in SLIDER_CLASSES:
        var slider: Dictionary = SLIDER_CLASSES[cls]
        for box_name: String in slider["parts"]:
            theme.set_stylebox(box_name, cls, _slider_box(String(slider["parts"][box_name]), int(slider["margin"])))
    for cls: String in SCROLLBAR_CLASSES:
        var scrollbar: Dictionary = SCROLLBAR_CLASSES[cls]
        var horizontal: bool = String(scrollbar["axis"]) == "horizontal"
        for box_name: String in scrollbar["parts"]:
            theme.set_stylebox(box_name, cls, make_scrollbar_style(String(scrollbar["parts"][box_name]), horizontal))
        theme.set_stylebox("scroll_focus", cls, _scrollbar_focus_box())
    theme.set_stylebox("panel", "ScrollContainer", scroll_panel_box())
    for state: String in SPINBOX_BOXES:
        var spin_box := _spinbox_box(state)
        for box_name: String in SPINBOX_BOXES[state]:
            theme.set_stylebox(box_name, "SpinBox", spin_box)
    paint_slider_icons(theme)


## The colour half alone, which is what a theme switch has to redo.
##
## A `Color` on a `Theme` is a value and not an object, so unlike a bound
## stylebox it cannot be rewritten in place: `SaTheme._refresh_bound` calls
## this beside the bound lists for exactly that reason.
##
## Writes only a colour that differs, and answers the theme types whose colours
## moved, which [method retell] takes.
static func paint_colors(theme: Theme) -> Array[String]:
    var moved: Array[String] = []
    if theme == null:
        return moved
    for cls: String in COLORS:
        var keys: Dictionary = COLORS[cls]
        for color_name: String in keys:
            var color: Color = SaTheme.palette.get(keys[color_name])
            if not theme.has_color(color_name, cls) or theme.get_color(color_name, cls) != color:
                theme.set_color(color_name, cls, color)
                if not moved.has(cls):
                    moved.append(cls)
    return moved


## The bound boxes by key, `{palette key: [instance id, property, ...]}`, read
## off `SaTheme._bound_styles` at the first edit after a bind.
static var _boxes_by_key := {}
## The colour each key's boxes were last given by an edit, so the next edit
## writes only the keys that moved.
static var _box_colors := {}
## A copy of the palette a switch wrote every box from, the colour of a key no
## edit has written since, or null when that is not known.
static var _switched: SaPalette = null


## Forgets the index of bound boxes, which a bind leaves out of date.
static func forget_boxes() -> void:
    _boxes_by_key.clear()


## Says every box now holds *written*, as after a switch, or null when a switch
## in slices leaves some boxes behind, so an edit writes each key once more.
static func boxes_hold(written: SaPalette) -> void:
    _boxes_by_key.clear()
    _box_colors.clear()
    _switched = written.duplicate() as SaPalette if written != null else null


## Writes the palette into the boxes of *bound*, `SaTheme`'s table, whose key
## moved since the last edit, each box hushed. Walking all 2,657 boxes to find
## the few a background colour holds took 5 to 7 ms of a dragged frame.
static func paint_edited_boxes(bound: Dictionary) -> void:
    if _boxes_by_key.is_empty():
        for id: int in bound:
            for property: String in bound[id]:
                (_boxes_by_key.get_or_add(bound[id][property], []) as Array).append_array([id, property])
    for key: String in _boxes_by_key:
        var now: Variant = SaTheme.palette.get(key)
        var was: Variant = _switched.get(key) if _switched != null else null
        if _box_colors.get(key, was) == now and now != null:
            continue
        _box_colors[key] = now
        var listed: Array = _boxes_by_key[key]
        for i in range(0, listed.size(), 2):
            var style := instance_from_id(listed[i]) as StyleBox
            if style != null:
                style.set_block_signals(true)
                style.set(listed[i + 1], now)
                style.set_block_signals(false)


## Draws every item in *tree* again, and has the controls and windows of a
## theme type in *moved* take their theme again: what one edited colour needs
## where the shared theme's `changed` would have every control in every window
## take its theme, 150 ms a frame with Preferences open.
##
## The bound boxes are written in place with their own signals hushed, so the
## redraw is what shows them, and only what is shown is drawn again, about a
## fifth of the tree with Preferences open: a hidden item is drawn when it is
## shown. A type in *moved* is a class, or a theme type variation such as
## `TooltipLabel`, looked for among the controls, hidden ones as well, since a
## control keeps the theme it last took until it is told.
static func retell(tree: SceneTree, moved: Array[String]) -> void:
    if tree == null:
        return
    var shown: Array[Node] = [tree.root]
    while not shown.is_empty():
        var node: Node = shown.pop_back()
        if (node is CanvasItem and not (node as CanvasItem).visible) or (node is Window and not (node as Window).visible):
            continue
        if node is CanvasItem:
            (node as CanvasItem).queue_redraw()
        shown.append_array(node.get_children())
    for cls: String in moved:
        var variation := not ClassDB.class_exists(cls)
        for node: Node in tree.root.find_children("*", "Control" if variation else cls, true, false):
            if not variation or (node as Control).theme_type_variation == StringName(cls):
                node.notification(Control.NOTIFICATION_THEME_CHANGED if node is Control else Window.NOTIFICATION_THEME_CHANGED)


## The grabber of an engine slider, drawn from the palette.
##
## The engine's three are light grey textures, so on Paper White the disc at rest
## was white on a ground of 0.95. A texture is not a bound stylebox and cannot be
## rewritten in place, so like a colour it is written again on every switch,
## which is why `SaTheme._refresh_bound` calls this beside `paint_colors`.
##
## Each disc is an SVG handed to `DPITexture`, the class the engine's own grabber
## is: it reports 16 logical units and rasterises at whatever scale the window
## draws it, so nothing here multiplies by a scale and hard rule 7 holds. An
## `ImageTexture` was the other way and was not taken, because it is a fixed
## grid of pixels and a 16 pixel disc on a window at 2 is a blurred one.
##
## A disc is drawn again only when its colour moved, and the answer is the
## slider types then, as [method paint_colors] answers.
static func paint_slider_icons(theme: Theme) -> Array[String]:
    var moved: Array[String] = []
    if theme == null:
        return moved
    for icon_name: String in SLIDER_DISCS:
        var color: Color = SaTheme.palette.get(SLIDER_DISCS[icon_name])
        var held: Texture2D = theme.get_icon(icon_name, "HSlider") if theme.has_icon(icon_name, "HSlider") else null
        if held != null and held.get_meta(&"sa_color", null) == color:
            continue
        var disc := _disc(color)
        disc.set_meta(&"sa_color", color)
        theme.set_icon(icon_name, "HSlider", disc)
        theme.set_icon(icon_name, "VSlider", disc)
        moved.assign(["HSlider", "VSlider"])
    return moved


## A filled disc of *color* with a hairline of the same colour at half strength
## around it, so its edge reads over a fill of any hue.
static func _disc(color: Color) -> DPITexture:
    var side := SLIDER_DISC_SIZE
    var svg := (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 16 16">' % [side, side]
        + '<circle cx="8" cy="8" r="6.5" fill="#%s" fill-opacity="%f"/>' % [color.to_html(false), color.a * 0.5]
        + '<circle cx="8" cy="8" r="5.5" fill="#%s" fill-opacity="%f"/></svg>' % [color.to_html(false), color.a]
    )
    return DPITexture.create_from_string(svg)


## One part of an engine slider. The door's own box, with every corner rounded
## alike: the door's fill is squarer on its right for `FactorSlider`, whose fill
## ends in a flat edge, and an engine fill ends under a round grabber and runs
## upwards in a `VSlider`.
static func _slider_box(part: String, margin: int) -> StyleBoxFlat:
    var style := SaTheme.make_slider_style(part, margin)
    style.set_corner_radius_all(SaUI.px(4))
    return style


## One class's box for one state, bound so a theme switch rewrites it in place.
static func _box(cls: String, state: String, margin_x: int) -> StyleBoxFlat:
    # A text field's ground and rim are the palette's own field states, and the
    # box is the one the strip draws for the family.
    if FIELD_CLASSES.has(cls) and SaPalette.FIELD_BOXES.has(state):
        return make_field_style(state)
    # A tab, which no class in the tree draws yet. The engine's own name for the
    # state is the table's key, so nothing is translated here.
    if TAB_CLASSES.has(cls) and SaPalette.TAB_BOXES.has(state):
        return SaTheme.make_tab_style(state)
    var style := StyleBoxFlat.new()
    var bindings: Dictionary = (BOX_COLORS[state] as Dictionary).duplicate()
    # A push button's ground is the palette's own state field.
    if cls == "Button" and SaPalette.BUTTON_GROUNDS.has(state):
        bindings["bg_color"] = SaPalette.BUTTON_GROUNDS[state]
    # A switch's ground and rim are the switch family's states, and its focus
    # box stays the shared rim-only one. A check box reads the same family, so
    # the two never step differently under the pointer, and a hovered one that
    # is on keeps the ground it has when it is not hovered.
    if cls in SWITCH_CLASSES:
        var family_state := "pressed" if state == "hover_pressed" else state
        if SaPalette.SWITCH_BOXES.has(family_state):
            bindings = (SaPalette.SWITCH_BOXES[family_state] as Dictionary).duplicate()
    # A menu's highlighted row is the menu row family's hovered field. The rim
    # is the same `border_selected` the table names, so a palette that sets
    # none of the family's fields draws the box its bases give.
    if cls == "PopupMenu" and state == "hover":
        bindings["bg_color"] = String((SaPalette.MENU_ROW_BOXES["hover"] as Dictionary)["bg_color"])
    SaTheme.bind(style, bindings)
    if not bindings.has("bg_color"):
        style.bg_color = Color(0, 0, 0, 0)
    style.set_border_width_all(2 if state == "focus" else 1)
    style.set_corner_radius_all(3)
    style.content_margin_left = float(SaUI.px(margin_x))
    style.content_margin_right = float(SaUI.px(margin_x))
    style.content_margin_top = float(SaUI.px(MARGIN_Y))
    style.content_margin_bottom = float(SaUI.px(MARGIN_Y))
    return style


## One state's box for a spin box's arrow: a fill and nothing else, because that
## is what Godot's own `up_background_hovered` and `up_background_pressed` are.
## A border or a margin this file invented would be a mark the engine never drew
## on either arrow, so this does not go through `_box`'s shape the way a push
## button's own hover and pressed boxes do.
static func _spinbox_box(ground_state: String) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"bg_color": SaPalette.BUTTON_GROUNDS[ground_state]})
    return style


## One part's box for an engine scroll bar: the track, the grabber, and the
## grabber hovered or pressed.
##
## Public because the control states strip and the Colour Themes page draw a
## scroll bar in every state, and the box they draw has to be the box the
## interface draws. *horizontal* is which axis the bar's own track runs
## along, because the track's margin sits across its thickness and not along
## its length, and a grabber's inset sits across it too while its length is
## along it.
static func make_scrollbar_style(part: String, horizontal: bool = true) -> StyleBoxFlat:
    var table: Dictionary = SaPalette.SCROLLBAR_BOXES.get(part, SaPalette.SCROLLBAR_BOXES["track"])
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, table)
    var across := float(SaUI.px(SCROLLBAR_THICKNESS)) / 2.0
    if part == "track":
        style.set_corner_radius_all(SaUI.px(4))
        style.content_margin_left = across if not horizontal else 0.0
        style.content_margin_right = across if not horizontal else 0.0
        style.content_margin_top = across if horizontal else 0.0
        style.content_margin_bottom = across if horizontal else 0.0
        return style
    var along := float(SaUI.px(SCROLLBAR_GRABBER_LENGTH)) / 2.0
    var inset := SaUI.px(SCROLLBAR_GRABBER_INSET)
    style.border_color = Color(0, 0, 0, 0)
    style.border_blend = false
    style.border_width_left = inset if not horizontal else 0
    style.border_width_right = inset if not horizontal else 0
    style.border_width_top = inset if horizontal else 0
    style.border_width_bottom = inset if horizontal else 0
    @warning_ignore("integer_division")
    style.set_corner_radius_all(SaUI.px(SCROLLBAR_THICKNESS / 2))
    style.content_margin_left = across if not horizontal else along
    style.content_margin_right = across if not horizontal else along
    style.content_margin_top = across if horizontal else along
    style.content_margin_bottom = across if horizontal else along
    return style


## A scroll container's panel: nothing drawn, as the engine's, with
## `SCROLLBAR_EDGE_GAP` on its right so the vertical bar stands clear of
## whatever lies along the container's right side.
static func scroll_panel_box() -> StyleBoxEmpty:
    var style := StyleBoxEmpty.new()
    style.content_margin_right = float(SaUI.px(SCROLLBAR_EDGE_GAP))
    return style


## The rim `scroll_focus` draws, a border with no ground the way `focus` is
## at line 250 of `BOX_COLORS`: Godot draws it over the state box rather than
## instead of it, so a filled one would repaint a scroll bar at rest.
static func _scrollbar_focus_box() -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, {"border_color": "border_selected"})
    style.bg_color = Color(0, 0, 0, 0)
    style.set_border_width_all(2)
    style.set_corner_radius_all(SaUI.px(4))
    style.set_content_margin_all(float(SaUI.px(SCROLLBAR_MARGIN)))
    return style


## One state's box for a text field: the ground this file once chose by class,
## and the rim it read from `BOX_COLORS`.
##
## Public because the control states strip draws a field in every state, and the
## box it draws has to be the box the interface draws. The two field classes
## share one margin, which is why this takes no margin argument.
static func make_field_style(state: String) -> StyleBoxFlat:
    var table: Dictionary = SaPalette.FIELD_BOXES.get(state, SaPalette.FIELD_BOXES["normal"])
    var style := StyleBoxFlat.new()
    SaTheme.bind(style, table)
    if not table.has("bg_color"):
        # A focus box has no ground: Godot draws it over the state box rather
        # than instead of it, so a filled one would repaint a field at rest.
        style.bg_color = Color(0, 0, 0, 0)
    style.set_border_width_all(2 if state == "focus" else 1)
    style.set_corner_radius_all(3)
    style.content_margin_left = float(SaUI.px(4))
    style.content_margin_right = float(SaUI.px(4))
    style.content_margin_top = float(SaUI.px(MARGIN_Y))
    style.content_margin_bottom = float(SaUI.px(MARGIN_Y))
    return style
