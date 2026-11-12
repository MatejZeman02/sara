## A full undo history says so on the docker's frame rather than in a pop-up.
##
## The full undo stack does not throw an info pop-up. The line is there on purpose, one refusal per dropped step,
## because eight ramps had left a painter with six rows called Gradient and no
## word about the ones that were gone. This file grades both halves of the
## answer: a drop raises no refusal, and the count is readable where the row puts
## it, which is the Undo History docker's own footer.
##
## The footer's wiring to the document is the scenario's to prove rather than
## this file's: a docker built detached has no canvas to find a document
## through, so every case here hands the line its number, the shape
## `test_undo_docker.gd` uses for the rows.
extends "res://tests/test_framework.gd"

## The docker's `_init` builds real controls and a document needs a device.
const REQUIRES_GPU := true

## A 4 by 3 grid, so a whole-canvas step is twelve chunk snapshots, the document
## `test_history_depth.gd` uses for the same arithmetic.
const CANVAS := Vector2i(1024, 768)

var _host: Node = null
var _docker: UndoDocker = null
var _easel: SaEasel = null
var _depth_before: int = 0


func before_each() -> void:
    _depth_before = SaSettings.history_depth
    _easel = SaEasel.create_default(CANVAS)
    # The line a drop leaves is the console's, and this suite drops steps on
    # purpose: a transcript's worth of lines would bury the assertions.
    _easel.document.history.announce_drops = false
    _host = Node.new()
    _docker = UndoDocker.new()
    _host.add_child(_docker)
    SaProblems.pending_refusals = PackedStringArray()


func after_each() -> void:
    SaSettings.history_depth = _depth_before
    SaProblems.pending_refusals = PackedStringArray()
    _host.free()
    _host = null
    _docker = null
    _easel.free()
    _easel = null


## The pop-up's shape, which is gone: the budget takes steps off the front
## and no refusal arrives over the canvas about them.
func test_a_dropped_step_raises_no_refusal() -> void:
    var doc: SaDocument = _easel.document
    _overfill(doc)
    assert_true(doc.history.dropped_steps > 0, "The budget took steps off the front")
    assert_true(SaProblems.pending_refusals.is_empty(), "and nothing was refused to the painter about it")


## The half that stays: a painter can find out why their history is short.
## The number is the docker's own footer, so it is read here the way a scenario
## reads it, off the words rather than off the model.
func test_the_footer_says_the_count_the_history_kept() -> void:
    var doc: SaDocument = _easel.document
    _overfill(doc)
    _docker._show_dropped(doc.history.dropped_steps)
    var line := _docker.dropped_line()
    assert_true(line.contains(str(doc.history.dropped_steps)), "The footer carries the count: %s" % line)
    assert_true(line.contains("Preferences > Interface"), "and names the setting that changes it: %s" % line)


## A docker nobody has cost a step is the docker it always was, with nothing said
## about a history that is not short.
func test_the_footer_is_hidden_until_a_step_is_dropped() -> void:
    _docker._show_dropped(0)
    assert_false(_docker.dropped_label.visible, "Nothing was dropped, so nothing is said")
    assert_eq(_docker.dropped_line(), "", "and the line reads empty rather than zero")
    _docker._show_dropped(1)
    assert_true(_docker.dropped_label.visible, "One dropped step is worth saying")
    assert_true(_docker.dropped_line().contains("One"), "and reads as one step rather than as 1 of them")


## The line counts rather than arriving per drop, which is the difference between
## a footer and the pop-up there was: the tenth dropped step replaces the ninth.
func test_the_footer_is_one_line_that_counts_rather_than_a_row_per_drop() -> void:
    _docker._show_dropped(1)
    var first := _docker.dropped_line()
    _docker._show_dropped(10)
    var tenth := _docker.dropped_line()
    assert_true(first != tenth, "The line follows the count")
    assert_true(tenth.contains("10"), "so the tenth drop is what it says: %s" % tenth)
    assert_eq(_dropped_labels(), 1, "and the docker carries one such line rather than one per dropped step")


## How many labels the docker holds under the footer's own name. A second one
## would be a line per drop by another route.
func _dropped_labels() -> int:
    var found := 0
    for child in _docker.dropped_label.get_parent().get_children():
        var label := child as Label
        if label != null and label.name == "Dropped":
            found += 1
    return found


## Steps enough to push the budget over, at the shallowest depth a painter can
## set, so four whole-canvas steps are all that fit.
##
## Unpinned on purpose. `pin_budget` is the arithmetic's escape hatch and it
## returns before a drop says anything at all, and whether a drop says anything
## is exactly what this suite is about.
func _overfill(doc: SaDocument) -> void:
    SaSettings.history_depth = SaSettingsValues.MIN_HISTORY_DEPTH
    doc.history.budget_bytes = 1
    for i in 6:
        doc.fill_layer(Color(float(i + 1) / 7.0, 0.2, 0.2, 1.0), SaLayerOps.new(doc).layers()[0])
