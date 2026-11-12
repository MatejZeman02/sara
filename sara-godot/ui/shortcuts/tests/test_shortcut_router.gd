## What the router does with Escape and Ctrl+Q, the two keys that quit.
##
## Escape closed Sara through Godot's own `ui_cancel` and a generated
## `ui_quit_esc`, so the key every other program uses to back out of something
## threw the session away without a word. Ctrl+Q is the one
## quit chord, and routes it through main so a modified document gets asked.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func _key(keycode: Key, ctrl: bool = false, shift: bool = false) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.ctrl_pressed = ctrl
    event.shift_pressed = shift
    event.pressed = true
    return event


func _router() -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    return router


func test_escape_no_longer_quits() -> void:
    var router := _router()
    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    assert_false(router.handle(_key(KEY_ESCAPE)), "Escape is nobody's shortcut")
    assert_eq(quits, [], "and asks for no quit")
    assert_false(InputMap.has_action("ui_quit_esc"), "The generated action that bound it is gone from the map")
    router.free()


func test_ctrl_q_asks_main_rather_than_quitting_itself() -> void:
    var router := _router()
    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    assert_true(router.handle(_key(KEY_Q, true)), "Ctrl+Q is consumed")
    assert_eq(quits, [true], "and handed to main, which owns the prompt")
    router.free()


func test_the_input_map_holds_only_actions_something_reads() -> void:
    # The four file actions have a reader in the File menu. Everything
    # else that survived the purge is read by the router, a docker or a tool.
    # tool_gradient is on the first list because the app builds the tool it names.
    for action: String in ["file_new", "file_open", "file_save", "file_save_as", "ui_quit", "tool_brush", "tool_gradient"]:
        assert_true(InputMap.has_action(action), "%s stays" % action)
    # The clipboard chords and layer_move_up are registered commands and so have a
    # reader, which keeps them off this list. A name here has to be one that advertises something the
    # app does not do.
    for action: String in ["selection_deselect", "brush_preset_0"]:
        assert_false(InputMap.has_action(action), "%s advertised a feature that does not exist" % action)


## The chords reach the File menu through the router, whichever window has
## focus, because the MenuBar's own global shortcuts see only the root viewport.
func test_the_file_chords_are_handed_to_the_file_menu() -> void:
    var router := _router()
    var actions: Array = []
    router.file_command = func(action: StringName) -> void: actions.append(action)
    assert_true(router.handle(_key(KEY_N, true)), "Ctrl+N is consumed")
    assert_true(router.handle(_key(KEY_S, true)), "and Ctrl+S")
    var save_as := _key(KEY_S, true)
    save_as.shift_pressed = true
    assert_true(router.handle(save_as), "and Ctrl+Shift+S")
    assert_eq(actions, [&"file_new", &"file_save", &"file_save_as"], "each named by its action")
    assert_false(router.handle(_key(KEY_N)), "A bare N is not one of them")
    router.free()


## X and D reach the colour store, whichever window has focus.
func test_x_swaps_and_d_resets_the_colour_pair() -> void:
    var router := _router()
    SaColors.reset()
    SaColors.foreground = Color.RED
    assert_true(router.handle(_key(KEY_X)), "X is consumed")
    assert_eq(SaColors.foreground, Color.WHITE, "and the pair swapped")
    assert_eq(SaColors.background, Color.RED, "both ways")
    assert_true(router.handle(_key(KEY_D)), "D is consumed")
    assert_eq(SaColors.foreground, Color.BLACK, "and the pair is black")
    assert_eq(SaColors.background, Color.WHITE, "over white")
    router.free()


## The canvas proof is on Krita's and Photoshop's Ctrl+Y, and
## what it proofs to is a preference rather than a fixed `soft_proof`. The minimap answers Ctrl+Shift+Y and asks nobody about a
## mode, because it keeps its own.
func test_ctrl_y_proofs_the_canvas_and_ctrl_shift_y_the_minimap() -> void:
    var router := _router()
    var modes := Fixtures.make_registries().view_transforms
    router.bind_commands(SaCommandRegistry.new(), modes)
    # The minimap is found by name, and a docker is a `Window` a suite cannot
    # add, so a plain node answers for it.
    var minimap := MinimapStandIn.new()
    minimap.name = "MinimapDocker"
    EventBus.add_child(minimap)

    var was := SaSettings.canvas_proof_mode
    assert_true(router.handle(_key(KEY_Y, true)), "Ctrl+Y is consumed")
    assert_eq(modes.mode, StringName(was), "and names whatever the Canvas proof preference says")

    SaSettings.canvas_proof_mode = "lightness_check"
    modes.set_mode(SaViewTransformRegistry.NORMAL)
    router.handle(_key(KEY_Y, true))
    assert_eq(modes.mode, &"lightness_check", "so changing the preference changes what the chord shows")
    SaSettings.canvas_proof_mode = was
    # Putting the preference back moves the proof on screen with it, which is
    # the follower the proof needs, so the canvas is read after that.
    var canvas_mode := modes.mode

    assert_true(router.handle(_key(KEY_Y, true, true)), "Ctrl+Shift+Y is consumed")
    assert_eq(minimap.proofs, 1, "and reaches the minimap")
    assert_eq(modes.mode, canvas_mode, "without touching the canvas")

    assert_false(router.handle(_key(KEY_P, true)), "Ctrl+P is nobody's any more")
    minimap.free()
    router.free()


## What the minimap proof chord asks of the docker, and nothing else.
class MinimapStandIn:
    extends Node

    var proofs: int = 0

    func toggle_proof() -> bool:
        proofs += 1
        return true


## The router subscribes to a window that appears after it, which is how a
## dialog is reached: Ctrl+Shift+N inside Preferences reached nothing, and so
## did every other registered command.
func test_the_router_hears_a_window_that_appears_after_it() -> void:
    var host := Node.new()
    host.name = "DialogRouterTestHost"
    EventBus.add_child(host)
    var router := _router()
    router.name = "ShortcutRouter"
    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    host.add_child(router)
    router.watch_windows(router.get_tree())
    var dialog := SaSettingsWindow.new()
    host.add_child(dialog)

    dialog.window_input.emit(_key(KEY_Q, true))

    assert_eq(quits, [true], "Ctrl+Q inside a dialog reaches the router")
    host.free()


## An open dropdown swallowed every chord, so a note could not be taken about
## the menu that was open. The plain keys are still the menu's own.
func test_an_open_popup_hands_over_chords_and_keeps_the_plain_keys() -> void:
    var router := _router()
    var quits: Array = []
    var toggles: Array = []
    router.request_quit = func() -> void: quits.append(true)
    router.toggle_all_dockers = func() -> void: toggles.append(true)
    var popup := PopupMenu.new()

    router.handle_popup_input(_key(KEY_Q, true), popup)
    assert_eq(quits, [true], "Ctrl+Q over an open menu reaches the router")

    router.handle_popup_input(_key(KEY_TAB), popup)
    assert_eq(toggles, [], "and bare Tab is left to the menu")

    popup.free()
    router.free()


## The one chord a menu keeps is the one it carries itself, or the item and this
## router would both fire it.
func test_an_item_that_carries_the_chord_keeps_it() -> void:
    var router := _router()
    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    var popup := PopupMenu.new()
    var shortcut := Shortcut.new()
    shortcut.events = [_key(KEY_Q, true)]
    popup.add_shortcut(shortcut)

    router.handle_popup_input(_key(KEY_Q, true), popup)

    assert_eq(quits, [], "the item's own chord is not routed a second time")
    popup.free()
    router.free()


## A docker chord is matched exactly. A loose match asks only that the event
## hold at least the action's modifiers, so Shift+B for the toolbox also
## answered Ctrl+Shift+B, and this branch runs before the registry: the
## adjustment made there would have toggled the toolbox instead.
func test_a_docker_chord_does_not_answer_a_bigger_one() -> void:
    var router := _router()
    var toggled: Array = []
    var shift_b := InputEventKey.new()
    shift_b.keycode = KEY_B
    shift_b.shift_pressed = true
    # The toolbox holds no Shift+B of its own since that chord steps the Brush's
    # family, so the chord is laid on the action here and taken off after.
    var had_action := InputMap.has_action("docker_toolbox")
    var saved := InputMap.action_get_events("docker_toolbox").duplicate() if had_action else []
    if not had_action:
        InputMap.add_action("docker_toolbox")
    InputMap.action_erase_events("docker_toolbox")
    InputMap.action_add_event("docker_toolbox", shift_b)
    router.dockers_provider = func() -> Array[Dictionary]: return [{"id": "ToolBoxDocker", "shortcut": "docker_toolbox"}]
    router.toggle_docker = func(index: int) -> void: toggled.append(index)

    var pressed := _key(KEY_B)
    pressed.shift_pressed = true
    assert_true(router.handle(pressed), "Shift+B toggles the toolbox")
    assert_eq(toggled, [0], "which is the first docker")

    var with_ctrl := _key(KEY_B, true)
    with_ctrl.shift_pressed = true
    router.handle(with_ctrl)
    assert_eq(toggled, [0], "Ctrl+Shift+B is somebody else's and the toolbox stays put")
    InputMap.action_erase_events("docker_toolbox")
    for event: InputEvent in saved:
        InputMap.action_add_event("docker_toolbox", event)
    if not had_action:
        InputMap.erase_action("docker_toolbox")
    router.free()


## A held bracket answers every echo, not once, though
## `handle_viewport_input`'s own gate drops every echoed key before a chord
## is matched. Brush size alone is let through it now, so a bracket
## kept down keeps stepping while everything else still ignores its echoes.
func test_a_brush_size_echo_still_steps_but_other_echoes_do_not() -> void:
    var router := _router()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var settings: Resource = machine.get_tool(&"brush").get("settings")
    var before: float = settings.radius
    router.tool_machine_provider = func() -> ToolMachine: return machine

    var echoed_bracket := _key(KEY_BRACKETRIGHT)
    echoed_bracket.echo = true
    router.handle_viewport_input(echoed_bracket, null)
    assert_almost_eq(
        settings.radius,
        SaShortcutKeys.brush_size_step(before, 1) + before,
        1e-6,
        "the echo steps the size the same as a tap would"
    )

    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    var echoed_quit := _key(KEY_Q, true)
    echoed_quit.echo = true
    router.handle_viewport_input(echoed_quit, null)
    assert_eq(quits, [], "but Ctrl+Q's echo still reaches nobody")

    Fixtures.teardown(surface, machine)
    router.free()


## Holding down Ctrl+Z keeps performing the undo, not just
## triggering one. The twin of the bracket's test above, and it is the same
## assertion shape on purpose: three echoed presses undo three steps.
##
## `undo_redo` is asked rather than the document's `undo()`, because the count is
## what is measured. The three actions have no do or undo method at all,
## which is what `test_undo_docker.gd` builds its steps from: what walks
## back is the stack's own index, and the router's call is the only thing that
## moves it here.
func test_a_held_undo_walks_back_through_the_history() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var document := easel.document
    var undo_redo := document.undo_redo
    for name: String in ["Paint", "New Layer", "Merge Down"]:
        undo_redo.create_action(name)
        undo_redo.add_do_method(func() -> void: pass)
        undo_redo.add_undo_method(func() -> void: pass)
        undo_redo.commit_action()
    assert_eq(undo_redo.get_current_action(), 2, "Three steps, standing on the last")

    # The document arrives through the canvas provider, which is the only door
    # handle() reaches it by. Nothing of the view is read but the document, so
    # the canvas is a detached TextureRect whose `_ready` never runs.
    var canvas := SaCanvas.new()
    canvas.easel = easel

    var router := _router()
    router.canvas_provider = func() -> SaCanvas: return canvas

    var held := _key(KEY_Z, true)
    held.echo = true
    for i in 3:
        router.handle_viewport_input(held, null)
    assert_eq(undo_redo.get_current_action(), -1, "Three echoed presses undo three steps")

    # And the echo of a chord whose second press is not a second action still
    # reaches nobody, which is the half the bracket's test asserts with Ctrl+Q.
    var quits: Array = []
    router.request_quit = func() -> void: quits.append(true)
    var echoed_quit := _key(KEY_Q, true)
    echoed_quit.echo = true
    router.handle_viewport_input(echoed_quit, null)
    assert_eq(quits, [], "Ctrl+Q's echo still reaches nobody")

    router.free()
    canvas.free()
    easel.free()


## A bracket's step is a proportion of the size, so it is a step a painter can
## see at every size.
##
## A fixed step is a different proportion at every size: at
## the fifty-pixel brush a painter works at, nought point nought nought two of
## the canvas was a change of about nought point two per cent, which rounds to
## no move at all on a row showing whole pixels, and at half a pixel it was a
## jump of more than four times the size. The step is a tenth of the size
## instead, which is the same proportion of a pixel as of a thousand.
func test_a_bracket_steps_by_a_proportion_of_the_size() -> void:
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var settings: Resource = machine.get_tool(&"brush").get("settings")
    var router := _router()
    router.tool_machine_provider = func() -> ToolMachine: return machine

    # The small end: a half-pixel brush on a 1080-tall
    # document, which the floor now reaches.
    settings.radius = 0.5 / 1080.0
    var before: float = settings.radius
    router.handle_viewport_input(_key(KEY_BRACKETRIGHT), null)
    assert_almost_eq(settings.radius, before * 1.1, 1e-9, "A bracket is a tenth larger at half a pixel")

    # And the step down is the same tenth of the size it stands at, not the
    # arithmetic reverse of the step up: a proportional scale has no inverse
    # step, which is why the fixed amount could not be one either.
    var up: float = settings.radius
    router.handle_viewport_input(_key(KEY_BRACKETLEFT), null)
    assert_almost_eq(settings.radius, up * 0.9, 1e-9, "and a tenth smaller from where it now stands")

    # The same proportion at a size a painter works at, which is what the fixed
    # step could not be.
    settings.radius = 0.1
    router.handle_viewport_input(_key(KEY_BRACKETRIGHT), null)
    assert_almost_eq(settings.radius, 0.11, 1e-9, "and the same tenth at a hundred pixels")

    Fixtures.teardown(surface, machine)
    router.free()


## Ctrl+T is Transform on the shipped map. The Transform tool
## bound plain T while Krita says Ctrl+T, which left the chord dead. The tool names its own action on its
## descriptor, so the chord reaches the tool through the same door a module's
## would, and Ctrl+T is the one thing on that door: plain T switches nothing.
func test_ctrl_t_is_transform_on_the_shipped_map() -> void:
    var router := _router()
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    router.tool_machine_provider = func() -> ToolMachine: return machine

    assert_true(machine.registered_tools.has("transform"), "the base module registers the Transform tool")
    assert_false(router.handle(_key(KEY_T)), "plain T is nobody's")
    assert_eq(machine.active_tool_name, "brush", "so the brush stays")
    assert_true(router.handle(_key(KEY_T, true)), "Ctrl+T is consumed")
    assert_eq(machine.active_tool_name, "transform", "and it is the Transform tool")

    machine.set_active_tool(&"brush")
    Fixtures.teardown(surface, machine)
    router.free()


## E is `brush_toggle_eraser`, a command the stamp-brush module
## registers, and `Fixtures.make_bound_machine()` throws its own commands
## registry away, so this builds the wiring by hand to keep the one the module
## actually registered into within reach of both the router and the command's
## own handler.
func test_e_toggles_the_brush_and_picks_the_eraser_tool_otherwise() -> void:
    var surface := Fixtures.make_surface()
    var registries := Fixtures.make_registries(surface)
    var modules: Array = []
    for script: GDScript in [
        load("res://modules/sara-base-modules/stamp-brush/module.gd"),
        load("res://modules/sara-base-modules/base/module.gd"),
    ]:
        var module: SaModule = script.new()
        module.register(registries.context.for_module(module.get_id()))
        modules.append(module)
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine._ready()
    machine.bind(surface, registries.tools)

    var router := _router()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    router.bind_commands(registries.commands)

    assert_eq(machine.active_tool_name, "brush", "The machine starts on the first painting tool")
    assert_true(router.handle(_key(KEY_E)), "E is somebody's")
    assert_true(machine.active_tool.eraser_toggled, "and toggles the brush's own eraser mode")
    assert_eq(machine.active_tool_name, "brush", "without leaving the brush")

    machine.set_active_tool(&"pan")
    assert_true(router.handle(_key(KEY_E)), "and E still answers away from the brush")
    assert_eq(machine.active_tool_name, "eraser", "by switching straight to the Eraser tool")

    for module: SaModule in modules:
        module.unregister(registries.context)
    Fixtures.teardown(surface, machine)
    router.free()
