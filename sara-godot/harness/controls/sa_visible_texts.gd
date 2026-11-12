## The `texts` form of the `cut_labels` step: lists every text one window shows,
## as it is drawn, so a search in the test language can read which of them carry
## no mark and so skipped the catalogue.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What counts as a text the painter sees.** The words of a label and of a
## button, choices, toggles and menu buttons among them, the parsed words of a
## rich text label, the placeholder of a text field, the hover tip of any
## control, the tab titles of a tab bar, the rows of an item list and of a
## popup menu, and a window's title. A text field's own text is the painter's,
## and a tree's rows are a document's, so neither is read. Each text is read
## the way the control draws it, `atr()` of what it holds, which is the text
## itself where the control does not translate, so a word that reached the
## control already translated reads as it shows.
##
## The engine's own children of a control are read too, the label and buttons
## of a dialog and the tab bar of a tab container, since the painter sees them
## as the control's.
##
## Reached through `SaControlWalker.cut_labels`, the folder's facade.
extends RefCounted

const CutLabels := preload("res://harness/controls/sa_cut_labels.gd")

## The menus whose dialogs the search for unmarked texts opens.
const DIALOG_MENUS: Array[String] = ["File", "Layer", "Filter"]


## `{"cut_labels": {"texts": true, "main": true}}` reads the main window, and
## `"preferences"`, `"docker"` and `"menu"` the windows `cut_labels` reads, and
## `{"texts": true, "windows": true}` every other window that is open, a
## dialog, the welcome window or a corner message. The answer is one line,
## `SaCapture: texts '<name>' <count> read <json>`, the JSON a list of
## `{"path", "kind", "what", "text", "rect"}`, the rect in the main window's
## pixels, as a shot of it holds them.
##
## Four forms help a walk on its way. `{"texts": true, "list": true}` answers
## the dialog rows of File, Layer and Filter, `"open_windows": true` the paths
## of the windows open now, `"hide": [<path>, ...]` hides those of them a
## dialog left open once escape has been pressed, and `"tab": {"in":
## "Panes", "index": 2}` brings a tab container's tab forward, the welcome
## window's panes among them.
static func capture(tree: SceneTree, spec: Dictionary) -> String:
    if spec.get("list", false):
        return "SaCapture: texts list %s" % JSON.stringify(_dialog_rows(tree))
    if spec.get("open_windows", false):
        var open: Array = []
        for window in _open_windows(tree):
            open.append(String(tree.root.get_path_to(window)))
        return "SaCapture: texts windows %s" % JSON.stringify(open)
    if spec.has("hide"):
        var hidden := 0
        for path: String in spec["hide"]:
            var window := tree.root.get_node_or_null(NodePath(path)) as Window
            if window != null and window.visible:
                window.hide()
                hidden += 1
        return "SaCapture: texts hid %d windows" % hidden
    if spec.has("invoke"):
        var opened := SaFilterDriver.invoke_filter(tree, String(spec["invoke"]))
        return "SaCapture: texts %s filter '%s'" % ["opened" if opened else "found no", String(spec["invoke"])]
    if spec.has("tab"):
        var tab_spec: Dictionary = spec["tab"]
        var holder := tree.root.find_child(String(tab_spec.get("in", "")), true, false) as TabContainer
        if holder == null:
            return "SaCapture: texts found no tab container '%s'" % String(tab_spec.get("in", ""))
        holder.current_tab = int(tab_spec.get("index", 0))
        return "SaCapture: texts tab %d of '%s'" % [holder.current_tab, holder.name]
    var name := String(spec.get("name", ""))
    var scopes: Array[Node] = []
    if spec.get("windows", false):
        scopes.append_array(_open_windows(tree))
    else:
        var scope := CutLabels.window_of(tree, spec)
        if scope == null:
            return "SaCapture: texts '%s' found no window for %s" % [name, JSON.stringify(spec)]
        scopes.append(scope)
    var found: Array[Dictionary] = []
    for scope in scopes:
        if scope is Window and scope != tree.root:
            var window := scope as Window
            _add(tree, window, window, "title", window.atr(window.title), found)
        _read_node(tree, scope, found)
        _walk(tree, scope, found)
    return "SaCapture: texts '%s' %d read %s" % [name, found.size(), JSON.stringify(found)]


## The rows of File, Layer and Filter that open a dialog, which `{"texts":
## true, "list": true}` answers as `{"menu", "id", "text"}` for a walk to run
## each with `menu_item`: a row whose words end in an ellipsis, and every
## filter, since a filter's row opens its dialog with no ellipsis. A row that
## takes no press is left out.
static func _dialog_rows(tree: SceneTree) -> Array:
    var rows: Array = []
    var bar := CutLabels.top_bar(tree)
    if bar == null:
        return rows
    for menu_name: String in DIALOG_MENUS:
        var popup := bar.menus.get(menu_name) as SaChoicePopup
        if popup == null:
            continue
        for row_id in popup.row_ids():
            var id := SaMenu.id_of(row_id)
            var button := popup.label_button(row_id)
            if id < 0 or button == null or button.disabled:
                continue
            if button.text.contains("...") or button.text.contains("…"):
                rows.append({"menu": menu_name, "id": id, "text": button.text})
    var main_node := tree.current_scene
    var registries := main_node.get("registries") as SaRegistries if main_node != null else null
    var filters := registries.filters if registries != null else null
    if filters != null:
        for key: StringName in filters.list_keys():
            var filter := filters.get_filter(key)
            if filter != null:
                rows.append({"menu": "Filter", "filter": String(filter.id()), "text": filter.translated_title()})
    return rows


## Every window shown over the main one but the top bar's menus.
static func _open_windows(tree: SceneTree) -> Array[Node]:
    var open: Array[Node] = []
    for node in tree.root.find_children("*", "Window", true, false):
        var window := node as Window
        if window.visible and not _is_top_bar_menu(tree, window):
            open.append(window)
    return open


## A menu of the top bar, which the `menu` scope reads while it is open.
static func _is_top_bar_menu(tree: SceneTree, window: Window) -> bool:
    var bar := CutLabels.top_bar(tree)
    return bar != null and bar.menus.values().has(window)


static func _walk(tree: SceneTree, node: Node, found: Array[Dictionary]) -> void:
    for child in node.get_children(true):
        if child is Window:
            continue
        if child is CanvasItem and not (child as CanvasItem).visible:
            continue
        _read_node(tree, child, found)
        _walk(tree, child, found)


## Every text *node* shows, by the kind of control it is.
static func _read_node(tree: SceneTree, node: Node, found: Array[Dictionary]) -> void:
    if node is PopupMenu:
        var menu := node as PopupMenu
        for i in menu.item_count:
            if not menu.is_item_separator(i):
                _add(tree, menu, menu, "item %d" % i, menu.atr(menu.get_item_text(i)), found)
        return
    if not node is Control:
        return
    var control := node as Control
    if control is Label or control is Button:
        var shown := control.atr(String(control.get("text")))
        if control is Label and (control as Label).uppercase:
            shown = shown.to_upper()
        _add(tree, control, control, "text", shown, found)
    elif control is RichTextLabel:
        _add(tree, control, control, "text", (control as RichTextLabel).get_parsed_text(), found)
    elif control is LineEdit:
        _add(tree, control, control, "placeholder", control.atr((control as LineEdit).placeholder_text), found)
    elif control is TabBar:
        var tabs := control as TabBar
        for i in tabs.tab_count:
            _add(tree, control, control, "tab %d" % i, control.atr(tabs.get_tab_title(i)), found)
    elif control is ItemList:
        var items := control as ItemList
        for i in items.item_count:
            _add(tree, control, control, "item %d" % i, control.atr(items.get_item_text(i)), found)
    _add(tree, control, control, "tooltip", control.atr(control.tooltip_text), found)


static func _add(tree: SceneTree, node: Node, at: Node, what: String, shown: String, found: Array[Dictionary]) -> void:
    if shown.strip_edges().is_empty():
        return
    (
        found
        . append(
            {
                "path": String(tree.root.get_path_to(node)),
                "kind": node.get_class(),
                "what": what,
                "text": shown,
                "rect": _rect_in_main(tree, at),
            }
        )
    )


## Where *node* is drawn in the main window's pixels, the offsets of the
## embedded windows it sits in added and the main window's own scale applied,
## or an empty list for a window of its own the main window's shot never holds.
static func _rect_in_main(tree: SceneTree, node: Node) -> Array:
    var rect := Rect2()
    if node is Control:
        rect = (node as Control).get_global_rect()
    elif node is Window:
        rect = Rect2(Vector2.ZERO, Vector2((node as Window).size))
    else:
        return []
    var window := node as Window if node is Window else (node as Node).get_window()
    while window != null and window != tree.root:
        if not window.is_embedded():
            return []
        rect.position += Vector2(window.position)
        var parent := window.get_parent()
        window = parent.get_window() if parent != null else null
    rect = tree.root.get_final_transform() * rect
    return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)]
