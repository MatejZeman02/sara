## Starring a preset: the star over every cell's picture and the Starred filter
## on the chooser's top row.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `brush_presets_chooser.gd` for the reason
## `SaBrushPresetTags` is: the chooser owns a grid of pictures and which filters
## it is under, the profile owns which presets are starred
## (`SaSettings.preset_favorites`), and this owns the gesture in between. The
## chooser gains the calls and nothing else.
##
## **The star is always there and always at full strength.** An unstarred
## preset shows an outline in the body colour and a starred one a filled star
## in the accent, never a dimmed star, so a painter reads at a glance where the
## click is and what it will do. The colours are the button's own icon colours
## taken from the palette, and taken again on a theme switch, so the stars
## follow it with the loaded cell's rim.
##
## **It costs the grid nothing.** The star is a child of the cell's picture
## button, which is not a container, so the button's minimum size is its own
## declared size and the chooser's column count, taken from the widest cell,
## is the count it was without stars. That keeps the chooser's column ratchet shut.
##
## **A click stars and never loads.** The star is a button over the picture's
## top right corner and takes the press itself, so the picture's `pressed`,
## which is the host's load, never fires.
class_name SaBrushPresetStars
extends RefCounted

## The grid has to be built again: the filter was turned, or the stars moved.
signal changed

## The star's side, in logical pixels. Twelve fits inside the stroke cell's
## fifteen pixel height at the slider's smallest icon of thirty, and reads
## there as a star rather than a speck.
const STAR_SIZE: int = 12

## Every state the star draws its box in. One chip in the button colour for all
## of them, so the star reads over a white paper thumbnail and a dark stroke
## alike, on either theme.
const BOX_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]

## The toggle on the top row. Public because a test and a scenario press it.
var filter: Button = null

## Whether the grid lists the starred presets alone. Held per chooser for the
## session, as the tag is, and written by this class alone.
var starred_only: bool = false

## Preset name -> the star drawn on its cell, for the cells the grid holds now.
var _stars: Dictionary = {}

## The box every star is drawn on, one for the chooser and bound to the palette
## once. A binding per star piled up faster than a rebuild freed its cells.
var _chip: StyleBoxFlat = null

## The profile's stars as the last build saw them. `SaSettings.load_settings`
## writes every key, this one included, so a load that changed nothing still
## says the stars moved, and a suite loading the profile three times rebuilt
## every live grid three times.
var _seen: Array = []


## Takes nothing from the chooser that builds it: the store a question is about
## is handed to that question, since a host can bind another one.
func _init() -> void:
    filter = SaMake.button(null, "ChooserStarred")
    filter.toggle_mode = true
    filter.focus_mode = Control.FOCUS_NONE
    SaUI.set_button_icon(filter, "star")
    # Square at the theme's icon size, because an expanded icon asks for no
    # width and the row's two dropdowns would take all of it.
    var side := float(SaUI.px(SaUI.BASE_ICON_SIZE + 8))
    filter.custom_minimum_size = Vector2(side, side)
    _bind_icon(filter, "text_primary", "accent_primary")
    filter.toggled.connect(_on_filter_toggled)
    _chip = StyleBoxFlat.new()
    SaTheme.bind(_chip, {"bg_color": "bg_slider"})
    _chip.set_corner_radius_all(SaUI.px(3))
    _chip.set_content_margin_all(float(SaUI.px(1)))


## Whether *preset_name* is starred in the profile.
static func is_starred(preset_name: String) -> bool:
    return SaSettings.preset_favorites.has(preset_name)


## The starred presets *store* lists, in the store's order.
static func starred_in_store(store: SaPresetStore) -> Array[String]:
    var starred: Array[String] = []
    if store == null:
        return starred
    for stored_name: String in store.list_names():
        if is_starred(stored_name):
            starred.append(stored_name)
    return starred


## Whether the filter lets *preset_name* through. The chooser asks this beside
## the tag and the search, so the three combine.
func passes(preset_name: String) -> bool:
    return not starred_only or is_starred(preset_name)


## Called by the chooser as it starts a build of *store*'s grid. The cells
## about to be freed let go of their stars, and the toggle is brought to what
## the store holds: off and disabled while nothing in it is starred, by the
## rule that a button that can do nothing is disabled. Turned off
## rather than left on, or a painter who unstars the last preset is left with
## an empty grid and a toggle they cannot press.
func begin_build(store: SaPresetStore) -> void:
    _stars.clear()
    _seen = SaSettings.preset_favorites.duplicate()
    var none := starred_in_store(store).is_empty()
    if none:
        starred_only = false
    filter.set_pressed_no_signal(starred_only)
    filter.disabled = none
    filter.tooltip_text = (
        tr("Nothing is starred yet. Click the star on a preset to star it.")
        if none
        else (tr("Show every preset.") if starred_only else tr("Show only the starred presets."))
    )


## Puts a star on *button*, the picture of *preset_name*'s cell.
func add_to(button: Button, preset_name: String) -> Button:
    var star := SaMake.button(button, "Star")
    star.focus_mode = Control.FOCUS_NONE
    star.expand_icon = true
    star.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    star.add_theme_constant_override("icon_max_width", 0)
    for state: String in BOX_STATES:
        star.add_theme_stylebox_override(state, _chip)
    # Anchored to the corner rather than laid out, since the picture button
    # sorts no children, and a child it does not sort asks it for no room.
    var side := float(SaUI.px(STAR_SIZE))
    star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    star.offset_left = -side
    star.offset_right = 0.0
    star.offset_top = 0.0
    star.offset_bottom = side
    star.pressed.connect(_on_star_pressed.bind(preset_name))
    _stars[preset_name] = star
    _paint(star, preset_name)
    return star


## Hears the profile's stars while *on*, which the chooser says while it is in
## the tree. A chooser out of it, one a suite built or one a host has not shown
## yet, builds from the profile the next time it builds anything.
func listen(on: bool) -> void:
    var hearing := SaSettings.preset_favorites_changed.is_connected(_on_favorites_changed)
    if on and not hearing:
        SaSettings.preset_favorites_changed.connect(_on_favorites_changed)
        # A star made while it was out of the tree. Deferred, because the tree
        # is still adding this chooser and a rebuild moves its children.
        _on_favorites_changed.call_deferred()
    elif not on and hearing:
        SaSettings.preset_favorites_changed.disconnect(_on_favorites_changed)


## A star was clicked. The profile says so to every chooser listening, and this
## one is asked again by hand, which does nothing when the signal already
## rebuilt it and follows the click when it is out of the tree.
func _on_star_pressed(preset_name: String) -> void:
    SaSettings.toggle_preset_favorite(preset_name)
    _on_favorites_changed()


## The profile's stars moved, from this chooser's cell, the other host's, or a
## delete. The grid is built again rather than repainted in place, because
## with the filter on the grid lists other presets, and the second chooser
## follows the first by the same path.
func _on_favorites_changed() -> void:
    if SaSettings.preset_favorites != _seen:
        changed.emit()


func _on_filter_toggled(on: bool) -> void:
    starred_only = on
    changed.emit()


## The palette moved. Every star takes its colours again, since `_paint`
## writes them as values rather than binding each star, which is what the
## chooser's theme notification is for.
func repaint() -> void:
    for stored_name: String in _stars:
        var star: Button = _stars[stored_name]
        if is_instance_valid(star):
            _paint(star, stored_name)


## Draws *star* as its preset stands: filled in the accent, or an outline in
## the body colour, and a tooltip saying what a click does. The icon colours
## are written from the palette rather than bound, because every bind walks
## the whole list of bindings, and a grid of twenty-one cells rebuilt on each
## keystroke of a search, with the old cells not yet freed, grew that list by a
## hundred and twenty-six a build.
func _paint(star: Button, preset_name: String) -> void:
    var on := is_starred(preset_name)
    star.icon = SaUI.get_icon("star" if on else "star_outline")
    var colour: Color = SaTheme.palette.get("accent_primary" if on else "text_primary")
    for state: String in SaThemeDefaults.ICON_STATES:
        star.add_theme_color_override(state, colour)
    star.tooltip_text = tr("Unstar %s.") % preset_name if on else tr("Star %s, so the Starred filter lists it.") % preset_name


## Binds *button*'s icon colours to the palette: *resting* on every state but
## the pressed ones, which take *pressed*, and the disabled one muted.
static func _bind_icon(button: Button, resting: String, pressed: String) -> void:
    for state: String in SaThemeDefaults.ICON_STATES:
        var key := resting
        if state == "icon_pressed_color" or state == "icon_hover_pressed_color":
            key = pressed
        elif state == "icon_disabled_color":
            key = "text_muted"
        SaTheme.bind_font(button, key, state)


## What a dump reads: the starred presets *store* holds, whether the filter
## is on, whether it can be pressed, and what each star on the grid shows.
func report(store: SaPresetStore) -> Dictionary:
    var cells: Dictionary = {}
    for stored_name: String in _stars:
        var star: Button = _stars[stored_name]
        if is_instance_valid(star):
            cells[stored_name] = "filled" if is_starred(stored_name) else "outline"
    return {
        "starred": starred_in_store(store),
        "starred_only": starred_only,
        "filter_disabled": filter.disabled,
        "stars": cells,
    }


## The star on *preset_name*'s cell, or null when the grid is not showing it.
func star_of(preset_name: String) -> Button:
    var star: Button = _stars.get(preset_name, null)
    return star if is_instance_valid(star) else null


## A scenario's `{"preset": {"star": "Ink"}}`: presses that cell's star the way
## a hand would. A preset the grid is not showing is a loud failure.
func capture_star(preset_name: String) -> void:
    var star := star_of(preset_name)
    if star == null:
        push_warning("SaCapture: preset star failed, the grid shows no '%s'" % preset_name)
        return
    star.pressed.emit()


## A scenario's `{"preset": {"starred": true}}`: turns the filter on or off. A
## disabled toggle is a loud failure, as a hand's press on it does nothing.
func capture_filter(on: bool) -> void:
    if filter.disabled and on:
        push_warning("SaCapture: preset starred failed, nothing in the store is starred")
        return
    filter.button_pressed = on
