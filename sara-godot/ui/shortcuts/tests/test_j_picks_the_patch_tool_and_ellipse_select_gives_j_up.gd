## J picks the Patch tool in Sara's own map and in the Photoshop
## profile, and Ellipse Select keeps J only in the Krita profile, where Krita
## puts it and Krita has no patch tool.
##
## The key goes through `Input.parse_input_event` to a node that hands the
## root's unhandled input to a shortcut router, the way `Main` does, over a main
## canvas in the tree whose tools are the base module's. A key an earlier
## suite's window took instead is handed to the router once, as the usage
## tally's suite does. The page is the Keyboard Shortcuts page bound to the same
## tools, so its rows read the names the toolbox shows.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")


## Hands the root's unhandled input to the router, which is `Main`'s one line.
class Forward:
    extends Node

    var router: ShortcutRouter = null
    var heard: int = 0

    func _unhandled_input(event: InputEvent) -> void:
        heard += 1
        router.handle_viewport_input(event, get_viewport())


var _host: Node = null
var _main_canvas: Control = null
var _forward: Forward = null
var _saved_events: Dictionary = {}


func before_each() -> void:
    SaShortcutStore.capture_defaults()
    _saved_events.clear()
    for action: StringName in InputMap.get_actions():
        _saved_events[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
    if _main_canvas != null:
        _main_canvas.tool_machine.registered_tools.clear()
        _main_canvas.tool_machine.active_tool = null
        _main_canvas.tool_machine.registry = null
        _main_canvas = null
    if _host != null:
        _host.free()
        _host = null
    _forward = null
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    for action: StringName in _saved_events:
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        for event: InputEvent in _saved_events[action]:
            InputMap.action_add_event(action, event)


## The row's proof: J in the default map, then in Krita's, then in Photoshop's,
## each a real key over the canvas.
func test_j_picks_the_patch_in_sara_and_photoshop_and_ellipse_select_in_krita() -> void:
    var machine := _canvas_in_the_tree().tool_machine as ToolMachine
    var router := _router(machine)
    assert_eq(machine.get_descriptor(&"patch").activate_action, &"tool_patch", "The Patch tool names its action")

    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    machine.set_active_tool(&"brush")
    _key(router, KEY_J)
    assert_eq(machine.active_tool_name, &"patch", "J in Sara's own map picks the Patch tool")

    SaShortcutStore.apply_profile("Krita")
    machine.set_active_tool(&"brush")
    _key(router, KEY_J)
    assert_eq(machine.active_tool_name, &"ellipse_select", "J in the Krita profile picks Ellipse Select")
    assert_true(SaShortcutStore.chords_for(&"tool_patch").is_empty(), "and the Krita profile gives the patch nothing")

    SaShortcutStore.apply_profile("Photoshop")
    machine.set_active_tool(&"brush")
    _key(router, KEY_J)
    assert_eq(machine.active_tool_name, &"patch", "J in the Photoshop profile picks the Patch tool")
    assert_true(SaShortcutStore.chords_for(&"tool_ellipse_select").is_empty(), "and leaves Ellipse Select without a chord")


## The shortcut settings page lists Patch on J and Ellipse Select on nothing,
## and the conflict check finds nothing else on J.
func test_the_page_lists_patch_on_j_and_ellipse_select_on_nothing() -> void:
    SaShortcutStore.apply_profile(SaShortcutStore.DEFAULT_PROFILE)
    var tools := Fixtures.make_tool_registry()
    var page := SaShortcutsPage.new()
    page.bind_tools(tools)
    assert_eq(SaShortcutsPage.label_for("tool_patch", tools), "Patch", "The row reads the tool's name")
    assert_eq(SaShortcutsPage.label_for("tool_ellipse_select", tools), "Ellipse Select", "as Ellipse Select's does")
    assert_true(page.row_shown(&"tool_patch"), "The page lists Patch")
    assert_eq(page.chords_shown(&"tool_patch"), ["J"] as Array[String], "on J")
    assert_true(page.row_shown(&"tool_ellipse_select"), "and lists Ellipse Select, where the painter can give it a key")
    var on_j := func(text: String) -> bool: return text.contains("J")
    assert_false(page.chords_shown(&"tool_ellipse_select").any(on_j), "with no chord on J")
    assert_eq(SaShortcutStore.chords_for(&"tool_ellipse_select"), [] as Array[String], "and no chord at all")
    assert_eq(SaShortcutStore.conflicts("J", &"tool_patch"), [] as Array[String], "The conflict check finds nothing else on J")
    assert_eq(SaShortcutStore.holders("J"), ["tool_patch"] as Array[String], "and the Patch tool is the one that holds it")
    page.free()


func _canvas_in_the_tree() -> Control:
    _host = Node.new()
    _host.name = "U86Host"
    EventBus.add_child(_host)
    _main_canvas = MainCanvasScript.new()
    _host.add_child(_main_canvas)
    _main_canvas.bind_tools(Fixtures.make_tool_registry())
    return _main_canvas


func _router(machine: ToolMachine) -> ShortcutRouter:
    var router := ShortcutRouter.new()
    router.tool_machine_provider = func() -> ToolMachine: return machine
    _host.add_child(router)
    _forward = Forward.new()
    _forward.router = router
    _host.add_child(_forward)
    return router


## A press and a release of *code* through the engine. A press an earlier
## suite's window took instead is handed to the router, once.
func _key(router: ShortcutRouter, code: Key) -> void:
    for pressed: bool in [true, false]:
        var event := InputEventKey.new()
        event.keycode = code
        event.physical_keycode = code
        event.pressed = pressed
        var before := _forward.heard
        Input.parse_input_event(event)
        Input.flush_buffered_events()
        if pressed and _forward.heard == before:
            router.handle_viewport_input(event, (Engine.get_main_loop() as SceneTree).root)
