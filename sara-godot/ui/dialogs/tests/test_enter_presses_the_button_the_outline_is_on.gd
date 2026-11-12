## Enter presses the button the outline is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Image, Colour Space once opened
## with the outline on Cancel, one Enter pressed Assign, and the whole painting
## turned red, its Oklab numbers read as sRGB. Select, Feather did the same with
## its 5 px. `SaDialogWindow` said a focused `Button` takes `ui_accept` itself,
## and in Godot 4.7 it does not: the button counts the press as the start of a
## click, presses itself on the release and accepts neither edge, so the press
## went on to `_unhandled_key_input`, which pressed the default and closed the
## dialog before the release came. Feather never reached the base at all, its
## own `_unhandled_key_input` applied on every Enter.
##
## The key goes in through `push_input` on the dialog's own window, press and
## release, keycode and physical code both, which is the shape a keyboard sends
## and the one `SaInputDriver.key` injects. The window is embedded so no OS
## window maps, the way `test_escape_cancels_the_edit.gd` opens Preferences.
##
## **A typed number waits for a frame**, because the dialog answers a number
## field on a deferred call, after a `SpinBox`'s own deferred submit. A suite
## has no frame, so the answer is asked for by hand, the trade
## `test_a_dialog_opens_to_show_its_own_buttons.gd` makes with the fit, and the
## route on the running app is
## `scenarios/enter-presses-the-button-the-outline-is-on.json`.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
## Opens real windows, and only a run with a RenderingDevice has one.
const REQUIRES_GPU := true

## Where the dialog classes live, walked whole.
const UI_DIR := "res://ui"

## How few dialogs with a default the walk may find before it is the walk that
## broke rather than the tree that shrank. Sixteen set one on 2026-09-30.
const FLOOR := 16

## A filter the tree's own module draws, for the filter dialog's walk.
const THRESHOLD := &"sara-base-modules.threshold"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

var _host: Node = null
var _kept_embedding: bool = true
var _easel: SaEasel = null
var _canvas: SaCanvas = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    _kept_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "EnterOutlineTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    var tree := Engine.get_main_loop() as SceneTree
    tree.root.gui_embed_subwindows = _kept_embedding


## One edge of Enter, spelled with both keycode fields as a keyboard sends it.
static func _enter(pressed: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = KEY_ENTER
    key.physical_keycode = KEY_ENTER
    key.pressed = pressed
    return key


## A tap: the press, then the release the button waits for.
static func _tap_enter(window: Window) -> void:
    window.push_input(_enter(true))
    window.push_input(_enter(false))


func _shown(dialog: SaDialogWindow) -> SaDialogWindow:
    _host.add_child(dialog)
    dialog.show()
    return dialog


func test_enter_on_colour_spaces_cancel_closes_it_and_assigns_nothing() -> void:
    var dialog := _shown(ColorSpaceDialog.new()) as ColorSpaceDialog
    var asked: Array[String] = []
    dialog.assign_requested.connect(func(_space: SaColorSpace) -> void: asked.append("assign"))
    dialog.convert_requested.connect(func(_space: SaColorSpace) -> void: asked.append("convert"))
    assert_eq(dialog.default_button, dialog.assign_button, "Assign stays the default, for the dialog's own reason")

    dialog.cancel_button.grab_focus()
    assert_true(dialog.cancel_button.has_focus(true), "Cancel carries the outline")
    _tap_enter(dialog)
    assert_false(dialog.visible, "one Enter closed Colour Space")
    assert_eq(asked, [] as Array[String], "and neither assigned nor converted, which is what writes a history step")


func test_enter_on_feathers_cancel_closes_it_and_feathers_nothing() -> void:
    var dialog := _shown(SaRadiusDialog.new()) as SaRadiusDialog
    dialog.configure("Feather", 5)
    var confirmed: Array[int] = []
    dialog.radius_confirmed.connect(func(radius: int) -> void: confirmed.append(radius))
    var cancel := dialog.find_child("CancelButton", true, false) as Button

    cancel.grab_focus()
    assert_true(cancel.has_focus(true), "Cancel carries the outline")
    _tap_enter(dialog)
    assert_false(dialog.visible, "one Enter closed Feather")
    assert_eq(confirmed, [] as Array[int], "and feathered nothing, which is what writes a history step")


## The field case: a radius typed into Feather and taken with Enter is the
## radius the default applies. It never was before the fix, because the field eats
## Return and the dialog's own Enter could not hear it.
func test_a_radius_typed_into_feathers_field_and_entered_applies_that_radius() -> void:
    var dialog := _shown(SaRadiusDialog.new()) as SaRadiusDialog
    dialog.configure("Feather", 5)
    var confirmed: Array[int] = []
    dialog.radius_confirmed.connect(func(radius: int) -> void: confirmed.append(radius))
    var slider := dialog.find_child("RadiusSlider", true, false) as FactorSlider

    slider.start_editing()
    var field := slider._line_edit
    assert_true(field.has_focus(), "the radius field holds the keyboard")
    field.text = "9"
    _tap_enter(dialog)
    assert_almost_eq(slider.value, 9.0, 1e-6, "the field took the typed radius")
    assert_eq(confirmed, [] as Array[int], "and the answer waits for the frame after the field's own submit")
    assert_true(_answers_deferred(field, dialog), "on a deferred call the field's focus set up")

    dialog.answer_for_a_number_field()
    assert_eq(confirmed, [9] as Array[int], "which applies the radius typed, once")
    assert_false(dialog.visible, "and closes the dialog")


## With the outline on nothing, which is how a dialog stands once a pointer
## clicked into its empty space, the default answers as it always did.
func test_with_focus_nowhere_the_default_still_answers() -> void:
    var dialog := _shown(ColorSpaceDialog.new()) as ColorSpaceDialog
    var asked: Array[String] = []
    dialog.assign_requested.connect(func(_space: SaColorSpace) -> void: asked.append("assign"))

    dialog.gui_release_focus()
    _tap_enter(dialog)
    assert_eq(asked, ["assign"] as Array[String], "Enter with nothing focused is Assign, the default")
    assert_false(dialog.visible, "which closes the dialog")


## A button a pointer clicked holds the focus with no outline drawn, and the
## painter, who sees no outline anywhere, means the dialog's answer.
func test_a_clicked_button_without_its_outline_leaves_enter_to_the_default() -> void:
    var dialog := _shown(SaRadiusDialog.new()) as SaRadiusDialog
    dialog.configure("Feather", 5)
    var confirmed: Array[int] = []
    dialog.radius_confirmed.connect(func(radius: int) -> void: confirmed.append(radius))
    var cancel := dialog.find_child("CancelButton", true, false) as Button

    cancel.grab_focus(true)
    assert_true(cancel.has_focus() and not cancel.has_focus(true), "Cancel holds the focus with its outline hidden")
    _tap_enter(dialog)
    assert_eq(confirmed, [5] as Array[int], "so Enter applied the default's 5 px")


## A held Enter is one press, as a button reads it.
func test_a_held_enter_answers_once() -> void:
    var dialog := _shown(ColorSpaceDialog.new()) as ColorSpaceDialog
    var asked: Array[String] = []
    dialog.assign_requested.connect(func(_space: SaColorSpace) -> void: asked.append("assign"))
    dialog.assign_requested.connect(func(_space: SaColorSpace) -> void: dialog.show())

    dialog.gui_release_focus()
    dialog.push_input(_enter(true))
    var echo := _enter(true)
    echo.echo = true
    dialog.push_input(echo)
    dialog.push_input(echo)
    dialog.push_input(_enter(false))
    assert_eq(asked.size(), 1, "the press answered and its two echoes did not")


## Every dialog that sets a default, walked the same way: the outline on another
## button and Enter presses that one, the outline on nothing and Enter presses
## the default, a clicked button and Enter presses the default and lets the
## click's focus go, and a number typed into a field answers with the default
## unless the dialog said its fields do not.
##
## The walk measures the route and none of the answers, so both buttons' own
## connections are taken off first: Export would open a picker and New Module
## would write a folder.
func test_every_dialog_with_a_default_is_walked() -> void:
    var paths := _scripts_setting_a_default()
    assert_true(paths.size() >= FLOOR, "Found %d dialogs that set a default under %s" % [paths.size(), UI_DIR])
    var walked: Array[String] = []
    for path: String in paths:
        var dialog := _open(path)
        if dialog == null or dialog.default_button == null:
            assert_true(false, "%s sets a default the walk could not reach, so give it an opener here" % path.get_file())
            continue
        _walk(dialog, path.get_file())
        walked.append(path.get_file())
        dialog.free()
    print("   walked %d dialogs: %s" % [walked.size(), ", ".join(walked)])


func _walk(dialog: SaDialogWindow, name: String) -> void:
    var default := dialog.default_button
    var other := _other_button(dialog)
    if other == null:
        _walk_alone(dialog, name)
        return
    default.disabled = false
    var pressed := {"default": 0, "other": 0}
    _count_presses(default, pressed, "default")
    _count_presses(other, pressed, "other")

    other.grab_focus()
    _tap_enter(dialog)
    assert_eq(pressed["other"], 1, "%s: the outline on %s and Enter pressed it" % [name, other.name])
    assert_eq(pressed["default"], 0, "%s: and not the default, %s" % [name, default.name])

    dialog.gui_release_focus()
    _tap_enter(dialog)
    assert_eq(pressed["default"], 1, "%s: the outline on nothing and Enter pressed the default" % name)

    other.grab_focus(true)
    _tap_enter(dialog)
    assert_eq(pressed["default"], 2, "%s: a clicked %s shows no outline, and Enter pressed the default" % [name, other.name])
    assert_eq(pressed["other"], 1, "%s: and the release did not press the clicked button as well" % name)

    var slider := _first_slider(dialog)
    if slider == null:
        return
    slider.start_editing()
    _tap_enter(dialog)
    assert_true(_answers_deferred(slider._line_edit, dialog), "%s: %s's field answers on a deferred call" % [name, slider.name])
    assert_eq(pressed["default"], 2, "%s: and not before the field's own submit has landed" % name)
    dialog.answer_for_a_number_field()
    var wanted := 3 if dialog.number_field_answers else 2
    assert_eq(pressed["default"], wanted, "%s: a number typed and entered answers only where the dialog says so" % name)


## A dialog whose default is its one button, the Manual's Close, has no other
## button for the outline to sit on, so the walk is the one press it can make:
## the outline on nothing and Enter presses the default. Every focusable button
## under the content is counted first, so a dialog with a Cancel the walk
## missed still fails rather than being let off.
func _walk_alone(dialog: SaDialogWindow, name: String) -> void:
    var focusable: Array[Button] = []
    for node: Node in dialog.content.find_children("*", "Button", true, false):
        if SaDialogWindow.is_focusable(node as Button):
            focusable.append(node as Button)
    assert_eq(focusable.size(), 1, "%s has a button beside its default for the outline to sit on, or none at all" % name)
    if focusable.size() != 1 or focusable[0] != dialog.default_button:
        return
    var pressed := {"default": 0}
    _count_presses(dialog.default_button, pressed, "default")
    dialog.gui_release_focus()
    _tap_enter(dialog)
    assert_eq(pressed["default"], 1, "%s: its one button, and the outline on nothing and Enter pressed it" % name)


## Takes *button*'s own connections off and counts its presses under *slot*.
static func _count_presses(button: Button, into: Dictionary, slot: String) -> void:
    for connection: Dictionary in button.pressed.get_connections():
        button.pressed.disconnect(connection["callable"])
    button.pressed.connect(func() -> void: into[slot] += 1)


## The button the walk puts the outline on: Cancel where there is one, or else
## the first button the Tab walk reaches that is not the default.
static func _other_button(dialog: SaDialogWindow) -> Button:
    var cancel := dialog.content.find_child("CancelButton", true, false) as Button
    if cancel != null and cancel != dialog.default_button and SaDialogWindow.is_focusable(cancel):
        return cancel
    for node: Node in dialog.content.find_children("*", "Button", true, false):
        var button := node as Button
        if button != dialog.default_button and SaDialogWindow.is_focusable(button):
            return button
    return null


static func _first_slider(dialog: SaDialogWindow) -> FactorSlider:
    for node: Node in dialog.content.find_children("*", "FactorSlider", true, false):
        if (node as FactorSlider).is_visible_in_tree():
            return node as FactorSlider
    return null


## Whether *field* answers *dialog* on a deferred call.
static func _answers_deferred(field: LineEdit, dialog: SaDialogWindow) -> bool:
    for connection: Dictionary in field.text_submitted.get_connections():
        var callable: Callable = connection["callable"]
        if callable.get_object() == dialog and int(connection["flags"]) & CONNECT_DEFERRED:
            return true
    return false


## One dialog of *path*, built, in the tree and shown, and opened on what it
## needs before it has a default. Most need nothing.
func _open(path: String) -> SaDialogWindow:
    var script := load(path) as GDScript
    if script == null or not script.can_instantiate():
        return null
    # The filter browser is no dialog. It sets the default of the one it stands
    # in, which is the layer kind browser.
    if script == SaFilterBrowser:
        script = SaLayerKindBrowser
    var dialog := script.new() as SaDialogWindow
    if dialog == null:
        return null
    if dialog is SaFilterDialogWindow:
        (dialog as SaFilterDialogWindow).target_canvas = _a_canvas()
        (dialog as SaFilterDialogWindow).watch(_easel.compositor.filter_chain.registry)
    _host.add_child(dialog)
    dialog.show()
    if dialog is SaColorRangeDialog:
        (dialog as SaColorRangeDialog).build_page(Color.WHITE, 10.0, true, 0)
    elif dialog is SaFilterDialogWindow:
        (dialog as SaFilterDialogWindow).open_filter(THRESHOLD)
    elif dialog is SaFilterEditWindow:
        _a_canvas()
        var registry := _easel.compositor.filter_chain.registry
        var edit := dialog as SaFilterEditWindow
        edit.watch(registry)
        var record := SaFilterOps.new(_easel.document).attach(_easel.document.active_layer, THRESHOLD, {})
        edit.open(record, _easel.document)
    return dialog


## A painting with the threshold filter registered, for the two filter windows.
func _a_canvas() -> SaCanvas:
    if _canvas != null:
        return _canvas
    _easel = Bench.easel(Vector2i(256, 256))
    _easel.compositor.filter_chain.registry.register(Bench.threshold(), &"sara-base-modules")
    _canvas = SaCanvas.new()
    _canvas.easel = _easel
    return _canvas


## Every script under `res://ui/` whose source sets a `default_button`, the base
## and the suites aside.
func _scripts_setting_a_default() -> Array[String]:
    var paths: Array[String] = []
    _collect(UI_DIR, paths)
    paths.sort()
    return paths


func _collect(dir_path: String, into: Array[String]) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return
    for entry: String in dir.get_files():
        var path := dir_path.path_join(entry)
        if entry.ends_with(".gd") and entry != "sa_dialog_window.gd" and _sets_a_default(path):
            into.append(path)
    for sub: String in dir.get_directories():
        if sub != "tests":
            _collect(dir_path.path_join(sub), into)


static func _sets_a_default(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var text := file.get_as_text()
    var at := text.find("default_button = ")
    while at != -1:
        # `= null` is a dialog letting its default go on close, not setting one.
        if not text.substr(at, 21).ends_with("null"):
            return true
        at = text.find("default_button = ", at + 1)
    return false
