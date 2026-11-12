## The scratchpad column follows the editor's width: the share
## is taken again on every resize and not only on an open, and a painter who
## dragged the grabber keeps what they dragged.
##
## **The audit row this answers.** `the-scratchpad-in-the-brush-editor` was
## marked partly on the clause "pad sized by the editor's width", because the
## scenario's resize test moved the brush radius rather than the window. The
## clause was not only unproven, it was untrue past the first bind: the two
## callers of `size_to_editor` both handed it the dialog's `logical_size`,
## which is what the constructor set and never follows a resize.
##
## **Detached, like `test_scratchpad_snap.gd`.** The editor is a `Window`
## and a `Window` in a headless tree hangs, so the arithmetic is stated on a
## pad built over a bare `HSplitContainer`. What the window contributes is one
## line, `size_changed` calling `size_to_editor` with the live width, and
## `scenarios/the-scratchpad-follows-the-editors-width.json` is where that
## line is proved on the running app.
extends "res://tests/test_framework.gd"

const PadScript = preload("res://ui/brush_editor/preview/editor_scratchpad.gd")

## The editor's own default, so the numbers below are the ones a painter meets.
const EDITOR_WIDTH: int = 900

var _was_width: int = 0
var _was_shut: bool = false


func before_each() -> void:
    _was_width = SaSettings.brush_editor_pad_width
    _was_shut = SaSettings.brush_editor_pad_shut
    SaSettings.brush_editor_pad_width = 0
    SaSettings.brush_editor_pad_shut = false


func after_each() -> void:
    SaSettings.brush_editor_pad_width = _was_width
    SaSettings.brush_editor_pad_shut = _was_shut


## A split with a page on the left and the pad on the right, the way the window
## builds it, without the window.
func _split_and_pad(width: int = EDITOR_WIDTH) -> Array:
    var split := HSplitContainer.new()
    var page := Control.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(page)
    var pad: SaEditorScratchpad = PadScript.new(split)
    split.add_child(pad)
    pad.size_to_editor(width)
    pad.restore_width()
    return [split, pad]


func _share_of(width: int) -> int:
    return maxi(SaEditorScratchpad.MIN_WIDTH, int(round(float(width) * SaEditorScratchpad.WIDTH_SHARE)))


# --- The share ---------------------------------------------------------------------


func test_the_share_is_the_editors_width_times_the_constant() -> void:
    var pair := _split_and_pad()
    var pad: SaEditorScratchpad = pair[1]

    assert_eq(pad.snap.open_width, 252, "0.28 of the editor's own 900, which is the pad at very nearly its 256")
    assert_eq(pad.snap.open_width, _share_of(EDITOR_WIDTH), "and the arithmetic is the one the file states")
    (pair[0] as HSplitContainer).free()


func test_a_wider_editor_widens_the_column_a_hand_never_touched() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]

    for width: int in [1200, 1600, 900]:
        pad.size_to_editor(width)
        assert_eq(pad.snap.open_width, _share_of(width), "An editor %d wide gives the column its share" % width)
        assert_eq(split.split_offset, -_share_of(width), "which is the offset, negated")
    split.free()


func test_the_floor_is_the_share_a_narrow_editor_gets() -> void:
    var pair := _split_and_pad(400)
    var pad: SaEditorScratchpad = pair[1]

    # 0.28 of 400 is 112, under the 150 the drag floor sits at, and a column
    # narrower than the floor is one a drag would shut on the next pixel.
    assert_eq(pad.snap.open_width, SaEditorScratchpad.MIN_WIDTH, "so the share is floored rather than followed down")
    assert_eq(_share_of(400), SaEditorScratchpad.MIN_WIDTH, "which is the same rule stated twice")
    (pair[0] as HSplitContainer).free()


func test_a_width_of_nothing_leaves_the_share_where_it_was() -> void:
    var pair := _split_and_pad()
    var pad: SaEditorScratchpad = pair[1]

    # A window asked for its size before it has one answers nought, and a share
    # of nought is the floor, which would shrink a pad nobody touched.
    pad.size_to_editor(0)
    assert_eq(pad.snap.open_width, 252, "The share the editor's real width gave stands")
    (pair[0] as HSplitContainer).free()


# --- What a hand on the grabber does to it -----------------------------------------


func test_a_dragged_column_keeps_its_width_when_the_editor_grows() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]

    pad.drag_to(320)
    assert_eq(SaSettings.brush_editor_pad_width, 320, "The drag is the profile's now")

    pad.size_to_editor(1600)
    assert_eq(pad.snap.open_width, 320, "and a wider editor does not take it away")
    assert_eq(split.split_offset, -320, "so the column is where the hand left it")
    split.free()


func test_a_dragged_column_reopens_at_its_width_and_not_at_the_share() -> void:
    var pair := _split_and_pad()
    var pad: SaEditorScratchpad = pair[1]

    pad.drag_to(300)
    # What `bind_tool` does on every open of the editor, in its own order.
    pad.size_to_editor(1600)
    pad.restore_width()

    assert_eq(pad.snap.open_width, 300, "The profile wins over the share, which is what a stored width is for")
    (pair[0] as HSplitContainer).free()


func test_a_shut_column_stays_shut_however_wide_the_editor_gets() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]

    pad.drag_to(SaEditorScratchpad.MIN_WIDTH - 1)
    assert_true(pad.snap.shut, "Under the floor is shut")

    pad.size_to_editor(1600)
    assert_true(pad.snap.shut, "and a resize is not a reason to put the pad back")
    assert_eq(split.split_offset, 0, "so the page still has the whole width")
    split.free()


# --- The dump ----------------------------------------------------------------------


func test_the_dump_says_which_editor_width_the_share_came_from() -> void:
    var pair := _split_and_pad()
    var pad: SaEditorScratchpad = pair[1]

    pad.size_to_editor(1300)
    var report := pad.pad_report()

    assert_eq(report["editor_width"], 1300, "The report gives the width the share was taken from")
    assert_eq(report["share"], _share_of(1300), "beside the share itself")
    assert_eq(report["open_width"], _share_of(1300), "and the column that followed it")
    (pair[0] as HSplitContainer).free()
