## A crop leaves the brush its size. Crop to Selection once shrank a 15 px
## brush to 7.32 px, 15 times 500 over 1025, because the radius is a fraction
## of the canvas and the side it was a
## fraction of was the canvas's shorter side, whatever had made the canvas
## smaller. A crop does not change the size of a pixel. The side is now the
## document's `brush_side`: the shorter side when a document is made or opened,
## kept by Crop to Selection and Canvas Size, scaled with the picture by Image
## Size, and written into a `.sad` when it is not the shorter side.
##
## The document is a photo's size, 1280 by 1025, the brush is 15 px, and the
## selection is 600 by 500. Each case reads the
## two numbers a painter sees, the bar's Radius row and the ring, which is the
## stroke's own `_base_radius`.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## A crop is a compute pass over the chunks, and the bar needs a machine on a
## surface.
const REQUIRES_GPU := true

const PHOTO := Vector2i(1280, 1025)
const SELECTED := Rect2i(500, 300, 600, 500)
const BRUSH_PX := 15.0

static var scratch_profile: String = SaDataRoot.path("test_p8_brush_size.cfg")

var _saved_path: String = ""
var _surface: SaSurface = null
var _machine: ToolMachine = null
var _registries: SaRegistries = null
var _bar: ToolOptionsBar = null
var _doc: SaDocument = null
var _file: String = ""


func before_each() -> void:
    _saved_path = SaSettings.settings_path
    SaSettings.settings_path = ProjectSettings.globalize_path(scratch_profile)
    _remove_profile()
    SaSettings.load_settings()
    _surface = Fixtures.make_surface(PHOTO)
    _machine = Fixtures.make_bound_machine(_surface)
    _registries = Fixtures.make_registries(_surface)
    _bar = ToolOptionsBar.new()
    _bar.target_tool_machine = _machine
    _bar._ready()
    _bar.bind_registries(_registries.blend_modes)
    _doc = _surface.get_document()
    _machine.set_active_tool(&"brush")
    _brush().settings.radius = BRUSH_PX / float(PHOTO.y)
    _bar._sync_ui_from_settings()
    _file = SaDataRoot.path("test_p8_brush_size_%d.sad" % OS.get_process_id())


func after_each() -> void:
    _doc = null
    _bar.free()
    Fixtures.teardown(_surface, _machine)
    _registries = null
    _remove_profile()
    SaSettings.settings_path = _saved_path
    SaSettings.load_settings()
    if FileAccess.file_exists(_file):
        DirAccess.remove_absolute(_file)


func _remove_profile() -> void:
    for suffix: String in ["", ".bak", ".broken"]:
        var path := ProjectSettings.globalize_path(scratch_profile) + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)


func _brush() -> ToolState:
    return _machine.get_tool("brush")


## The pixels the bar's Radius row shows.
func _row_px() -> float:
    var size := _bar.control_for(&"radius") as FactorSlider
    return size.display_value_multiplier * size.value


## Both numbers a painter reads are *px*, and the stored fraction is the one
## the brush was set to, so nothing rewrote the setting to get there.
func _reads(px: float, when: String) -> void:
    assert_almost_eq(_row_px(), px, 0.01, "The Radius row reads %.2f px %s" % [px, when])
    assert_almost_eq(_brush().get_cursor_radius(), px, 0.01, "and so does the ring %s" % when)
    assert_almost_eq(_brush().settings.radius, BRUSH_PX / float(PHOTO.y), 1e-7, "on the fraction it was set to %s" % when)


func _crop_to_the_hunts_selection() -> void:
    _doc.selection.select_rect(SELECTED)
    assert_true(SaCrop.new(_doc).crop_to_selection(), "Crop to Selection happens")
    assert_eq(_doc.canvas_size, SELECTED.size, "and the canvas is the selection")


func test_crop_to_selection_leaves_a_15_px_brush_at_15_px() -> void:
    _reads(BRUSH_PX, "before the crop")
    _crop_to_the_hunts_selection()
    _reads(BRUSH_PX, "after the crop, where it read 7.32")
    _doc.undo_redo.undo()
    assert_eq(_doc.canvas_size, PHOTO, "Undo puts the photo's size back")
    _reads(BRUSH_PX, "after the undo")
    _doc.undo_redo.redo()
    _reads(BRUSH_PX, "after the redo")


func test_canvas_size_leaves_the_brush_its_size() -> void:
    assert_true(SaCrop.new(_doc).resize_to(Vector2i(1600, 900), Vector2i.ZERO), "Canvas Size happens")
    _reads(BRUSH_PX, "on a 1600 by 900 canvas")
    assert_true(SaCrop.new(_doc).resize_to(Vector2i(400, 300), Vector2i(1, 1)), "and again, smaller")
    _reads(BRUSH_PX, "on a 400 by 300 canvas")


func test_a_quarter_turn_leaves_the_brush_its_size() -> void:
    _crop_to_the_hunts_selection()
    assert_true(SaOrient.new(_doc).rotate_image(1), "Rotate 90 degrees clockwise happens")
    assert_eq(_doc.canvas_size, Vector2i(500, 600), "and the cropped canvas stands on its side")
    _reads(BRUSH_PX, "after the turn of a cropped canvas")


## The other half: the smaller size must not carry over to the next document
## opened. A new document is read against its own shorter side,
## so the crop's side goes with the cropped document. On one the photo's size
## the brush is 15 px again, and on another size it is the fraction of that
## one, which is the resolution independence of the radius.
func test_the_next_document_reads_the_brush_against_its_own_side() -> void:
    _crop_to_the_hunts_selection()
    _doc.reset_to_default(PHOTO)
    EventBus.document_resized.emit(_doc, _doc.canvas_size)
    _reads(BRUSH_PX, "on the next document of the photo's size")
    _doc.reset_to_default(Vector2i(1920, 1080))
    EventBus.document_resized.emit(_doc, _doc.canvas_size)
    _reads(BRUSH_PX * 1080.0 / 1025.0, "on a 1920 by 1080 one, the same fraction of its 1080")


## Image Size scales the picture, so it scales the brush with it: the brush
## covers as much of what is painted as it did. A 640 by 513 canvas reads 7.51
## px, which is that rule and stays. After a crop the side the crop kept is
## scaled, so halving the cropped canvas halves the 15 px rather than the 7.32.
func test_image_size_scales_the_brush_with_the_picture() -> void:
    assert_true(SaResample.new(_doc).resample_to(Vector2i(640, 513)), "Image Size to 640 by 513 happens")
    _reads(BRUSH_PX * 513.0 / 1025.0, "after Image Size, as before the fix")
    _doc.undo_redo.undo()
    _reads(BRUSH_PX, "after its undo")
    _crop_to_the_hunts_selection()
    assert_true(SaResample.new(_doc).resample_to(Vector2i(300, 250)), "Image Size to half the crop happens")
    _reads(BRUSH_PX / 2.0, "after halving the cropped canvas")
    _doc.undo_redo.undo()
    _reads(BRUSH_PX, "after that undo")


## The Feather is a fraction of the same side, so a crop keeps its pixels too.
func test_the_feather_keeps_its_pixels_through_a_crop() -> void:
    var feather := 20.0 / float(PHOTO.y)
    assert_eq(SaSelectionFilters.feather_radius(feather, _doc.brush_side), 20, "A 20 px feather on the photo")
    _crop_to_the_hunts_selection()
    assert_eq(SaSelectionFilters.feather_radius(feather, _doc.brush_side), 20, "is 20 px after the crop, where it was 10")


## A cropped document saved and opened again keeps the side its crop kept, so
## the brush is the size it was before the save, and a document whose side is
## its shorter one opens read against that side.
func test_a_cropped_document_saved_and_opened_again_keeps_the_brush_its_size() -> void:
    _crop_to_the_hunts_selection()
    assert_eq(SaExport.save_sad(_doc, _file, 0), OK, "The cropped document saves")
    _doc.reset_to_default(PHOTO)
    assert_eq(SaExport.load_sad(_doc, _file), OK, "and opens again")
    EventBus.document_resized.emit(_doc, _doc.canvas_size)
    assert_eq(_doc.canvas_size, SELECTED.size, "at the cropped size")
    _reads(BRUSH_PX, "on the cropped document opened again")

    _doc.reset_to_default(Vector2i(600, 500))
    assert_eq(SaExport.save_sad(_doc, _file, 0), OK, "A document made at that size saves")
    _doc.reset_to_default(PHOTO)
    assert_eq(SaExport.load_sad(_doc, _file), OK, "and opens again")
    assert_almost_eq(_doc.brush_side, 500.0, 0.0001, "read against its own shorter side")
