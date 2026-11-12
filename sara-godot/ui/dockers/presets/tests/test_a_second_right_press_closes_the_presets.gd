## A second right press on the canvas closes the Brush Presets docker.
##
## If a right click on the brush tool opens it, another right click
## closes it. The handler was `_right_click_opens_the_presets` and
## called `reveal` alone, which is open-only: a visible docker skipped the show
## and the repositioning and only took the focus back, so the second press
## looked like nothing at all.
##
## Driven through `handle_input` with a real docker in the tree, because the
## handler finds the docker under `get_tree().root` by name and answers false
## outside a tree at all. The machine is a child of the host for the same
## reason, which is one more than `Fixtures.make_bound_machine` does on its own.
## What a painter sees is
## `scenarios/a-second-right-press-closes-the-presets.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")

const REQUIRES_GPU := true


## Open, shut, open. The third press is here because a toggle that works once is
## what once failed, and because `reveal` positions the docker on
## the way in: the second opening has to survive whatever the closing left.
func test_the_right_press_opens_then_shuts_then_opens_again() -> void:
    var built := _build()
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    var docker: Window = built["docker"]

    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    assert_false(docker.visible, "The docker starts shut")
    machine.handle_input(_right_press())
    assert_true(docker.visible, "The first right press opens it")
    machine.handle_input(_right_press())
    assert_false(docker.visible, "and the second shuts it, which is the whole claim")
    machine.handle_input(_right_press())
    assert_true(docker.visible, "and the third opens it again")
    assert_eq(asked.size(), 0, "None of the three fell through to the context menu")

    _tear_down(built)


## The toggle belongs to the brush. Another tool's right press is the context
## menu it always was, and an open docker is left exactly as the painter left it
## rather than shut by a gesture that was never about it.
func test_another_tools_right_press_leaves_an_open_docker_open() -> void:
    var built := _build()
    if built.is_empty():
        return
    var machine: ToolMachine = built["machine"]
    var docker: Window = built["docker"]

    var asked: Array = []
    machine.context_menu_requested.connect(func(at: Vector2) -> void: asked.append(at))

    machine.handle_input(_right_press())
    assert_true(docker.visible, "The brush opened it")
    machine.set_active_tool(&"eyedropper")
    machine.handle_input(_right_press())
    assert_true(docker.visible, "and the eyedropper's press left it open")
    assert_eq(asked.size(), 1, "asking for its own context menu instead")

    _tear_down(built)


## A docker of its own and a machine bound to a surface, both in the tree under
## an autoload: the runner calls this from its own `_ready` and a parent
## mid-`_ready` rejects `add_child`.
func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because the handler looks under its root")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "B4RightPressTestHost"
    EventBus.add_child(host)

    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    host.add_child(machine)
    machine.set_active_tool(&"brush")

    var docker := DockerScript.new()
    host.add_child(docker)
    # A `Window` is visible when it is built, and the press this suite is about
    # starts from a shut docker.
    docker.hide()

    return {"tree": tree, "host": host, "machine": machine, "docker": docker, "surface": surface, "embedded": embedded}


func _tear_down(built: Dictionary) -> void:
    var host: Node = built["host"]
    var machine: ToolMachine = built["machine"]
    # Taken out of the host first, because `Fixtures.teardown` frees it and it
    # holds the registry, which holds every descriptor and their settings.
    host.remove_child(machine)
    host.free()
    Fixtures.teardown(built["surface"], machine)
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])


## A plain right press at the middle of the canvas, the same event
## `test_presets_button_opens_the_docker.gd` sends.
func _right_press() -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_RIGHT
    event.pressed = true
    event.position = Vector2(100, 100)
    event.global_position = Vector2(100, 100)
    return event
