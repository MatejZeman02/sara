## Procreate's keyboard shortcuts on an iPad keyboard, for the commands Sara
## shares with it, read by the shipped Procreate profile, which the store ships
## as `PROCREATE_DEFAULTS`. Private to the chord store's folder, a table beside
## its reader the way `SaShortcutPhotoshopTable` is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Read from the Keyboard Shortcuts page of the Procreate Handbook
## (procreate.com/handbook/procreate/interface-gestures/shortcuts), written
## from memory, because no iPad and no network are here to read it again. The
## iPad's Command key is Sara's Ctrl, as Photoshop's is. A command missing from
## the table keeps Sara's own chord.
##
## **What Procreate has and Sara does not stays unbound.** Its S is the Smudge
## tool, and Sara has no smudge tool, only a brush that smudges, so S is left
## free once the brush size steps move to Procreate's brackets. Its
## Adjustments, Actions and Selection buttons have no single command in Sara
## either.
class_name SaShortcutProcreateTable
extends RefCounted

## Sara's command -> the chord the Procreate profile gives it, in the spelling
## `SaShortcutStore.chord_text` writes, empty to leave the command unbound.
const CHORDS: Dictionary[String, String] = {
    "edit_undo": "Ctrl+Z",
    "edit_redo": "Ctrl+Shift+Z",
    "edit_cut": "Ctrl+X",
    "edit_copy": "Ctrl+C",
    "edit_paste": "Ctrl+V",
    "select_all": "Ctrl+A",
    # Procreate's Paint. Its E, the Erase tool, is not named here: Sara's own E
    # already gives the eraser, and a row would take E off the brush's eraser
    # toggle beside it.
    "tool_brush": "B",
    # Procreate's V is the Transform tool. Sara's Ctrl+T goes with it, since
    # Procreate has no second chord for it.
    "tool_transform": "V",
    # Procreate's L opens the Layers panel and its C the Colours panel. Sara's
    # own L is the Lasso and C the Crop, which Procreate has no letter for, so
    # both are given up for the panels.
    "docker_layers": "L",
    "docker_color_selector": "C",
    "tool_lasso": "",
    "tool_crop": "",
    "brush_size_increase": "]",
    "brush_size_decrease": "[",
    # Procreate's Command with plus and minus. Ctrl+0 is its Fit to Screen,
    # which Sara's own Reset Zoom is at its default.
    "view_zoom_in": "Ctrl+Equal",
    "view_zoom_out": "Ctrl+Minus",
    # Procreate has no docker maximise, so the chord is cleared here for the
    # reason it is in Krita and Photoshop.
    "docker_maximise": "",
}
