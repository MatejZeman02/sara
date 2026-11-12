## The door's `pattern` step: opens the pattern chooser in a window over the
## app, picks a pattern and writes what the chooser shows where a reviewer
## reads it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A chooser no page hosts yet has nothing a scenario can click, and a feature
## is proved on the running app, so this is the step that proves one, the way
## `sa_kpp_capture.gd` proves a reader with no button. The editor's Texture
## page hosts the control, and this window is how the chooser alone is shot.
## Reached by the `pattern_capture` role the module registers, so the
## skeleton's step table names no module class.
##
## `{"pattern": {"open": true, "icon_size": 64, "pick": "Paper Grain", "close": true}}`,
## each key optional and applied in that order. A pick also writes the name
## onto the live brush's `pattern_name`, so a preset saved by the next step
## carries it and a load proves the round trip on the app. With no window
## open the step drives the chooser on screen instead, which is the Texture
## page's, so `{"pattern": {"pick": "Paper Grain"}}` after a `brush_editor`
## step on that page picks on the page.
##
## **The window's chooser lists from the module's store**, found through the
## live brush's settings the way a pick finds them, so what the store
## remembers between two `open`s is what the shot shows. Two keys for proving
## that memory: `"unreadable": ["Lienzo 01", ...]` writes a `.pat` of each
## name into the painter's folder that no reader can read, and `"tidy": true`
## removes what this step wrote, so the next scenario's store does not list
## them. Both rescan the store.
class_name SaPatternCapture
extends RefCounted

const REPORT_FILE: String = "pattern.txt"
const WINDOW_NAME: String = "PatternChooserWindow"

## The window this opened, so a later step finds the same chooser.
static var _window: Window = null

## The files `"unreadable"` wrote, for `"tidy"` to remove.
static var _written: PackedStringArray = PackedStringArray()

## What an unreadable `.pat` holds: ten bytes, short of any header.
const TORN_BYTES: PackedByteArray = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]


## Handed the tree and the run's folder, which is all it would take the
## capture node for.
static func capture(tree: SceneTree, out_dir: String, spec: Dictionary) -> String:
    if spec.has("unreadable"):
        _write_unreadable(tree, Array(spec["unreadable"]))
    if bool(spec.get("tidy", false)):
        _tidy(tree)
    if bool(spec.get("open", false)):
        _open(tree, int(spec.get("icon_size", SaPatternChooser.DEFAULT_ICON)))
    var chooser := _chooser(tree)
    if chooser == null:
        return "SaCapture: pattern step has no chooser open and none on a page, so open one first"
    if spec.has("icon_size") and not bool(spec.get("open", false)):
        chooser.icon_size = int(spec["icon_size"])
        chooser.refresh()
        _fit(_window)
    if spec.has("pick"):
        chooser.pick(String(spec["pick"]))
        _write_brush(tree, chooser.selected)
    var line := (
        "SaCapture: pattern chooser %s, brush pattern '%s'" % [JSON.stringify(chooser.chooser_report()), _brush_pattern(tree)]
    )
    _append_line(out_dir, line)
    if bool(spec.get("close", false)):
        _close()
    return line


## The module's store, off the live brush's settings, or a fresh one when no
## brush is live, which is a run with no module loaded.
static func _store(tree: SceneTree) -> SaPatternStore:
    var settings := _brush_settings(tree)
    if settings != null and "pattern_store" in settings:
        var store := settings.get("pattern_store") as SaPatternStore
        if store != null:
            return store
    return SaPatternStore.new()


## Writes one unreadable `.pat` per name into the painter's folder and rescans
## the store, so the next listing meets them.
static func _write_unreadable(tree: SceneTree, names: Array) -> void:
    DirAccess.make_dir_recursive_absolute(SaPatternStore.saved_dir())
    for entry: Variant in names:
        var path := SaPatternStore.saved_dir().path_join("%s.%s" % [String(entry), SaPattern.PAT_EXTENSION])
        var file := FileAccess.open(path, FileAccess.WRITE)
        if file == null:
            push_warning("SaPatternCapture: could not write %s" % path)
            continue
        file.store_buffer(TORN_BYTES)
        file.close()
        if not _written.has(path):
            _written.append(path)
    _store(tree).rescan()


## Removes what `_write_unreadable` wrote and rescans the store.
static func _tidy(tree: SceneTree) -> void:
    for path in _written:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)
    _written = PackedStringArray()
    _store(tree).rescan()


## A window over the main one holding a fresh chooser over the module's store,
## or over *parent* when one is named, which is a suite's, whose root is busy.
static func _open(tree: SceneTree, icon_size: int, parent: Node = null) -> void:
    _close()
    var window := Window.new()
    window.name = WINDOW_NAME
    window.title = TranslationServer.translate("Patterns")
    window.transient = true
    window.unresizable = true
    var panel := PanelContainer.new()
    panel.name = "Panel"
    var chooser := SaPatternChooser.new(_store(tree), icon_size)
    chooser.name = "Chooser"
    panel.add_child(chooser)
    window.add_child(panel)
    (parent if parent != null else tree.root).add_child(window)
    _fit(window)
    window.show()
    _window = window


## Sizes *window* to the chooser it holds and centres it, so a grid drawn
## again at a larger tile is not clipped by the frame the smaller one got.
static func _fit(window: Window) -> void:
    if window == null:
        return
    var panel := window.get_node_or_null("Panel") as Control
    if panel == null:
        return
    var wanted := Vector2i(panel.get_combined_minimum_size()) + Vector2i(SaUI.px(24), SaUI.px(24))
    window.size = wanted
    @warning_ignore("integer_division")
    window.position = (window.get_parent().get_window().size - wanted) / 2


static func _close() -> void:
    if _window != null and is_instance_valid(_window):
        _window.get_parent().remove_child(_window)
        _window.queue_free()
    _window = null


## The chooser this step drives: the one in the window this opened, or, with
## no window open, the one on screen, which is the brush editor's Texture
## page. Found by method the way the curve control is, so a pick lands on the
## page's own control and goes through its write door, which is what marks the
## preset dirty and redraws the preview.
static func _chooser(tree: SceneTree) -> SaPatternChooser:
    if _window != null and is_instance_valid(_window):
        return _window.find_child("Chooser", true, false) as SaPatternChooser
    for node in tree.root.find_children("*", "VBoxContainer", true, false):
        # By class rather than by method: the presets docker's chooser answers
        # `chooser_report` too, and it is always on screen.
        if node is SaPatternChooser and (node as Control).is_visible_in_tree():
            return node as SaPatternChooser
    return null


## The live brush's settings: the brush of the surface the painter is working
## on, which is the tool a `brush` step moves.
static func _brush_settings(tree: SceneTree) -> Resource:
    var canvas := SaCanvasView.front_canvas()
    if canvas == null or canvas.get_tree() != tree:
        return null
    var machine := canvas.get_node_or_null("ToolMachine") as ToolMachine
    var tool: ToolState = machine.get_tool("brush") if machine != null else null
    return tool.settings if tool != null and "settings" in tool else null


static func _write_brush(tree: SceneTree, pattern_name: String) -> void:
    var settings := _brush_settings(tree)
    if settings != null and "pattern_name" in settings:
        settings.set("pattern_name", pattern_name)


static func _brush_pattern(tree: SceneTree) -> String:
    var settings := _brush_settings(tree)
    return String(settings.get("pattern_name")) if settings != null and "pattern_name" in settings else ""


static func _append_line(dir: String, line: String) -> void:
    if dir.is_empty():
        return
    var path := dir.path_join(REPORT_FILE)
    var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
    if file == null:
        push_warning("SaPatternCapture: could not write %s" % path)
        return
    file.seek_end()
    file.store_line(line)
    file.close()
