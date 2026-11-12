## The Brush Editor's scratchpad column: its width is the split's offset, a drag
## under the floor snaps it shut, a drag back past the floor snaps it to the
## width it had, and the profile keeps both across a close and a reopen.
## The snap itself is `SaSplitSnap`, shared with the presets
## column, and what is stated here is the pad's side of it: the share, the
## inset, the chrome and the two profile keys.
##
## **Detached, like `test_editor_scratchpad.gd`.** The editor is a `Window`
## and a `Window` in a headless tree hangs, so the pad is built with a bare
## `HSplitContainer` that is never laid out. Everything here is stated on the
## split's `split_offset`, which the running app turns into the column's width
## and the scenario's dump reads back as `width`.
extends "res://tests/test_framework.gd"

const PadScript = preload("res://ui/brush_editor/preview/editor_scratchpad.gd")

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
func _split_and_pad() -> Array:
    var split := HSplitContainer.new()
    var page := Control.new()
    page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(page)
    var pad: SaEditorScratchpad = PadScript.new(split)
    split.add_child(pad)
    pad.size_to_editor(900)
    pad.restore_width()
    return [split, pad]


func test_the_column_is_the_offset_and_opens_at_the_share() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]
    assert_eq(pad.snap.open_width, 252, "A profile with no width gets the share of 900")
    assert_eq(split.split_offset, -252, "and the column is the offset, negated")
    assert_false(pad.snap.shut, "open")
    assert_eq(pad.size_flags_horizontal, Control.SIZE_FILL, "The column never expands, which is what makes the offset its width")
    split.free()


func test_a_drag_under_the_floor_snaps_shut_and_takes_the_inset_with_it() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]
    pad.drag_to(SaEditorScratchpad.MIN_WIDTH - 1)
    assert_true(pad.snap.shut, "Under the floor is shut")
    assert_eq(split.split_offset, 0, "at the right edge")
    assert_eq(pad.get_theme_constant("margin_left"), 0, "with no inset left to show")
    assert_false(pad.column.visible, "and nothing of the pad on screen")
    assert_true(SaSettings.brush_editor_pad_shut, "The profile knows")
    assert_eq(pad.snap.open_width, 252, "and the width to snap back to is kept")
    assert_eq(SaSettings.brush_editor_pad_width, 252, "and is the profile's, so a reopen has it whatever the editor's width")
    split.free()


func test_a_shut_column_snaps_back_to_the_width_it_had() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]
    pad.drag_to(300)
    assert_eq(SaSettings.brush_editor_pad_width, 300, "A width above the floor is the profile's")
    pad.drag_to(20)
    assert_true(pad.snap.shut, "shut")
    # The hand under the floor, as a drag that has not been let go yet.
    split.split_offset = -40
    pad.snap._on_dragged(-40)
    assert_eq(split.split_offset, 0, "Under the floor a shut column stays at the edge, no sliver")
    assert_true(pad.snap.shut, "and stays shut")
    # The hand crosses the floor.
    split.split_offset = -SaEditorScratchpad.MIN_WIDTH
    pad.snap._on_dragged(-SaEditorScratchpad.MIN_WIDTH)
    assert_false(pad.snap.shut, "Past the floor it opens")
    assert_eq(split.split_offset, -300, "to the width it had, not to where the hand is")
    assert_false(SaSettings.brush_editor_pad_shut, "and the profile knows")
    # The hand keeps moving, still short of that width.
    split.split_offset = -200
    pad.snap._on_dragged(-200)
    assert_eq(split.split_offset, -300, "The snap holds while the hand is short of the width")
    assert_eq(SaSettings.brush_editor_pad_width, 300, "and the profile is not dragged down with it")
    # The hand passes it.
    split.split_offset = -340
    pad.snap._on_dragged(-340)
    assert_eq(split.split_offset, -340, "Past the snapped width the column follows the hand")
    assert_eq(pad.snap.open_width, 340, "and that is the new width")
    split.free()


## After the grabber is let go and the pad snapped open, a fresh drag from that
## width follows the hand at once, so the hold is a property of one drag.
func test_the_hold_ends_with_the_drag() -> void:
    var pair := _split_and_pad()
    var split: HSplitContainer = pair[0]
    var pad: SaEditorScratchpad = pair[1]
    pad.drag_to(10)
    pad.drag_to(160)
    assert_eq(split.split_offset, -252, "Dragged back, the column snapped to its width")
    pad.drag_to(200)
    assert_eq(split.split_offset, -200, "and a new drag short of it is followed, the hold having ended with the last")
    split.free()


## The profile. Read on every open of the editor and written on every drag, so
## the offset survives a close and a reopen, and a second Sara reading the same
## profile opens the pad where the first left it.
func test_the_offset_is_kept_across_a_close_and_a_reopen() -> void:
    var pair := _split_and_pad()
    var pad: SaEditorScratchpad = pair[1]
    pad.drag_to(320)
    pad.drag_to(0)
    (pair[0] as HSplitContainer).free()

    var again := _split_and_pad()
    var split: HSplitContainer = again[0]
    var reopened: SaEditorScratchpad = again[1]
    assert_true(reopened.snap.shut, "Reopened shut, the way it was left")
    assert_eq(split.split_offset, 0, "at the edge")
    assert_eq(reopened.snap.open_width, 320, "with the width it had ready to snap back to")

    SaSettings.load_settings()
    assert_eq(SaSettings.brush_editor_pad_width, 320, "The profile read back gives the width")
    assert_true(SaSettings.brush_editor_pad_shut, "and the shut state")
    split.free()

    var fresh := SaSettingsValues.new()
    assert_eq(fresh.brush_editor_pad_width, 0, "A profile that never saw the key takes the share")
    assert_false(fresh.brush_editor_pad_shut, "and opens the pad")
    assert_true(SaSettingsKeys.KEYS.has("brush_editor_pad_width"), "The width is declared, so it is written and read back")
    assert_true(SaSettingsKeys.KEYS.has("brush_editor_pad_shut"), "and so is the shut state")
    fresh.free()


## A pad built alone, which is every other test of this file's class, has no
## split and a drag is nothing rather than a crash.
func test_a_pad_without_a_split_takes_a_drag_quietly() -> void:
    var pad: SaEditorScratchpad = PadScript.new()
    pad.size_to_editor(900)
    pad.restore_width()
    pad.drag_to(0)
    assert_false(pad.snap.shut, "Nothing to drag, so nothing shut")
    pad.free()
