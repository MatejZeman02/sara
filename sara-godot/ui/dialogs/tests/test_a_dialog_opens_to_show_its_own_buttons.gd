## Every dialog opens at a size its own content fits in.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A dialog window that opens too small hides its buttons (like export and
## cancel) until it is resized. `SaDialogWindow._init_dialog` opens at the
## `logical_min_size` its constructor declares, a number a dialog's author
## guesses, and without asking the content afterwards a dialog that gains a row
## opens at a height its own column no longer fits. Nothing clips, so there is
## no sign of it on screen either. The export dialog, whose column is
## the one that went off the bottom, is
## `scenarios/a-dialog-opens-too-small-to-show-its-own-buttons.json`: at a font
## size of 1.5 its Cancel and Export buttons were below the bottom edge, and
## `scenarios/export-dialog.json` is the same dialog at the default size, where
## the fit moves it five pixels.
##
## `SaDialogWindow.fit_opening_size` is the fix and this is its proof. The
## dialogs are **discovered** rather than listed: every `.gd`
## under `res://ui/` whose source says it extends the dialog window is opened
## here, so a dialog added tomorrow is covered the day it lands. Each one is
## opened embedded in the real tree, at scale 1 and at scale 2, and three things
## are read off it: the floor it opens with against what its content measures,
## the size it opens with against that floor, and the buttons' own rectangles
## against the window's.
##
## **The fit is called by hand here**, because the app calls it a frame after the
## window is built and a test cannot await a frame. That is the same trade
## `test_dialog_keeps_its_resized_size` makes with `_track_logical_size`. What
## it costs is the two things a frame is needed for: that the wiring runs at all,
## and how tall the window ends up on a real layout. Both are on the running app
## in `scenarios/a-dialog-opens-too-small-to-show-its-own-buttons.json`, which
## opens the export dialog at a font size of 1.5 and whose dump carries the size
## it ends at. What this suite is worth is that it is **red on the commit before
## the fix**: twelve of the twenty-two dialogs declare a floor under what their
## own content measures, and the list is printed below.
##
## `test_windows_open.gd` asks the same question of two dialogs by hand, which is
## where the colour space dialog's 3716-against-500 column was caught. It stays
## as it is: it reads the container's minimum, and this reads the laid-out
## button.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

## Where the dialog classes live, walked whole.
const UI_DIR := "res://ui"

## The two scales the interface runs at. An embedded subwindow inherits its
## host's scale and writes none of its own, so both passes lay out the same
## logical rectangle and the second one is what proves the arithmetic went
## through `SaUI.window_size_for` rather than a raw write of the number.
const SCALES: Array[float] = [1.0, 2.0]

## How few dialog classes the walk may find before it is the walk that broke
## rather than the tree that shrank.
##
## Seventeen, since the Levels and Curves dialogs live in the base module as
## filters, and the palette's followed.
const FLOOR := 17

var _kept_scale: float = 1.0
var _kept_embedding: bool = true
var _host: Node = null


func before_each() -> void:
    _kept_scale = SaUI.user_scale
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        _kept_embedding = tree.root.gui_embed_subwindows
        # A Window added to the tree without embedding maps a real OS window and
        # the run blocks until the watchdog fires. Whether the app embeds is a
        # user setting, so it is forced here rather than assumed.
        tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "DialogFitTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaUI.user_scale = _kept_scale
    var tree := Engine.get_main_loop() as SceneTree
    if tree != null:
        tree.root.gui_embed_subwindows = _kept_embedding
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null


## Every dialog Sara has, at both scales, at a size its content fits in.
func test_every_dialog_opens_at_a_size_its_content_fits() -> void:
    var paths := _dialog_scripts()
    assert_true(
        paths.size() >= FLOOR, "Found %d dialog classes under %s, which is far fewer than Sara has" % [paths.size(), UI_DIR]
    )

    for scale: float in SCALES:
        SaUI.user_scale = scale
        for path: String in paths:
            _check_dialog(path, scale)


## The dialogs whose declared floor is under what their content measures, which
## is what a painter sees and what "some" counts.
##
## Read off an instance that never entered the tree, where `ready` has not run
## and `logical_min_size` is still the constructor's number, against the same
## class opened properly. A dialog that passes here is one whose author guessed
## its floor right, and the list is expected to change as content grows rather
## than to stay empty, which is why it is only printed.
func test_the_declared_floor_is_the_thing_that_was_too_small() -> void:
    var wanted := _dialog_scripts()
    assert_true(wanted.size() >= FLOOR, "The dialog walk found %d classes" % wanted.size())

    var rescued: Array[String] = []
    for path: String in wanted:
        var declared := _declared_floor(path)
        if declared == Vector2i.ZERO:
            continue
        var opened := _open(path)
        if opened == null:
            continue
        var needed := opened.content_minimum_size()
        if declared.x < needed.x or declared.y < needed.y:
            rescued.append("%s declared %s and needs %s" % [path.get_file(), declared, needed])
        opened.free()

    print("   dialogs under their own content: %d of %d" % [rescued.size(), wanted.size()])
    for line: String in rescued:
        print("      %s" % line)


## One dialog, one scale: the floor, the size and the buttons.
func _check_dialog(path: String, scale: float) -> void:
    var window := _open(path)
    if window == null:
        assert_true(false, "%s could not be opened at scale %.2f" % [path, scale])
        return

    var name := path.get_file()
    # What the content needs, or the whole host when that is less: a
    # dialog's floor is never larger than its host, and its scrolling
    # body is what takes the difference.
    var needed := window.content_minimum_size()
    var room := window.host_room(0)
    if room.x > 0 and room.y > 0:
        needed = needed.min(room)
    assert_true(
        window.logical_min_size.x >= needed.x and window.logical_min_size.y >= needed.y,
        "%s at scale %.2f opens at a floor of %s, under the %s its content needs" % [name, scale, window.logical_min_size, needed]
    )
    assert_true(
        window.logical_size.x >= window.logical_min_size.x and window.logical_size.y >= window.logical_min_size.y,
        (
            "%s at scale %.2f opens at %s, under the floor of %s it just took"
            % [name, scale, window.logical_size, window.logical_min_size]
        )
    )
    assert_eq(
        window.min_size,
        SaUI.window_size_for(window, window.logical_min_size),
        "%s at scale %.2f must take its floor through SaUI, which is the one scale writer" % [name, scale]
    )

    _check_buttons(window, name, scale)
    window.free()


## Every button inside the dialog lies within the window's own rectangle.
##
## The proof that no button is out of reach. A test cannot await a frame, so the
## layout is driven by hand: a container sorts its children when it is sent
## `NOTIFICATION_SORT_CHILDREN`, and sending it outside in lays the whole column
## out now rather than on the next frame.
func _check_buttons(window: SaDialogWindow, name: String, scale: float) -> void:
    _sort_children(window.content)

    var frame := Rect2(Vector2.ZERO, Vector2(window.size))
    var outside: Array[String] = []
    for button: Button in _buttons_under(window.content):
        if not button.visible:
            continue
        var rect := button.get_global_rect()
        if not frame.encloses(rect):
            outside.append("%s at %s" % [button.name, rect])
    assert_true(
        outside.is_empty(),
        "%s at scale %.2f is %s and holds buttons outside it: %s" % [name, scale, window.size, ", ".join(outside)]
    )


## Sorts every container under *node*, outside in, so the rectangles below it are
## the ones the running app would draw.
func _sort_children(node: Node) -> void:
    if node == null:
        return
    for child: Node in node.get_children():
        if child is Container:
            (child as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
        _sort_children(child)


## Every `Button` under *node*, however deep, that is not inside a scrolled
## region.
##
## A `ScrollContainer` is the one widget where content past the window's edge is
## correct rather than the defect: the Preferences pages run several screens tall
## on purpose and the wheel reaches the rest. What matters is
## a button no gesture can bring back.
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


## One dialog of *path*, opened in the tree with its own `ready` run, and fitted.
##
## The fit is called by hand, for the reason the suite's header gives: the app
## asks for it on the frame after the window is built, and no frame passes inside
## a test.
func _open(path: String) -> SaDialogWindow:
    var script := load(path) as GDScript
    if script == null or not script.can_instantiate():
        return null
    var window := script.new() as SaDialogWindow
    if window == null:
        return null
    _host.add_child(window)
    window.show()
    _settle(window)
    window.fit_opening_size()
    return window


## Lays *window* out the way a drawn frame would before the fit reads it: every
## container sorted, which gives a wrapping label its width, and every control
## asked for its minimum again, which a label answers for that width only when
## told to. Twice, because the first answer is the whole text one character wide.
##
## The fit once took that answer as it stood, and grew the
## export dialog to 2600 high to hold it. Since a dialog is never made larger
## than its host, the same answer would leave the buttons of four dialogs under a
## window cut to the host, which is a layout no painter sees: the running app
## lays the label out before the fit.
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


## Every control under *node* asked for its minimum again, inside out.
func _ask_again(node: Node) -> void:
    for child: Node in node.get_children():
        _ask_again(child)
        if child is Control:
            (child as Control).update_minimum_size()


## The floor *path* declares, read off an instance that never entered the tree,
## so `fit_opening_size` has not run over it. Zero when the class cannot be built
## that way.
func _declared_floor(path: String) -> Vector2i:
    var script := load(path) as GDScript
    if script == null or not script.can_instantiate():
        return Vector2i.ZERO
    var window := script.new() as SaDialogWindow
    if window == null:
        return Vector2i.ZERO
    var floor_size := window.logical_min_size
    window.free()
    return floor_size


## Every script under `res://ui/` that says it extends the dialog window, but a
## suite in a `tests` folder, which is not the program.
##
## By source text rather than by instantiating everything under `ui/`: half of
## those classes need a document or a registry to build, and a dialog that cannot
## be built is not a dialog this suite can ask about.
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
        if sub == "tests":
            continue
        _walk(dir_path.path_join(sub), into)


func _extends_dialog_window(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    for line: String in file.get_as_text().split("\n"):
        var text := line.strip_edges()
        if text.begins_with("extends SaDialogWindow") or text.begins_with('extends "res://ui/dialogs/sa_dialog_window.gd"'):
            return true
        # The header ends at the first member, and `class_name` sits above
        # `extends` in these files rather than below it.
        if text.begins_with("func ") or text.begins_with("var ") or text.begins_with("const "):
            return false
    return false
