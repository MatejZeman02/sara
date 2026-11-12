## A quit collects the card's worker task, so the pool holds none of Sara's
## lambdas for the engine's teardown to free.
##
## A finished `WorkerThreadPool` task keeps its callable until someone waits
## for it. A Sara quit before the first `SaCardMemory.total()` left the
## reading's lambda with the pool, which drops it after GDScript is gone, and
## the engine aborted on a locked mutex that no longer existed (the pitfall "A
## worker task nobody waited for aborts the engine at exit"). The abort cannot
## be read in a suite, so this holds what prevents it: the task is collected by
## `finish_aside`, and the figure it read is still what `total` answers.
extends "res://tests/test_framework.gd"


func before_each() -> void:
    SaCardMemory.stand_in_machine(null, null)


func after_each() -> void:
    SaCardMemory.stand_in(-1)
    SaCardMemory.stand_in_machine(null, null)


## The boot's exit leaves no task pending.
func test_finishing_the_reading_leaves_no_worker_task_pending() -> void:
    SaCardMemory.read_aside()
    if SaCardMemory._task < 0:
        # A `--card-memory` flag answered at once and started no worker.
        skip("the figure was given on the command line, so no worker ran")
        return
    SaCardMemory.finish_aside()
    assert_eq(SaCardMemory._task, -1, "a quit left the worker task for the engine's teardown")


## The figure the worker read is kept for a `total` after the exit.
func test_the_figure_the_worker_read_survives_the_exit() -> void:
    SaCardMemory.read_aside()
    SaCardMemory.finish_aside()
    var kept := SaCardMemory.total()
    assert_true(kept >= 0, "the card's memory was lost by collecting the worker")
    assert_eq(SaCardMemory.total(), kept, "a second ask changed the figure")


## With nothing started, finishing is harmless and can be called twice.
func test_finishing_with_no_reading_started_does_nothing() -> void:
    SaCardMemory.finish_aside()
    SaCardMemory.finish_aside()
    assert_eq(SaCardMemory._task, -1, "a finish with no reading started made a task")
