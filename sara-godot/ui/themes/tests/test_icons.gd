## Every icon the UI asks for must ship in res://assets/icons/.
##
## SaUI.get_icon() does not fall back to the editor's "EditorIcons" theme, which is
## stripped from exported builds: an icon reached that way looked fine while
## developing and silently vanished in a release. The fallback is gone, so this
## suite is what keeps the guarantee, add the icon name here when the UI starts
## using a new one.
extends "res://tests/test_framework.gd"

## Names passed to SaUI.get_icon / set_button_icon / make_drag_bar across the UI.
const REQUIRED_ICONS: Array[String] = [
    # Toolbox (toolbox_docker.gd)
    "Paint",
    "Bucket",
    "Eraser",
    "ColorPick",
    "ToolPan",
    "Zoom",
    "Tools",
    "wrench",
    "marquee",
    "lasso",
    "polygonal_lasso",
    "wand",
    "patch",
    "transform",
    "liquify",
    # Layers docker
    "GuiVisibilityVisible",
    "GuiVisibilityHidden",
    "GuiMiniCheckerboard",
    "Lock",
    "Unlock",
    "ToolAddNode",
    "Quad",
    "Duplicate",
    "Clear",
    "VisualShaderNodeComment",
    "group",
    "merge_down",
    "layer_mask",
    # The kind button beside + and a group's fold mark, which the Recorder's
    # and the brush editor's folds draw too
    "chevron_down",
    "chevron_right",
    # The Colour Picker's pair, and reset on the top bar's rotation too
    "swap",
    "reset",
    "undo",
    "redo",
    # The top bar's Focus Mode button, four corners round a point
    "focus_mode",
    # The Transform's pointer by a corner, where a press would turn the box
    "cursor_rotate",
    # Title bar window controls
    "window_minimize",
    "window_maximize",
    "window_close",
    # Tool options bar
    "eraser",
    "size_pressure",
    "opacity_pressure",
    "symmetry_horizontal",
    "symmetry_vertical",
    # Preset chooser stars (brush_preset_stars.gd)
    "star",
    "star_outline",
    # The pin on every docker's bar (docker_pin.gd)
    "pin",
    "pin_outline",
    # The search's loupe after the top bar's last menu title
    "search",
    # The Reference hover bar's grey toggle
    "greyscale",
]


func test_every_required_icon_resolves() -> void:
    var missing: Array[String] = []
    for icon_name in REQUIRED_ICONS:
        if SaUI.get_icon(icon_name) == null:
            missing.append(icon_name)
    assert_true(missing.is_empty(), "Icons missing from res://assets/icons/: %s" % ", ".join(missing))


## get_icon must resolve from the project's own assets only. An editor-only icon
## name has to come back null rather than quietly working in the editor.
func test_unknown_icon_returns_null() -> void:
    assert_null(SaUI.get_icon("NoSuchIconAnywhere"), "An unknown icon must not resolve")
    assert_null(SaUI.get_icon("GuiTabMenuHl"), "An editor-only icon name must not resolve at runtime")


## The lookup tries the lowercased name first, so "Paint" and "paint" are the
## same asset. Callers rely on this: the toolbox passes "Paint", the options bar
## passes "eraser".
func test_icon_lookup_is_case_insensitive() -> void:
    assert_not_null(SaUI.get_icon("Paint"), "Capitalised name should resolve")
    assert_not_null(SaUI.get_icon("paint"), "Lowercase name should resolve")
    assert_eq(SaUI.get_icon("Paint"), SaUI.get_icon("paint"), "Both spellings should be the same asset")
