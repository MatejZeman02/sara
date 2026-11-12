## The card's memory is read on a worker from the boot, so the
## first stroke's release, the first to ask for it, waits for no reading.
##
## The settle at the first stroke's release asked
## `SaCardMemory.total()` first, and on an NVIDIA card that ran `nvidia-smi` on
## the main thread, about 20 ms of one frame. A suite runner may have read the
## figure already, so these tests hold what stays true either way: starting the
## reading returns at once, and the figure it hands over is the one every later
## ask answers.
extends "res://tests/test_framework.gd"

## Starting the reading on the calling thread costs no more than asking the
## adapter's name, far under the tens of milliseconds `nvidia-smi` takes.
const START_BUDGET_MS := 5.0


func after_each() -> void:
    SaCardMemory.stand_in(-1)


## Starting the reading returns before the reading is done.
func test_starting_the_reading_returns_at_once() -> void:
    var before := Time.get_ticks_usec()
    SaCardMemory.read_aside()
    var spent := (Time.get_ticks_usec() - before) / 1000.0
    assert_true(spent < START_BUDGET_MS, "read_aside held the calling thread for %.1f ms" % spent)


## The figure the worker read is what every later ask answers, and a second
## start reads nothing again.
func test_the_figure_read_aside_is_the_one_every_ask_answers() -> void:
    SaCardMemory.read_aside()
    var first := SaCardMemory.total()
    assert_true(first >= 0, "the card's memory was never read")
    SaCardMemory.read_aside()
    assert_eq(SaCardMemory.total(), first, "a second start changed the figure")
    assert_eq(SaCardMemory._task, -1, "a second start left a worker pending")


## A stand-in still leads over the figure read aside.
func test_a_stand_in_leads_over_the_figure_read_aside() -> void:
    SaCardMemory.read_aside()
    SaCardMemory.stand_in(3 << 30)
    assert_eq(SaCardMemory.total(), 3 << 30, "the stand-in was not answered")
    SaCardMemory.stand_in(-1)
    assert_true(SaCardMemory.total() >= 0, "the card's own figure was lost under the stand-in")
