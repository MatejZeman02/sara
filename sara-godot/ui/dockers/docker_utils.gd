## Helper utility for docker windows to manage drag bars and window backgrounds.
@tool
class_name DockerUtils
extends Object

## Base sizes in logical pixels (kept for compatibility with layout setups)
const BASE_FONT_SIZE: int = SaUI.BASE_FONT_SIZE
const BASE_DRAG_H: int = SaUI.BASE_DRAG_H
const BASE_MARGIN: int = SaUI.BASE_MARGIN
const BASE_SEPARATOR: int = SaUI.BASE_SEPARATOR
const BASE_BTN_H: int = SaUI.BASE_BTN_H
const BASE_TOOL_BTN: int = SaUI.BASE_TOOL_BTN
const BASE_ICON_SIZE: int = SaUI.BASE_ICON_SIZE
const BASE_FACTOR_SLIDER_W: int = SaUI.BASE_FACTOR_SLIDER_W
const BASE_FACTOR_SLIDER_H: int = SaUI.BASE_FACTOR_SLIDER_H

## Smallest docker a user can usefully shrink to, in logical pixels.
const MIN_DOCKER_LOGICAL_SIZE := Vector2i(200, 160)


## Forwarding calls to SaUI
static func px(logical: int) -> int:
    return SaUI.px(logical)


static func pxf(logical: float) -> float:
    return SaUI.pxf(logical)


static func get_icon(icon_name: String) -> Texture2D:
    return SaUI.get_icon(icon_name)


static func set_button_icon(btn: Button, icon_name: String, fallback_text: String = "") -> void:
    SaUI.set_button_icon(btn, icon_name, fallback_text)


## Smallest useful docker size, in physical pixels.
##
## Measured against the screen the docker is actually on: taking the primary
## screen's size gave the wrong floor on a mixed-DPI multi-monitor setup, and the
## old 10%-of-screen term meant a docker on a 4K panel had twice the minimum of
## the same docker on a FullHD one, in logical terms, not just physical.
static func get_min_docker_size(window: Window = null) -> Vector2i:
    var floor_size := SaUI.to_physical_v(MIN_DOCKER_LOGICAL_SIZE)

    var screen := window.current_screen if window != null and window.is_inside_tree() else -1
    var usable := DisplayServer.screen_get_usable_rect(screen)
    if usable.size.x <= 0 or usable.size.y <= 0:
        return floor_size

    # Never demand more than half the screen: a floor larger than the display
    # would make the docker unusable rather than merely small.
    var half := Vector2i(usable.size.x >> 1, usable.size.y >> 1)
    return Vector2i(mini(floor_size.x, half.x), mini(floor_size.y, half.y))


## Create a self-sizing drag-bar PanelContainer with a centred Label or Icon.
##
## *title* is the docker's title in English, the key a catalogue translates
## from, and the bar shows it in the locale set now. `DockerWindow` reads it
## again whenever the locale changes. A bar with an icon has room for nothing
## else, so it says the title on hover, or a tall toolbox would have no name.
static func make_drag_bar(title: String, vertical: bool = false, icon_name: String = "") -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = "DragHandle"

    var style := SaTheme.make_drag_bar_style(vertical)
    if vertical:
        panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
        panel.custom_minimum_size = Vector2(float(SaUI.px(BASE_DRAG_H)), 0.0)
    else:
        panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        panel.custom_minimum_size = Vector2(0.0, float(SaUI.px(BASE_DRAG_H)))

    panel.add_theme_stylebox_override("panel", style)

    if icon_name != "":
        var tex_rect := TextureRect.new()
        tex_rect.name = "TitleIcon"
        tex_rect.texture = get_icon(icon_name)
        tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tex_rect.custom_minimum_size = Vector2(SaUI.px(BASE_ICON_SIZE), SaUI.px(BASE_ICON_SIZE))

        var center := CenterContainer.new()
        center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        center.size_flags_vertical = Control.SIZE_EXPAND_FILL
        center.add_child(tex_rect)
        panel.add_child(center)
        panel.tooltip_text = TranslationServer.translate(title)
    else:
        var lbl := SaGrip.before(SaMake.label(panel, "TitleLabel", title), not vertical and title != "")
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
        # Bound rather than set, so a switch of palette repaints the title on
        # the new bar instead of leaving it in the colour it was built under.
        SaTheme.bind_font(lbl, "text_primary")

    return panel


## Create a sleek dark background panel
##
## **The shadow comes off here**. `SaTheme.make_docker_background_style` asks
## for a soft shadow eight logical units wide, and a docker window is exactly
## this panel's rectangle, so the shadow is clipped away along every straight
## edge and is visible **only** in the four corners, in the wedge the rounded
## radius leaves between the panel and the square window, where it reads as a
## square background creeping back behind round corners. With the shadow off
## the wedge shows the canvas, and the window is already `transparent_bg`, so
## nothing has to be painted: the wedge simply stops being drawn in.
##
## Here rather than in `SaTheme`, because the style is the theme's answer to
## what a docker looks like and this is a docker window's answer to what its own
## rectangle can show. A shadow that a caller could see would still be that
## caller's to draw.
static func create_docker_background(parent: Control) -> Panel:
    var panel := Panel.new()
    panel.name = "DockerBackground"
    panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var style := SaTheme.make_docker_background_style()
    style.shadow_size = 0
    panel.add_theme_stylebox_override("panel", style)

    parent.add_child(panel)
    parent.move_child(panel, 0)
    return panel


# --- Backwards compatibility wrappers ---
static func apply_ui_theme(root: Node) -> void:
    SaUI.apply_ui_theme(root)


static func init_global_theme(tree: SceneTree) -> void:
    SaUI.init_global_theme(tree)


static func apply_docker_ui(root: Node) -> void:
    SaUI.apply_ui_theme(root)


static func apply_compact_ui(root: Node) -> void:
    SaUI.apply_ui_theme(root)


static func style_all_controls(root: Node) -> void:
    SaUI.apply_ui_theme(root)
