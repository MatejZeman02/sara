## What a changed preference does to the running application.
##
## The push half of the settings. `SaSettingsValues` says which preference moved
## and this is what tells the theme, the fonts, the cursor, the tonemapper and
## the root window about it. An input source hears the setting it names through
## its own registry, so it is not told here. Here rather than inside each
## preference's setter, so a setter is the config write and the save and nothing
## that reaches into the tree.
##
## Its own autoload, right after `SaSettings` in `project.godot`, so
## `SaSettings._ready()` has loaded the profile from disk before this one
## applies it. Not something the boot builds: the suites run with no main window
## and still expect a changed scale to reach `SaUI`, which an autoload's own
## `_ready()` gives for nothing, whatever scene is running.
##
## Beside the Preferences window, rather than in `ui/themes`, because it pushes
## a preference into the theme, the fonts, the cursor, the tonemapper and the
## root window, and is none of them.
##
## `@tool` for the same reason `SaSettings` is: the editor loads both.
@tool
extends Node

## The dockers are about to be let out of the main window or taken back into
## it, and every window still measures its position the old way. The layout
## store remembers each docker's place here.
signal embedding_will_change

## The switch is made and every window it hid is shown again, so a position
## now means the new side's. The layout store puts each docker back here.
signal embedding_changed

## Instance id -> the rectangle a window the switch hid last had inside the
## main window, in its logical space. Written as the windows go out, read as
## they come back in.
var _stood_inside: Dictionary = {}


## Nothing to build, and here for the boot mark alone, whose gap since the
## autoload before it is this script's own load.
func _init() -> void:
    SaBootMarks.mark(&"settings_apply_init")


func _ready() -> void:
    SaBootMarks.mark(&"settings_apply_ready_begin")
    # The editor loads this autoload too, and the runners' class cache rescan
    # starts one, but `SaPalette` is no tool script, so the theme it would push
    # is a placeholder there and `derive_states` raises a script error.
    if Engine.is_editor_hint():
        return
    SaSettings.changed.connect(_on_value_changed)
    SaSettings.proof_mode_replaced.connect(_on_proof_mode_replaced)
    _apply_on_ready()
    SaBootMarks.mark(&"settings_apply_ready_end")


## The WinTab look `_apply_on_ready` started may still be waiting on its
## helper when Sara quits, and a thread left running at exit is not a clean
## exit, so it is let go here.
func _exit_tree() -> void:
    SaTabletDriver.stop_looking()


## The pushes a launch owes, after the profile has been read.
##
## `load_from_disk()` runs before the tree is ready for some of these, so
## without this the persisted scale is read from disk and applied to nothing.
func _apply_on_ready() -> void:
    SaUI.user_scale = maxf(0.1, SaSettings.ui_scale)
    SaUI.user_font_scale = clampf(SaSettings.ui_font_scale, SaUI.MIN_FONT_SCALE, SaUI.MAX_FONT_SCALE)
    _apply_ui_scale()
    # The palette the profile named, before any window is built.
    SaTheme.use_named(SaSettings.theme_name)
    _apply_embed_subwindows()
    # The tablet driver the profile asked for, over the project's default.
    SaTabletDriver.apply_stored()
    # The language, before any window is built, so the first `tr()` reads it.
    # The catalogue it names arrives with its module and is read from then on.
    _apply_language()
    _apply_screen_mode()


## The preferences the canvas material is built from. Each one announces the
## same change, because what the material reads is the whole chain rather than
## the key that moved. The Shape Check's are not listed here but read off
## `SaSettings.shape_check_uniforms()`, the one list of them the canvas writes
## from, so an option the Shape Check gains reaches the material without a
## second list to forget. The relief's light and strength are not here, because
## they are the document's, `SaReliefLight`, and the two settings say only where
## a new document's start.
const VIEW_KEYS: Array[StringName] = [
    &"tonemap_highlights",
    &"tonemap_knee",
    &"tonemap_desaturation",
    &"gamut_mapping",
    &"display_exposure_enabled",
    &"display_exposure_stops",
    &"display_profile",
    &"display_profile_file",
    &"display_fill",
    &"proof_profile",
    &"proof_profile_file",
    &"show_relief",
    &"relief_gloss",
]


## One preference moved, so whatever it drives is told.
func _on_value_changed(property: StringName) -> void:
    if VIEW_KEYS.has(property) or SaSettings.shape_check_uniforms().has(String(property)):
        EventBus.tonemap_changed.emit(SaSettings.tonemap_highlights)
        return
    match property:
        &"ui_scale":
            SaUI.user_scale = SaSettings.ui_scale
            _apply_ui_scale()
        &"ui_font_scale":
            SaUI.user_font_scale = SaSettings.ui_font_scale
            _apply_ui_font_scale()
        &"embed_subwindows":
            _apply_embed_subwindows()
        &"advanced_options":
            EventBus.advanced_options_changed.emit(SaSettings.advanced_options)
        &"theme_name":
            SaTheme.use_named(SaSettings.theme_name)
        &"ui_font":
            SaFonts.use(SaSettings.ui_font)
        &"software_cursor":
            SaCursorPolicy.sync_os_cursor_visibility()
        &"ui_language":
            _apply_language()
        &"screen_mode":
            _apply_screen_mode()


## The locale the profile names, set on `TranslationServer`, which every
## `tr()` reads from then on. Not in the editor, whose own words would follow
## it, since this script is a tool script.
func _apply_language() -> void:
    if not Engine.is_editor_hint():
        TranslationServer.set_locale(SaSettings.ui_language)


## The screen mode choice on Android, full screen a few rows short of the
## display or maximised under the system bars. The full screen toggle keeps the
## choice it made, so its press arrives here as well.
func _apply_screen_mode() -> void:
    if OS.has_feature("android") or OS.get_name() == "Android":
        SaAndroidWindow.shared().apply_choice(
            SaSettings.screen_mode,
            func() -> DisplayServer.WindowMode: return DisplayServer.window_get_mode(),
            func(mode: DisplayServer.WindowMode) -> void: DisplayServer.window_set_mode(mode)
        )


## The canvas proof mode was replaced, which the docker and the canvas both
## rebuild on, and which is the one push that needs the id that was there.
func _on_proof_mode_replaced(previous: String, current: String) -> void:
    EventBus.canvas_proof_mode_changed.emit(StringName(previous), StringName(current))


## Push the scale onto the root window and tell everything else to re-apply.
##
## Dockers and workspace hosts have their own Window and therefore their own
## content_scale_factor, so they cannot inherit the root's: they listen for
## ui_scale_changed and call SaUI.apply_to_window on themselves.
func _apply_ui_scale() -> void:
    if not is_inside_tree():
        return
    SaUI.apply_to_window(get_tree().root)
    EventBus.ui_scale_changed.emit(SaUI.scale())


## Rewrites the shared theme and tells the interface to re-apply it.
##
## Deliberately not ui_scale_changed: that signal makes every window re-derive
## its size from the logical size its constructor set, so announcing a font
## change through it would snap a docker the painter had resized back to its
## default. Nothing here writes content_scale_factor (hard rule 7).
func _apply_ui_font_scale() -> void:
    SaUI.refresh_font_sizes()
    if not is_inside_tree():
        return
    EventBus.ui_font_scale_changed.emit(SaSettings.ui_font_scale)


## Applies the embedded-subwindow choice. Godot refuses this while any child
## window is displayed, so windows are hidden, the change made, put back.
##
## **The one door to the switch.** The Workspace page's row and the welcome
## window's both write `SaSettings.embed_subwindows`, and its `changed` is what
## runs this, so neither has a way round it.
##
## A window's position means a place in the main window's logical space on one
## side of the switch and a place on the screen on the other, and nothing put
## one back for the other, so taking the dockers back in piles them all in the
## top left corner, over the menus. The dockers are the layout store's, which
## hears the two signals either side of the switch. Any other window shown
## again, Preferences above all, goes back to the rectangle it had the last time
## it was inside. A window of the system under Wayland is given no position and
## reads (0, 0), so without the rectangle Preferences comes back over the menu
## bar, and shorter as well, at a size its own tracking took from the window the
## system had been drawing.
func _apply_embed_subwindows() -> void:
    var vp := get_viewport()
    if vp == null or vp.gui_embed_subwindows == SaSettings.embed_subwindows:
        return

    embedding_will_change.emit()
    var hidden: Array[Window] = []
    _collect_visible_windows(vp, hidden)
    if vp.gui_embed_subwindows:
        _stood_inside.clear()
    for window in hidden:
        if window.is_embedded():
            _stood_inside[window.get_instance_id()] = Rect2i(window.position, window.size)
        window.hide()

    vp.gui_embed_subwindows = SaSettings.embed_subwindows

    for window in hidden:
        window.show()
        # A window's size, min_size and position mean different things on each
        # side of this setting, so anything that keeps logical geometry has to
        # re-derive it now.
        if window.has_method("apply_window_scale"):
            window.apply_window_scale()
        if window.is_embedded() and _stood_inside.has(window.get_instance_id()):
            var stood: Rect2i = _stood_inside[window.get_instance_id()]
            window.position = stood.position
            if not window is DockerWindow:
                window.size = stood.size
    embedding_changed.emit()


## Every currently visible Window below *node*, parents before children.
static func _collect_visible_windows(node: Node, into: Array[Window]) -> void:
    for child in node.get_children():
        var window := child as Window
        if window != null and window.visible:
            into.append(window)
        _collect_visible_windows(child, into)
