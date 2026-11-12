## The plain preferences: a typed property for each plain row of
## [constant SaSettingsKeys.SETTINGS], whose setter is the row's clamp and the
## announcement, and the two lines every such setter is.
##
## Its own class because it owns the write path of a plain preference, which is
## the row's bounds and how the row is told, and nothing else. A preference whose
## setter does more than clamp keeps its body in [SaSettingsValues], which
## extends this.
##
## **The properties below the marker line are written by
## `scripts/gen_settings_plain.py` from the rows** and are never edited by hand.
## A plain preference is added as its row in [SaSettingsKeys] and its row on a
## Preferences page, and the script then writes its property here. The package's
## suite fails while this file and the rows disagree.
##
## It extends [SaSettingsSearchRecents], the last of the families of preferences
## that left the values file before it, and that chain declares
## [signal SaSettingsImporting.changed].
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsPlain
extends SaSettingsSearchRecents

## Emitted when a key a whole surface has to be rebuilt for changes, which is
## the shortcuts profile, the window buttons and the rows of the top bar.
signal profile_changed

## Whether the last plain write moved its value, which [method _took] finds and
## [method _announce] reads, the two lines of a plain setter.
var _moved := false


## Every plain preference at the default its row declares.
func _init() -> void:
    for property: String in SaSettingsKeys.SETTINGS:
        if SaSettingsKeys.is_plain(property):
            set(property, SaSettingsKeys.SETTINGS[property][2])


## *val* held to *property*'s bounds, noting whether it differs from *now*, the
## value the property holds before the write.
func _took(property: StringName, now: Variant, val: Variant) -> Variant:
    var wanted: Variant = SaSettingsKeys.bounded(property, val)
    if typeof(wanted) == TYPE_FLOAT:
        var before: float = now
        var after: float = wanted
        _moved = not is_equal_approx(before, after)
    else:
        _moved = now != wanted
    return wanted


## Says *property* was written: always, or for a row marked
## [constant SaSettingsKeys.ONCE] or [constant SaSettingsKeys.REBUILD] only when
## the value moved, and the rebuild as well for the second.
func _announce(property: StringName) -> void:
    var how := SaSettingsKeys.how(property)
    if how != 0 and not _moved:
        return
    changed.emit(property)
    if how == SaSettingsKeys.REBUILD:
        profile_changed.emit()


# --- Below this line is written by scripts/gen_settings_plain.py from the rows of SaSettingsKeys. ---

var ui_scale: float:
    set(val):
        ui_scale = _took(&"ui_scale", ui_scale, val)
        _announce(&"ui_scale")

var ui_font_scale: float:
    set(val):
        ui_font_scale = _took(&"ui_font_scale", ui_font_scale, val)
        _announce(&"ui_font_scale")

var embed_subwindows: bool:
    set(val):
        embed_subwindows = _took(&"embed_subwindows", embed_subwindows, val)
        _announce(&"embed_subwindows")

var main_window: Dictionary:
    set(val):
        main_window = _took(&"main_window", main_window, val)
        _announce(&"main_window")

var screen_mode: String:
    set(val):
        screen_mode = _took(&"screen_mode", screen_mode, val)
        _announce(&"screen_mode")

var secondary_workspace_screen: int:
    set(val):
        secondary_workspace_screen = _took(&"secondary_workspace_screen", secondary_workspace_screen, val)
        _announce(&"secondary_workspace_screen")

var secondary_workspace_rect: Rect2i:
    set(val):
        secondary_workspace_rect = _took(&"secondary_workspace_rect", secondary_workspace_rect, val)
        _announce(&"secondary_workspace_rect")

var advanced_options: bool:
    set(val):
        advanced_options = _took(&"advanced_options", advanced_options, val)
        _announce(&"advanced_options")

var experimental_tools: bool:
    set(val):
        experimental_tools = _took(&"experimental_tools", experimental_tools, val)
        _announce(&"experimental_tools")

var second_row: bool:
    set(val):
        second_row = _took(&"second_row", second_row, val)
        _announce(&"second_row")

var docker_hide_button: bool:
    set(val):
        docker_hide_button = _took(&"docker_hide_button", docker_hide_button, val)
        _announce(&"docker_hide_button")

var show_grid: bool:
    set(val):
        show_grid = _took(&"show_grid", show_grid, val)
        _announce(&"show_grid")

var grid_size: int:
    set(val):
        grid_size = _took(&"grid_size", grid_size, val)
        _announce(&"grid_size")

var integer_zoom: bool:
    set(val):
        integer_zoom = _took(&"integer_zoom", integer_zoom, val)
        _announce(&"integer_zoom")

var color_picker_shape: String:
    set(val):
        color_picker_shape = _took(&"color_picker_shape", color_picker_shape, val)
        _announce(&"color_picker_shape")

var keep_blend_mode: bool:
    set(val):
        keep_blend_mode = _took(&"keep_blend_mode", keep_blend_mode, val)
        _announce(&"keep_blend_mode")

var tonemap_highlights: bool:
    set(val):
        tonemap_highlights = _took(&"tonemap_highlights", tonemap_highlights, val)
        _announce(&"tonemap_highlights")

var tonemap_knee: float:
    set(val):
        tonemap_knee = _took(&"tonemap_knee", tonemap_knee, val)
        _announce(&"tonemap_knee")

var tonemap_desaturation: float:
    set(val):
        tonemap_desaturation = _took(&"tonemap_desaturation", tonemap_desaturation, val)
        _announce(&"tonemap_desaturation")

var show_relief: bool:
    set(val):
        show_relief = _took(&"show_relief", show_relief, val)
        _announce(&"show_relief")

var relief_strength: float:
    set(val):
        relief_strength = _took(&"relief_strength", relief_strength, val)
        _announce(&"relief_strength")

var relief_gloss: float:
    set(val):
        relief_gloss = _took(&"relief_gloss", relief_gloss, val)
        _announce(&"relief_gloss")

var display_exposure_enabled: bool:
    set(val):
        display_exposure_enabled = _took(&"display_exposure_enabled", display_exposure_enabled, val)
        _announce(&"display_exposure_enabled")

var display_exposure_stops: float:
    set(val):
        display_exposure_stops = _took(&"display_exposure_stops", display_exposure_stops, val)
        _announce(&"display_exposure_stops")

var display_profile_file: String:
    set(val):
        display_profile_file = _took(&"display_profile_file", display_profile_file, val)
        _announce(&"display_profile_file")

var display_custom_space: Dictionary:
    set(val):
        display_custom_space = _took(&"display_custom_space", display_custom_space, val)
        _announce(&"display_custom_space")

var display_fill: String:
    set(val):
        display_fill = _took(&"display_fill", display_fill, val)
        _announce(&"display_fill")

var proof_profile: String:
    set(val):
        proof_profile = _took(&"proof_profile", proof_profile, val)
        _announce(&"proof_profile")

var proof_profile_file: String:
    set(val):
        proof_profile_file = _took(&"proof_profile_file", proof_profile_file, val)
        _announce(&"proof_profile_file")

var proof_custom_space: Dictionary:
    set(val):
        proof_custom_space = _took(&"proof_custom_space", proof_custom_space, val)
        _announce(&"proof_custom_space")

var software_cursor: String:
    set(val):
        software_cursor = _took(&"software_cursor", software_cursor, val)
        _announce(&"software_cursor")

var window_button_position: String:
    set(val):
        window_button_position = _took(&"window_button_position", window_button_position, val)
        _announce(&"window_button_position")

var window_button_style: String:
    set(val):
        window_button_style = _took(&"window_button_style", window_button_style, val)
        _announce(&"window_button_style")

var welcome_at_start: bool:
    set(val):
        welcome_at_start = _took(&"welcome_at_start", welcome_at_start, val)
        _announce(&"welcome_at_start")

var show_last_session: bool:
    set(val):
        show_last_session = _took(&"show_last_session", show_last_session, val)
        _announce(&"show_last_session")

var last_version_seen: String:
    set(val):
        last_version_seen = _took(&"last_version_seen", last_version_seen, val)
        _announce(&"last_version_seen")

var last_tip_shown: String:
    set(val):
        last_tip_shown = _took(&"last_tip_shown", last_tip_shown, val)
        _announce(&"last_tip_shown")

var tablet_driver: String:
    set(val):
        tablet_driver = _took(&"tablet_driver", tablet_driver, val)
        _announce(&"tablet_driver")

var theme_name: String:
    set(val):
        theme_name = _took(&"theme_name", theme_name, val)
        _announce(&"theme_name")

var ui_font: String:
    set(val):
        ui_font = _took(&"ui_font", ui_font, val)
        _announce(&"ui_font")

var shortcuts_profile: String:
    set(val):
        shortcuts_profile = _took(&"shortcuts_profile", shortcuts_profile, val)
        _announce(&"shortcuts_profile")

var sad_versions: int:
    set(val):
        sad_versions = _took(&"sad_versions", sad_versions, val)
        _announce(&"sad_versions")

var autosave_interval_minutes: float:
    set(val):
        autosave_interval_minutes = _took(&"autosave_interval_minutes", autosave_interval_minutes, val)
        _announce(&"autosave_interval_minutes")

var autosave_to_working_file: bool:
    set(val):
        autosave_to_working_file = _took(&"autosave_to_working_file", autosave_to_working_file, val)
        _announce(&"autosave_to_working_file")

var recorder_settle_seconds: float:
    set(val):
        recorder_settle_seconds = _took(&"recorder_settle_seconds", recorder_settle_seconds, val)
        _announce(&"recorder_settle_seconds")

var selection_feather: float:
    set(val):
        selection_feather = _took(&"selection_feather", selection_feather, val)
        _announce(&"selection_feather")

var preset_icon_size: int:
    set(val):
        preset_icon_size = _took(&"preset_icon_size", preset_icon_size, val)
        _announce(&"preset_icon_size")

var preset_thumb_tip: bool:
    set(val):
        preset_thumb_tip = _took(&"preset_thumb_tip", preset_thumb_tip, val)
        _announce(&"preset_thumb_tip")

var brush_editor_page: String:
    set(val):
        brush_editor_page = _took(&"brush_editor_page", brush_editor_page, val)
        _announce(&"brush_editor_page")

var brush_editor_presets_open: bool:
    set(val):
        brush_editor_presets_open = _took(&"brush_editor_presets_open", brush_editor_presets_open, val)
        _announce(&"brush_editor_presets_open")

var brush_editor_pad_width: int:
    set(val):
        brush_editor_pad_width = _took(&"brush_editor_pad_width", brush_editor_pad_width, val)
        _announce(&"brush_editor_pad_width")

var brush_editor_pad_shut: bool:
    set(val):
        brush_editor_pad_shut = _took(&"brush_editor_pad_shut", brush_editor_pad_shut, val)
        _announce(&"brush_editor_pad_shut")

var brush_editor_presets_width: int:
    set(val):
        brush_editor_presets_width = _took(&"brush_editor_presets_width", brush_editor_presets_width, val)
        _announce(&"brush_editor_presets_width")

var history_depth: int:
    set(val):
        history_depth = _took(&"history_depth", history_depth, val)
        _announce(&"history_depth")

var visibility_in_history: bool:
    set(val):
        visibility_in_history = _took(&"visibility_in_history", visibility_in_history, val)
        _announce(&"visibility_in_history")

var half_size_view_while_moving: bool:
    set(val):
        half_size_view_while_moving = _took(&"half_size_view_while_moving", half_size_view_while_moving, val)
        _announce(&"half_size_view_while_moving")
