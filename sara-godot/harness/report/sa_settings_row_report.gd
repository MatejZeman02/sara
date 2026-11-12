## What the open Preferences page's rows say, for a state dump.
##
## Its own file outside `ui/settings/`, so a later count of the pages alone
## stays a count of the pages alone. Walks the window the way
## `SaSettingsSearch` does, live `ROW_META` lines under
## `window.content_container`, so a page converted onto `SaPage` later can be
## proved row for row against what it was before, the two dumps matching row
## for row.
class_name SaSettingsRowReport
extends RefCounted


## The open Preferences page's own rows, section by section, for the record a
## page conversion has to match, or an empty dictionary when the window has
## never been built. The finder `SaSettingsSearch.capture_state` uses, and
## untyped for the reason it gives.
static func capture_state(root: Window) -> Dictionary:
    for node in root.find_children("*", "Window", true, false):
        if node.has_method("show_page") and node.get("search") != null:
            return report(node)
    return {}


## The open page's title, whether it was built through `SaPage`, and one entry
## per live row.
static func report(window: SaSettingsWindow) -> Dictionary:
    var declared := false
    for node in window.content_container.find_children("*", "Container", true, false):
        var box := node as Container
        if box != null and not _is_going(box) and box.has_meta(SaPage.PAGE_META):
            declared = true
            break
    var rows: Array = []
    for node in window.content_container.find_children("*", "HBoxContainer", true, false):
        var line := node as Control
        if line == null or not line.has_meta(SaSettingsRows.ROW_META):
            continue
        if _is_going(line):
            continue
        rows.append(_row_entry(line))
    return {
        "page": String(window.categories[window.current]) if window.current >= 0 else "",
        "declared": declared,
        "rows": rows,
    }


static func _row_entry(line: Control) -> Dictionary:
    return {
        "section": _section_title(line),
        "title": String(line.get_meta(SaSettingsRows.TITLE_META, "")),
        "hint": _hint(line),
        "words": SaSettingsSearch.row_haystack(line),
        "control": _control_class(line),
        "value": _value(line),
        "live": SaOptionSpec.row_reads_enabled(line),
        "shown": line.visible,
        "keys": _keys(line),
    }


## The heading of the block *line* sits in, the way `color_themes_page.gd`'s
## own `_section_title` reads it: the first `Label` of the rows container's
## parent.
static func _section_title(line: Control) -> String:
    var rows_container := line.get_parent()
    if rows_container == null:
        return ""
    var block := rows_container.get_parent()
    if block == null:
        return ""
    for child in block.get_children():
        var label := child as Label
        if label != null:
            return label.text
    return ""


## The dimmed explanation under the title, the label column's second child
## when `SaSettingsRows.row` was handed one.
static func _hint(line: Control) -> String:
    if line.get_child_count() == 0:
        return ""
    var labels := line.get_child(0)
    if labels.get_child_count() < 2:
        return ""
    var hint_lbl := labels.get_child(1) as Label
    return hint_lbl.text if hint_lbl != null else ""


static func _control_class(line: Control) -> String:
    if line.get_child_count() < 2:
        return ""
    return _class_of(line.get_child(1))


## The value the row's control holds, off the first one under it that answers
## a kind `SaSettingsRows.row` builds. `SaChoiceButton` and `ColorPickerButton`
## are checked ahead of a plain toggle-mode `BaseButton`, since both are one
## under the hood.
static func _value(line: Control) -> Variant:
    if line.get_child_count() < 2:
        return null
    return _first_value(line.get_child(1))


static func _first_value(node: Node) -> Variant:
    if node is SaChoiceButton:
        return (node as SaChoiceButton).selected_value()
    if node is ColorPickerButton:
        return "#" + (node as ColorPickerButton).color.to_html(true)
    if node is Range:
        return (node as Range).value
    if node is LineEdit:
        return (node as LineEdit).text
    if node is BaseButton and (node as BaseButton).toggle_mode:
        return (node as BaseButton).button_pressed
    for child in node.get_children():
        var found: Variant = _first_value(child)
        if found != null:
            return found
    return null


## The class of every control under *line* that takes the keyboard, in tree
## order and by class rather than by node name, because Godot numbers a
## control nobody named.
static func _keys(line: Control) -> Array:
    var out: Array = []
    for node in line.find_children("*", "Control", true, false):
        var control := node as Control
        if control != null and control.focus_mode != Control.FOCUS_NONE:
            out.append(_class_of(control))
    return out


## The `class_name` a control's script declares, or the engine class under it
## for one that declares none, the way `sa_capture_notes.gd`'s `_kind_of`
## reads a node for a capture's own refusal.
static func _class_of(node: Node) -> String:
    var script := node.get_script() as Script
    var declared := String(script.get_global_name()) if script != null else ""
    return declared if not declared.is_empty() else node.get_class()


## Whether *node* is on a page already queued for deletion, the way
## `SaSettingsSearch._is_going` guards the moment a category switch leaves two
## pages in the tree.
static func _is_going(node: Node) -> bool:
    var walk := node
    while walk != null:
        if walk.is_queued_for_deletion():
            return true
        walk = walk.get_parent()
    return false
