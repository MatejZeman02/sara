## A focused text box owns the keyboard, and a chord still gets past it.
##
## Typing into a search box in Preferences must not trigger shortcuts, and
## Ctrl+comma must still toggle Preferences instead of typing a comma.
##
## Three things hold. A focused `LineEdit` keeps
## every key that is not a chord, in whatever window it sits in. A chord goes
## past it to the router, which is what makes Ctrl+comma a toggle rather than a
## comma. And Escape leaves the box without closing what the box is in.
##
## The window half is proven on the running app rather than here, for the reason
## `test_escape_closes_docker.gd` records: a `Window` added to the tree in a
## headless run hangs the suite. A `SubViewport` is a `Viewport` with a focus
## owner of its own and is what stands in for one, so every gate the router asks
## is exercised, and `scenarios/text-box-owns-the-keyboard.json` drives the
## real Preferences window and the real Brush Presets docker.
##
## A chord goes past the box, and six of them are the box's own: with the Colour
## Picker's Hex field focused Ctrl+A selected the field's text and the whole canvas, and
## Ctrl+Z in Brush Presets' search took the last stroke off the canvas. Select
## all, copy, cut, paste, undo and redo stay with the box while it has the focus,
## and every other chord still passes.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Applying a profile rebinds the live InputMap, so every test puts it back the
## way `test_shortcut_profiles.gd` does.
var _saved_events: Dictionary = {}


func before_each() -> void:
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    for action: StringName in _saved_events:
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


func _key(keycode: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    event.pressed = true
    return event


## A viewport in the tree with a text box in it, which is the least a focus owner
## needs. `EventBus` is the host every other suite parks one under.
func _bench() -> Dictionary:
    var host := Node.new()
    host.name = "C2TextBoxTestHost"
    EventBus.add_child(host)
    var viewport := SubViewport.new()
    host.add_child(viewport)
    var field := LineEdit.new()
    viewport.add_child(field)
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    return {"host": host, "viewport": viewport, "field": field, "router": router}


func _teardown(bench: Dictionary) -> void:
    (bench["router"] as ShortcutRouter).free()
    (bench["host"] as Node).free()


func test_a_text_box_keeps_every_key_that_is_not_a_chord() -> void:
    var field := LineEdit.new()

    assert_true(ShortcutRouter.text_field_keeps(field, _key(KEY_B)), "a bare letter is typing, not the brush")
    assert_true(ShortcutRouter.text_field_keeps(field, _key(KEY_SPACE)), "Space is a space, not the held pan")
    assert_true(ShortcutRouter.text_field_keeps(field, _key(KEY_BRACKETRIGHT)), "a bracket is a bracket, not a brush size")
    assert_true(ShortcutRouter.text_field_keeps(field, _key(KEY_A, false, true)), "Shift and a letter is how a capital is typed")

    field.free()


func test_a_chord_goes_past_the_box_to_the_router() -> void:
    var field := LineEdit.new()

    assert_false(ShortcutRouter.text_field_keeps(field, _key(KEY_COMMA, true)), "Ctrl+comma is the Preferences case")
    assert_false(ShortcutRouter.text_field_keeps(field, _key(KEY_Q, true)), "and Ctrl+Q still quits from inside a box")

    field.free()


func test_only_a_text_box_is_asked_about_at_all() -> void:
    var button := Button.new()
    var text := TextEdit.new()

    assert_false(ShortcutRouter.text_field_keeps(button, _key(KEY_B)), "a button is not typing, so B is the brush")
    assert_false(ShortcutRouter.text_field_keeps(null, _key(KEY_B)), "and nothing focused is nobody's key to keep")
    assert_true(ShortcutRouter.text_field_keeps(text, _key(KEY_B)), "a TextEdit is a text box the same way a LineEdit is")

    button.free()
    text.free()


## End to end through the router, which is where the gate has to sit: the same
## letter reaches a shortcut from an unfocused viewport and does not from one
## whose text box has the keyboard.
func test_the_router_leaves_a_focused_box_its_letters_and_takes_the_chord() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var toggles := [0]
    var quits := [0]
    router.toggle_all_dockers = func() -> void: toggles[0] += 1
    router.request_quit = func() -> void: quits[0] += 1

    router.handle_viewport_input(_key(KEY_TAB), viewport)
    assert_eq(toggles[0], 1, "With nothing focused, Tab reaches the router")

    field.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), field, "The box really holds the focus")

    router.handle_viewport_input(_key(KEY_TAB), viewport)
    assert_eq(toggles[0], 1, "and with the box focused the key is typing")

    router.handle_viewport_input(_key(KEY_Q, true), viewport)
    assert_eq(quits[0], 1, "while a chord goes past the box and is routed")

    _teardown(bench)


## The gate is asked of the viewport the key arrived in, which is the whole of
## why the Preferences window matters: `handle_docker_input` once
## handed `window.get_viewport()` on, and for an embedded subwindow that answers
## the embedder, so a box in the Preferences window was judged against the main
## window's focus owner.
func test_the_focus_owner_read_is_the_one_of_the_viewport_the_key_arrived_in() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var other := SubViewport.new()
    (bench["host"] as Node).add_child(other)
    var toggles := [0]
    router.toggle_all_dockers = func() -> void: toggles[0] += 1
    field.grab_focus()

    router.handle_viewport_input(_key(KEY_TAB), viewport)
    assert_eq(toggles[0], 0, "the viewport holding the box keeps the key")

    router.handle_viewport_input(_key(KEY_TAB), other)
    assert_eq(toggles[0], 1, "and a viewport with nothing focused does not, on the same press")

    _teardown(bench)


## Escape out of a box leaves the box and nothing else, which is the
## first Escape.
##
## The second press closes nothing either, so both are read here: Escape
## escapes from what is selected and never closes what is open.
func test_escape_releases_the_box_and_closes_no_docker() -> void:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var docker := Window.new()
    docker.name = "C2Docker"
    var closed: Array = []
    router.dockers_provider = (func() -> Array[Dictionary]:
        return [{"id": "C2Docker", "name": "C2", "node": docker, "shortcut": ""}])
    router.toggle_docker = func(index: int) -> void: closed.append(index)
    field.grab_focus()

    var escape := _key(KEY_ESCAPE)
    router.handle_viewport_input(escape, viewport)
    assert_eq(closed, [], "the first Escape is the box's, so nothing closes")
    assert_eq(viewport.gui_get_focus_owner(), null, "and the box has let the keyboard go")

    router.handle_viewport_input(_key(KEY_ESCAPE), viewport)
    assert_eq(closed, [], "and the second Escape closes nothing either")

    _teardown(bench)
    docker.free()


## The six chords, in every form the engine binds them and the shipped profiles
## carry them, judged for both kinds of box.
func test_a_box_keeps_the_six_chords_it_answers_itself() -> void:
    var line := LineEdit.new()
    var text := TextEdit.new()
    var chords := {
        "select all": _key(KEY_A, true),
        "copy": _key(KEY_C, true),
        "cut": _key(KEY_X, true),
        "paste": _key(KEY_V, true),
        "undo": _key(KEY_Z, true),
        "redo": _key(KEY_Z, true, true),
        "redo, the engine's second form": _key(KEY_Y, true),
    }

    for name: String in chords:
        assert_true(ShortcutRouter.text_field_keeps(line, chords[name]), "a LineEdit keeps %s" % name)
        assert_true(ShortcutRouter.text_field_keeps(text, chords[name]), "and a TextEdit keeps %s" % name)

    var released := _key(KEY_A, true)
    released.pressed = false
    assert_true(ShortcutRouter.text_field_keeps(line, released), "the key up goes with the key down")

    line.free()
    text.free()


## Nothing else changes: a chord no box acts on is the router's, and a chord that
## is one of the six with a modifier more is a different chord.
func test_every_other_chord_still_goes_past_the_box() -> void:
    var line := LineEdit.new()

    assert_false(ShortcutRouter.text_field_keeps(line, _key(KEY_COMMA, true)), "Ctrl+comma opens Preferences from inside a box")
    assert_false(ShortcutRouter.text_field_keeps(line, _key(KEY_S, true)), "Ctrl+S saves")
    assert_false(ShortcutRouter.text_field_keeps(line, _key(KEY_Q, true)), "Ctrl+Q quits")
    assert_false(
        ShortcutRouter.text_field_keeps(line, _key(KEY_A, true, true)), "Ctrl+Shift+A is Krita's Deselect, not select all"
    )
    var alt_z := _key(KEY_Z, true)
    alt_z.alt_pressed = true
    assert_false(ShortcutRouter.text_field_keeps(line, alt_z), "Ctrl+Alt+Z is not undo, which the router matches exactly as well")
    assert_false(ShortcutRouter.text_field_keeps(null, _key(KEY_A, true)), "and with no box focused Ctrl+A is Select All")

    line.free()


## Through the router: the box acts on the chord and the
## document does not, for Ctrl+A and Ctrl+Z and the other four,
## and a chord that is not the box's still answers with the box focused.
func test_the_router_leaves_the_document_alone_under_the_boxes_chords() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var bench := _bench_over(surface, registries)

    _check_the_document_stays_put(bench, surface, "under Sara Default")

    SaShortcutStore.apply_profile("Krita")
    _check_the_document_stays_put(bench, surface, "under the Krita profile")
    _check_deselect_passes(bench, surface)

    _teardown_over(bench)
    Fixtures.teardown(surface)


func _bench_over(surface: SaSurface, registries: SaRegistries) -> Dictionary:
    var bench := _bench()
    var router := bench["router"] as ShortcutRouter
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel
    router.canvas_provider = func() -> SaCanvas: return canvas
    router.bind_commands(registries.commands)
    bench["canvas"] = canvas
    return bench


func _teardown_over(bench: Dictionary) -> void:
    (bench["canvas"] as SaCanvas).free()
    _teardown(bench)


## Three steps on the history and nothing selected, then the box's chords with the
## box focused, then the chord that is not the box's.
func _check_the_document_stays_put(bench: Dictionary, surface: SaSurface, where: String) -> void:
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var document := surface.get_document()
    var undo_redo := document.undo_redo
    document.selection.deselect()
    for name: String in ["Paint", "New Layer", "Merge Down"]:
        undo_redo.create_action(name)
        undo_redo.add_do_method(func() -> void: pass)
        undo_redo.add_undo_method(func() -> void: pass)
        undo_redo.commit_action()
    var standing := undo_redo.get_current_action()

    field.grab_focus()
    assert_eq(viewport.gui_get_focus_owner(), field, "%s: the box holds the focus" % where)

    router.handle_viewport_input(_key(KEY_A, true), viewport)
    assert_false(document.selection.active, "%s: Ctrl+A in the box does not select the canvas" % where)
    for chord: InputEventKey in [_key(KEY_C, true), _key(KEY_X, true), _key(KEY_V, true), _key(KEY_Z, true), _key(KEY_Y, true)]:
        router.handle_viewport_input(chord, viewport)
    assert_eq(undo_redo.get_current_action(), standing, "%s: Ctrl+Z in the box takes no step off the history" % where)
    assert_false(document.selection.active, "%s: and nothing else selected the canvas" % where)

    # Redo is asked the other way round: one step back with nothing focused, then
    # the box's redo, which must not bring it forward.
    field.release_focus()
    router.handle_viewport_input(_key(KEY_Z, true), viewport)
    assert_eq(undo_redo.get_current_action(), standing - 1, "%s: with the box not focused Ctrl+Z is Undo" % where)
    field.grab_focus()
    router.handle_viewport_input(_key(KEY_Z, true, true), viewport)
    assert_eq(undo_redo.get_current_action(), standing - 1, "%s: Ctrl+Shift+Z in the box does not redo the canvas" % where)

    field.release_focus()
    router.handle_viewport_input(_key(KEY_Z, true, true), viewport)
    assert_eq(undo_redo.get_current_action(), standing, "%s: with the box not focused it does" % where)
    router.handle_viewport_input(_key(KEY_A, true), viewport)
    assert_true(document.selection.active, "%s: and Ctrl+A is Select All" % where)
    document.selection.deselect()

    field.grab_focus()
    var saves: Array = []
    router.file_command = func(action: StringName) -> void: saves.append(action)
    router.handle_viewport_input(_key(KEY_S, true), viewport)
    assert_eq(saves, [&"file_save"], "%s: Ctrl+S still saves from inside the box" % where)
    router.file_command = Callable()
    _check_preferences_answers(bench, where)


## Ctrl+comma is the chord the Preferences toggle uses, so it is asked again here through a
## command bound to the action `edit_preferences` names.
func _check_preferences_answers(bench: Dictionary, where: String) -> void:
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var commands := router.commands
    var opened: Array = []
    var had_action := InputMap.has_action(&"edit_preferences")
    var handler := func() -> void: opened.append(true)
    var probe := SaCommandDescriptor.create(&"d21_probe_preferences", "A stand-in for Preferences", handler)
    probe.action = &"edit_preferences"
    probe.default_events = [_key(KEY_COMMA, true)]
    commands.register(probe, &"d21-probe-module")

    router.handle_viewport_input(_key(KEY_COMMA, true), viewport)
    assert_eq(opened, [true], "%s: Ctrl+comma still answers from inside the box" % where)

    commands.unregister(&"d21_probe_preferences")
    if not had_action:
        InputMap.erase_action(&"edit_preferences")


## Krita's Deselect is Ctrl+Shift+A, the one chord here that looks like a box's
## select all and is not, which is why the match is exact.
func _check_deselect_passes(bench: Dictionary, surface: SaSurface) -> void:
    var router := bench["router"] as ShortcutRouter
    var viewport := bench["viewport"] as SubViewport
    var field := bench["field"] as LineEdit
    var document := surface.get_document()
    field.release_focus()
    router.handle_viewport_input(_key(KEY_A, true), viewport)
    assert_true(document.selection.active, "Krita: Ctrl+A with nothing focused selects the canvas")

    field.grab_focus()
    router.handle_viewport_input(_key(KEY_A, true, true), viewport)
    assert_false(document.selection.active, "Krita: Ctrl+Shift+A in the box is still Deselect, the router's")
