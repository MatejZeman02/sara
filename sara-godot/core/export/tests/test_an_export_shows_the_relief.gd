## An export shows the relief the canvas shows.
##
## A flat export lights the picture with the resolved relief and the light,
## a chunk cell at a time, and writes the lit colour. The suite exports a
## picture with height with Include impasto lighting on and off and finds the
## two different where there is a slope and equal to the texel elsewhere,
## reads a 16-bit PNG of the lit picture back and holds it to the view's own
## frame, and drives the dialog's row.
extends "res://tests/test_framework.gd"

const Teardown := preload("res://tests/fixtures/teardown.gd")
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## Two cells wide, so one can hold height and the other none.
const SIZE := Vector2i(512, 256)

## The ramp the sibling suite lights: a tenth of a millimetre over four pixels.
const RAMP_MM: float = 0.025

## How far the 16-bit file may stand from the view's eight-bit frame, in
## steps of 255: the frame's own rounding, and a float or two of difference
## between the view's Oklab decode and the export's.
const VIEW_STEPS: float = 1.5

static var scratch_png_path: String = SaDataRoot.path("h6-relief.png")
static var scratch_png_path_flat: String = SaDataRoot.path("h6-flat.png")
static var scratch_exr_path: String = SaDataRoot.path("h6-relief.exr")
static var scratch_exr_path_flat: String = SaDataRoot.path("h6-flat.exr")

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _canvas: SaCanvas = null
var _doc: SaDocument = null


func before_each() -> void:
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0
    _registries = Fixtures.make_picture_registries()
    _build(null)


## A canvas over a document stored in *space*, the default when null, filled
## with one blue the picker would give in any space.
func _build(space: SaColorSpace) -> void:
    _drop()
    _easel = SaEasel.create_default(SIZE, null, space)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _doc.active_layer.fill(_doc.color_space.from_display(Color(0.3, 0.55, 0.8, 1.0)))
    _easel.process_pending_composite()
    _canvas = SaCanvas.new()
    _canvas.canvas_size = SIZE
    _canvas.easel = _easel
    _canvas.sync_tonemap()


func _drop() -> void:
    Teardown.free_nodes([_canvas, _easel])
    _canvas = null
    _easel = null
    _doc = null


func after_each() -> void:
    for path: String in [scratch_png_path, scratch_png_path_flat, scratch_exr_path, scratch_exr_path_flat]:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    _drop()
    _registries = null
    SaSettings.show_relief = true
    SaSettings.relief_light_angle = 315.0
    SaSettings.relief_strength = 4.0


## A ramp of height across the first cell of the active layer, rising to the
## right, dirtied the way a dab dirties it, and composited.
func _raise_ramp() -> void:
    var grid_pos := Vector2i.ZERO
    SaHeightOps.new(_doc).gain(_doc.active_layer)
    var texture := _doc.active_layer.get_or_create_field(grid_pos, SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for y in texture.size.y:
        for x in texture.size.x:
            bytes.encode_half((y * texture.size.x + x) * 2, float(x) * RAMP_MM)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([grid_pos])
    _easel.process_pending_composite()
    _canvas.view_changed()


## Whether the resolved relief's surface is tilted at *at*.
func _sloped(relief: PackedByteArray, at: Vector2i) -> bool:
    var normal := SaFieldSpec.decode_texel(relief, _easel.relief.texture.format, at.y * SIZE.x + at.x)
    return normal.r != 0.0 or normal.g != 0.0


func _relief_bytes() -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.relief.texture.rid, 0)


## The PNG at *path*, decoded by Godot's reader, which gives eight bits.
static func _png(path: String) -> Image:
    var image := Image.new()
    image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
    return image


## The easel's output drawn through the canvas's material one texel a pixel,
## which is the sibling suite's frame: the view's own picture.
func _view_frame() -> Image:
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var output := Texture2DRD.new()
    output.texture_rd_rid = _easel.output.rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, _canvas.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), output.get_rid())
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    return image


## The samples of the 16-bit RGBA PNG *bytes* as fractions of 65535, one
## Color a pixel, read the way `test_png16_writer.gd` reads them: the
## writer writes every scanline unfiltered, so each is its filter byte and
## then the samples big-endian.
static func _png16(bytes: PackedByteArray) -> Array[Color]:
    var data := PackedByteArray()
    var at := 8
    while at + 12 <= bytes.size():
        var length := (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]
        if bytes.slice(at + 4, at + 8).get_string_from_ascii() == "IDAT":
            data.append_array(bytes.slice(at + 8, at + 8 + length))
        at += 12 + length
    var raw := data.decompress_dynamic(1 << 23, FileAccess.COMPRESSION_DEFLATE)
    var stride := 1 + SIZE.x * 8
    var pixels: Array[Color] = []
    for y in SIZE.y:
        for x in SIZE.x:
            var i := y * stride + 1 + x * 8
            var c := PackedFloat32Array()
            for channel in 4:
                c.append(float((raw[i + channel * 2] << 8) | raw[i + channel * 2 + 1]) / 65535.0)
            pixels.append(Color(c[0], c[1], c[2], c[3]))
    return pixels


## The case that matters: with Include impasto lighting on and off the two
## files differ where there is height and are equal elsewhere.
func test_baked_and_unbaked_differ_only_where_the_surface_slopes() -> void:
    _raise_ramp()
    assert_eq(SaExport.export_png(_easel, scratch_png_path, 8, false, SaGamutMapping.CLIP, true), OK, "The baked export writes")
    assert_eq(
        SaExport.export_png(_easel, scratch_png_path_flat, 8, false, SaGamutMapping.CLIP, false), OK, "and so does the flat one"
    )
    var baked := _png(scratch_png_path)
    var flat := _png(scratch_png_path_flat)
    var relief := _relief_bytes()
    var sloped_differ := 0
    var flat_differ := 0
    for y in SIZE.y:
        for x in SIZE.x:
            var at := Vector2i(x, y)
            if baked.get_pixelv(at) == flat.get_pixelv(at):
                continue
            if _sloped(relief, at):
                sloped_differ += 1
            else:
                flat_differ += 1
    assert_eq(flat_differ, 0, "No texel with a flat surface under it changes, the cell with no height included")
    assert_true(sloped_differ > 200 * 200, "and the ramp's cell is lit, %d texels of it" % sloped_differ)
    var far := Vector2i(400, 128)
    assert_eq(baked.get_pixelv(far), flat.get_pixelv(far), "A texel of the cell with no height is the flat file's")
    var near := Vector2i(128, 128)
    assert_true(
        baked.get_pixelv(near).get_luminance() > flat.get_pixelv(near).get_luminance(),
        "and a face turned to the light is brighter in the baked file"
    )


## The walk is the export's cell walk: one cell at a time, and no scratch
## bigger than a cell, whatever the picture measures (hard rule 2).
func test_the_bake_walks_the_picture_a_cell_at_a_time() -> void:
    _raise_ramp()
    SaExport.export_png(_easel, scratch_png_path, 16, false, SaGamutMapping.CLIP, true)
    assert_eq(SaExportGamut.cells_visited, 2, "Two cells, walked one at a time")
    var cell_bytes := SaChunk.SIZE * SaChunk.SIZE * 16
    assert_true(SaExportGamut.peak_scratch_bytes <= cell_bytes, "and the scratch is one cell's")


## The case that matters: a 16-bit PNG of the lit relief, read back, matches
## the view's frame within the display transform's rounding.
func test_a_sixteen_bit_file_of_the_lit_relief_matches_the_view() -> void:
    _raise_ramp()
    _assert_the_file_is_the_view("an sRGB document")


## The same over a document that stores Oklab, which the view lights in linear
## sRGB and the export decodes by its own coordinates.
func test_an_oklab_document_bakes_what_the_view_shows() -> void:
    _build(SaColorSpace.oklab())
    _raise_ramp()
    _assert_the_file_is_the_view("an Oklab document")


## And over a document that stores linear light, which the export decodes by
## its own curve. A wider gamut is left out on purpose: its file is written in
## that gamut and named for it, so its numbers are not the sRGB screen's.
func test_a_linear_document_bakes_what_the_view_shows() -> void:
    _build(SaColorSpace.linear_srgb())
    _raise_ramp()
    _assert_the_file_is_the_view("a linear sRGB document")


func _assert_the_file_is_the_view(what: String) -> void:
    var frame := _view_frame()
    assert_eq(SaExport.export_png(_easel, scratch_png_path, 16, false, SaGamutMapping.CLIP, true), OK, "The 16-bit export writes")
    var pixels := _png16(FileAccess.get_file_as_bytes(scratch_png_path))
    assert_eq(pixels.size(), SIZE.x * SIZE.y, "and reads back whole")
    var worst := 0.0
    var worst_at := Vector2i.ZERO
    for y in SIZE.y:
        for x in SIZE.x:
            var shown := frame.get_pixel(x, y)
            var written := pixels[y * SIZE.x + x]
            var gap := maxf(absf(shown.r - written.r), maxf(absf(shown.g - written.g), absf(shown.b - written.b)))
            if gap > worst:
                worst = gap
                worst_at = Vector2i(x, y)
    var said := "In %s the file is the view's picture within %.1f steps" % [what, VIEW_STEPS]
    assert_true(worst * 255.0 <= VIEW_STEPS, "%s, the worst %.2f at %s" % [said, worst * 255.0, worst_at])


## A document with no height writes the same picture whatever the row says.
func test_a_document_without_height_bakes_nothing() -> void:
    assert_null(SaExportRelief.prepare(_easel, true, SaRelief.light_toward(315.0), 4.0), "No height, no pass")
    SaExport.export_png(_easel, scratch_png_path, 8, false, SaGamutMapping.CLIP, true)
    SaExport.export_png(_easel, scratch_png_path_flat, 8, false, SaGamutMapping.CLIP, false)
    assert_eq(_png(scratch_png_path).get_data(), _png(scratch_png_path_flat).get_data(), "and the two files hold the same pixels")


## A strength of nought is the view drawing the paint flat, and the export
## does the same.
func test_a_strength_of_nought_bakes_nothing() -> void:
    _raise_ramp()
    assert_null(SaExportRelief.prepare(_easel, true, SaRelief.light_toward(315.0), 0.0), "Nought strength, no pass")


## The float files take the light as well: an EXR holds what the document
## stores, lit, and is untouched where the surface is flat.
func test_an_exr_bakes_the_relief_into_the_stored_numbers() -> void:
    _raise_ramp()
    assert_eq(SaExport.export_exr(_easel, scratch_exr_path, false, true), OK, "The baked EXR writes")
    assert_eq(SaExport.export_exr(_easel, scratch_exr_path_flat, false, false), OK, "and so does the flat one")
    var baked := Image.load_from_file(ProjectSettings.globalize_path(scratch_exr_path))
    var flat := Image.load_from_file(ProjectSettings.globalize_path(scratch_exr_path_flat))
    assert_true(baked.get_pixel(128, 128) != flat.get_pixel(128, 128), "The slope is lit in the float file")
    assert_eq(baked.get_pixel(400, 128), flat.get_pixel(400, 128), "and a flat texel is the stored number, bit for bit")


## The Export dialog's row: shown for a flat format over a document with
## height, hidden for OpenRaster, which says it writes colour only, and what
## it is left at is what the file gets.
func test_the_dialog_offers_the_row_where_there_is_height() -> void:
    var dialog := ExportDialogScript.new(_canvas, &"png", 0.9, false, {}, false, true)
    assert_false(dialog.shows(&"relief"), "No height, no row")
    dialog.free()

    _raise_ramp()
    dialog = ExportDialogScript.new(_canvas, &"png", 0.9, false, {}, false, true)
    assert_true(dialog.shows(&"relief"), "A document with height shows Include impasto lighting for a PNG")
    assert_true(dialog._relief_check.button_pressed, "ticked")
    dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(&"ora"))
    assert_false(dialog.shows(&"relief"), "OpenRaster does not offer it")
    assert_true(dialog._loss_label.text.contains("colour only"), "and says it writes colour only")
    dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(&"png"))

    dialog._export_to(scratch_png_path)
    SaExportInTurns.finish_all()
    dialog._relief_check.button_pressed = false
    assert_false(dialog._bake_relief, "Unticking the check is what the export reads")
    dialog._export_to(scratch_png_path_flat)
    SaExportInTurns.finish_all()
    var near := Vector2i(128, 128)
    assert_true(
        _png(scratch_png_path).get_pixelv(near) != _png(scratch_png_path_flat).get_pixelv(near),
        "and the two files differ on the slope"
    )
    dialog.free()
