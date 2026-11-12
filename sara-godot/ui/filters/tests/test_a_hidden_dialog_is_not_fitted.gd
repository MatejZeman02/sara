## A dialog that is hidden is not measured, so the filter browser opens at the
## size it asks for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fault: the browser "asks for 720 by 520 and opens far taller", its
## Close, Attach and Open buttons below the screen's edge. The measurement, from
## `scenarios/the-filter-browser-opens-taller-than-the-screen.json` on the
## commit before the fix: the window stood at 720 by 2780 with its top at y -866,
## and the two wrapping labels of the detail column asked for 2069 and 333 of
## that height, the sentence and the title, each one pixel wide.
##
## The cause is the frame the fit runs on. `SaDialogWindow._ready` asks for
## `fit_opening_size` on the next frame, and the browser is installed at boot and
## hidden in its `_init`. A `Container` in a hidden `Window` sorts none of its
## children, which is a known engine behaviour, so a
## wrapping label there stays as wide as it was built, which is nothing, and
## answers a line per word for ever. The fit took that answer for the content's
## demand, raised the floor to 2780, and the fit never shrinks a floor, so the
## honest 456 it measured one frame after the window opened changed nothing.
##
## So the fit leaves a hidden window alone, and the one that runs a frame after
## `visible` is the first to measure. This suite holds the hidden half, which is
## the half a test can reach: no frame passes inside a test, so the open window's
## 720 by 520 and its buttons' rectangles are the scenario's to show.
##
## The Filters browser is a docker, and a docker is not
## fitted, so the window held here is the layer kind browser, which carries the
## same detail column at the same floor and is built hidden the same way.
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
        # the run blocks until the watchdog fires.
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "HiddenDialogFitTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## The browser as its first use leaves it: in the tree, hidden, and fitted once.
func test_a_hidden_browser_keeps_the_floor_it_declared() -> void:
    var browser := SaLayerKindBrowser.new()
    _host.add_child(browser)
    assert_false(browser.visible, "The browser hides itself in _init, which is the state boot fits it in")
    var declared := browser.logical_min_size
    var asked := browser.logical_size

    browser.fit_opening_size()

    assert_eq(browser.logical_min_size, declared, "A fit over a hidden window raised its floor from what nobody laid out")
    assert_eq(browser.logical_size, asked, "A fit over a hidden window grew the size the browser asks for")
    # What the fit would have believed, so the number that made the defect is on
    # the record beside the floor it no longer reaches. The scroll counts at
    # what its column asks, since the sentence sits in it and the
    # fit hands that column as much of the host as it asks.
    var body := browser.scrolling_body
    var column := body.get_child(0) as Control
    var unsorted := browser.content_minimum_size().y - body.get_combined_minimum_size().y + column.get_combined_minimum_size().y
    assert_true(
        unsorted > declared.y,
        "The unsorted labels no longer overstate the height (%d), so this suite proves nothing and wants rewriting" % unsorted
    )


## The layout block a scenario reads names the window and the buttons, the
## Filters docker's under the keys the window's had, and the layer kind
## browser's with its Close beside the Open.
func test_the_layout_block_names_the_window_and_the_buttons() -> void:
    var docker := FiltersDocker.new()
    var browser := SaLayerKindBrowser.new()
    _host.add_child(browser)
    var placed := {
        "docker": [docker.describe()["layout"], ["BrowserOpenButton"]],
        "kind browser": [browser.describe()["layout"], ["BrowserCloseButton", "BrowserOpenButton"]],
    }
    for holder: String in placed:
        var layout: Dictionary = placed[holder][0]
        for key: String in ["window", "logical_min_size", "content_minimum", "minimums", "buttons"]:
            assert_true(layout.has(key), "The %s's layout block has no '%s'" % [holder, key])
        var buttons: Dictionary = layout["buttons"]
        for button_name: String in placed[holder][1]:
            assert_true(buttons.has(button_name), "The %s's layout block does not place %s" % [holder, button_name])
    docker.free()
