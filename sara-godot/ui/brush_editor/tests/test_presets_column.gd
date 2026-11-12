## The Brush Editor's presets column, left of the page rows: it takes the split's
## first slot and the editor's height, the header folds it, the grabber snaps it
## the way the scratchpad snaps, and the profile keeps its width under a key of
## its own beside the open flag.
##
## **Detached, like `test_scratchpad_snap.gd`.** The editor is a `Window` and
## a `Window` in a headless tree hangs, so the list is built with a bare
## `HSplitContainer` that is never laid out, and every claim is on the split's
## `split_offset`, which the running app turns into the column's width.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

var _was_width: int = 0
var _was_open: bool = false


func before_each() -> void:
    _was_width = SaSettings.brush_editor_presets_width
    _was_open = SaSettings.brush_editor_presets_open
    SaSettings.brush_editor_presets_width = 0
    SaSettings.brush_editor_presets_open = false


func after_each() -> void:
    SaSettings.brush_editor_presets_width = _was_width
    SaSettings.brush_editor_presets_open = _was_open


## The split with the column first and a stand-in for the rest of the editor
## second, the way the window builds it, without the window.
func _split_and_list() -> Array:
    var split := HSplitContainer.new()
    var list := SaBrushEditorPageList.new(split)
    split.add_child(list.presets_column)
    var rest := Control.new()
    rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    split.add_child(rest)
    list.restore_presets()
    return [split, list]


func test_the_column_is_first_and_its_width_is_the_offset() -> void:
    var pair := _split_and_list()
    var split: HSplitContainer = pair[0]
    var list: SaBrushEditorPageList = pair[1]
    assert_eq(split.get_child(0), list.presets_column, "The column is the split's first child, left of everything")
    assert_eq(
        list.presets_column.size_flags_horizontal,
        Control.SIZE_FILL,
        "and never expands, which is what makes its width the offset"
    )
    assert_true(list.snap.leading, "The snap knows it is the first child")
    assert_false(list.presets_open, "Shut when the profile says nothing")
    assert_eq(split.split_offset, 0, "at the left edge")
    assert_eq(list.presets_column.get_theme_constant("margin_left"), 0, "with no inset left to show")
    list.fold_presets(true)
    assert_eq(split.split_offset, SaBrushEditorPageList.PRESETS_WIDTH, "Opened by the header, the column is the default width")
    assert_eq(list.presets_column.get_theme_constant("margin_left"), SaBrushEditorPageList.MARGIN, "with its inset back")
    assert_true(list.presets_box.visible, "and the box on screen")
    split.free()
    list.free()


## The header and the grabber move one state. A drag that shuts the column is
## the same fold a press makes, announced so the window writes the open flag's key.
func test_a_drag_under_the_floor_is_a_fold_and_says_so() -> void:
    var pair := _split_and_list()
    var split: HSplitContainer = pair[0]
    var list: SaBrushEditorPageList = pair[1]
    var heard: Array[bool] = []
    list.presets_folded.connect(func(open: bool) -> void: heard.append(open))
    list.fold_presets(true)
    list.snap.drag_to(300)
    assert_eq(SaSettings.brush_editor_presets_width, 300, "A width above the floor is the profile's at once")
    assert_eq(heard, [true] as Array[bool], "and a wider column is not a fold")
    list.snap.drag_to(SaBrushEditorPageList.PRESETS_MIN_WIDTH - 1)
    assert_false(list.presets_open, "Under the floor the fold is shut")
    assert_eq(split.split_offset, 0, "the column gone")
    assert_eq(list.presets_header.icon, SaUI.get_icon(SaBrushEditorPageList.FOLDED_ARROW), "the header's arrow folded")
    assert_eq(heard, [true, false] as Array[bool], "and the window told, as for a press")
    list.snap.drag_to(SaBrushEditorPageList.PRESETS_MIN_WIDTH + 10)
    assert_true(list.presets_open, "Dragged back past the floor it is open")
    assert_eq(split.split_offset, 300, "at the width it had, not where the hand is")
    assert_eq(heard, [true, false, true] as Array[bool], "and told again")
    split.free()
    list.free()


## The profile. The width has a key of its own, the open state keeps the flag's, and
## a new list reading both opens where the last was left.
func test_the_width_and_the_fold_are_kept_across_a_reopen() -> void:
    var pair := _split_and_list()
    var list: SaBrushEditorPageList = pair[1]
    list.fold_presets(true)
    list.snap.drag_to(280)
    SaSettings.brush_editor_presets_open = list.presets_open
    (pair[0] as HSplitContainer).free()
    list.free()

    var again := _split_and_list()
    var split: HSplitContainer = again[0]
    var reopened: SaBrushEditorPageList = again[1]
    assert_true(reopened.presets_open, "Reopened open, the way it was left")
    assert_eq(split.split_offset, 280, "at the width it was dragged to")

    SaSettings.load_settings()
    assert_eq(SaSettings.brush_editor_presets_width, 280, "The profile read back gives the width")
    assert_true(SaSettings.brush_editor_presets_open, "and the open state under F6's key")
    split.free()
    reopened.free()

    var fresh := SaSettingsValues.new()
    assert_eq(fresh.brush_editor_presets_width, 0, "A profile that never saw the key takes the default")
    assert_true(SaSettingsKeys.KEYS.has("brush_editor_presets_width"), "and the key is declared, so it is written and read back")
    fresh.free()


## The step a scenario writes, and the numbers it reads back.
func test_the_capture_step_drags_and_the_report_says_where() -> void:
    var pair := _split_and_list()
    var list: SaBrushEditorPageList = pair[1]
    list.capture_presets({"fold": true, "drag": 260})
    var report := list.presets_report()
    assert_true(bool(report["open"]), "Open")
    assert_eq(report["open_width"], 260, "at the width the step dragged to")
    assert_eq(report["split_offset"], 260, "which is the offset")
    assert_false(bool(report["shut"]), "and not shut")
    (pair[0] as HSplitContainer).free()
    list.free()


## A list built alone, which is every other test of this class, has no split
## and a drag is nothing rather than a crash.
func test_a_list_without_a_split_folds_and_takes_a_drag_quietly() -> void:
    var list := SaBrushEditorPageList.new()
    list.fold_presets(true)
    assert_true(list.presets_open, "The fold works with no split")
    list.snap.drag_to(0)
    assert_true(list.presets_open, "and a drag with nothing to drag changes nothing")
    list.free()
