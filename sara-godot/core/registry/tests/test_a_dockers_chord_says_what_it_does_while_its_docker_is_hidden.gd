## A docker's chord says what it does while its docker is hidden.
##
## A painter's answer to question 17 of the page: "popup message tells what
## shortcut does if it (reference docker in this example, but should work for
## any docker) is not visible". A command names the docker it acts in, and
## `SaCommandRegistry.try_handle_input` runs nothing for it while that docker is
## hidden and says in the corner what the chord does and how to show the
## docker. These are the registry's half with a docker of the suite's own, so
## nothing here is the Reference docker's. Its own case is in
## `ui/dockers/reference/tests/test_reference_solo.gd`, and the running app's
## is `scenarios/a-dockers-chord-says-what-it-does-while-its-docker-is-hidden.json`.
extends "res://tests/test_framework.gd"

const DOCKER := &"D5ProbeDocker"
const COMMAND := &"d5_probe_command"
const TOGGLE := &"d5_probe_toggle"


## Counts the handler's runs, so a test reads whether the chord ran anything.
class Counter:
    extends RefCounted

    var runs := 0

    func run() -> bool:
        runs += 1
        return true


## A registry pair with the probe docker registered on *window* and the probe
## command naming it, bound to Ctrl+Alt+J, and the docker's toggle to Shift+J.
## The actions are made here, before the command registers, so nothing is
## written to the shipped map and [method _forget] takes them away whole.
func _registries(window: Window, counter: Counter, sentence: String) -> SaCommandRegistry:
    _forget()
    InputMap.add_action(COMMAND)
    InputMap.action_add_event(COMMAND, _chord(KEY_J, true, true, false))
    InputMap.add_action(TOGGLE)
    InputMap.action_add_event(TOGGLE, _chord(KEY_J, false, false, true))
    var ui := SaUIRegistry.new()
    ui.register_docker(DOCKER, "Probe", func() -> Window: return null, TOGGLE)
    ui.set_docker_node(DOCKER, window)
    var commands := SaCommandRegistry.new(ui)
    var command := SaCommandDescriptor.create(COMMAND, "Probe: count a run", counter.run)
    command.docker = DOCKER
    command.sentence = sentence
    commands.register(command)
    return commands


func _forget() -> void:
    for action: StringName in [COMMAND, TOGGLE]:
        if InputMap.has_action(action):
            InputMap.erase_action(action)


func _chord(keycode: Key, ctrl: bool, alt: bool, shift: bool) -> InputEventKey:
    var key := InputEventKey.new()
    key.keycode = keycode
    key.ctrl_pressed = ctrl
    key.alt_pressed = alt
    key.shift_pressed = shift
    key.pressed = true
    return key


## What *action* said in the corner, in order.
func _said(action: Callable) -> Array[String]:
    var said: Array[String] = []
    var ear := func(text: String) -> void: said.append(text)
    EventBus.corner_notice.connect(ear)
    action.call()
    EventBus.corner_notice.disconnect(ear)
    return said


## The suite's whole ask: the chord with the docker hidden runs nothing and
## says what it does and the docker's own chord, and the same chord with the
## docker shown runs the handler and says nothing.
func test_a_hidden_dockers_chord_says_so_and_a_shown_ones_runs() -> void:
    var window := Window.new()
    window.visible = false
    var counter := Counter.new()
    var commands := _registries(window, counter, "Count one run of the probe.")
    var press := _chord(KEY_J, true, true, false)

    var answered := [false]
    var said := _said(func() -> void: answered[0] = commands.try_handle_input(press))
    assert_eq(counter.runs, 0, "With the docker hidden the chord runs nothing")
    assert_true(answered[0], "and is answered, so it travels on to no other command")
    assert_eq(commands.last_command, COMMAND, "under the command's own id")
    assert_eq(
        said,
        ['Ctrl+Alt+J would run "Probe: count a run". Show the Probe docker first (Shift+J).'] as Array[String],
        "The corner says what the chord does and the docker's chord"
    )

    window.visible = true
    said = _said(func() -> void: answered[0] = commands.try_handle_input(press))
    assert_eq(counter.runs, 1, "With the docker shown the same chord runs the handler")
    assert_true(answered[0], "which consumed it")
    assert_eq(said, [] as Array[String], "and the corner says nothing")

    window.free()
    _forget()


## The toggle's chord is the one the painter's map binds now, and a docker
## whose toggle has none is shown from the Window menu.
func test_the_line_names_the_toggle_as_bound_or_the_window_menu() -> void:
    var window := Window.new()
    window.visible = false
    var counter := Counter.new()
    var commands := _registries(window, counter, "Count one run of the probe.")
    var press := _chord(KEY_J, true, true, false)

    InputMap.action_erase_events(TOGGLE)
    InputMap.action_add_event(TOGGLE, _chord(KEY_K, true, false, false))
    var said := _said(func() -> void: commands.try_handle_input(press))
    assert_eq(said.size(), 1, "A rebound toggle still gets a line")
    assert_true(said[0].ends_with("Show the Probe docker first (Ctrl+K)."), "naming the chord bound now: %s" % said)

    InputMap.action_erase_events(TOGGLE)
    said = _said(func() -> void: commands.try_handle_input(press))
    assert_true(
        said[0].ends_with("Show the Probe docker first, from the Window menu."), "and no chord sends it to the menu: %s" % said
    )
    assert_eq(counter.runs, 0, "Neither ran the handler")

    window.free()
    _forget()


## The command is named by its title whether it has a sentence or not, in one
## whole sentence, so nothing is lowered and a translation reads as written.
func test_the_line_names_the_command_by_its_title() -> void:
    var window := Window.new()
    window.visible = false
    var press := _chord(KEY_J, true, true, false)
    # Held here, because a Callable does not keep its object alive.
    var counter := Counter.new()

    var commands := _registries(window, counter, "")
    var said := _said(func() -> void: commands.try_handle_input(press))
    assert_true(said[0].begins_with('Ctrl+Alt+J would run "Probe: count a run".'), "No sentence names the title: %s" % said)

    commands = _registries(window, counter, "HSV sliders for the probe")
    said = _said(func() -> void: commands.try_handle_input(press))
    assert_true(said[0].begins_with('Ctrl+Alt+J would run "Probe: count a run".'), "A sentence leaves the title: %s" % said)
    assert_false(said[0].contains("HSV sliders"), "and is not lowered into the line: %s" % said)

    window.free()
    _forget()


## A docker with no window built yet is hidden too, and a command whose docker
## is not registered, or a registry built with no dockers at all, runs as every
## command always did.
func test_an_unbuilt_docker_is_hidden_and_an_unknown_one_is_the_handlers() -> void:
    var counter := Counter.new()
    var commands := _registries(null, counter, "Count one run of the probe.")
    var said := _said(func() -> void: commands.try_handle_input(_chord(KEY_J, true, true, false)))
    assert_eq(said.size(), 1, "A docker whose window is not built yet is hidden")
    assert_eq(counter.runs, 0, "and its chord runs nothing")

    var alone := SaCommandRegistry.new()
    var command := SaCommandDescriptor.create(COMMAND, "Probe: count a run", counter.run)
    command.docker = DOCKER
    alone.register(command)
    said = _said(func() -> void: alone.try_handle_input(_chord(KEY_J, true, true, false)))
    assert_eq(counter.runs, 1, "A registry with no dockers runs the handler")
    assert_eq(said, [] as Array[String], "and says nothing")

    var unknown := SaCommandRegistry.new(SaUIRegistry.new())
    command = SaCommandDescriptor.create(COMMAND, "Probe: count a run", counter.run)
    command.docker = DOCKER
    unknown.register(command)
    said = _said(func() -> void: unknown.try_handle_input(_chord(KEY_J, true, true, false)))
    assert_eq(counter.runs, 2, "A docker nobody registered leaves the press to the handler")
    assert_eq(said, [] as Array[String], "which says nothing here")

    _forget()
