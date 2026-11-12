## The right press opens the Brush Presets docker beside the pointer, so the
## point it was pressed at is still canvas for the press after it.
##
## Putting the docker's own top left on the pressed point would make the second
## right press, of "another right click should
## also close it", land inside an embedded `Window`, never reach
## `ToolMachine.handle_input`, and shut nothing. The placement is the toggle's
## cost, and it must not be paid.
##
## **The placement gives way and the gesture does not.** The alternative, a press over the docker
## being read as "not the canvas, so not a toggle", leaves a painter's reflex
## doing nothing. The docker itself answering a right press is a
## gesture already spent: a right press on a cell opens that preset's tag
## menu, and one window cannot answer the same button two ways.
##
## `clear_axis`, in `brush_presets_placement.gd`, is the whole of the
## arithmetic and is static, so most of this suite needs no window at all. The
## two cases that do build the docker the way
## `test_the_right_press_opens_the_presets_where_it_asks.gd` does, under an
## autoload, because the runner calls these from its own `_ready` and a parent
## mid-`_ready` rejects `add_child`.
extends "res://tests/test_framework.gd"

const DockerScript = preload("res://ui/dockers/presets/brush_presets_docker.gd")
const Placement = preload("res://ui/dockers/presets/brush_presets_placement.gd")

const REQUIRES_GPU := true

## Small enough that a host of any size this runs on has room on both sides of
## the presses below, so what the cases read is the gap and never the clamp.
const TEST_SIZE := Vector2i(200, 200)
const PRESSED_AT := Vector2i(400, 300)


func test_the_docker_goes_after_the_point_when_there_is_room_for_it() -> void:
    assert_eq(Placement.clear_axis(400, 200, 12, 1920), 412, "the gap, then the docker")


func test_it_goes_before_the_point_when_there_is_not() -> void:
    # 400 + 12 + 200 is 612 and the room is 610, so the only side left is the
    # near one, where 400 - 12 - 200 is 188.
    assert_eq(Placement.clear_axis(400, 200, 12, 610), 188, "and the near side is taken instead")


func test_it_gives_the_point_back_when_neither_side_fits() -> void:
    # A host with 210 of room cannot hold a 200 extent and a 12 gap on either
    # side of a point in the middle of it. The press lands on the docker and the
    # toggle is the lesser loss, which the docstring on `beside_pointer` says.
    assert_eq(Placement.clear_axis(100, 200, 12, 210), 100, "the point itself, clamped by the caller")


## The near side is taken only when it really fits, so a press near the left
## edge never puts the docker off it.
func test_a_press_near_the_near_edge_does_not_go_negative() -> void:
    # 4 - 12 - 200 is -208, which is off the host, and 4 + 12 + 200 is 216,
    # which is past a host of 210. Neither side fits and the point comes back.
    assert_eq(Placement.clear_axis(4, 200, 12, 210), 4, "no room after it and none before it either")
    assert_eq(Placement.clear_axis(4, 200, 12, 1920), 16, "and room after it is taken when there is some")


## The whole of the point: whatever the placement, the press is not on the
## docker afterwards, which is what makes the next press a toggle.
func test_the_press_is_not_inside_the_docker_it_opened() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: Window = built["docker"]

    assert_true(docker.call("reveal", Vector2(PRESSED_AT)), "the press opens it")
    var rect := Rect2i(docker.position, docker.size)
    assert_false(rect.has_point(PRESSED_AT), "and the point it was pressed at is not on the docker")
    assert_true(docker.position.x > PRESSED_AT.x, "the docker stands right of the press")
    assert_true(docker.position.y > PRESSED_AT.y, "and below it")

    _tear_down(built)


## The docker is at the press when it becomes
## visible rather than being dragged there a frame later, which is the order
## `reapply_deferred` undoes when it is the other way round.
func test_it_is_already_beside_the_press_when_it_becomes_visible() -> void:
    var built := _build()
    if built.is_empty():
        return
    var docker: Window = built["docker"]

    var seen: Array[Vector2i] = []
    var watch := func() -> void:
        if docker.visible:
            seen.append(docker.position)
    docker.visibility_changed.connect(watch)

    docker.position = Vector2i(900, 700)
    assert_true(docker.call("reveal", Vector2(PRESSED_AT)), "the press opens it")
    assert_eq(seen.size(), 1, "it became visible once")
    if seen.size() == 1:
        assert_false(
            Rect2i(seen[0], docker.size).has_point(PRESSED_AT),
            "and it was already clear of the press when it did, not moved clear afterwards"
        )
    assert_eq(docker.position, seen[0] if seen.size() == 1 else docker.position, "which is where it stays")

    docker.visibility_changed.disconnect(watch)
    _tear_down(built)


func _build() -> Dictionary:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "This suite needs the real scene tree, because `_host_room` asks the parent for its window")
    if tree == null:
        return {}

    var embedded: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    var host := Node.new()
    host.name = "D29PresetsPlacementTestHost"
    EventBus.add_child(host)

    var docker := DockerScript.new()
    host.add_child(docker)
    # A `Window` is visible when it is built and the reveal this suite is about
    # starts from a shut docker, and the size is set rather than left at
    # `DEFAULT_SIZE` so the presses above are clear of the clamp on any host.
    docker.hide()
    docker.size = TEST_SIZE

    return {"tree": tree, "host": host, "docker": docker, "embedded": embedded}


func _tear_down(built: Dictionary) -> void:
    var host: Node = built["host"]
    host.free()
    (built["tree"] as SceneTree).root.gui_embed_subwindows = bool(built["embedded"])
