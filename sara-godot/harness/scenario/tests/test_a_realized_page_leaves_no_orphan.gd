## A realized page leaves no control of its own without a parent.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A suite that opens every dialog under `res://ui/`
## and frees it reported two leaked canvas items at exit, one
## `ColorPickerButton` and one `Label`, with a font and seventeen `ObjectDB`
## instances behind them. A control a page built and never handed to a container
## is exactly that shape: nothing outside the page's own table holds it and
## nothing frees it, so Godot reports it at exit as a RID nobody released.
##
## **The check is the invariant rather than the exit report**, because a suite
## cannot read what the process leaks when it exits, and a leak report is
## somebody's reading of a log. A row's `control` and `custom_control` are the
## two places the page layer puts a control it built, and after a realization
## every one of them is either in a tree or already queued for freeing. Anything
## else is orphaned, which is what `SaFilterBrowser._free_declared` walks
## for on the browser's probe, and what this fails the run over.
##
## Both walks a page takes are here: one into a container that is in the tree,
## which is `SaPageDemo`, `SaSettingsWindow` and every converted Preferences
## page, and one into a container that is in no tree, which is a dialog built
## and never shown. The demo is the page, because it declares all ten row kinds
## and the row was filed against the colour one.
##
## The calibrating measurement, for a reader who has to know the check can see
## the shape at all: a `ColorPickerButton` with a `Label` child, created and
## left unparented in a suite, is reported at exit as two `CanvasItem` RIDs, one
## font, two shaped-text RIDs and seventeen `ObjectDB` instances.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _kept_embedding = tree.root.gui_embed_subwindows
        # A Window added to the tree without embedding maps a real OS window and
        # the run blocks until the watchdog fires. Whether the app embeds is a
        # user setting, so it is forced here rather than assumed.
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "PageOrphanTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## A page built into a container in the tree, rebuilt over itself, and freed
## with the window. The rebuild is the second realization, which is the one a
## page layer drops the first generation's controls in.
func test_a_page_in_a_live_container_holds_no_orphan() -> void:
    var demo := SaPageDemo.new()
    _host.add_child(demo)
    demo.show()
    assert_not_null(demo.page, "The demo declares its page in _init")
    _assert_no_orphans(demo.page, "one realization in the tree")
    demo.page.rebuild()
    _assert_no_orphans(demo.page, "a rebuild in the tree")
    demo.free()


## A page built into a container that is in no tree, which is the walk a dialog
## takes when it is built and never shown.
func test_a_page_in_a_detached_container_holds_no_orphan() -> void:
    var demo := SaPageDemo.new()
    assert_not_null(demo.page, "The demo declares its page in _init")
    _assert_no_orphans(demo.page, "a realization outside the tree")
    demo.free()


## Every control a row of *page* holds is parented or on its way out.
func _assert_no_orphans(page: SaPage, when: String) -> void:
    var orphans: Array[String] = []
    for row: SaPageRow in page.rows():
        for node: Control in [row.control, row.custom_control]:
            if node == null or not is_instance_valid(node):
                continue
            if node.get_parent() == null and not node.is_queued_for_deletion():
                orphans.append("%s holds a %s with no parent" % [String(row.key), node.get_class()])
    assert_true(
        orphans.is_empty(), "The page after %s leaves %d control(s) nothing owns: %s" % [when, orphans.size(), ", ".join(orphans)]
    )
