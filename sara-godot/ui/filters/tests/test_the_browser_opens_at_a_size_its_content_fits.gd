## The Filters browser opens at a size its own content fits in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The fault: Filter > Browse Filters opened the window 720 by 2780 with its
## top at y -866, so the list, the preview and the Close and Open buttons were
## off the screen and what the painter saw was a dark column down the middle of
## the canvas. `fit_opening_size` is why. A `Container` in a hidden window
## sorts none of its children, so nothing inside has a width yet, and a wrapping
## `Label` answers the height of its whole text one character wide. The browser's
## own sentence measured 2069 pixels that way, on the frame the fit ran, which is
## the frame after every dialog installed at boot is built and still hidden. The
## fit grows and never shrinks, so the real number a frame later could not take
## it back.
##
## Two halves, one per direction. A browser that is still hidden is not fitted at
## all, which is the guard in `SaDialogWindow.fit_opening_size`, and a browser
## that has been shown and laid out opens at a size its content fits, which is
## what the fit is for.
##
## The second half lays the window out by hand, because a test cannot await a
## frame: a container sorts its children when it is sent
## `NOTIFICATION_SORT_CHILDREN`. `test_a_dialog_opens_to_show_its_own_buttons.gd`
## makes the same trade, and the frame itself is on the running app in
## `scenarios/the-filter-browser.json` and
## `scenarios/a-filter-carries-no-sentence.json`, whose dumps read the
## window 720 by 520 at (600, 264) inside the 1920 by 1048 root.
##
## The Filters browser is a docker, which a layout places
## rather than a fit, so the window held here is the layer kind browser: the
## same list, search and detail at the same floor, in the dialog that is left.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## The floor the browser's own constructor declares, in logical units. Every
## number this suite reads is against it rather than against the pixels below it,
## because the interface scale is a preference and a raw pixel is only true at
## one of them.
const FLOOR := Vector2i(720, 520)

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
    _host.name = "D26BrowserTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## The defect: a fit taken on a window nothing has laid out grows it against a
## number no layout produced.
##
## The fixture guard is the first assertion rather than a decoration. Without it
## this test would pass just as green on a browser whose sentence happened to be
## short enough to wrap inside the floor while hidden, which is a fact about the
## words rather than about the fit.
func test_a_hidden_browser_is_not_fitted() -> void:
    var browser := _browser()
    assert_false(browser.visible, "a browser is installed hidden and has to start that way")
    # The scroll's own column, because the sentence sits in the scroll
    # and the fit hands that column as much of the host as it asks.
    var words := browser.scrolling_body.get_child(0) as Control
    assert_true(
        words.get_combined_minimum_size().y > FLOOR.y,
        "the hidden browser's content must measure its unlaid-out self here, or this fixture is not the 2780 the defect opened at"
    )
    browser.fit_opening_size()
    assert_eq(browser.logical_size, FLOOR, "a hidden window has no laid-out content to fit, so it stays at its floor")
    assert_eq(
        browser.size,
        SaUI.window_size_for(browser, FLOOR),
        "and it stays at the size that floor is, in whatever units the window measures in"
    )
    browser.free()


## The other half: shown and laid out, it opens at a size its content fits, and
## every button it offers is inside it.
func test_a_shown_browser_opens_at_a_size_its_content_fits() -> void:
    var browser := _browser()
    browser.show()
    # The size the app opens it at, laid out the way the app's own frame lays it
    # out: the floor first, then sorted until every wrapping label has a width.
    # One round left the sentence one character wide and the content 2308 tall,
    # which the fit grew to before a window was held to its host.
    browser.size = SaUI.window_size_for(browser, FLOOR)
    _settle(browser)

    browser.fit_opening_size()

    # What the content needs, as far as the host has it, because past the host
    # the fit cuts the window at the bottom edge rather than hang it off.
    var needed := browser.content_minimum_size()
    var whole := browser.host_room(0)
    if whole.x > 0 and whole.y > 0:
        needed = needed.min(whole)
    assert_true(
        browser.logical_min_size.x >= needed.x and browser.logical_min_size.y >= needed.y,
        "at scale 1 the browser opens at a floor of %s, under the %s its content needs" % [browser.logical_min_size, needed]
    )
    assert_true(
        browser.logical_size.x >= browser.logical_min_size.x and browser.logical_size.y >= browser.logical_min_size.y,
        "the browser opens at %s, under the floor of %s it just took" % [browser.logical_size, browser.logical_min_size]
    )
    assert_eq(
        browser.min_size,
        SaUI.window_size_for(browser, browser.logical_min_size),
        "its floor goes through SaUI, which is the one writer of UI scale"
    )
    _check_buttons_inside(browser)
    browser.free()


## One browser, built and in the tree, hidden, with the sentence its own
## constructor's first selection draws.
##
## `watch` with no registry is what the app itself does before a module has
## loaded: it refreshes, and the refresh picks nothing and writes the browser's
## own explanation into the sentence, which is the text that made it tall. The
## sentence is the whole point, so a fixture that skipped the refresh would be a
## browser with an empty label and nothing to measure.
func _browser() -> SaLayerKindBrowser:
    var browser := SaLayerKindBrowser.new()
    _host.add_child(browser)
    browser.browser.watch(null, null)
    return browser


## Lays *window* out the way the frames after it is shown would, which a test
## cannot await: sorted and asked again twice, so a wrapping label measures the
## width it was given, then a pixel on the window and back, so a control laid out
## by its anchors takes its new minimum without the deferred call no frame runs.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


## Every control under *node* asked for its minimum again, inside out.
func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## Sorts every container under *node*, outside in, so the rectangles below it are
## the ones the running app would draw.
func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Every button the browser offers lies within its own rectangle.
##
## The scrolled list is skipped, because content past a `ScrollContainer`'s edge
## is correct rather than the defect: the browser's list runs several rows tall
## and the wheel reaches the rest.
func _check_buttons_inside(browser: SaLayerKindBrowser) -> void:
    var frame := Rect2(Vector2.ZERO, Vector2(browser.size))
    var outside: Array[String] = []
    for button: Button in _buttons_under(browser.content):
        if not button.visible:
            continue
        var rect := button.get_global_rect()
        if not frame.encloses(rect):
            outside.append("%s at %s" % [button.name, rect])
    assert_true(outside.is_empty(), "the browser is %s and holds buttons outside it: %s" % [browser.size, ", ".join(outside)])


func _buttons_under(node: Node) -> Array[Button]:
    var found: Array[Button] = []
    if node == null:
        return found
    for child: Node in node.get_children():
        if child is ScrollContainer:
            continue
        if child is Button:
            found.append(child as Button)
        found.append_array(_buttons_under(child))
    return found
