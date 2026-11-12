## The `cut_labels` capture step: lists every label and button of one window
## whose words do not fit where they are drawn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **How a cut label is told from a whole one.** A label or a button that may
## not cut its words asks for the width they need as its minimum, and the
## containers give it, so such a control is never narrower than its words. One
## that clips (`clip_text`) or trims (`text_overrun_behavior`) asks for nothing,
## and is drawn at whatever width its row leaves. So the width the words need is
## read as the engine reads it, the control's own minimum with clipping and
## trimming off for that one call and put back at once, and the control is cut
## when that is wider than the control. A control that wraps is cut when it has
## more lines than its height shows. A whole control can still be cut by what
## holds it: one whose right edge passes the right edge of an ancestor that
## clips its children, or of its window, has its end hidden, and so has a window
## that passes the main window's edge. The engine's own measure is used and not
## a sum of glyph widths, so the stylebox, the icon and the arrow of a choice
## are counted the way the drawing counts them.
##
## Labels and buttons are measured, choices, toggles and menu buttons among
## them. A text field scrolls its text and a rich text label sizes itself, so
## neither is read here.
##
## Reached through `SaControlWalker.cut_labels`, the folder's facade, by path
## like the rest of the harness.
extends RefCounted

const CaptureRun := preload("res://harness/sa_capture_run.gd")

## How far past the width a control may reach before it counts as cut, for the
## rounding of a container's sort.
const SLACK: float = 0.5

## The marks the test language puts round every message, `scripts/write_pseudo.py`'s.
const OPEN_MARK := "‹"
const CLOSE_MARK := "›"


## `{"cut_labels": {"list": true}}` answers the titles of the Preferences pages,
## the ids of the dockers and the names of the top bar's menus, so a scenario
## walks every one of them without a list written by hand.
##
## `{"cut_labels": {"name": "prefs Languages", "preferences": true}}` reads the
## open Preferences window, `{"docker": "LayersDocker"}` a docker's window,
## `{"menu": "File"}` a top bar menu's open list, and `{"main": true}` the main
## window without the windows over it, and `{"shut": "LayersDocker"}` hides
## a docker again once the walk has read it, so the next one is pictured alone.
## The answer is one line,
## `SaCapture: cut labels '<name>' <cut> of <read> read, <marked> in the test
## language's marks <json>`, the JSON a list of
## `{"path", "kind", "text", "width", "needs", "how"}`, the text as drawn.
static func capture(tree: SceneTree, spec: Variant) -> String:
    var wanted: Dictionary = spec if spec is Dictionary else {}
    if wanted.get("list", false):
        return "SaCapture: cut labels list %s" % JSON.stringify(_lists(tree))
    if wanted.has("shut"):
        var shut := CaptureRun.DockerLookup.window(tree, StringName(String(wanted["shut"])))
        if shut == null:
            return "SaCapture: cut labels found no docker '%s' to shut" % String(wanted["shut"])
        shut.visible = false
        return "SaCapture: cut labels shut docker '%s'" % String(wanted["shut"])
    var label_name := String(wanted.get("name", ""))
    var scope := window_of(tree, wanted)
    if scope == null:
        return "SaCapture: cut labels '%s' found no window for %s" % [label_name, JSON.stringify(wanted)]
    var found: Array[Dictionary] = []
    if scope is Window and scope != tree.root:
        _window_past_the_edge(tree, scope as Window, found)
    var read := {"read": 0, "marked": 0}
    _walk(scope, scope, found, read)
    return (
        "SaCapture: cut labels '%s' %d of %d read, %d in the test language's marks %s"
        % [label_name, found.size(), read["read"], read["marked"], JSON.stringify(found)]
    )


## The pages, dockers and menus a walk of every one names.
static func _lists(tree: SceneTree) -> Dictionary:
    var pages: Array = []
    for node in tree.root.find_children("*", "Window", true, false):
        var settings := node as SaSettingsWindow
        if settings != null:
            pages = settings.categories.duplicate()
    var bar := top_bar(tree)
    var menus: Array = TopMenuBar.MENU_NAMES.duplicate() if bar != null else []
    var registry := CaptureRun.DockerLookup.registry_of(tree)
    var dockers: Array = Array(CaptureRun.DockerLookup.registered_ids(registry)) if registry != null else []
    return {"pages": pages, "dockers": dockers, "menus": menus}


static func top_bar(tree: SceneTree) -> TopMenuBar:
    for node in tree.root.find_children("*", "PanelContainer", true, false):
        if node is TopMenuBar:
            return node as TopMenuBar
    return null


## The window *wanted* names, or null.
static func window_of(tree: SceneTree, wanted: Dictionary) -> Node:
    if wanted.get("main", false):
        return tree.root
    if wanted.get("preferences", false):
        for node in tree.root.find_children("*", "Window", true, false):
            var settings := node as SaSettingsWindow
            if settings != null and settings.visible:
                return settings
        return null
    if wanted.has("docker"):
        return CaptureRun.DockerLookup.window(tree, StringName(String(wanted["docker"])))
    if wanted.has("menu"):
        var bar := top_bar(tree)
        var popup: Variant = bar.menus.get(String(wanted["menu"])) if bar != null else null
        return popup as Node if popup is Window and (popup as Window).visible else null
    return null


## A window that passes the main window's right or bottom edge, whose end the
## painter never sees.
static func _window_past_the_edge(tree: SceneTree, window: Window, found: Array[Dictionary]) -> void:
    if not window.visible or not window.is_embedded():
        return
    var screen := tree.root.get_visible_rect()
    var rect := Rect2(window.position, window.size)
    if rect.end.x > screen.end.x + SLACK or rect.end.y > screen.end.y + SLACK:
        var room := screen.size.x - rect.position.x
        found.append(_entry(window, window, window.title, room, rect.size.x, "the window passes the main window's edge"))


## Every control under *node* in *scope*, the windows over it left to their own
## walk. *read* counts the labels and buttons measured, and *marked* those of
## them whose words carry the test language's marks.
static func _walk(scope: Node, node: Node, found: Array[Dictionary], read: Dictionary) -> void:
    for child in node.get_children():
        if child is Window:
            continue
        if child is CanvasItem and not (child as CanvasItem).visible:
            continue
        if child is Label or child is Button:
            _check(scope, child as Control, found, read)
        _walk(scope, child, found, read)


static func _check(scope: Node, control: Control, found: Array[Dictionary], read: Dictionary) -> void:
    var raw := String(control.get("text"))
    if raw.strip_edges().is_empty():
        return
    var shown := control.atr(raw)
    if control is Label and (control as Label).uppercase:
        shown = shown.to_upper()
    read["read"] += 1
    if shown.contains(OPEN_MARK) or shown.contains(CLOSE_MARK):
        read["marked"] += 1
    var width := control.size.x
    if control is Label and (control as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
        var label := control as Label
        if label.max_lines_visible < 0 and label.get_line_count() > label.get_visible_line_count():
            var how := "%d of %d lines show" % [label.get_visible_line_count(), label.get_line_count()]
            found.append(_entry(scope, control, shown, width, width, how))
        return
    var needs := whole_width(control)
    if needs > width + SLACK:
        found.append(_entry(scope, control, shown, width, needs, "narrower than its words"))
        return
    # Where the words end, which is short of the control's own end when a row
    # stretches it wider than its words.
    var start := control.get_global_rect().position.x
    var words_end := start + needs
    var holder := control.get_parent_control()
    while holder != null:
        if holder.clip_contents:
            var edge := holder.get_global_rect().end.x
            if words_end > edge + SLACK:
                found.append(_entry(scope, control, shown, edge - start, needs, "clipped by %s" % holder.name))
                return
        holder = holder.get_parent_control()
    var window_edge := control.get_viewport_rect().end.x
    if words_end > window_edge + SLACK:
        found.append(_entry(scope, control, shown, window_edge - start, needs, "passes its window's edge"))


## The width *control*'s words need, its own minimum with clipping and trimming
## off for this one call, both put back before it returns.
static func whole_width(control: Control) -> float:
    var clip: bool = control.get("clip_text")
    var overrun: int = control.get("text_overrun_behavior")
    if not clip and overrun == TextServer.OVERRUN_NO_TRIMMING:
        return control.get_minimum_size().x
    control.set("clip_text", false)
    control.set("text_overrun_behavior", TextServer.OVERRUN_NO_TRIMMING)
    var needs := control.get_minimum_size().x
    control.set("clip_text", clip)
    control.set("text_overrun_behavior", overrun)
    return needs


static func _entry(scope: Node, control: Node, shown: String, width: float, needs: float, how: String) -> Dictionary:
    return {
        "path": String(scope.get_path_to(control)) if control != scope else String(scope.name),
        "kind": control.get_class(),
        "text": shown,
        "width": snappedf(width, 0.1),
        "needs": snappedf(needs, 0.1),
        "how": how,
    }
