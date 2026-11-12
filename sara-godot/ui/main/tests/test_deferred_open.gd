## Every offscreen gate run printed two deferred calls onto a freed Main.
##
## `Main._ready` ended with `MainArguments.open_requested.call_deferred(main)`,
## which opens a path given on the command line once the window is up. Two suites
## build a `Main`, call `_ready()` on it by hand and free it in the same frame,
## `ui/dockers/tests/test_ui_components.gd` twice and `ui/notes/tests/test_note_mode.gd` once, and
## the deferred call then fired on a node that had gone:
##
##     ERROR: Error calling deferred method: 'GDScript::open_requested':
##     Cannot convert argument 1 from Object to Object.
##
## It is `ERROR` rather than `SCRIPT ERROR`, so nothing failed on it, which was
## the whole problem: two engine errors that are always there are two a reader
## learns to scroll past, and the run that matters is the one where a third
## appears.
##
## **"The run is quiet" is not assertable from inside GDScript.** Nothing here
## can read the runner's own log, and the message queue offers no way to ask what
## is pending. So what this suite asserts is the decision behind the quiet, which
## `Main.should_open_the_command_line` exists to name, and the count of
## the line in a full run is the other half.
extends "res://tests/test_framework.gd"

const MainScript = preload("res://ui/main/main.gd")

## Builds a real `Main` and calls `_ready()`, which is what the defect needs.
const REQUIRES_GPU := true


## A `Main` built the way the two suites build one: never parented, `_ready()`
## called by hand, freed straight after.
func _detached_main() -> Node:
    var main := MainScript.new()
    main.name = "Main"
    main.is_test_environment = true
    main.dockers.layout_store.path = SaDataRoot.path("test_f87_docker_layout.cfg")
    if FileAccess.file_exists(main.dockers.layout_store.path):
        DirAccess.remove_absolute(main.dockers.layout_store.path)
    return main


## The decision, which is the fix. A `Main` that is not in a tree has no window
## to open a document into and no user argument to read, so the deferred call had
## nothing to do and only something to go wrong.
func test_a_main_no_tree_holds_never_queues_the_command_line_open() -> void:
    var main := _detached_main()
    assert_false(main.is_inside_tree(), "The two suites build a Main they never parent")
    assert_false(
        Main.should_open_the_command_line(main), "so nothing is deferred onto it, which is what stopped the two errors a run"
    )
    main._ready()
    main.free()
    # The Main ran its boot by hand and loaded every module, and a Main never
    # parented never puts them down, so the linux-pen module's reader thread
    # outlived the run and threw at exit.
    ModuleLoader.unload_all()


## The guard is not "never open". A `Main` inside a tree is the app's own case
## and the one the deferred call exists for, so a suite that only proved the
## refusal would pass on a bootstrap that had deleted the feature.
##
## Asked about the runner's own root rather than about a `Main` this parents.
## `add_child` from inside a test answers `Parent node is busy setting up
## children`, because the runner is still in its own `_ready`, and the rule under
## test is about the tree rather than about the class.
func test_a_node_in_a_tree_is_still_one_to_open_into() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    assert_not_null(tree, "The runner is a SceneTree")
    assert_true(tree.root.is_inside_tree(), "and its root is in it")
    assert_true(
        Main.should_open_the_command_line(tree.root),
        "so the command line's document is still opened into a Main the app parented"
    )


## Two shapes that look like a safety net and are not, pinned so the next reader
## does not try either again.
##
## **A check inside the predicate is too late for a freed Main.** A freed
## instance cannot reach a `Node` parameter: the call fails on the same argument
## conversion the defect is about, one frame earlier, with
## `The Object-derived class of argument 1 (previously freed) is not a subclass
## of the expected argument class`. So `should_open_the_command_line` asks about
## the tree and nothing else, and the guard has to run while the Main is alive.
##
## **A closure over the Main is worse than the argument.** GDScript prints
## `Lambda capture at index 0 was freed. Passed "null" instead.` and calls the
## body with null, so it trades one always-there error for another. The only
## deferred form the message queue drops in silence is a Callable whose own
## object has gone, and the opener was a static `MainArguments.open_requested`
## then, so there was no such form. It is a method of `Main` now
## and the deferred call is that quiet form, and the guard stays because a
## suite's `Main` has nothing to open.
func test_neither_a_late_check_nor_a_closure_saves_a_freed_main() -> void:
    var main := _detached_main()
    var seen := [0]
    var open_it := func() -> void: seen[0] += 1
    open_it.call()
    assert_eq(seen[0], 1, "A closure over a live Main runs its body")
    main.free()
    assert_false(is_instance_valid(main), "and once the Main is freed")
    assert_true(open_it.is_valid(), "the Callable is still valid, which is the trap")
