## The one door the Edit Brush command, the Tool Options docker and a scenario
## open the brush editor through.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A door, and not a capture.** This holds the lines that open the editor for
## a painter, called from the bar's Edit Brush button and the Edit Brush
## command. A scenario's hand is `brush_editor_capture.gd` under
## `harness/captures`, which reaches the window through [method live_window]
## here, because the door, the drivers and the captures are not the interface.
##
## One door rather than two lookups that disagree: the window is found by name
## here and nowhere else.
##
## **Edit Brush is a toggle**, as F5 is in Krita, whose chord
## Sara took. [method toggle] is what F5 over the main window and the bar's Edit
## Brush button run, and F5 pressed into the editor itself is the window's own,
## `SaBrushEditorWindow.close_on_its_chord`. Closing is the window's own Close, a `hide`, so the
## window keeps what it holds and opening again binds the brush in hand.
@tool
class_name SaBrushEditorDoor
extends RefCounted


## The editor window in *tree*, or null when nothing has opened one.
##
## Asks whether the window exists and nothing about whether it is visible, which
## is deliberate and is why `capture_editor` asks the second question itself.
static func live_window(tree: SceneTree) -> Node:
    return tree.root.find_child("SaBrushEditorWindow", true, false)


## Puts the editor away when it is on screen and opens it when it is not, and
## answers the window it opened, or null when it closed one or found no bar.
static func toggle(tree: SceneTree) -> Node:
    var window := live_window(tree) as Window
    if window != null and window.visible:
        window.hide()
        return null
    return open(tree)


## Opens the editor on whatever tool the tool options bar is showing, building
## the window on first use, and answers it.
##
## Through the bar rather than through the machine, because the bar already
## answers the three questions this window has: which tool is shown, which specs
## it declares, and which preset store the painter's presets are in. Reaching
## into the machine would have given the editor a second store and a second
## preset list, and Save would have written somewhere the bar's dropdown never
## looks.
static func open(tree: SceneTree) -> Node:
    var bar := tool_options_bar(tree)
    if bar == null:
        return null
    var state := bar.shown_tool()
    if state == null:
        return null
    var window := live_window(tree) as SaBrushEditorWindow
    if window == null:
        window = SaBrushEditorWindow.new()
        tree.root.add_child(window)
        # Bound once the window exists, so a `CURVE_OPTION` row's button in the
        # Tool Options docker opens the page here instead of the bare host, and
        # nothing else changes.
        ToolOptionControls.open_curve_editor = window.show_curve_option
        # The bar keeps the preset list a painter picks from, and the editor
        # writes straight to the store, so the two would drift the moment Save As
        # named something new: reopening the editor read the bar's idea of the
        # loaded preset and got the old one. Connected here rather than inside the
        # window, which must not know a bar exists.
        window.preset_written.connect(func(stored: String) -> void: _tell_the_bar(tree, stored))
        # The presets fold, the same seam the other way round: a cell picked in
        # the editor is applied by the bar, so the settings resource is written
        # once and the Brush Presets docker's marked cell follows through
        # `EventBus.preset_loaded` rather than through a second path.
        window.preset_chosen.connect(func(stored: String) -> void: _load_on_the_bar(tree, stored))
        # The window was bound once, when it opened, and a tool picked after
        # that left it holding the old tool's settings. A stamp preset loaded
        # then was compared with the noise brush's settings and stopped the
        # script. Connected after the bar's own handler, so the
        # bar already shows the new tool when this asks it.
        EventBus.tool_changed.connect(func(_tool_name: String) -> void: follow_the_bar(tree))
        # A tab brought forward, or the one left after a close, is the document
        # the blend row names from then on, whether or not the tool changes.
        # Connected after the tabs' own handler, which points the bar at the
        # front document's machine first.
        EventBus.active_document_changed.connect(func(_surface: SaSurface) -> void: follow_the_bar(tree))
    var loaded := bar.preset_box.selected_preset if bar.preset_box != null else ""
    window.bind_tool(state, bar.shown_specs(), bar.preset_store, loaded, bar.canvas_min_dimension())
    # The blend row's binding, which the bar's own controls already have and the
    # editor's are a second instance of: the registry fills the list and the
    # document names the space in plain Normal's label. Read off the bar the way
    # the canvas right-click menu reads them, rather than reached for through
    # the tree, because the bar is where the rest of this window's binding comes
    # from.
    window.follow_blend_modes(bar.options.binding.blend_registry, bar.options.binding.document())
    window.popup_centered()
    return window


## Rebinds the live window to the tool the bar shows, when that is not the tool
## it was bound to. A window never opened, or already on the shown tool, keeps
## its rows, so a held tool, which the bar does not show, rebuilds nothing. The
## blend row's document is handed over either way, because a tab closed or
## brought forward changes it without changing the tool.
static func follow_the_bar(tree: SceneTree) -> void:
    var window := live_window(tree) as SaBrushEditorWindow
    var bar := tool_options_bar(tree)
    if window == null or bar == null:
        return
    # Handed before the rows are rebuilt, since a rebuild hands the blend row
    # the document held then, and after a close that was the freed one.
    window.follow_blend_modes(bar.options.binding.blend_registry, bar.options.binding.document())
    var state := bar.shown_tool()
    if state == null or state == window.tool_state:
        return
    var loaded := bar.preset_box.selected_preset if bar.preset_box != null else ""
    # The bar can still name the old tool's preset in the moment the tool
    # changed, and a preset of another engine is not what this brush is on.
    var settings := state.get("settings") as Resource
    if bar.preset_store != null and not bar.preset_store.refusal(loaded, settings).is_empty():
        loaded = ""
    window.bind_tool(state, bar.shown_specs(), bar.preset_store, loaded, bar.canvas_min_dimension())


## Applies *stored* through the bar, which is the same call the Brush Presets
## docker makes: the settings resource is written once and everything listing
## presets is told by `EventBus.preset_loaded`.
static func _load_on_the_bar(tree: SceneTree, stored: String) -> void:
    var bar := tool_options_bar(tree)
    if bar != null:
        bar.load_preset(stored)


## Points the bar's preset group at *stored*, so its dropdown shows what the
## editor just wrote.
static func _tell_the_bar(tree: SceneTree, stored: String) -> void:
    var bar := tool_options_bar(tree)
    if bar != null and bar.preset_box != null:
        bar.preset_box.refresh(stored)


## The tool options bar in *tree*, or null. The editor asks it which tool is
## shown and where its presets are, and a capture asks it which curve option a
## page names.
static func tool_options_bar(tree: SceneTree) -> ToolOptionsBar:
    for node in tree.root.find_children("*", "HBoxContainer", true, false):
        var bar := node as ToolOptionsBar
        if bar != null:
            return bar
    return null
