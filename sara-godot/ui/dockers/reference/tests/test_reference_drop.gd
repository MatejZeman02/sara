## A file let go over the Reference docker reaches the board, not the canvas.
##
## What is proved here is the routing question and nothing else: given a point,
## does the docker want the drop. The point itself is the document flow's to find
## and the reason it was once wrong is written at `_on_files_dropped`, so the
## suite that could prove it would need a compositor and a second application
## holding a file. `scenarios/a-dropped-file-reaches-the-reference-docker.json`
## proves the two ends on the running app, with subwindows embedded and let out.
##
## The docker goes into the real tree rather than standing detached the way the
## other Reference suites build it, because `is_embedded()` is false for a Window
## nobody has added and that is half of the question being asked.
extends "res://tests/test_framework.gd"

const REFERENCE_IMAGE := "res://ui/icon.png"

const DOCKER_AT := Vector2i(900, 120)
const DOCKER_SIZE := Vector2i(400, 300)
## Where the drop case puts the pointer, in the root viewport.
const DROPPED_AT := Vector2(937.0, 211.0)


func after_each() -> void:
    SaPointerDevice.suite_pointer = null


## A Reference docker in the tree at a known rectangle, and the host to free.
##
## Under `EventBus` rather than `tree.root`: a parent that is mid-`_ready`
## rejects `add_child` outright, and an autoload finished its own long ago.
func _docker_in_tree() -> Array:
    var host := Node.new()
    host.name = "ReferenceDropTestHost"
    EventBus.add_child(host)
    var docker := ReferenceDocker.new()
    docker.name = "ReferenceDocker"
    host.add_child(docker)
    docker.show()
    docker.position = DOCKER_AT
    docker.size = DOCKER_SIZE
    docker.board_view.size = Vector2(DOCKER_SIZE) - Vector2(8, 60)
    return [docker, host]


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


## Adding a Window to the tree only stays inside the process while the root
## viewport embeds subwindows. Whether it does is a painter's setting, so it is
## forced and put back, the way `test_windows_open.gd` does it.
func _with_embedding(embedded: bool) -> bool:
    var tree := _tree()
    var previous: bool = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = embedded
    return previous


## A point inside the docker is the docker's, one outside it is not.
func test_wants_drop_is_the_rectangle_and_nothing_else() -> void:
    var tree := _tree()
    assert_not_null(tree, "This suite needs the real scene tree to embed a docker in")
    if tree == null:
        return
    var previous := _with_embedding(true)
    var built := _docker_in_tree()
    var docker: ReferenceDocker = built[0]

    assert_true(docker.is_embedded(), "The docker must embed here, or this test maps a real OS window")
    assert_true(docker.wants_drop(Vector2(DOCKER_AT) + Vector2(20, 20)), "Just inside the top left corner is the docker's")
    assert_true(
        docker.wants_drop(Vector2(DOCKER_AT + DOCKER_SIZE) - Vector2(1, 1)), "The last texel inside is still the docker's"
    )
    assert_false(docker.wants_drop(Vector2(DOCKER_AT) - Vector2(1, 1)), "One unit above and left of the corner is the canvas's")
    assert_false(docker.wants_drop(Vector2(DOCKER_AT + DOCKER_SIZE)), "The corner past the far edge is the canvas's")

    docker.visible = false
    assert_false(
        docker.wants_drop(Vector2(DOCKER_AT) + Vector2(20, 20)), "A hidden docker wants no drop, wherever the pointer is"
    )

    built[1].free()
    tree.root.gui_embed_subwindows = previous


## The drop the docker wants lands on its board, and the one it does not is left
## for the document flow to import as a layer.
func test_take_drop_puts_the_picture_on_the_board_only_when_it_is_wanted() -> void:
    var tree := _tree()
    assert_not_null(tree, "This suite needs the real scene tree to embed a docker in")
    if tree == null:
        return
    var previous := _with_embedding(true)
    var built := _docker_in_tree()
    var docker: ReferenceDocker = built[0]
    var files := PackedStringArray([REFERENCE_IMAGE])

    var outside := ReferenceDocker.take_drop(tree, files, Vector2(DOCKER_AT) - Vector2(40, 40))
    assert_false(outside, "A drop off the docker is not the docker's to take")
    assert_eq(docker.board().pictures.size(), 0, "and it put nothing on the board")

    var inside := ReferenceDocker.take_drop(tree, files, Vector2(DOCKER_AT) + Vector2(30, 30))
    assert_true(inside, "A drop over the docker is the docker's")
    assert_eq(docker.board().pictures.size(), 1, "and the picture is on the board")
    assert_eq(docker.board().pictures[0].path, REFERENCE_IMAGE, "the file that was let go, not another")

    built[1].free()
    tree.root.gui_embed_subwindows = previous


## A docker the painter has let out into an OS window of its own hears the drop
## from the compositor, so the root window's handler must leave it alone.
func test_a_docker_in_its_own_window_is_not_the_root_windows_to_route() -> void:
    var tree := _tree()
    assert_not_null(tree, "This suite needs the real scene tree to embed a docker in")
    if tree == null:
        return
    var previous := _with_embedding(true)
    var built := _docker_in_tree()
    var docker: ReferenceDocker = built[0]

    # Not `gui_embed_subwindows = false`, which would map a real OS window and
    # block the run until the watchdog fires. A Window taken out of the tree
    # reports `is_embedded()` false for the same reason a let-out one does, and
    # that is the reading `wants_drop` asks for.
    built[1].remove_child(docker)
    assert_false(docker.is_embedded(), "A docker outside the tree stands in for one in its own OS window")
    assert_false(docker.wants_drop(Vector2(DOCKER_AT) + Vector2(30, 30)), "so the root window's handler leaves its drops alone")

    docker.free()
    built[1].free()
    tree.root.gui_embed_subwindows = previous


## The point the document flow hands over is the one reading Sara has of the
## pointer, so the ring, the over-UI test and a drop cannot disagree.
##
## Two reads of the live pointer compared with each other held only while it
## stood still and could be read. The Windows desktop of 2026-10-01 answered
## two x values thousands apart near -1.85e9, so the pointer
## is the suite's place, and the drop has to land on it.
func test_the_drop_point_is_the_cursor_policys_reading() -> void:
    var tree := _tree()
    assert_not_null(tree, "This suite needs the real scene tree to read a pointer from")
    if tree == null:
        return
    SaCursorPolicy.forget_pointer_device()
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(tree.root)
    SaPointerDevice.suite_pointer = to_desktop * DROPPED_AT
    var dropped := SaDocumentFiles.drop_point(tree)
    assert_true(
        dropped.is_equal_approx(DROPPED_AT), "The drop lands where the pointer is, read %s for %s" % [dropped, DROPPED_AT]
    )
    assert_eq(
        dropped, SaCursorPolicy.pointer_in_window(tree.root), "The drop asks the one class that answers where the pointer is"
    )
