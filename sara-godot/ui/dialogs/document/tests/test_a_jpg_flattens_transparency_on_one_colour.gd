## A JPG export flattens transparency on one colour.
##
## A stroke on a transparent document exported as JPG
## came out as a white page with a black block behind the stroke. A JPEG has no
## alpha, the encoder dropped it and kept the colour under it, and under alpha 0
## that colour was black where the compositor had written a cell and white where
## it never had. The export now lays the picture over one colour first, White
## unless the dialog's Transparent areas row says otherwise.
##
## The first half holds the writer on a texture built by hand, the second the
## compositor's own output, which is where a half-covered texel shows whether
## the alpha the flatten reads is straight, and the third the dialog's row.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the export reads a texture back and dispatches a
## kernel.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The side of one cell of the hand-built texture. A JPEG codes 8 by 8 blocks
## with its colour halved to 16 by 16, so a cell this size holds a whole block
## of one colour at its centre and nothing of its neighbour bleeds into it.
const CELL := 32
## The centre of a cell along either side.
const MIDDLE := CELL >> 1

## The stored texel of each cell, left to right: transparent black, transparent
## white, a red at half cover and an opaque blue-grey that has to come out as it
## went in.
const CELLS: Array[Color] = [
    Color(0.0, 0.0, 0.0, 0.0),
    Color(1.0, 1.0, 1.0, 0.0),
    Color(1.0, 0.0, 0.0, 0.5),
    Color(0.2, 0.4, 0.6, 1.0),
]

## What JPEG's own rounding may move a channel of a flat block by at quality 1.
const JPEG_ERROR := 2

## The three colours a painter can lay the picture over: the two buttons and one
## off the swatch.
const FLATTENS: Array[Color] = [Color.WHITE, Color.BLACK, Color(40.0 / 255.0, 160.0 / 255.0, 90.0 / 255.0)]


func _cleanup(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A texture of `CELLS`, each a `CELL` square, in one row.
func _cells_texture() -> SaTexture:
    var size := Vector2i(CELL * CELLS.size(), CELL)
    var texture := SaTexture.new(size)
    var texels := PackedFloat32Array()
    for y in size.y:
        for color: Color in CELLS:
            for x in CELL:
                texels.append_array([color.r, color.g, color.b, color.a])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels.to_byte_array())
    return texture


## The three channels of *color* as bytes.
func _bytes_of(color: Color) -> Vector3i:
    return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))


## The pixel at *at* of the JPEG at *path* as bytes.
func _read(path: String, at: Vector2i) -> Vector3i:
    var image := Image.load_from_file(ProjectSettings.globalize_path(path))
    if image == null or image.is_empty():
        return Vector3i(-1, -1, -1)
    image.convert(Image.FORMAT_RGB8)
    var data := image.get_data()
    var offset := (at.y * image.get_width() + at.x) * 3
    return Vector3i(data[offset], data[offset + 1], data[offset + 2])


## Whether every channel of *got* is within JPEG's error of *want*.
func _near(got: Vector3i, want: Vector3i) -> bool:
    return absi(got.x - want.x) <= JPEG_ERROR and absi(got.y - want.y) <= JPEG_ERROR and absi(got.z - want.z) <= JPEG_ERROR


## Straight alpha over *flatten*, in bytes, the way the eight-bit image the
## export reads back holds it: the alpha is rounded to its byte first.
func _over(color: Color, flatten: Color) -> Vector3i:
    var alpha := roundf(color.a * 255.0) / 255.0
    var top := _bytes_of(color)
    var under := _bytes_of(flatten)
    return Vector3i(
        roundi(top.x * alpha + under.x * (1.0 - alpha)),
        roundi(top.y * alpha + under.y * (1.0 - alpha)),
        roundi(top.z * alpha + under.z * (1.0 - alpha))
    )


## Both transparent cells are the flatten colour whatever colour sits under
## their alpha, the half-covered one is the mix, and the opaque one is untouched.
func test_every_transparent_texel_is_the_flatten_colour() -> void:
    var texture := _cells_texture()
    for flatten: Color in FLATTENS:
        var path := SaDataRoot.path("test_s9_cells.jpg")
        var written := SaExport.export_jpg_texture(
            texture, SaColorSpace.srgb(), path, 1.0, PackedFloat32Array(), SaGamutMapping.CLIP, null, flatten
        )
        assert_eq(written, OK, "the JPEG over %s is written" % flatten.to_html(false))
        var want := _bytes_of(flatten)
        for i in CELLS.size():
            var got := _read(path, Vector2i(i * CELL + MIDDLE, MIDDLE))
            var expected := _over(CELLS[i], flatten)
            assert_true(
                _near(got, expected), "cell %d over #%s reads %s, %s expected" % [i, flatten.to_html(false), got, expected]
            )
        assert_true(_near(_read(path, Vector2i(MIDDLE, MIDDLE)), want), "transparent black is the flatten colour")
        assert_true(_near(_read(path, Vector2i(CELL + MIDDLE, MIDDLE)), want), "and so is transparent white")
        _cleanup(path)


## The half-covered cell sits between the stroke and the flatten colour rather
## than on either, so the edge of a soft stroke blends into the ground.
func test_a_half_covered_texel_sits_between_the_two() -> void:
    var texture := _cells_texture()
    var path := SaDataRoot.path("test_s9_half.jpg")
    var written := SaExport.export_jpg_texture(
        texture, SaColorSpace.srgb(), path, 1.0, PackedFloat32Array(), SaGamutMapping.CLIP, null, Color.WHITE
    )
    assert_eq(written, OK, "the JPEG is written")
    var got := _read(path, Vector2i(2 * CELL + MIDDLE, MIDDLE))
    assert_true(got.x >= 255 - JPEG_ERROR, "red stays full, %s" % got)
    assert_true(got.y > 100 and got.y < 155, "green is halfway to white's, %s" % got)
    assert_true(got.z > 100 and got.z < 155, "and so is blue, %s" % got)
    _cleanup(path)


## The compositor's own output, over a transparent document with a sparse grid:
## one chunk painted half red, one allocated and left transparent, and one
## never allocated. Before the flatten the second came out black and the third
## white. The half red reads 255, 128, 128 over white only if the output is
## straight alpha. Premultiplied, it would read 191, 128, 128.
func test_a_transparent_document_flattens_on_one_colour() -> void:
    var easel := SaEasel.create_default(Vector2i(64, 64), null, SaColorSpace.srgb())
    var pitch := easel.document.active_layer.get_or_create_chunk(Vector2i.ZERO).pixel_size()
    var size := Vector2i(pitch * 3, pitch)
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    easel.document.reset_to_default(size, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    assert_not_null(easel.resize_output(size), "the output is the three chunks' size")
    var layer := easel.document.active_layer
    assert_true(layer.chunks.is_empty(), "the transparent document starts with no chunk")
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(Color(1.0, 0.0, 0.0, 0.5))
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(Color(0.0, 0.0, 0.0, 0.0))
    easel.request_full_composite()
    easel.process_pending_composite()

    var middle := pitch >> 1
    for flatten: Color in [Color.WHITE, Color.BLACK]:
        var path := SaDataRoot.path("test_s9_document.jpg")
        assert_eq(SaExport.export_jpg(easel, path, 1.0, false, SaGamutMapping.CLIP, false, flatten), OK, "written")
        var want := _bytes_of(flatten)
        var half := _over(Color(1.0, 0.0, 0.0, 0.5), flatten)
        var painted := _read(path, Vector2i(middle, middle))
        assert_true(_near(painted, half), "the half red over #%s is %s, read %s" % [flatten.to_html(false), half, painted])
        var allocated := _read(path, Vector2i(pitch + middle, middle))
        assert_true(_near(allocated, want), "an allocated empty chunk is the flatten colour, read %s" % allocated)
        var never := _read(path, Vector2i(2 * pitch + middle, middle))
        assert_true(_near(never, want), "and so is a chunk never allocated, read %s" % never)
        _cleanup(path)
    easel.free()


## The row is JPG's alone, starts White, and its two buttons and its swatch
## write the colour the export lays the picture over.
func test_the_dialog_offers_the_colour_for_jpg_only() -> void:
    var dialog := ExportDialogScript.new(null, &"png")
    assert_false(dialog.shows(&"flatten"), "PNG keeps its alpha and has no row")
    for format_id: StringName in [&"exr", &"tiff", &"ora"]:
        dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(format_id))
        assert_false(dialog.shows(&"flatten"), "%s has no row" % format_id)
    dialog.page.row(&"format").drive(ExportDialogScript.format_ids().find(&"jpg"))
    assert_true(dialog.shows(&"flatten"), "JPG has the row")
    assert_eq(dialog.flatten, Color.WHITE, "which starts White")
    assert_eq(dialog._flatten_swatch.color, Color.WHITE, "and its swatch shows it")

    (dialog.find_child("FlattenBlack", true, false) as Button).pressed.emit()
    assert_eq(dialog.flatten, Color.BLACK, "Black lays the picture over black")
    assert_eq(dialog._flatten_swatch.color, Color.BLACK, "and the swatch shows it")
    var picked := FLATTENS[2]
    dialog._flatten_swatch.color_changed.emit(picked)
    assert_eq(dialog.flatten, picked, "the swatch lays it over any colour")
    (dialog.find_child("FlattenWhite", true, false) as Button).pressed.emit()
    assert_eq(dialog.flatten, Color.WHITE, "and White gives the default back")
    assert_false(dialog._flatten_swatch.edit_alpha, "the swatch edits no alpha, since a JPEG has none")
    dialog.free()


## The dialog hands its colour to the writer: a transparent document exported
## through `_export_to` with Black chosen reads black.
func test_the_dialog_exports_over_the_colour_it_shows() -> void:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(32, 32)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    var background := SaDocumentBackground.default_choice()
    background[SaDocumentBackground.KIND] = SaDocumentBackground.TRANSPARENT
    canvas.document.reset_to_default(canvas.canvas_size, SaColorSpace.srgb(), SaDocument.DEFAULT_DPI, background)
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    var dialog := ExportDialogScript.new(canvas, &"jpg", 1.0, false, {}, false, false, Color.BLACK)
    assert_true(dialog.shows(&"flatten"), "the row shows for JPG")
    assert_eq(dialog._flatten_swatch.color, Color.BLACK, "the swatch starts on the colour it was handed")
    var path := SaDataRoot.path("test_s9_dialog.jpg")
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    assert_true(_near(_read(path, Vector2i(16, 16)), Vector3i.ZERO), "the transparent page is black")
    _cleanup(path)
    dialog.free()
    canvas.free()
