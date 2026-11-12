## The Tip Image row over a preset whose picture is gone.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A drive restarted with a preset whose tip file had been deleted, and the row
## read the file's name over an empty preview on one tree and Procedural on the
## other, while the brush painted nothing on both. Each test here saves a preset
## with a real picture, deletes the picture and applies the preset, which is the
## restart without the restart.
##
## The row is the door's grid of pictures, so the word is
## on the cell now: a mark in place of the picture and the reason under its
## name, where the dropdown said it in the label.
##
## The window is built and never added to the tree, the way
## `test_tip_preview_follow.gd` builds it, because a `Window` in a headless tree
## maps a real OS window and the run blocks until the watchdog fires.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A tip load uploads the image and the brush compiles its kernel.
const REQUIRES_GPU := true

static var scratch_dir: String = SaDataRoot.path("test_tip_row_unreadable")
static var scratch_preset_dir: String = SaDataRoot.path("test_tip_row_unreadable_presets")
const PRESET: String = "Rock from a bundle"
const TIP_ROW: StringName = &"tip_image_path"

var _surface: SaSurface = null
var _machine: ToolMachine = null
var _tip_path: String = ""


func before_each() -> void:
    _clear(scratch_dir)
    _clear(scratch_preset_dir)
    DirAccess.make_dir_recursive_absolute(scratch_dir)
    # A copy of a shipped tip under a name of its own, so deleting it deletes
    # nothing the build ships and the name is in neither tip folder.
    _tip_path = scratch_dir.path_join("rock-8.png")
    var file := FileAccess.open(_tip_path, FileAccess.WRITE)
    file.store_buffer(FileAccess.get_file_as_bytes("res://tips/tree.png"))
    file.close()
    _surface = Fixtures.make_surface()
    _machine = Fixtures.make_bound_machine(_surface)
    _brush().load_tip("")
    SaBrushTipMask.forget_loaded_elsewhere()


func after_each() -> void:
    _brush().load_tip("")
    SaBrushTipMask.forget_loaded_elsewhere()
    Fixtures.teardown(_surface, _machine)
    _clear(scratch_dir)
    _clear(scratch_preset_dir)


func _clear(dir: String) -> void:
    if not DirAccess.dir_exists_absolute(dir):
        return
    for file_name: String in DirAccess.get_files_at(dir):
        DirAccess.remove_absolute(dir.path_join(file_name))
    DirAccess.remove_absolute(dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_preset_dir
    return store


func _brush() -> ToolState:
    return _machine.get_tool("brush")


func _specs() -> Array[SaOptionSpec]:
    var out: Array[SaOptionSpec] = []
    out.assign(_machine.get_descriptor(&"brush").options)
    return out


func _spec(key: StringName) -> SaOptionSpec:
    for spec: SaOptionSpec in _specs():
        if spec.key == key:
            return spec
    return null


## The Tip Image grid on the open page.
func _grid(window: SaBrushEditorWindow) -> SaTipGrid:
    return window.pages.page_controls.control(TIP_ROW) as SaTipGrid


## The cell the grid draws for *path*, or null when it draws none.
func _cell(window: SaBrushEditorWindow, path: String) -> Button:
    for cell: Node in _grid(window).cells.get_children():
        if cell is Button and (cell as Button).tooltip_text.contains(path.get_file().get_basename().capitalize()):
            return cell as Button
    return null


## Saves the brush holding the picture as a preset, puts the brush back on the
## procedural tip, and applies the preset with the picture deleted or not.
func _apply_preset_with_the_picture(kept: bool) -> void:
    assert_true(_brush().load_tip(_tip_path), "The picture loads while it is there")
    assert_true(_store().save_preset(PRESET, _brush().settings) != "", "and the brush holding it saves as a preset")
    _brush().load_tip("")
    if not kept:
        DirAccess.remove_absolute(_tip_path)
    assert_true(_store().apply_preset(PRESET, _brush().settings), "The preset applies")


## Opens the page holding the Tip Image row, so its grid has listed the tips.
func _window_on_the_tip_row() -> SaBrushEditorWindow:
    var window := SaBrushEditorWindow.new()
    window.bind_tool(_brush(), _specs(), _store())
    for index in window.page_list.row_report().size():
        window.show_page(index)
        for spec: SaOptionSpec in window.pages.open_specs():
            if spec != null and spec.key == TIP_ROW:
                return window
    return window


func test_a_preset_whose_picture_is_gone_names_it_unreadable() -> void:
    _apply_preset_with_the_picture(false)
    assert_eq(String(_brush().settings.tip.image_path), _tip_path, "The preset keeps the path it was saved with")
    var window := _window_on_the_tip_row()
    var report := _grid(window).tip_grid_report()
    assert_true((report["tips"] as Array).has(_tip_path), "The grid still draws a cell for the file")
    assert_true((report["unreadable"] as Dictionary).has(_tip_path), "and marks it as one the brush could not read")
    assert_eq(String(report["chosen"]), _tip_path, "holding it, because the preset holds it")
    var cell := _cell(window, _tip_path)
    assert_not_null(cell, "The cell is there")
    assert_eq(cell.text, SaTipGrid.UNREADABLE_MARK, "showing the mark in place of a picture")
    assert_true(cell.tooltip_text.contains("Rock 8 (unreadable)"), "and naming it unreadable: %s" % cell.tooltip_text)

    var refusals: Array[String] = []
    var ear := func(text: String) -> void: refusals.append(text)
    EventBus.paint_refused.connect(ear)
    _grid(window).pick(_tip_path)
    EventBus.paint_refused.disconnect(ear)
    assert_eq(refusals.size(), 1, "A press on it says why where refusals go")
    window.free()


## What the row's word stands on: the brush binds the stand-in and paints with no
## picture, which is also why the preview beside the row is empty.
func test_the_brush_holds_no_picture_for_it() -> void:
    _apply_preset_with_the_picture(false)
    var refusals: Array[String] = []
    var ear := func(text: String) -> void: refusals.append(text)
    EventBus.paint_refused.connect(ear)
    var mask := SaStampBindings.bind(_brush().compute, _brush().settings.tip, null)
    EventBus.paint_refused.disconnect(ear)
    assert_false(mask.has_image(), "The bind finds no picture to sample")
    assert_eq(refusals.size(), 1, "and says so once, which is the toast a painter sees")
    assert_false(_brush().tip_readable(_tip_path), "The brush answers the path as unreadable")


## The control: the same preset with its picture still there reads plainly, so
## the word above is about the missing file and not about the preset.
func test_a_preset_whose_picture_is_there_names_it_plainly() -> void:
    _apply_preset_with_the_picture(true)
    var window := _window_on_the_tip_row()
    var report := _grid(window).tip_grid_report()
    assert_false((report["unreadable"] as Dictionary).has(_tip_path), "The grid does not mark the picture")
    var cell := _cell(window, _tip_path)
    assert_not_null(cell, "and draws its cell")
    assert_not_null(cell.icon, "with its picture")
    assert_true(cell.button_pressed, "pressed, because the brush holds it")
    window.free()


## A picture that is on disk and is not a picture at all is the same word, from
## the mask the brush bound rather than from the disk.
func test_a_file_that_is_there_and_not_a_picture_is_unreadable_too() -> void:
    _apply_preset_with_the_picture(true)
    var file := FileAccess.open(_tip_path, FileAccess.WRITE)
    file.store_string("not a picture")
    file.close()
    var ear := func(_text: String) -> void: pass
    EventBus.paint_refused.connect(ear)
    _brush().tip_mask = SaStampBindings.bind(_brush().compute, _brush().settings.tip, null)
    EventBus.paint_refused.disconnect(ear)
    var labels: Array = _brush().tip_choices()["labels"]
    var ids: Array = _brush().tip_choices()["ids"]
    assert_eq(String(labels[ids.find(_tip_path)]), "Rock 8 (unreadable)", "The list marks the file the bind refused")
