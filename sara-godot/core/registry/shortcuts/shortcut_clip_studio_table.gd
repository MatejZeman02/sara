## Clip Studio Paint's stock chords for the commands Sara shares with it, read
## by the shipped Clip Studio Paint profile, which the store ships as
## `CLIP_STUDIO_DEFAULTS`. Private to the chord store's folder, a table beside
## its reader the way `SaShortcutPhotoshopTable` is.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Written from Clip Studio Paint's default shortcut set for Windows, the list
## its File > Shortcut Settings shows on a fresh install, from memory, because
## no Clip Studio Paint install is here to read. A command missing from the
## table keeps Sara's own chord.
##
## **Clip Studio Paint's chords Sara has no command for** go unbound by having
## no row: Operation (O), Move Layer (K), Pen and Pencil (P), Airbrush and
## Decoration under B beside the Brush, Blend (J), Figure, Frame Border and
## Ruler (U), Text and Balloon (T), Correct Line (Y), the Rotate tool (R),
## Free Transform (Ctrl+Shift+T) and Hide All Palettes (Tab).
class_name SaShortcutClipStudioTable
extends RefCounted

## Sara's command -> the chord the Clip Studio Paint profile gives it, in the
## spelling `SaShortcutStore.chord_text` writes, empty to leave the command
## unbound.
const CHORDS: Dictionary[String, String] = {
    "select_all": "Ctrl+A",
    "select_none": "Ctrl+D",
    "select_invert": "Ctrl+Shift+I",
    # Layer > New Raster Layer, Merge with Layer Below, Merge Visible Layers,
    # Clip at Layer Below and Create Folder and Insert Layer, which is what
    # Sara's Group Layers does. Clip Studio Paint ships no chord for Duplicate
    # Layer, so Sara's own stays.
    "layer_new_paint": "Ctrl+Shift+N",
    "layer_merge_down": "Ctrl+E",
    "layer_merge_visible": "Ctrl+Shift+E",
    "layer_clip_to_below": "Ctrl+Alt+G",
    "layer_group": "Ctrl+G",
    # Redo is Ctrl+Y in Clip Studio Paint, which on Sara's own map is the soft
    # proof, so the proof is cleared beside it and keeps the View menu.
    "edit_undo": "Ctrl+Z",
    "edit_redo": "Ctrl+Y",
    "view_soft_proof": "",
    "edit_cut": "Ctrl+X",
    "edit_copy": "Ctrl+C",
    "edit_paste": "Ctrl+V",
    "edit_preferences": "Ctrl+K",
    # Edit > Transform > Scale Up/Scale Down/Rotate, the transform in hand.
    "tool_transform": "Ctrl+T",
    # No zoom in or out row: Clip Studio Paint's Ctrl with plus and minus are
    # Sara's own. Its Ctrl+0 is Fit to Navigator, which Sara's Reset Zoom is
    # at its default, and its 100% is Ctrl+Alt+0, Sara's Actual Pixels here.
    "view_actual_pixels": "Ctrl+Alt+0",
    # View > Rotate/Invert > Rotate Left and Rotate Right, the minus and the
    # caret, which a US keyboard types with Shift and 6. Clip Studio Paint
    # ships no chord for Flip Horizontal or Reset Rotation, so Sara's own stay.
    "view_rotate_left": "-",
    "view_rotate_right": "Shift+6",
    "brush_size_increase": "]",
    "brush_size_decrease": "[",
    "color_swap": "X",
    "tool_brush": "B",
    # The Eraser, and with it Sara's eraser switch on the brush in hand, which
    # is one gesture with it. Clip Studio Paint's C, Switch Between Drawing
    # Colour and Transparent Colour, is the nearest thing it has to that
    # switch, but the pair holds one chord, so E is it and C goes unbound.
    "tool_eraser": "E",
    "tool_eyedropper": "I",
    "tool_marquee": "M",
    # Auto Select, Clip Studio Paint's magic wand.
    "tool_wand": "W",
    # Fill and Gradient share G in Clip Studio Paint, which steps between the
    # two on a second press. Sara's map gives a key one command, so Fill takes
    # it and the Gradient is left unbound and keeps the toolbox.
    "tool_bucket_fill": "G",
    "tool_gradient": "",
    # Clip Studio Paint has no Crop tool, and its C is the transparent colour
    # named above, so Sara's crop chord is cleared rather than left where a
    # habit lands on it.
    "tool_crop": "",
    # Ctrl+Space is Clip Studio Paint's temporary zoom, and it has no docker
    # maximise, so the maximise chord is cleared as Krita's and Photoshop's
    # tables clear it.
    "docker_maximise": "",
}
