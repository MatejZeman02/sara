## How large the Tools docker's buttons and its flyouts' rows are, the menu a
## right press on its drag bar opens, and the value kept in the layout file.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The buttons are 40 logical pixels a side unless the painter says otherwise,
## and the window's scale multiplies whatever is chosen, so a size here is on top
## of the UI scale and never instead of it. A painter with a pen wants them
## larger and one short of room wants them smaller, and the scale of the whole
## interface was the only way to either.
##
## **One menu on the bar.** A right press on any docker's drag bar opens its
## opacity, `SaDockerOpacity`. The toolbox's bar opens this menu instead, the
## sizes above and the opacity's steps below, so the bar keeps one menu and the
## opacity stays reachable. The opacity's own handler is taken off the bar once
## it is attached, and its rows here call its `choose`.
##
## **Kept with the layout**, as the opacity is: a key of the docker's section in
## the layout file, so a named layout carries it and loading one puts it back.
## The store is the one `MainDockers` gave the opacity, read off it rather than
## handed a second time, so `main_dockers.gd` takes no line.
class_name SaToolBoxSize
extends Node

## Announced after a size is shown, with the size in logical pixels.
signal size_changed(new_size: int)

## The key of the docker's layout section the value is stored under.
const KEY: String = "button_size"

## The size of a toolbox nobody has resized.
const DEFAULT_SIZE: int = SaUI.BASE_TOOL_BTN

## The ends a size is held to. Below 24 an icon is a smudge, and above 72 a
## column of eight tools is taller than a laptop's screen at its own scale.
const MIN_SIZE: int = 24
const MAX_SIZE: int = 72

## The named steps of the menu, in logical pixels.
const STEPS: Array[int] = [24, 32, 40, 56, 72]

## The side of the corner mark on a button with a flyout, at the default size.
const FLYOUT_MARK_SIDE := 10

## Named, because a suite finds the node, the menu and the slider by name.
const NODE_NAME := &"ToolBoxSize"
const MENU_NAME := &"ToolBoxMenu"
const SLIDER_NAME := &"CustomSize"

## The prefix the opacity's rows carry in this menu, so a size of 50 and an
## opacity of 50 per cent are two rows.
const OPACITY_ROW := "opacity_"

## The prefix of a row standing for a window button the narrow bar folded away,
## followed by the button's node name.
const WINDOW_ROW := "window_"

## The size of the last toolbox built, for the Preferences' tool views, which
## are buttons of the toolbox drawn on a page and are never handed the docker.
static var shown_size: int = DEFAULT_SIZE

## The size shown now, in logical pixels.
var current_size: int = DEFAULT_SIZE

## The menu a right press on the bar opens, built on first use.
var menu: SaChoicePopup = null

var _window: DockerWindow


func _init(window: DockerWindow) -> void:
    name = NODE_NAME
    _window = window


## The bar's right press is this menu's, and an opacity attached later is
## joined to it. Called from the docker's `_ready`, once its bar is built.
func take_the_bar() -> void:
    var bar := _window.drag_handle
    if not bar.gui_input.is_connected(_on_bar_input):
        bar.gui_input.connect(_on_bar_input)
    var content := _window.get_node_or_null("Control")
    if content != null and not content.child_entered_tree.is_connected(_on_child_entered):
        content.child_entered_tree.connect(_on_child_entered)
    _join_opacity()
    # The window buttons' switches and the docker's width both decide the bar's
    # form, and the size's own handler on the docker runs before this one.
    for button in SaNarrowBar.extras(_window):
        if not button.visibility_changed.is_connected(fit_edges):
            button.visibility_changed.connect(fit_edges, CONNECT_DEFERRED)
    if not EventBus.docker_layout_changed.is_connected(snap_to_buttons):
        _window.size_changed.connect(fit_edges, CONNECT_DEFERRED)
        size_changed.connect(overlay_the_grip.unbind(1))
        EventBus.docker_layout_changed.connect(snap_to_buttons)
    # After the opening height the docker grows to, deferred before this.
    snap_to_buttons.call_deferred()


# --- The docker's edges, here because the docker is near the length limit ----


func _scroll() -> ScrollContainer:
    return _window.get_node_or_null("Control/VBoxContainer/Scroll") as ScrollContainer


func _grid() -> GridContainer:
    return _scroll().get_node_or_null("MarginContainer/GridContainer") as GridContainer if _scroll() != null else null


## Folds the bar's window buttons and the scroll's bar away where *width* has
## no room for them. A negative *width* is the docker's own, and 0 the narrowest
## it can be, the form the floor is read in, so neither holds the docker wider
## than its buttons, and the docker's own form follows on the next frame.
func fit_edges(width: float = -1.0) -> void:
    var at := float(_window.size.x) / SaUI.window_scale(_window) if width < 0.0 else width
    SaNarrowBar.fit(_window, at)
    SaToolBoxGrid.fit_scroll_bar(_scroll(), at)
    if width == 0.0:
        fit_edges.call_deferred()


## The grip draws over the corner, where every other docker holds a strip clear
## under its last row for it, as `reserve_grip_corner` explains. Here only the
## last button's corner is under it and the strip was empty docker. The floor is
## the bar and the margins as measured, the bar's theme height rather than the
## `BASE_DRAG_H` the declared floor counts, and one row.
func overlay_the_grip() -> void:
    _window.content_column().offset_bottom = 0.0
    var tall := SaUI.window_size_for(_window, Vector2i(0, roundi(_around_the_grid() + float(SaUI.px(current_size)))))
    _window.min_size = Vector2i(_window.min_size.x, tall.y)
    _window.size = _window.size.max(_window.min_size)


func _around_the_grid() -> float:
    var grid := _grid()
    var held := grid.get_combined_minimum_size().y if grid != null else 0.0
    return float(DockerWindow.column_content_height(_window)) - held


## Cuts the docker to whole rows of its buttons and its width to theirs, when
## the painter lets go of a grip or a bar, which `docker_layout_changed` says,
## and once it has opened. The nearest whole count of rows, one to all of them.
## Never while maximised, and never where the cut would turn a column into a row
## or back, since the shape is the painter's: a row then keeps its width, which
## its buttons fill, and has only its height cut.
func snap_to_buttons() -> void:
    var grid := _grid()
    if not _window.is_inside_tree() or SaDockerMaximise.is_maximised(_window) or grid == null:
        return
    var count := SaToolBoxGrid.visible_button_count(grid)
    if count == 0:
        return
    var columns := maxi(1, grid.columns)
    var button := float(SaUI.px(current_size))
    var gap := float(grid.get_theme_constant(&"v_separation"))
    var around := _around_the_grid()
    var at := Vector2(_window.size) / SaUI.window_scale(_window)
    var rows := clampi(roundi((at.y - around + gap) / (button + gap)), 1, ceili(float(count) / float(columns)))
    fit_edges(0.0)
    var tall := around + rows * button + (rows - 1) * gap
    var narrowest := maxf(grid.get_parent_control().get_combined_minimum_size().x, DockerWindow.column_min_width(_window))
    var cut := Vector2(narrowest, tall)
    for tried: Vector2 in [cut, Vector2(at.x, tall), at]:
        if SaToolBoxGrid.columns_for(count, tried.x, tried.y, button) == columns or tried == at:
            _window.size = SaUI.window_size_for(_window, Vector2i(roundi(tried.x), roundi(tried.y))).max(_window.min_size)
            break
    fit_edges()


## The opacity's node arrives before its `_ready` connects it to the bar, so
## the joining waits a frame for the connection it takes off.
func _on_child_entered(child: Node) -> void:
    if child is SaDockerOpacity:
        _join_opacity.call_deferred()


func _join_opacity() -> void:
    var opacity := SaDockerOpacity.of(_window)
    if opacity == null:
        return
    var bar := _window.drag_handle
    if bar.gui_input.is_connected(opacity._on_bar_input):
        bar.gui_input.disconnect(opacity._on_bar_input)
    var store := opacity._store
    if store != null and not store.presets_changed.is_connected(read_back):
        store.presets_changed.connect(read_back)
    read_back()


## The layout store the docker's opacity was given, or null before it has one.
func _layout_store() -> DockerLayoutStore:
    var opacity := SaDockerOpacity.of(_window)
    return opacity._store if opacity != null else null


## The docker's section of the layout file, its registered id.
func section() -> String:
    return String(_window.name)


## What the layout file holds, the default when it holds nothing or nonsense.
func stored() -> int:
    var store := _layout_store()
    if store == null:
        return DEFAULT_SIZE
    var held: Variant = store.value_for(section(), KEY, DEFAULT_SIZE)
    if not (held is int or held is float):
        return DEFAULT_SIZE
    return clampi(int(held), MIN_SIZE, MAX_SIZE)


## Shows what the layout file holds, after a layout was loaded over it.
func read_back() -> void:
    show_size(stored())


## Shows *value*, held to the ends, and writes nothing. Announces nothing when
## the size is the one shown, so a toolbox reading back its default at start
## lays itself out once, as it did before it had a size.
func show_size(value: int) -> void:
    var held := clampi(value, MIN_SIZE, MAX_SIZE)
    shown_size = held
    if held == current_size:
        return
    current_size = held
    size_changed.emit(current_size)


## The painter's choice: shown, written into the layout file and announced as a
## change of the layout, which is what forks a shipped layout.
func choose(value: int) -> void:
    show_size(value)
    var store := _layout_store()
    if store == null:
        EventBus.docker_layout_changed.emit()
        return
    var cfg := ConfigFile.new()
    # A file not there yet is written fresh, as the store's own save does.
    cfg.load(store.path)
    if current_size == DEFAULT_SIZE:
        if cfg.has_section_key(section(), KEY):
            cfg.erase_section_key(section(), KEY)
    else:
        cfg.set_value(section(), KEY, current_size)
    DirAccess.make_dir_recursive_absolute(store.path.get_base_dir())
    if cfg.save(store.path) != OK:
        push_error("Failed to save the toolbox's button size to %s" % store.path)
        return
    EventBus.docker_layout_changed.emit()


func _mark_side() -> float:
    return float(SaUI.px(roundi(float(FLYOUT_MARK_SIDE) * float(current_size) / float(DEFAULT_SIZE))))


## The icon's widest, half the button, so a small button keeps a margin round
## its icon and a large one does not blow a 24 pixel drawing up past its lines.
func _icon_side() -> int:
    return SaUI.px(clampi(roundi(float(current_size) * 0.5), 16, current_size - 4))


## Sizes a button of the toolbox, its icon and its corner mark to the size
## shown, putting the mark on a button that has none yet. Every category
## button carries one, and the docker shows it only where a flyout is.
func size_button(btn: Button) -> void:
    var side := SaUI.px(current_size)
    btn.custom_minimum_size = Vector2(side, side)
    btn.add_theme_constant_override("icon_max_width", _icon_side())
    var mark := btn.get_node_or_null("FlyoutMark") as FlyoutMark
    if mark != null:
        mark.resize(_mark_side())
        return
    mark = FlyoutMark.new(_mark_side())
    # With offsets and at its minimum size, not `set_anchors_preset`: that moves
    # the anchors and leaves the offsets, so the mark came out zero by zero and
    # drew nothing at all, because a Control
    # with no size draws nothing, however loudly it draws it.
    mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
    SaTheme.bind_font(mark, "text_muted")
    btn.add_child(mark)


## Sizes every button in *buttons* and every row of the flyouts in *flyouts*.
func apply_to_buttons(buttons: Dictionary, flyouts: Dictionary) -> void:
    for btn: Variant in buttons.values():
        if btn is Button and is_instance_valid(btn):
            size_button(btn)
    for flyout: Variant in flyouts.values():
        if flyout is SaToolFlyout and is_instance_valid(flyout):
            (flyout as SaToolFlyout).size_rows(current_size)


## The menu filled with the window buttons the narrow bar folded away, the
## sizes, the custom slider and the opacity's steps, without opening it, which
## is the half a suite runs.
func fill_menu() -> SaChoicePopup:
    if menu == null:
        menu = SaChoicePopup.new()
        menu.name = MENU_NAME
        menu.chosen.connect(_on_row_chosen)
        add_child(menu)
    var list := menu
    list.clear()
    # The button's own words, so a row says what the button would have said and
    # a translation of the one is the translation of the other.
    var folded := SaNarrowBar.folded(_window)
    for button in folded:
        list.add_row(StringName(WINDOW_ROW + String(button.name)), button.tooltip_text.trim_suffix("."))
    if not folded.is_empty():
        list.add_gap()
    list.add_section(tr("Button size"))
    for step: int in STEPS:
        list.add_row(StringName(str(step)), "%d px" % step)
    if current_size in STEPS:
        list.set_current(StringName(str(current_size)))
    _add_slider(list)
    var opacity := SaDockerOpacity.of(_window)
    if opacity != null:
        list.add_gap()
        list.add_section(tr("Background opacity"))
        for step: int in SaDockerOpacity.STEPS:
            list.add_row(StringName(OPACITY_ROW + str(step)), "%d%%" % step)
            if is_equal_approx(float(step) / 100.0, opacity.alpha):
                list.set_current(StringName(OPACITY_ROW + str(step)))
    return list


## The custom size, typed or dragged, in the slider the options bar uses. It
## goes into the menu's column below the steps, which `clear` frees with the rows.
func _add_slider(list: SaChoicePopup) -> void:
    var column := list.find_child("ChoiceColumn", true, false) as Container
    if column == null:
        return
    var slider := FactorSlider.new()
    slider.name = SLIDER_NAME
    slider.min_value = MIN_SIZE
    slider.max_value = MAX_SIZE
    slider.step = 1.0
    slider.decimal_places = 0
    slider.value_format = "%d"
    slider.prefix = tr("Custom: ")
    slider.suffix = " px"
    slider.value = current_size
    slider.default_value = DEFAULT_SIZE
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(func(moved: float) -> void: choose(roundi(moved)))
    column.add_child(slider)


func _on_row_chosen(id: StringName) -> void:
    var text := String(id)
    if text.begins_with(WINDOW_ROW):
        for button in SaNarrowBar.extras(_window):
            if String(button.name) == text.trim_prefix(WINDOW_ROW):
                button.pressed.emit()
        return
    if text.begins_with(OPACITY_ROW):
        var opacity := SaDockerOpacity.of(_window)
        if opacity != null:
            opacity.choose(float(text.trim_prefix(OPACITY_ROW).to_int()) / 100.0)
        return
    choose(text.to_int())


## A right press on the drag bar opens the menu at the pointer. The bar's own
## drag takes the left button only, so the right press is this menu's alone.
func _on_bar_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_RIGHT:
        return
    var bar := _window.drag_handle
    fill_menu().open_under(bar, Vector2(SaPopupRect.at_press(press, bar)))
    bar.accept_event()


## The corner mark itself, a triangle in the font colour `SaTheme.bind_font`
## gives it. Drawn rather than written: it was the glyph U+25E2, which none of
## the four shipped faces has, so it drew only where the system lent a font
## that had it and a box everywhere else.
class FlyoutMark:
    extends Control

    ## The triangle's side in pixels, which is the mark's minimum size too.
    var side: float = 0.0

    func _init(side_px: float) -> void:
        side = side_px
        name = "FlyoutMark"
        # Or the corner eats the press that is supposed to open the flyout.
        mouse_filter = Control.MOUSE_FILTER_IGNORE

    ## A new side, after the button under it was resized. The corner preset is
    ## laid again, since it placed the mark by its old minimum.
    func resize(side_px: float) -> void:
        side = side_px
        update_minimum_size()
        set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
        queue_redraw()

    # The size the corner preset asks for. A `custom_minimum_size` is not: the
    # preset asks `get_minimum_size`, so the mark came out at zero offsets and
    # grew out of the button's corner instead of into it.
    func _get_minimum_size() -> Vector2:
        return Vector2(side, side)

    func _draw() -> void:
        draw_colored_polygon(
            PackedVector2Array([Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]), get_theme_color(&"font_color")
        )
