## Photoshop's stock chords for the commands Sara shares with it, read by the
## shipped Photoshop profile, which the store ships as `PHOTOSHOP_DEFAULTS`.
## Private to the chord store's folder, a table beside its reader the way
## `SaShortcutKritaTable` is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Written from memory, because no Photoshop install is here to read. A command
## missing from the table keeps Sara's own chord.
class_name SaShortcutPhotoshopTable
extends RefCounted

## Sara's command -> the chord the Photoshop profile gives it, in the spelling
## `SaShortcutStore.chord_text` writes, empty to leave the command unbound.
const CHORDS: Dictionary[String, String] = {
    "select_all": "Ctrl+A",
    "select_none": "Ctrl+D",
    "select_invert": "Ctrl+Shift+I",
    # Photoshop's Ctrl+J is Layer via Copy, which duplicates with nothing
    # selected, and it ships no chord for Duplicate Layer.
    "layer_via_copy": "Ctrl+J",
    "layer_via_cut": "Ctrl+Shift+J",
    "layer_group": "Ctrl+G",
    "layer_merge_down": "Ctrl+E",
    "layer_new_paint": "Ctrl+Shift+N",
    # Photoshop's Select Forward Layer and Select Backward Layer. The bracket
    # rule declines a chord an action holds, so Alt with a bracket is theirs.
    "layer_select_above": "Alt+]",
    "layer_select_below": "Alt+[",
    "edit_undo": "Ctrl+Z",
    "edit_redo": "Ctrl+Shift+Z",
    "edit_cut": "Ctrl+X",
    "edit_copy": "Ctrl+C",
    "edit_paste": "Ctrl+V",
    "edit_preferences": "Ctrl+K",
    # Photoshop's Export As, whose Alt+Shift+Ctrl+W Sara spells this way. The
    # chord is the Pop-up Palette's locked summon on Sara's own map, so the
    # twin is cleared beside it: the profile's rule already leaves every summon
    # unbound, and naming the twin here keeps the chord Export's should that
    # rule ever change.
    "file_export": "Ctrl+Alt+Shift+W",
    "docker_summon_locked_palette": "",
    "brush_size_increase": "]",
    "brush_size_decrease": "[",
    "color_swap": "X",
    "color_reset": "D",
    # No zoom row. Photoshop's Ctrl+1 is 100%, which is Sara's own Actual
    # Pixels on the same chord, and its Ctrl+0 is Fit on Screen, which Sara's
    # own Reset Zoom is at its default. An entry here would only drop the
    # numpad twin Sara ships beside either.
    "tool_brush": "B",
    "tool_eyedropper": "I",
    "tool_marquee": "M",
    # Photoshop's J is the healing group, the Patch tool among it.
    "tool_patch": "J",
    "tool_lasso": "L",
    "tool_wand": "W",
    "tool_zoom": "Z",
    # Fill with Background Color (Sara's Alt+Backspace foreground fill stays)
    # and Create Clipping Mask. The Hand tool's H is not here, it is the view
    # mirror's chord on every profile.
    "fill_background": "Ctrl+Backspace",
    "layer_clip_to_below": "Ctrl+Alt+G",
    # Image > Adjustments > Invert, which inverts the mask when the mask is the
    # target, as the base module's Invert does.
    "layer_invert": "Ctrl+I",
    # Photoshop's Ctrl+Space is the temporary zoom, and it has no docker
    # maximise, so the maximise chord is cleared here for the same reason it is
    # in Krita.
    "docker_maximise": "",
    # The docker toggles leave Shift and a letter, which in Photoshop steps
    # through the tools of a letter's group, so a Photoshop habit never hides a
    # docker. Sara's own map has since taken the same step, see
    # `SaToolFamilies`, and these rows stay because the toggles of the dockers
    # that kept their chord there are cleared here too. Layers, Colour and Info take Photoshop's own panel keys, F7,
    # F6 and F8, which nothing in the build holds. F5 is Photoshop's Brush
    # Settings and already Sara's Edit Brush Settings, so Brush Presets is not
    # given it. The rest go unbound here and keep the Window menu, as the
    # summons already are under this profile (`SaShortcutStore.SUMMON_PREFIX`).
    # The toggles of `project.godot` are reached the way Krita's table reaches
    # the Colour Picker's, by the action's name, so no default there changes.
    "docker_layers": "F7",
    "docker_color_selector": "F6",
    "info_docker": "F8",
    "docker_toolbox": "",
    "docker_tool_options": "",
    "docker_brush_presets": "",
    "docker_history": "",
    "docker_undo": "",
    "docker_recorder": "",
    "docker_minimap": "",
    "docker_graph": "",
    "docker_reference": "",
    "docker_palette": "",
    # Shift with a tool's letter steps the tool's group, as it does in
    # Photoshop. Sara's own map gives the same chords, and they are written out
    # here so the profile and the habit it serves read as one row each.
    "tool_family_brush": "Shift+B",
    "tool_family_crop": "Shift+C",
    "tool_family_gradient": "Shift+G",
    "tool_family_eyedropper": "Shift+I",
    "tool_family_eraser": "Shift+E",
    "tool_family_marquee": "Shift+M",
    "tool_family_patch": "Shift+J",
    "tool_family_lasso": "Shift+L",
    "tool_family_wand": "Shift+W",
    # The ten brush slots, cleared where the Krita table keeps them on Krita's
    # Ctrl+Alt digits: Photoshop has no brush slots at all, and its Ctrl+Alt
    # with a digit is nothing a painter arriving from it would reach for.
    "brush_slot_1": "",
    "brush_slot_2": "",
    "brush_slot_3": "",
    "brush_slot_4": "",
    "brush_slot_5": "",
    "brush_slot_6": "",
    "brush_slot_7": "",
    "brush_slot_8": "",
    "brush_slot_9": "",
    "brush_slot_10": "",
}
