## An export target writes what File > Export writes, the
## impasto lighting and the paper included.
##
## A document on a paper ground with a ramp of impasto height across its first
## cell is written through a target, as a save writes it, and through File >
## Export's own dialog with the same options, and the two files are read equal,
## with the lighting on and off, at both depths, dithered and rolled off. A
## target kept without options takes the dialog's defaults, and the targets dialog
## shows each target's options and sets them.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## Two cells wide, so one holds the impasto and the other the paper alone.
const SIZE := Vector2i(512, 256)
## The ramp, a tenth of a millimetre over four pixels.
const RAMP_MM: float = 0.025

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _doc: SaDocument = null
var _folder := ""


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    _registries = Fixtures.make_picture_registries()
    var types := SaLayerTypeRegistry.new()
    types.register(SaLayerTypeDescriptor.paper())
    _easel = SaEasel.create_default(SIZE, null, null)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.COLOUR
    background[SaDocumentBackground.COLOR] = Color.html("#e8dcc4")
    background[SaDocumentBackground.GROUND] = &"paper"
    _doc.reset_to_default(SIZE, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background, types)
    _easel.process_pending_composite()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = _easel
    _canvas.sync_tonemap()
    _folder = OS.get_temp_dir().path_join("sara-%d" % OS.get_process_id())
    DirAccess.make_dir_recursive_absolute(_folder)


func after_each() -> void:
    SaExportTargets.finish_writes()
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _doc = null
    _registries = null
    for file in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(file))
    DirAccess.remove_absolute(_folder)
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


## The paint layer over the paper, filled with a ramp of height across its first
## cell, the impasto a thick stroke leaves.
func _paint_impasto() -> void:
    var layer := _doc.active_layer
    assert_false(layer.is_generated(), "The paint layer is in front, over the paper")
    layer.fill(_doc.color_space.from_display(Color(0.12, 0.3, 0.62, 0.6)))
    var grid_pos := Vector2i.ZERO
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(x % 64) * RAMP_MM)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])
    _easel.process_pending_composite()
    _canvas.view_changed()


## The bytes a target with these options writes after a save of the document.
func _through_target(depth: int, relief: bool, dither: bool, rolloff: bool) -> PackedByteArray:
    var path := _folder.path_join("target.png")
    var target := SaExportTargets.Target.new(path, &"png", depth, relief, dither, rolloff)
    SaExportTargets.name_all(_doc, [target] as Array[SaExportTargets.Target])
    SaExportTargets.write_after_save(_doc, _folder.path_join("picture.sad"))
    assert_true(SaExportTargets.finish_writes(), "The target is written")
    return FileAccess.get_file_as_bytes(path)


## The bytes File > Export's dialog writes with these options, its rows left
## where the painter would leave them.
func _through_file_export(depth: int, relief: bool, dither: bool, rolloff: bool) -> PackedByteArray:
    var path := _folder.path_join("export.png")
    var dialog := ExportDialogScript.new(_canvas, &"png", 0.9, false, {"png": depth}, rolloff, relief, Color.WHITE, dither)
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    dialog.free()
    return FileAccess.get_file_as_bytes(path)


## Both files, written again once when they straddle a second, because each
## names the second it was written in.
func _assert_same(depth: int, relief: bool, dither: bool, rolloff: bool, what: String) -> PackedByteArray:
    var target := _through_target(depth, relief, dither, rolloff)
    var exported := _through_file_export(depth, relief, dither, rolloff)
    if target != exported:
        target = _through_target(depth, relief, dither, rolloff)
        exported = _through_file_export(depth, relief, dither, rolloff)
    assert_true(target.size() > 0, "%s: the target holds a picture" % what)
    assert_true(target == exported, "%s: the target is the bytes File > Export writes" % what)
    return target


static func _decoded(bytes: PackedByteArray) -> Image:
    var image := Image.new()
    image.load_png_from_buffer(bytes)
    return image


func test_a_target_writes_the_bytes_file_export_writes_with_the_lighting_on_and_off() -> void:
    _paint_impasto()
    assert_true(SaRelief.shows_height(_doc), "The document shows height")
    for depth: int in [8, 16]:
        var lit := _assert_same(depth, true, false, false, "%d-bit, impasto lighting on" % depth)
        var flat := _assert_same(depth, false, false, false, "%d-bit, impasto lighting off" % depth)
        var near := Vector2i(130, 128)
        assert_true(
            _decoded(lit).get_pixelv(near) != _decoded(flat).get_pixelv(near),
            "%d-bit: the lighting is in the target's pixels, on the slope" % depth
        )
        var paper := Vector2i(400, 128)
        var row_lit := PackedColorArray()
        for x in range(300, 500):
            row_lit.append(_decoded(lit).get_pixel(x, paper.y))
        var varies := false
        for colour in row_lit:
            varies = varies or colour != row_lit[0]
        assert_true(varies, "%d-bit: the paper's tooth is lit where no paint has height" % depth)
    _assert_same(8, true, true, false, "8-bit, dithered")
    _assert_same(8, true, false, true, "8-bit, rolled off")


func test_a_target_kept_before_takes_the_dialog_s_defaults() -> void:
    _doc.module_data[SaExportTargets.KEY] = [{"path": _folder.path_join("old.png"), "format": "png", "depth": 8}]
    var targets := SaExportTargets.of(_doc)
    assert_eq(targets.size(), 1, "The old target is read")
    if targets.is_empty():
        return
    assert_true(targets[0].relief, "with the impasto lighting on, as File > Export opens")
    assert_false(targets[0].dither, "the dither off")
    assert_eq(targets[0].rolloff, SaSettings.tonemap_highlights, "and the rolloff where the view's tonemap is")
    SaExportTargets.name_all(_doc, targets)
    var kept: Dictionary = (_doc.module_data[SaExportTargets.KEY] as Array)[0]
    assert_true(bool(kept["relief"]), "The .sad keeps the lighting from then on")
    assert_false(bool(kept["dither"]), "and the dither")


func test_the_targets_dialog_shows_each_target_s_options_and_sets_them() -> void:
    var dialog := SaExportTargetsDialog.new()
    EventBus.add_child(dialog)
    dialog.open_for(_doc)
    dialog.add_target(_folder.path_join("hero"))
    var relief := dialog.find_child("ReliefCheck", true, false) as CheckBox
    var dither := dialog.find_child("DitherCheck", true, false) as CheckBox
    var rolloff := dialog.find_child("RolloffCheck", true, false) as CheckBox
    assert_not_null(relief, "The row shows Impasto lighting")
    assert_not_null(dither, "and Dither")
    assert_not_null(rolloff, "and Roll off highlights")
    if relief == null or dither == null or rolloff == null:
        dialog.free()
        return
    var options := dialog.find_child("OptionsRow", true, false) as Control
    var room := dialog.min_size.x - 2 * SaUI.px(SaTheme.PAD)
    assert_true(options.get_combined_minimum_size().x <= room, "The options fit the dialog at its smallest")
    assert_true(relief.button_pressed, "The lighting starts on")
    assert_true(dither.visible, "Dither is offered at eight bits")
    relief.button_pressed = false
    assert_false(SaExportTargets.of(_doc)[0].relief, "Unticking it is what the target keeps")
    (dialog.find_child("DitherCheck", true, false) as CheckBox).button_pressed = true
    assert_true(SaExportTargets.of(_doc)[0].dither, "and ticking Dither")
    dialog.set_option(0, &"depth", 16)
    assert_eq(SaExportTargets.of(_doc)[0].depth, 16, "The depth is the target's")
    assert_false((dialog.find_child("DitherCheck", true, false) as CheckBox).visible, "and sixteen bits offer no dither")
    assert_false(SaExportTargets.of(_doc)[0].relief, "while the other options stay as set")
    dialog.free()
