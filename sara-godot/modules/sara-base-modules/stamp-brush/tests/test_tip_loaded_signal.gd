## The stamp brush says when an image tip was loaded, once per load that
## succeeded and never for one that was refused, and lists the file it holds
## among its tip choices.
##
## The brush is built alone, the way `test_layer_locks.gd` builds it: its
## `_init` compiles the dab kernel and a load uploads the image, so this suite
## wants the device the runner has. A tool state is `RefCounted` and goes with
## the last reference, so nothing here frees one by hand.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")


func test_a_successful_load_says_so_once_and_a_refusal_says_nothing() -> void:
    var brush := StateBrushScript.new()
    var heard: Array[String] = []
    brush.tip_loaded.connect(func(path: String) -> void: heard.append(path))
    var refusals: Array[String] = []
    var ear := func(text: String) -> void: refusals.append(text)
    EventBus.paint_refused.connect(ear)

    assert_true(brush.load_tip("res://tips/tree.png"), "A shipped tip loads")
    assert_eq(heard, ["res://tips/tree.png"] as Array[String], "and is announced once, with its path")
    assert_true(refusals.is_empty(), "with nothing refused")

    assert_false(brush.load_tip("res://tips/no-such-tip.png"), "A file that is not there is refused")
    assert_eq(heard.size(), 1, "and announced to nobody")
    assert_eq(refusals.size(), 1, "the refusal going where refusals go")

    assert_true(brush.load_tip("res://tips/square.png"), "A second load")
    assert_eq(heard.size(), 2, "is a second announcement")

    EventBus.paint_refused.disconnect(ear)


## The Tip Image list the grid draws: the procedural entry, the two folders,
## and every picture loaded from neither, so a picture picked from anywhere on
## disk has a cell in the grid.
func test_the_choices_carry_the_folders_and_the_held_file() -> void:
    SaBrushTipMask.forget_loaded_elsewhere()
    var brush := StateBrushScript.new()
    var before: Dictionary = brush.tip_choices()
    assert_eq(before["ids"][0], "", "The first choice is the procedural tip")
    assert_eq(before["labels"][0], "Procedural", "by that name")
    assert_true((before["ids"] as Array).has("res://tips/tree.png"), "and the shipped folder is listed")
    assert_eq((before["ids"] as Array).size(), (before["labels"] as Array).size(), "one label per id")

    assert_true(brush.load_tip("res://ui/icon-bw.png"), "A picture from outside the tip folders loads")
    var after: Dictionary = brush.tip_choices()
    assert_eq((after["ids"] as Array).size(), (before["ids"] as Array).size() + 1, "and is one more choice")
    assert_eq((after["ids"] as Array).back(), "res://ui/icon-bw.png", "by its path")
    assert_eq((after["labels"] as Array).back(), "Icon Bw", "under its file name")

    # A tip loaded with Load Tip stays in the list as the brush moves off it
    # and joins the grid under its folder, which a cell that goes at the next
    # load would not do.
    assert_true(brush.load_tip("res://tips/tree.png"), "Back on a shipped tip")
    assert_eq(
        (brush.tip_choices()["ids"] as Array).size(),
        (before["ids"] as Array).size() + 1,
        "the outside file stays in the list for the rest of the run"
    )
    SaBrushTipMask.forget_loaded_elsewhere()
    assert_eq((brush.tip_choices()["ids"] as Array).size(), (before["ids"] as Array).size(), "and goes when the door forgets it")
