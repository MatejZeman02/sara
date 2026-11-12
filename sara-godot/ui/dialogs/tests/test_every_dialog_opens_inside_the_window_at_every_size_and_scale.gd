## Every dialog opens below the top bar with its buttons inside the window, on
## a 1280 by 800 and a 1920 by 1080 screen at interface scales of 1 and 2.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## At scale 2 New Document once opened 660 tall at y -68 in a window 540 tall,
## so New Document and the Manual could not be closed by pointer, and
## Preferences sat over the menu bar at y 20. The host a dialog was kept in was
## the whole main window, bar included, and a dialog taller than it was moved
## and never made smaller.
##
## The fix is three things, and this holds all of them. The host starts below the
## bar, `SaDialogWindow.top_inset`, which `MainDialogs` hands the row
## `MainDockers.below_bar` gives. A dialog taller or wider than that host is given
## its size, and its `scrolling_body` takes the difference. Preferences measures
## the same host with the same margin.
##
## The screens are `SubViewport`s with subwindows embedded in them, for the reason
## `test_the_about_window_fits_a_screen` gives, at the logical size a screen has
## at each scale: an embedded dialog measures itself in its host's logical units,
## so scale 2 on a 1280 by 800 screen is a host of 640 by 400. The dialogs are
## discovered the way `test_a_dialog_opens_to_show_its_own_buttons` discovers
## them, so a dialog added tomorrow is held to the same rule, and the fit is
## called by hand after one sort of every container, because no frame passes
## inside a test.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Where the dialog classes live, walked whole.
const UI_DIR := "res://ui"

## How few dialog classes the walk may find before it is the walk that broke,
## the number the sibling suite keeps.
const FLOOR := 17

## The two screens the row names, in physical pixels.
const SCREENS: Array[Vector2i] = [Vector2i(1280, 800), Vector2i(1920, 1080)]

## The two interface scales the row names.
const SCALES: Array[float] = [1.0, 2.0]

## The first row below a one-row bar, which is `MainDockers.below_bar`'s floor.
const BAR := 65

## The one screen some dialog's content is taller than: 1280 by 800 at scale 2,
## which leaves 640 by 335 below the bar.
const SMALLEST := Vector2i(640, 400)

## The dialogs whose content is larger than `SMALLEST` has room for, each with
## the row that owns the file that has to change. The title strip is still held
## below the bar and the window inside the screen, and an entry whose buttons
## come inside the window fails the run, so the list only shrinks.
##
## Measured in the app's theme at the default Font size, in a window given the
## whole 640 by 335. Dialogs whose page sits in a scroll have left the list, as
## have those whose rows sit in one, where their buttons had ended at 340 and 338
## of 335, and the brush editor, whose Rename, Save and Save As sit in the row of
## buttons, where Save As had ended at 642 of 640 across.
const TOO_TALL_FOR_THE_SMALLEST := {}

var _kept_scale: float = 1.0
var _kept_font_scale: float = 1.0
var _kept_theme: Theme = null
var _kept_inset: Callable = Callable()
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    # The app's own theme at the default Font size, because the gate runs
    # `res://tests/run_all.tscn` rather than the app: alone this suite measured
    # Godot's smaller default font, and after a suite that had built the theme
    # it measured Sara's, so the same dialog fitted in one run and not the next.
    _kept_font_scale = SaUI.user_font_scale
    _kept_theme = SaUI.shared_theme
    SaUI.user_font_scale = 1.0
    SaUI.init_global_theme(null)
    _kept_inset = SaDialogWindow.top_inset
    SaDialogWindow.top_inset = func() -> int: return BAR
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    # A dialog added outside the screens below would map a real OS window and
    # block the run, so the root embeds as well.
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N56DialogHostTest"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    SaUI.user_font_scale = _kept_font_scale
    SaUI.shared_theme = _kept_theme
    SaDialogWindow.top_inset = _kept_inset
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## The row's own words: every dialog, both screens, both scales, the title strip
## below the bar and every button inside the window.
func test_every_dialog_opens_below_the_bar_with_its_buttons_inside_the_window() -> void:
    var paths := _dialog_scripts()
    assert_true(paths.size() >= FLOOR, "Found %d dialog classes under %s" % [paths.size(), UI_DIR])
    for screen: Vector2i in SCREENS:
        for scale: float in SCALES:
            SaUI.user_scale = scale
            var logical := Vector2i(Vector2(screen) / scale)
            for path: String in paths:
                _check_dialog(path, logical, "%s at scale %.0f on %d by %d" % [path.get_file(), scale, screen.x, screen.y])


## The three that were worst at scale 2, New Document, the Manual
## and the tablet sweep, are given the host's height rather than their own.
## New Document and the sweep scroll to do it, and the Manual already did.
func test_the_three_it_names_are_given_the_hosts_height_at_scale_2() -> void:
    SaUI.user_scale = 2.0
    var logical := Vector2i(640, 400)
    var room := logical.y - BAR - 2 * SaDialogWindow.HOST_MARGIN
    for path: String in [
        "res://ui/dialogs/document/new_document/new_document_dialog.gd",
        "res://ui/dialogs/sa_manual_window.gd",
        "res://ui/settings/input/tablet_sweep_dialog.gd",
    ]:
        var window := _opened(path, logical)
        var name := path.get_file()
        assert_true(window.size.y <= room, "%s is %d tall in a room %d tall" % [name, window.size.y, room])
        assert_true(window.min_size.y <= room, "%s keeps a floor of %d in a room %d tall" % [name, window.min_size.y, room])
        if window.scrolling_body != null:
            var body := window.scrolling_body
            var text := ceili((body.get_child(0) as Control).get_combined_minimum_size().y)
            assert_true(
                body.custom_minimum_size.y < text, "%s scrolls, asking %d for %d" % [name, body.custom_minimum_size.y, text]
            )
        else:
            assert_true(name == "sa_manual_window.gd", "%s has no scrolling body" % name)


## A small host takes room off a dialog and leaves the size it wants, so a larger
## one gives the room back. The engine sends `size_changed` on a hide and on a
## `popup_centered` to the same size, and the tracker read the room as a size the
## painter gave it: New Document opened 592 wide at scale 1 on the screen that
## had just held 640 of it at scale 2.
func test_a_small_host_leaves_the_size_the_dialog_wants() -> void:
    var window := NewDocumentDialog.new()
    var screen := SubViewport.new()
    screen.size = SMALLEST
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    window.popup_centered()
    _settle(window)
    var wanted := window.logical_size.x
    window.fit_opening_size()
    assert_true(
        window.size.x < wanted,
        "the smallest host has to take width off it, or this proves nothing: %d of %d" % [window.size.x, wanted]
    )
    assert_eq(window.logical_size.x, wanted, "the width it wants is kept while the host holds it narrower")
    window.hide()
    screen.size = Vector2i(1920, 1080)
    window.popup_centered()
    window.fit_opening_size()
    assert_eq(window.logical_size.x, wanted, "closed and opened again, it wants the same width")
    assert_eq(window.size.x, wanted, "and the larger host gives it that width back")


## Preferences keeps the same margin and the same top as every other dialog, and
## maximized it fills the whole window, bar and all, as the chord fills it.
func test_preferences_measures_the_host_every_dialog_does() -> void:
    var window := _opened("res://ui/settings/sa_settings_window.gd", Vector2i(960, 540)) as SaSettingsWindow
    assert_eq(window.frame.host_rect(), window.host_rect(), "Preferences is fitted to the host every dialog is kept in")
    assert_eq(window.host_rect().position.y, BAR, "which starts below the bar")
    assert_eq(SaSettingsFrame.HOST_MARGIN, 2 * SaDialogWindow.HOST_MARGIN, "with the margin every dialog keeps")
    window.frame.toggle_maximized()
    assert_eq(window.position.y, 0, "Maximized, it starts at the window's top as the chord's does")
    window.frame.set_mode(SaSettingsFrame.Mode.NORMAL)


## The bar comes off the host only where the bar is.
func test_the_bar_comes_off_the_top_of_the_host_and_nothing_else() -> void:
    var window := _opened("res://ui/dialogs/about_dialog.gd", Vector2i(640, 400))
    assert_eq(window.below_the_bar(Rect2i(0, 0, 640, 400)), Rect2i(0, BAR, 640, 400 - BAR), "The bar's rows come off the top")
    assert_eq(window.below_the_bar(Rect2i(0, 0, 640, 40)), Rect2i(0, 0, 640, 40), "A host shorter than the bar keeps its rows")
    SaDialogWindow.top_inset = Callable()
    assert_eq(window.below_the_bar(Rect2i(0, 0, 640, 400)), Rect2i(0, 0, 640, 400), "With no bar the host is whole")


## One dialog of *path* on a screen of *logical* units: the title strip below the
## bar, the window inside the screen, and every button inside the window.
func _check_dialog(path: String, logical: Vector2i, where: String) -> void:
    var window := _opened(path, logical)
    if window == null:
        assert_true(false, "%s could not be opened" % where)
        return
    var frame := Rect2i(window.position, window.size)
    assert_true(
        window.position.y >= BAR,
        "%s opens with its title strip at y %d, over a bar ending at %d" % [where, frame.position.y, BAR]
    )
    assert_true(
        Rect2i(Vector2i.ZERO, logical).encloses(frame), "%s opens at %s, outside a screen of %s" % [where, frame, logical]
    )
    var own := Rect2(Vector2.ZERO, Vector2(window.size))
    var outside: PackedStringArray = []
    for button: Button in _buttons_under(window):
        if not button.is_visible_in_tree():
            continue
        var rect := button.get_global_rect()
        if not own.encloses(rect):
            outside.append("%s at %s" % [button.name, rect])
    var owner: String = TOO_TALL_FOR_THE_SMALLEST.get(path.get_file(), "") if logical == SMALLEST else ""
    if not owner.is_empty():
        assert_false(
            outside.is_empty(), "%s now keeps every button inside it, so its entry for %s comes off the list" % [where, owner]
        )
        return
    assert_true(outside.is_empty(), "%s is %s and holds buttons outside it: %s" % [where, window.size, ", ".join(outside)])


## A dialog of *path* on a fresh screen of *logical* units, opened the way the
## app opens one and fitted. The screen is freed with the suite's host.
func _opened(path: String, logical: Vector2i) -> SaDialogWindow:
    var script := load(path) as GDScript
    if script == null or not script.can_instantiate():
        return null
    var window := script.new() as SaDialogWindow
    if window == null:
        return null
    var screen := SubViewport.new()
    screen.size = logical
    screen.gui_embed_subwindows = true
    _host.add_child(screen)
    screen.add_child(window)
    window.popup_centered()
    _settle(window)
    window.fit_opening_size()
    _settle(window)
    return window


## Lays *window* out the way a drawn frame would, twice over: every container
## sorted outside in, which gives a wrapping label its width, and then every
## control asked for its minimum again, which a label answers for that width
## only when told to. Once is not enough, because the first answer is the height
## of the whole text one character wide, the reason `_fit_scrolling_body` asks.
func _settle(window: Window) -> void:
    for _pass in range(2):
        _sort_children(window)
        _ask_again(window)
    # A control laid out by its anchors takes a new minimum on a deferred call,
    # which no frame runs here, so the export dialog's column kept the 2600 it
    # first answered. A pixel on the window and back has every one of them
    # derive its size again, the way a frame's resize would.
    var kept := window.size
    window.size = kept + Vector2i.ONE
    window.size = kept
    _sort_children(window)


## Every container under *node* sorted, outside in.
func _sort_children(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Every control under *node* asked for its minimum again, inside out.
func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## Every `Button` under *node* that is not inside a scrolled region, where a
## button past the window's edge is one the wheel brings back.
func _buttons_under(node: Node) -> Array[Button]:
    var found: Array[Button] = []
    for child: Node in node.get_children():
        if child is ScrollContainer or child is Window:
            continue
        if child is Button:
            found.append(child as Button)
        found.append_array(_buttons_under(child))
    return found


## Every script under `res://ui/` that says it extends the dialog window, but a
## suite, the walk the sibling suite makes.
func _dialog_scripts() -> Array[String]:
    var paths: Array[String] = []
    _walk(UI_DIR, paths)
    paths.sort()
    return paths


func _walk(dir_path: String, into: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for entry: String in dir.get_files():
        if entry.ends_with(".gd") and _extends_dialog_window(dir_path.path_join(entry)):
            into.append(dir_path.path_join(entry))
    for sub: String in dir.get_directories():
        if sub != "tests":
            _walk(dir_path.path_join(sub), into)


func _extends_dialog_window(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    for line: String in file.get_as_text().split("\n"):
        var text := line.strip_edges()
        if text.begins_with("extends SaDialogWindow") or text.begins_with('extends "res://ui/dialogs/sa_dialog_window.gd"'):
            return true
        if text.begins_with("func ") or text.begins_with("var ") or text.begins_with("const "):
            return false
    return false
