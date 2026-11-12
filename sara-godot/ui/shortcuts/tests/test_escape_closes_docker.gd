## Escape closes no docker.
##
## Escape does not close dialogs or dockers, and it does release what is
## selected. Every case below asks the same router the same way and reads an empty close
## list, and what Escape does instead is in
## `ui/shortcuts/tests/test_escape_releases_the_focus.gd`.
##
## **The file keeps its old name**, which says the opposite of what it proves.
## The scenario that shows the behaviour on the running app is
## `scenarios/escape-cancels-never-closes.json`.
extends "res://tests/test_framework.gd"


## A tool with a gesture in the air, or without one, and a record of the keys it
## was handed. `preview_shape` is the method the router asks through, because
## every tool that can have something pending already answers it.
class PendingTool:
    extends ToolState

    var shape: Dictionary = {}
    var keys: Array = []

    func preview_shape() -> Dictionary:
        return shape

    func handle_input(event: InputEvent) -> void:
        keys.append((event as InputEventKey).keycode)


func _escape(pressed: bool = true) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = KEY_ESCAPE
    event.physical_keycode = KEY_ESCAPE
    event.pressed = pressed
    return event


## Two dockers and a router wired the way `main.gd` wires one, with the closes
## it asks for collected rather than performed.
##
## The windows are never added to the tree: a `Window` added to one in a
## headless run hangs the suite, and every reading here is an identity or a
## flag on the object itself.
func _bench() -> Dictionary:
    var first := Window.new()
    first.name = "FirstDocker"
    var second := Window.new()
    second.name = "SecondDocker"
    var router := ShortcutRouter.new()
    var closed: Array = []
    router.canvas_provider = func() -> SaCanvas: return null
    router.tool_machine_provider = func() -> ToolMachine: return null
    router.dockers_provider = (func() -> Array[Dictionary]:
        return [
            {"id": "FirstDocker", "name": "First", "node": first, "shortcut": ""},
            {"id": "SecondDocker", "name": "Second", "node": second, "shortcut": ""},
        ])
    router.toggle_docker = func(index: int) -> void: closed.append(index)
    return {"router": router, "first": first, "second": second, "closed": closed}


func _teardown(bench: Dictionary) -> void:
    (bench["router"] as ShortcutRouter).free()
    (bench["first"] as Window).free()
    (bench["second"] as Window).free()


## The main window's own keys. Nothing there holds the keyboard, so there is
## nothing for Escape to do at all, and the docker in front stays open.
func test_escape_at_the_main_window_closes_no_docker() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]

    router.handle_viewport_input(_escape(), null)

    assert_eq(bench["closed"], [], "the docker in front is left alone")
    _teardown(bench)


## The release is not a close either, which is worth keeping now that the press
## is not one: a regression that put the behaviour back would show on both.
func test_neither_edge_of_the_press_closes() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]

    router.handle_viewport_input(_escape(), null)
    router.handle_viewport_input(_escape(false), null)

    assert_eq(bench["closed"], [], "no press, no release, no close")
    _teardown(bench)


## A docker that has the keyboard is not closed by Escape. It is the
## clearest case: the painter is standing in it and it stays.
func test_escape_in_a_docker_leaves_that_docker_open() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]

    router.handle_docker_input(_escape(), bench["first"])

    assert_eq(bench["closed"], [], "the docker the key arrived in stays open")
    _teardown(bench)


## A dialog never closes a docker. It closes itself, which `ui/dialogs/tests/test_escape_closes_a_dialog.gd` reads on a
## real one, and a window that is no `SaDialogWindow` is a docker to the key.
func test_escape_in_a_dialog_closes_no_docker() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]
    var dialog := Window.new()
    dialog.name = "ADialog"

    router.handle_docker_input(_escape(), dialog)

    assert_eq(bench["closed"], [], "nothing behind the dialog closes")
    dialog.free()
    _teardown(bench)


## A tool with something in the air still sees the key and still keeps it. The
## transform's move, the crop's rectangle and the polygon lasso's outline are
## all abandoned with Escape, and that stays.
func test_a_live_gesture_still_gets_the_key() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]
    var machine := ToolMachine.new()
    var tool := PendingTool.new()
    tool.shape = {"rect": Rect2(0, 0, 10, 10), "handles": true}
    machine.active_tool = tool
    router.tool_machine_provider = func() -> ToolMachine: return machine

    router.handle_viewport_input(_escape(), null)

    assert_eq(tool.keys, [KEY_ESCAPE], "the tool is handed the key")
    assert_eq(bench["closed"], [], "and nothing closes under the gesture")
    machine.active_tool = null
    machine.free()
    _teardown(bench)


## The same tool with nothing pending. The key falls through the whole order and
## reaches nothing, which is what "never closes what is open" means.
func test_a_tool_with_nothing_in_the_air_closes_nothing_either() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]
    var machine := ToolMachine.new()
    var tool := PendingTool.new()
    machine.active_tool = tool
    router.tool_machine_provider = func() -> ToolMachine: return machine

    router.handle_viewport_input(_escape(), null)

    assert_eq(tool.keys, [KEY_ESCAPE], "the tool is still offered the key first")
    assert_eq(bench["closed"], [], "and the front docker is not the fallback any more")
    machine.active_tool = null
    machine.free()
    _teardown(bench)


## Note mode owns every key while it is on, and its Escape leaves the mode. It
## reads the key in an overlay's `_input`, which a window reaches only after it
## has emitted `window_input`, so the router has to stand down rather than be
## outvoted.
func test_note_mode_stands_the_router_down() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]
    SaNoteMode.taking_note = true

    router.handle_viewport_input(_escape(), null)
    router.handle_docker_input(_escape(), bench["first"])

    SaNoteMode.taking_note = false
    assert_eq(bench["closed"], [], "neither door answers while a note is being taken")
    _teardown(bench)


## Escape stays off the `handle()` chain, which is what `test_escape_no_longer_quits`
## asserts and what keeps the key from becoming a shortcut like any other.
func test_escape_is_still_no_chord() -> void:
    var bench := _bench()
    var router: ShortcutRouter = bench["router"]

    assert_false(router.handle(_escape()), "Escape is nobody's shortcut")
    assert_eq(bench["closed"], [], "and nothing closes through that door")
    _teardown(bench)
