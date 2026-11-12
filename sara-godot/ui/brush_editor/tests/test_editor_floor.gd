## The Brush Editor cannot be made narrower than what is on it.
##
## The claim is the editor at 660 by 460, above the 640 its
## constructor names as a floor, with the header cut after two letters of
## "Save", 45 pixels of the pad and a lone "R" of the footer, because the column
## needs more than the window offers and runs past its right edge.
##
## Measured off the minimum the layout demands, for the reason
## `test_color_space_dialog_floor.gd` gives beside its own floor: a container
## lays its children out on a later frame and a suite runs inside `_ready`. The
## pictures are `scenarios/the-brush-editor-at-660-cuts-off-its-header-and-its-pad.json`.
extends "res://tests/test_framework.gd"

## The strip and the pad render through the rendering device.
const REQUIRES_GPU := true

var _host: Node = null
var _previous_embedding: bool = false
var _was_pad_width: int = 0
var _was_pad_shut: bool = false
var _was_presets_open: bool = false


func before_each() -> void:
    _was_pad_width = SaSettings.brush_editor_pad_width
    _was_pad_shut = SaSettings.brush_editor_pad_shut
    _was_presets_open = SaSettings.brush_editor_presets_open
    SaSettings.brush_editor_pad_width = 0
    SaSettings.brush_editor_pad_shut = false
    var tree := Engine.get_main_loop() as SceneTree
    _previous_embedding = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "D34EditorFloorTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _host.free()
    (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _previous_embedding
    SaSettings.brush_editor_pad_width = _was_pad_width
    SaSettings.brush_editor_pad_shut = _was_pad_shut
    SaSettings.brush_editor_presets_open = _was_presets_open


func _open_editor() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    _host.add_child(window)
    window.show()
    window.fit_to_content()
    return window


func _column(window: SaBrushEditorWindow) -> Control:
    return window.content.get_node("Column") as Control


func test_the_floor_is_measured_rather_than_the_constructors_guess() -> void:
    var window := _open_editor()

    assert_eq(window.logical_min_size, window.floor_minimum(), "The floor is what the content asked for")
    assert_true(
        window.logical_min_size.x >= SaBrushEditorWindow.MIN_LOGICAL_SIZE.x,
        "and never under the constructor's own, which is %d" % SaBrushEditorWindow.MIN_LOGICAL_SIZE.x
    )
    assert_true(
        window.logical_min_size.x > int(_column(window).get_combined_minimum_size().x),
        "It is wider than the column alone, by the pad's floor the column does not count"
    )
    window.free()


func test_asking_for_the_old_minimum_lands_on_the_floor_with_everything_on_it() -> void:
    var window := _open_editor()

    window.size = SaBrushEditorWindow.MIN_LOGICAL_SIZE
    assert_true(
        window.size.x >= window.floor_minimum().x,
        "Asked for 640 the window is %d wide and its content needs %d" % [window.size.x, window.floor_minimum().x]
    )
    assert_true(
        float(window.size.x) >= _column(window).get_combined_minimum_size().x,
        "so the header, the page list and the footer are inside the window rather than past its edge"
    )
    assert_true(window.floor_report()["fits"], "and the dump says so")
    window.free()


func test_a_long_preset_name_lifts_no_floor() -> void:
    var window := _open_editor()
    var before := window.floor_minimum()

    window.preset_bar.preset_label.text = "A preset imported from Krita with a name longer than the whole dashboard is wide"
    assert_true(
        window.preset_bar.preset_label.get_combined_minimum_size().x < 100.0,
        "The name is cut short with an ellipsis rather than asking for its whole width"
    )
    assert_eq(window.floor_minimum(), before, "so the floor stays where the buttons put it")
    window.free()


## Read off `content_floor`, because the content alone is under the
## constructor's floor in this theme since the buttons left the dashboard, and
## the window's floor would not move.
func test_a_shut_pad_gives_its_floor_back() -> void:
    var window := _open_editor()
    var open_floor := window.content_floor()

    window.scratchpad.drag_to(SaEditorScratchpad.MIN_WIDTH - 1)
    assert_true(window.scratchpad.snap.shut, "Under the pad's floor is shut")
    assert_true(
        window.content_floor().x < open_floor.x,
        "and a shut pad needs no room: %d under %d" % [window.content_floor().x, open_floor.x]
    )
    window.free()


## Measured against `content_floor` for the reason the test above gives.
func test_opening_the_presets_fold_lifts_the_floor_by_its_width() -> void:
    var window := _open_editor()
    var shut_floor := window.content_floor()

    window.page_list.capture_presets({"fold": true})
    assert_true(window.page_list.presets_open, "The fold is open")
    window.fit_to_content()
    var open_floor := window.floor_minimum()
    # The fold's own margin is already a minimum, so the width on top is the
    # rest of the width it opens at.
    var fold := window.page_list.snap.open_width - int(window.page_list.presets_column.get_combined_minimum_size().x)

    assert_true(
        open_floor.x >= shut_floor.x + fold,
        "Open, the floor is %d, which is the shut %d and %d of the fold" % [open_floor.x, shut_floor.x, fold]
    )
    assert_true(window.size.x >= open_floor.x, "and the window was lifted to it rather than left under it")
    window.free()
