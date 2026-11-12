## The one table of Sara's commands against Krita's, read by the shipped Krita
## profile and by Import from Krita alike.
##
## Keyed by Sara's command, in two columns: `ACTIONS`, the Krita action each
## command answers, and `CHORDS`, the chord the Krita profile gives it, which
## the store ships as `KRITA_DEFAULTS`. Private to the chord store's folder.
##
## **Two dictionaries with one set of keys, rather than one dictionary of
## pairs.** A shipped profile is a constant, `SHIPPED_PROFILES` and a dozen
## suites read `KRITA_DEFAULTS` as command -> chord, and GDScript cannot build
## a constant out of another one's column. So the columns are written side by
## side in one order, and `core/registry/tests/test_krita_profile.gd` fails the
## run on a row one column has and the other lacks.
##
## **One table, so the importer, the profile and the tick list cannot part.**
## Kept apart, the importer's own thirty Krita names, the profile's chords in
## the store and the tick list's map in `scripts/agents/krita_chords.py` drifted:
## a painter who imported Krita's own stock file got thirty of Krita's chords
## and kept the mirror on H and the Marquee on M, less Krita-like than one who
## picked the profile. The importer and the tick list both read `ACTIONS`.
class_name SaShortcutKritaTable
extends RefCounted

## Sara's command -> the Krita action it answers, as Krita's `.action` files
## and the `.shortcuts` files it exports name it. A list where one command
## answers two of Krita's, and empty where Krita has no action for it at all,
## which is a chord the profile places for a reason of Sara's own and an import
## leaves as the profile has it.
##
## A row here that `CHORDS` lacks is an action Krita ships with no chord: the
## profile leaves Sara's own chord on the command, and an import reads whatever
## a painter's file gives it.
const ACTIONS: Dictionary[String, Variant] = {
    "select_all": "select_all",
    "select_none": "deselect",
    "select_invert": "invert_selection",
    "layer_duplicate": "duplicatelayer",
    "layer_via_copy": "copy_selection_to_new_layer",
    "layer_via_cut": "cut_selection_to_new_layer",
    "layer_via_seamless_cut": "",
    "layer_group": "create_quick_group",
    "layer_clip_to_below": "create_quick_clipping_group",
    "layer_merge_down": "merge_layer",
    "layer_new_paint": "add_new_paint_layer",
    "layer_delete": "remove_layer",
    "layer_move_up": "move_layer_up",
    "layer_move_down": "move_layer_down",
    "layer_select_above": "activateNextLayer",
    "layer_select_below": "activatePreviousLayer",
    "layer_alpha_lock": "",
    "edit_undo": "edit_undo",
    "edit_redo": "edit_redo",
    "edit_cut": "edit_cut",
    "edit_copy": "edit_copy",
    "edit_paste": "edit_paste",
    "file_new": "file_new",
    "file_open": "file_open",
    # Save and Save Incremental Version, in the order `CHORDS` lists their keys
    "file_save": ["file_save", "save_incremental_version"],
    "file_save_as": "file_save_as",
    "docker_reference_solo": "",
    "image_canvas_size": "canvassize",
    "image_size": "imagesize",
    "brush_size_increase": "increase_brush_size",
    "brush_size_decrease": "decrease_brush_size",
    "brush_toggle_eraser": "erase_action",
    "brush_preset_previous": "previous_preset",
    "brush_preset_recent_walk": "",
    "color_swap": "toggle_fg_bg",
    "color_reset": "reset_fg_bg",
    "fill_foreground": "fill_selection_foreground_color",
    "fill_background": "fill_selection_background_color",
    "layer_clear": "clear",
    "view_zoom_in": "view_zoom_in",
    "view_zoom_out": "view_zoom_out",
    "view_zoom_100": "zoom_to_100pct",
    "view_rotate_left": "rotate_canvas_left",
    "view_rotate_right": "rotate_canvas_right",
    "view_soft_proof": "softProof",
    "view_mirror_horizontal": "mirror_canvas",
    # Krita's isolate_active_layer ships unbound, so the row names no action of
    # Krita's, the way docker_maximise below does, and only clears the chord.
    "view_isolate_active_layer": "",
    "view_wrap": "wrap_around_mode",
    "window_fullscreen": "fullscreen",
    "docker_maximise": "",
    # Sara's developer command, which Krita has no action for, so the row only
    # clears the chord, as CHORDS below says.
    "modules_reload_shaders": "",
    "filter_color_balance": "krita_filter_colorbalance",
    "filter_hue_saturation_lightness": "krita_filter_hsvadjustment",
    "filter_levels": "krita_filter_levels",
    "filter_curves": "krita_filter_perchannel",
    "filter_apply_again": "filter_apply_again",
    # Krita's Invert filter, which the base module's Invert runs on a layer and
    # turns to the mask while a mask is the paint target.
    "layer_invert": "krita_filter_invert",
    "tool_brush": "KritaShape/KisToolBrush",
    "tool_crop": "KisToolCrop",
    "tool_gradient": "KritaFill/KisToolGradient",
    "tool_bucket_fill": "KritaFill/KisToolFill",
    "tool_eyedropper": "KritaSelected/KisToolColorSampler",
    "tool_marquee": "KisToolSelectRectangular",
    "tool_ellipse_select": "KisToolSelectElliptical",
    # Krita's Outline and Polygonal Selection tools ship with no chord, so the
    # rows are here for an import and the Lasso keeps Sara's own L.
    "tool_lasso": "KisToolSelectOutline",
    "tool_polygonal_lasso": "KisToolSelectPolygonal",
    # Krita has no patch tool, so the row names no action of Krita's and only
    # clears the J Sara's own map gives it, which is Ellipse Select's here.
    "tool_patch": "",
    "tool_transform": "KisToolTransform",
    "tool_eyedropper_quick": "",
    "docker_tool_options": "show_tool_options",
    "docker_color_selector": "show_color_selector",
    # Krita has no Pop-up Palette chord, its palette is a right click, so the
    # row names no action of Krita's and only gives Shift+W up to the wrap.
    "docker_palette": "",
    "docker_summon_palette": "",
    # Shift with a letter is Krita's own for the wrap and the colour picker, so
    # the two family steps that would share them name no action of Krita's and
    # only give the chord up. The other seven keep Sara's own.
    "tool_family_wand": "",
    "tool_family_eyedropper": "",
    # Krita's Ten Brushes, where activate_preset_0 is preset 10 and Sara's slot 10
    "brush_slot_1": "activate_preset_1",
    "brush_slot_2": "activate_preset_2",
    "brush_slot_3": "activate_preset_3",
    "brush_slot_4": "activate_preset_4",
    "brush_slot_5": "activate_preset_5",
    "brush_slot_6": "activate_preset_6",
    "brush_slot_7": "activate_preset_7",
    "brush_slot_8": "activate_preset_8",
    "brush_slot_9": "activate_preset_9",
    "brush_slot_10": "activate_preset_0",
    # Three actions Krita ships with no chord, named so the importer reads
    # them
    "edit_preferences": "options_configure",
    "tool_wand": "KisToolSelectContiguous",
    "docker_recorder": "duc_RecorderDocker",
    # Krita's blending mode actions, on the brush's mode as Krita's are. The
    # twelve whose Alt+Shift letter a docker summon holds have no row.
    "blend_mode_next": "Next Blending Mode",
    "blend_mode_previous": "Previous Blending Mode",
    "blend_mode_behind": "Select Behind Blending Mode",
    "blend_mode_clear": "Select Clear Blending Mode",
    "blend_mode_darken": "Select Darken Blending Mode",
    "blend_mode_dissolve": "Select Dissolve Blending Mode",
    "blend_mode_hard_light": "Select Hard Light Blending Mode",
    "blend_mode_hard_mix": "Select Hard Mix Blending Mode",
    "blend_mode_hard_overlay": "Select Hard Overlay Blending Mode",
    "blend_mode_hue": "Select Hue Blending Mode",
    "blend_mode_lighten": "Select Lighten Blending Mode",
    "blend_mode_linear_light": "Select Linear Light Blending Mode",
    "blend_mode_luminosity": "Select Luminosity Blending Mode",
    "blend_mode_multiply": "Select Multiply Blending Mode",
    "blend_mode_normal": "Select Normal Blending Mode",
    "blend_mode_overlay": "Select Overlay Blending Mode",
}

## Sara's command -> the chord the Krita profile gives it, one chord text or a
## list of them in the spelling `SaShortcutStore.chord_text` writes, a list in
## the order of the actions `ACTIONS` names for the row. A command missing here
## keeps Sara's own chord, the same silence a saved profile keeps about an
## action nobody touched.
##
## **Read out of Krita rather than remembered.** Rebuilt from Krita 5.2.13's
## own action files, `krita/krita.action`, `krita/kritamenu.action`,
## `krita/data/actions/*.action` and `plugins/**/*.action`, which carry 201
## actions with a non-empty `<shortcut>`, rather than one painter's exported
## map, which leaves out every chord Krita ships that the painter never rebound.
##
## **`layer_alpha_lock` is cleared, because Krita has no alpha lock chord at
## all.** Sara's own map holds it on Ctrl+Alt+A, which Krita leaves free, and
## an empty entry keeps to what Krita ships, keeps the action in the list and
## leaves it rebindable. Sara's map puts nothing on Ctrl+Shift+A, Krita's
## `deselect`, but Deselect itself, so the table introduces no
## collision there.
const CHORDS: Dictionary[String, Variant] = {
    # Selections. Deselect is Ctrl+Shift+A alone here, where Sara's own map
    # holds it beside Photoshop's Ctrl+D, which Krita does not ship.
    "select_all": "Ctrl+A",
    "select_none": "Ctrl+Shift+A",
    "select_invert": "Ctrl+Shift+I",
    # Layers
    "layer_duplicate": "Ctrl+J",
    "layer_via_copy": "Ctrl+Alt+J",
    "layer_via_cut": "Ctrl+Shift+J",
    # Sara's own, which Krita has no action for and leaves unbound.
    "layer_via_seamless_cut": "",
    "layer_group": "Ctrl+G",
    "layer_clip_to_below": "Ctrl+Shift+G",
    "layer_merge_down": "Ctrl+E",
    "layer_new_paint": "Insert",
    "layer_delete": "Shift+Delete",
    "layer_move_up": "Ctrl+PageUp",
    "layer_move_down": "Ctrl+PageDown",
    # Krita's Activate Next Layer and Activate Previous Layer
    "layer_select_above": "PageUp",
    "layer_select_below": "PageDown",
    "layer_alpha_lock": "",
    # Edit
    "edit_undo": "Ctrl+Z",
    "edit_redo": "Ctrl+Shift+Z",
    "edit_cut": "Ctrl+X",
    "edit_copy": "Ctrl+C",
    "edit_paste": "Ctrl+V",
    # File
    "file_new": "Ctrl+N",
    "file_open": "Ctrl+O",
    # Krita's Save Incremental Version is Ctrl+Alt+S, and Sara has no
    # incremental save, so the key saves rather than doing nothing. The
    # Reference solo that holds it in Sara's map moves to Ctrl+Alt+D, which
    # Krita ships for nothing.
    "file_save": ["Ctrl+S", "Ctrl+Alt+S"],
    "file_save_as": "Ctrl+Shift+S",
    "docker_reference_solo": "Ctrl+Alt+D",
    # Image
    "image_canvas_size": "Ctrl+Alt+C",
    "image_size": "Ctrl+Alt+I",
    # The brush and the colours
    "brush_size_increase": "]",
    "brush_size_decrease": "[",
    "brush_toggle_eraser": "E",
    # Krita's Switch to Previous Preset
    "brush_preset_previous": "/",
    # Sara's walk through the recent presets, which Krita lacks, gives up its
    # Ctrl+R to Krita's Rectangular Selection below.
    "brush_preset_recent_walk": "",
    "color_swap": "X",
    "color_reset": "D",
    # Krita's bare Backspace is Clear and its bare Delete the background fill,
    # where Sara's own map gives both bare keys to the clear. So Delete goes
    # back to the fill here and the clear keeps Backspace alone, and no key of
    # this profile answers two commands. Ctrl+Backspace is Krita's opacity
    # variant of the fill, which Sara does not have.
    "fill_foreground": "Shift+Backspace",
    "fill_background": "Delete",
    "layer_clear": "Backspace",
    # The view
    "view_zoom_in": "Ctrl+Equal",
    "view_zoom_out": "Ctrl+Minus",
    "view_zoom_100": "Ctrl+0",
    "view_rotate_left": "Ctrl+BracketLeft",
    "view_rotate_right": "Ctrl+BracketRight",
    "view_soft_proof": "Ctrl+Y",
    "view_mirror_horizontal": "M",
    # Krita ships Isolate Active Layer with no chord and keeps `/` for the
    # previous preset, so the profile takes the `/` Sara's own map gives it and
    # leaves the numpad's slash, the key a Czech keyboard reaches without Shift.
    "view_isolate_active_layer": "Numpad /",
    # Krita's Wrap Around Mode, on the Shift+W Sara's own map gives the Pop-up
    # Palette.
    "view_wrap": "Shift+W",
    "window_fullscreen": "Ctrl+Shift+F",
    # Krita has no docker maximise, and Ctrl+Space there is a canvas gesture, so
    # the maximise chord is cleared rather than moved the way the alpha lock
    # above is.
    "docker_maximise": "",
    # Krita's Ctrl+Shift+R is Paste as Reference Image, a painter's action, and
    # a painter who pressed it here got kernels recompiled and "No shader
    # changed." in the corner. Sara has no command for that paste yet,
    # so Reload Shaders gives the chord up and is left on the Modules menu
    # alone, where a developer looks for it, rather than moved to another key.
    "modules_reload_shaders": "",
    # The filters Krita calls by another name
    "filter_color_balance": "Ctrl+B",
    "filter_hue_saturation_lightness": "Ctrl+U",
    "filter_levels": "Ctrl+L",
    "filter_curves": "Ctrl+M",
    # Krita's own name, and Sara Default's chord as well
    "filter_apply_again": "Ctrl+F",
    # Krita's Ctrl+I, the Invert filter, on the base module's Invert
    "layer_invert": "Ctrl+I",
    # The tools
    "tool_brush": "B",
    "tool_crop": "C",
    "tool_gradient": "G",
    "tool_bucket_fill": "F",
    "tool_eyedropper": "P",
    "tool_marquee": "Ctrl+R",
    "tool_ellipse_select": "J",
    "tool_patch": "",
    "tool_transform": "Ctrl+T",
    # Krita samples a colour on a held Ctrl from its canvas input settings
    # rather than an action, so the held eyedropper takes Ctrl beside Sara's
    # Alt. Ctrl+Space outranks it as the quick zoom.
    "tool_eyedropper_quick": ["Alt", "Ctrl"],
    # The dockers Krita opens with a key
    "docker_tool_options": "Backslash",
    "docker_color_selector": "Shift+I",
    # The Pop-up Palette gives Shift+W to the wrap above and keeps no toggle
    # chord here, since a right click with a brush opens it as in Krita. Its
    # summon keeps Alt+Shift+W, the chord the palette is for, where every other
    # summon is unbound in this profile (`SaShortcutStore.SUMMON_PREFIX`), so a
    # key still brings it under the pointer. The locked twin stays unbound.
    "docker_palette": "",
    "docker_summon_palette": "Alt+Shift+W",
    "tool_family_wand": "",
    "tool_family_eyedropper": "",
    # The ten brush slots, on the chords Krita 5.2.13 ships for its Ten Brushes
    # plugin, activate_preset_1 to activate_preset_0 in the plugin's own action
    # file, read into `scripts/agents/krita_chords.json`. Ctrl+Alt+0 is Krita's
    # preset 10 and Sara's slot 10. They are Sara Default's chords as well,
    # written out rather than left to it so the import and the profile read one
    # row, and the numpad's digits stay beside them as they do on the zoom.
    "brush_slot_1": "Ctrl+Alt+1",
    "brush_slot_2": "Ctrl+Alt+2",
    "brush_slot_3": "Ctrl+Alt+3",
    "brush_slot_4": "Ctrl+Alt+4",
    "brush_slot_5": "Ctrl+Alt+5",
    "brush_slot_6": "Ctrl+Alt+6",
    "brush_slot_7": "Ctrl+Alt+7",
    "brush_slot_8": "Ctrl+Alt+8",
    "brush_slot_9": "Ctrl+Alt+9",
    "brush_slot_10": "Ctrl+Alt+0",
    # Krita's blending mode chords, the fourteen letters no docker summon
    # holds. Krita writes "Alt+Shift++" and "Alt+Shift+-", which Godot names
    # Plus and Minus, the spelling Import from Krita reads them into.
    "blend_mode_next": "Alt+Shift+Plus",
    "blend_mode_previous": "Alt+Shift+Minus",
    "blend_mode_behind": "Alt+Shift+Q",
    "blend_mode_clear": "Alt+Shift+R",
    "blend_mode_darken": "Alt+Shift+K",
    "blend_mode_dissolve": "Alt+Shift+I",
    "blend_mode_hard_light": "Alt+Shift+H",
    "blend_mode_hard_mix": "Alt+Shift+L",
    "blend_mode_hard_overlay": "Alt+Shift+P",
    "blend_mode_hue": "Alt+Shift+U",
    "blend_mode_lighten": "Alt+Shift+G",
    "blend_mode_linear_light": "Alt+Shift+J",
    "blend_mode_luminosity": "Alt+Shift+Y",
    "blend_mode_multiply": "Alt+Shift+M",
    "blend_mode_normal": "Alt+Shift+N",
    "blend_mode_overlay": "Alt+Shift+O",
}


## The Krita actions *command*'s row names, in the order `CHORDS` lists its
## chords, and none for a row Krita has no action for.
static func actions_of(command: String) -> Array[String]:
    var named: Variant = ACTIONS.get(command, "")
    var listed: Array = named if named is Array else [named]
    var out: Array[String] = []
    for action: Variant in listed:
        if not str(action).is_empty():
            out.append(str(action))
    return out
