## The pattern chooser: a grid of tiles, one per pattern in a store, with the
## name under each and the chosen one pressed.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The browser the brush engine spec's deferred texture stage asked for, built to sit
## on the editor's Texture page: it knows a [SaPatternStore] and nothing else, the
## host connects [signal pattern_chosen] and decides what a choice means, and the icon
## size and the column count are the host's to set. Shaped after
## `ui/presets/brush_presets_chooser.gd`, without the search and the tags a dozen
## patterns do not need.
##
## **Every tile is the pattern itself at the icon's size**, a kernel generated
## at that many texels and read back, a picture resized. So the grid is the
## second size every generated pattern is asked for, which is the clause the
## resource is graded on, and a chooser opened at 48 and again at 96 draws two
## different textures rather than one scaled twice.
class_name SaPatternChooser
extends VBoxContainer

## A tile was clicked, or [method pick] was called. The host applies it.
signal pattern_chosen(pattern_name: String)

## The tile sizes a host may ask for, in logical pixels.
const MIN_ICON: int = 32
const MAX_ICON: int = 128
const DEFAULT_ICON: int = 64

## Columns when the host does not say. Three tiles of the default size is what
## the editor's page has room for beside its rows.
const DEFAULT_COLUMNS: int = 3

## The lines a cell gives its name, and the height every cell declares for it,
## so a row is one height whether or not a name needed both. Two, as the
## presets chooser's `NAME_LINES`, and for the same reason: a name is the one
## thing a tile of grey noise cannot say for itself, and past two lines it
## says it in the tooltip.
const NAME_LINES: int = 2

var store: SaPatternStore = null

## The tile's side in logical pixels, and how many tiles across. Both public
## and both read on [method refresh], so a host sets them and refreshes.
var icon_size: int = DEFAULT_ICON
var columns: int = DEFAULT_COLUMNS

## The pattern pressed in the grid, empty for none.
var selected: String = ""

var grid: GridContainer

## Pattern name -> its cell, in the order the grid holds them.
var _cells: Dictionary = {}
var _names: Array[String] = []

## One group, so pressing a tile releases the last one.
var _group := ButtonGroup.new()


func _init(pattern_store: SaPatternStore = null, side: int = DEFAULT_ICON, across: int = DEFAULT_COLUMNS) -> void:
    name = "PatternChooser"
    add_theme_constant_override("separation", SaUI.px(6))
    grid = GridContainer.new()
    grid.name = "ChooserGrid"
    grid.add_theme_constant_override("h_separation", SaUI.px(6))
    grid.add_theme_constant_override("v_separation", SaUI.px(6))
    add_child(grid)
    icon_size = side
    columns = across
    store = pattern_store
    if store != null:
        refresh()


## Rebuilds the grid from the store at the current icon size and column count.
func refresh() -> void:
    for child in grid.get_children():
        grid.remove_child(child)
        child.queue_free()
    _cells.clear()
    _names.clear()
    if store == null:
        return
    var side := clampi(icon_size, MIN_ICON, MAX_ICON)
    grid.columns = maxi(columns, 1)
    for pattern_name: String in store.names():
        _names.append(pattern_name)
        _cells[pattern_name] = _build_cell(pattern_name, side)


## Presses *pattern_name*'s tile and tells the host, the way a click does. A
## name the store does not have clears the choice.
func pick(pattern_name: String) -> void:
    show_choice(pattern_name)
    pattern_chosen.emit(selected)


## Presses *pattern_name*'s tile and tells nobody, which is what a binder
## showing the settings' own value wants: the Texture page mirrors the name
## onto this on every sync, and a pick it did not make must not mark the
## preset dirty.
func show_choice(pattern_name: String) -> void:
    selected = pattern_name if _cells.has(pattern_name) else ""
    for cell_name: String in _cells:
        (_cells[cell_name]["button"] as Button).set_pressed_no_signal(cell_name == selected)


## Every name the grid is showing, in the order it shows them.
func visible_names() -> Array[String]:
    return _names.duplicate()


## What a dump and a scenario read: the names, the choice, the size, how many
## tiles have a picture, and each pattern's error when it has one.
func chooser_report() -> Dictionary:
    var drawn := 0
    var errors: Dictionary = {}
    for pattern_name: String in _names:
        if bool(_cells[pattern_name]["drawn"]):
            drawn += 1
        var pattern := store.pattern(pattern_name) if store != null else null
        if pattern != null and not pattern.error.is_empty():
            errors[pattern_name] = pattern.error
    return {"names": _names.duplicate(), "selected": selected, "icon_size": icon_size, "drawn": drawn, "errors": errors}


## The height `NAME_LINES` lines of a name's font take, the floor every cell
## declares for its name so a short name and a long one stand in one row.
func _name_height() -> float:
    var font := get_theme_font("font", "Label")
    if font == null:
        return float(SaUI.px(SaUI.get_font_size() * NAME_LINES))
    return font.get_height(get_theme_font_size("font_size", "Label")) * float(NAME_LINES)


func _build_cell(pattern_name: String, side: int) -> Dictionary:
    var box := VBoxContainer.new()
    box.name = "Cell_" + pattern_name.validate_node_name()
    box.add_theme_constant_override("separation", SaUI.px(2))

    var button := Button.new()
    button.name = "Tile"
    button.toggle_mode = true
    button.button_group = _group
    button.custom_minimum_size = Vector2(float(SaUI.px(side)), float(SaUI.px(side)))
    button.expand_icon = true
    # The theme caps every button's icon at the toolbar's icon size, which is
    # a third of a tile, so the cap is lifted to the tile's own side here.
    button.add_theme_constant_override("icon_max_width", SaUI.px(side))
    button.tooltip_text = pattern_name
    # The chosen tile wears a frame in the accent colour. The first shots
    # could not tell the pressed tile from the others, the theme's pressed
    # style being a shade on a button whose face is a picture, and a border is
    # the one mark a picture cannot hide. Bound to the palette so a theme
    # change recolours it with everything else.
    var pressed := StyleBoxFlat.new()
    SaTheme.bind(pressed, {"bg_color": "bg_primary", "border_color": "accent_primary"})
    pressed.set_border_width_all(SaUI.px(2))
    button.add_theme_stylebox_override("pressed", pressed)
    button.pressed.connect(func() -> void: pick(pattern_name))
    box.add_child(button)

    var label := Label.new()
    label.name = "Name"
    label.text = pattern_name
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # Wrapped under the tile rather than trimmed to it: on the page a trimmed
    # "Canvas Weave" read "Can", and a name is the one thing a tile of grey
    # noise cannot say for itself.
    #
    # **And wrapped to two lines, not to as many as the name needs**. A name of
    # the length patterns are given, "Flowypaint Texture Gray 0002",
    # wraps to five lines under a 64 pixel tile, and a cell grown to hold them
    # stands taller than the rest of its row. `max_lines_visible` caps the
    # lines, the overrun draws an ellipsis at the end of the second, and the
    # label's tooltip carries the whole name, the way the presets chooser's cell
    # does. By the word alone and not the smart wrap the presets chooser uses:
    # at the page's 64 the shipped "Canvas" and "Screen" are each a hair wider
    # than the tile, and the smart wrap broke them into "Canva s..." and "Dot
    # Scre...", where a whole word overrunning its tile by a pixel reads as it
    # always did.
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    label.max_lines_visible = NAME_LINES
    label.text_overrun_behavior = SaTheme.TEXT_CUT
    label.tooltip_text = pattern_name
    label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    box.add_child(label)
    grid.add_child(box)
    # After the tree, because the height of two lines is the height of two
    # lines of the theme's font, and a Label outside a tree has no theme to ask.
    label.custom_minimum_size = Vector2(float(SaUI.px(side)), _name_height())

    var drawn := false
    var pattern := store.pattern(pattern_name)
    var picture := pattern.image_at(SaUI.px(side)) if pattern != null else null
    if picture != null:
        # **Grey, whatever the pattern came from.** A pattern is one value per
        # texel and `image_at` hands back whichever one-channel format its
        # source produced: `FORMAT_RF` for a loaded picture, and until this the
        # kernel path converted to `FORMAT_L8` on its own. The engine draws a
        # red-only texture as red, so the three GIMP patterns of a Krita import
        # sat on this page as red tiles beside the shipped ones in grey, and the
        # painter read two kinds of pattern where there is one.
        #
        # The convert is here rather than in either loader because this is the
        # one place a pattern becomes a tile, and a rule kept in one of two
        # places is the rule that was already broken.
        picture.convert(Image.FORMAT_L8)
        button.icon = ImageTexture.create_from_image(picture)
        drawn = true
    else:
        button.tooltip_text = pattern.error if pattern != null else pattern_name
    button.set_pressed_no_signal(pattern_name == selected)
    return {"box": box, "button": button, "label": label, "drawn": drawn}
