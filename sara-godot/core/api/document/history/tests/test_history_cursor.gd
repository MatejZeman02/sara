## The dump carries where the undo cursor is, not only how much it is holding.
##
## Filed by `s3-review-door` as `undo-invisible-in-the-dump`. `SaHistory`
## counts the snapshots it holds and its count does not move when the cursor
## does, which is right for a budget and useless for an undo: a successful
## `{"undo": 1}` printed `SaCapture: undo 1 of 1 step(s)` and left the whole
## state dump byte for byte identical, so no scenario could assert that a stroke
## came back rather than that an undo entry exists, which is what the `undo`
## handler's own doc comment promises.
##
## `UndoRedo.get_version()` is the cursor. It moves on a commit, on an undo and
## on a redo, and `has_undo` and `has_redo` are the two ends of the walk, so
## "the cursor moved" and "there is nothing left to undo" are separate
## assertions rather than one number a reader has to interpret.
##
## The running-app half is `scenarios/undo-invisible-in-the-dump.json`, whose
## four dumps read `version` 3, 2, 3 and 1 across two strokes, an undo, a redo
## and an undo of both, while `steps` stays 2 and `bytes` stays 782336 through
## all four. The second stroke overlaps the first on purpose: undoing a stroke
## that painted into chunks the layer already had swaps a delta, so the store
## and the VRAM total are the same either side of it and only the cursor moves.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func test_the_version_moves_across_an_undo_and_a_redo() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64))
    var document := easel.document
    assert_true(document.undo_redo != null, "a default document has a history to walk")

    var before: int = document.undo_redo.get_version()
    SaLayerOps.new(document).add()
    var after_add: int = document.undo_redo.get_version()
    assert_true(after_add != before, "an undoable action moves the version")
    assert_true(document.undo_redo.has_undo(), "and leaves something to undo")
    assert_false(document.undo_redo.has_redo(), "with nothing ahead of it")

    document.undo_redo.undo()
    assert_eq(document.undo_redo.get_version(), before, "an undo takes the version back")
    assert_true(document.undo_redo.has_redo(), "and leaves something ahead of it")

    document.undo_redo.redo()
    assert_eq(document.undo_redo.get_version(), after_add, "and a redo puts it forward again")

    easel.free()
