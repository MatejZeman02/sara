## A suite passes in a batch as it passes alone.
##
## Two things made a suite answer for the one before it. A case with an
## `await` in it handed the runner a function state at the wait and ran the
## rest, its assertions and its teardown, after the whole run, so a suite's
## hosts stayed under `EventBus` for every suite after them. And nothing
## looked for what a suite left, a node under `EventBus` or the root, or a
## picture format registry installed with no PNG in it, so the suite that met
## it was named and not the one that left it. The framework now waits for a
## case that waits, and the runner frees what a suite left and fails that
## suite, through `Leftovers` in `tests/run_all.gd`.
extends "res://tests/test_framework.gd"

const Runner = preload("res://tests/run_all.gd")

## What the cases of the wait did, in the order they did it, which a later case
## reads. Static, since the order is what is asked and a case reads it after
## the one that wrote it.
static var steps: Array[String] = []


func before_each() -> void:
    steps.append("before %s" % current_test_name)


func after_each() -> void:
    steps.append("after %s" % current_test_name)


## The case that waits a frame. Its last line runs before its teardown.
func test_a_case_that_waits_a_frame() -> void:
    steps.clear()
    steps.append("waiting")
    await (Engine.get_main_loop() as SceneTree).process_frame
    steps.append("waited")


## The case after it reads that the wait ended, and the teardown ran, before
## this case began. Without the framework's `await` it read "waiting" and the
## next case's start, and the rest of the case before came after the run.
func test_the_case_after_a_wait_begins_once_the_wait_and_its_teardown_ended() -> void:
    assert_eq(
        steps,
        [
            "waiting",
            "waited",
            "after test_a_case_that_waits_a_frame",
            "before test_the_case_after_a_wait_begins_once_the_wait_and_its_teardown_ended",
        ],
        "the case that waited ran to its end and its teardown before this case"
    )


## A node a suite left under `EventBus`, one queued to be freed as well, is
## freed and named, so the suite that left it fails and not the next.
func test_a_node_left_under_the_event_bus_is_freed_and_named() -> void:
    var leftovers := Runner.Leftovers.new()
    var left := Node.new()
    left.name = "LeftHost"
    EventBus.add_child(left)
    var queued := Control.new()
    queued.name = "QueuedControl"
    EventBus.add_child(queued)
    queued.queue_free()
    var lines := leftovers.put_back()
    assert_eq(lines.size(), 2, "both are named: %s" % [lines])
    assert_true(lines.size() == 2 and lines[0].contains("LeftHost"), "the host by its name")
    assert_true(lines.size() == 2 and lines[1].contains("queued"), "and the queued control as queued")
    assert_false(is_instance_valid(left), "the host is freed")
    assert_false(is_instance_valid(queued), "and so is the queued control, with no frame passed")


## A node that was there before the suite is not the suite's, and stays.
func test_a_node_there_before_the_suite_stays() -> void:
    var kept := Node.new()
    kept.name = "KeptHost"
    EventBus.add_child(kept)
    var leftovers := Runner.Leftovers.new()
    assert_eq(leftovers.put_back(), [] as Array[String], "nothing is named")
    assert_true(is_instance_valid(kept) and kept.get_parent() == EventBus, "and the node stays")
    kept.free()


## A registry installed with no PNG, which `SaImageFormatRegistry.shared()`
## answered, is let go of, so the skeleton's own reads a picture again. A
## kept registry like that left the skeleton reading no picture.
func test_a_registry_left_installed_without_png_is_let_go() -> void:
    var leftovers := Runner.Leftovers.new()
    var bare := SaImageFormatRegistry.new()
    SaImageFormatRegistry.install(bare)
    assert_false(SaImageImport.is_image_path("probe.png"), "the bare registry reads no PNG")
    var lines := leftovers.put_back()
    assert_eq(lines.size(), 1, "it is named: %s" % [lines])
    assert_true(SaImageImport.is_image_path("probe.png"), "and a PNG is a picture again")


## The runner asks after every suite, so the check is not a class nobody calls.
func test_the_runner_puts_back_after_every_suite() -> void:
    var runner := FileAccess.get_file_as_string("res://tests/run_all.gd")
    assert_true(runner.contains("Leftovers.new()"), "the runner takes the state before a suite")
    assert_true(runner.contains("leftovers.put_back()"), "and puts it back after")
    assert_true(runner.contains("await suite.run_all_tests("), "and waits for a suite whose cases wait")
