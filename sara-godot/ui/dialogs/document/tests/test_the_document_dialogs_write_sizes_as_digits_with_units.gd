## The document dialogs' built sentences read with digits and units.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sentences assembled at run time must not join numbers into prose, as
## "200.0 per cent across and 200.0 per cent down, read bilinear." and "20.0 MB a
## full layer" once did. Every number a painter reads has one form: digits with their unit, a size as "1920 × 1080
## px", a percentage as "50%". Each sentence is read here at two sizes, because
## a format string can read right at one size and wrong at another, the way
## "200.0" did. The dialogs are built detached, since a `Window` added to the
## tree in a headless run hangs, and read off the labels they drew.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice, for the New document dialog's colour space browser
## and the canvas the Export dialog reads its size from.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func test_new_document_says_what_one_layer_uses() -> void:
    var dialog := NewDocumentDialog.new()
    # A discrete card, so the plain line is read without the warning.
    dialog.memory_line.device_bytes = 0
    for size: Vector2i in [Vector2i(1920, 1080), Vector2i(16384, 16384)]:
        dialog.page.row(&"width").drive(size.x)
        dialog.page.row(&"height").drive(size.y)
        var layer := NewDocumentDialog.MemoryLine.layer_bytes(size, dialog.selected_space())
        var figure := NewDocumentDialog.MemoryLine.size_text(layer)
        assert_eq(dialog.memory_line.text, "One layer uses %s." % figure, "%s reads as a sentence" % size)
        assert_true(figure.ends_with(" MB") or figure.ends_with(" GB"), "with its unit: %s" % figure)
    var bytes := NewDocumentDialog.MemoryLine.layer_bytes(Vector2i(16384, 16384), dialog.selected_space())
    dialog.memory_line.device_bytes = 2 * bytes
    dialog.memory_line.show_cost(Vector2i(16384, 16384), dialog.selected_space())
    assert_eq(
        dialog.memory_line.text,
        (
            "One layer uses %s, more than a quarter of this GPU's %s."
            % [NewDocumentDialog.MemoryLine.size_text(bytes), NewDocumentDialog.MemoryLine.size_text(2 * bytes)]
        ),
        "and the warning is one sentence with both figures"
    )
    dialog.free()


## The figures in decimal units, a million bytes to the megabyte, with a tenth
## only where a whole number would hide a small canvas or a gigabyte's part.
func test_the_memory_figure_is_decimal() -> void:
    assert_eq(NewDocumentDialog.MemoryLine.size_text(20971520), "21 MB", "20,971,520 bytes are 21 MB")
    assert_eq(NewDocumentDialog.MemoryLine.size_text(4294967296), "4.3 GB", "and 4,294,967,296 are 4.3 GB")
    assert_eq(NewDocumentDialog.MemoryLine.size_text(524288), "0.5 MB", "and half a megabyte keeps its tenth")


func test_image_size_writes_a_percentage_and_the_filter_by_name() -> void:
    var dialog := SaImageSizeDialog.new()
    var current := dialog.find_child("CurrentLabel", true, false) as Label
    var scale := dialog.find_child("ScaleLabel", true, false) as Label
    dialog.configure(Vector2i(1920, 1080))
    dialog.page.row(&"width").drive(3840)
    assert_eq(current.text, "The image is 1920 × 1080 px.", "the size as digits and a unit")
    assert_eq(scale.text, "200% × 200%, resampled with Bilinear.", "a doubling reads as 200%")
    dialog.configure(Vector2i(1000, 750))
    dialog.page.row(&"width").drive(667)
    dialog.page.row(&"filter").drive(1)
    assert_eq(current.text, "The image is 1000 × 750 px.", "at a second size too")
    assert_eq(scale.text, "66.7% × 66.7%, resampled with Nearest.", "and a part keeps its tenth")
    dialog.free()


func test_canvas_size_writes_the_corner_in_pixels() -> void:
    var dialog := SaCanvasSizeDialog.new()
    var current := dialog.find_child("CurrentLabel", true, false) as Label
    var said := dialog.find_child("DifferenceLabel", true, false) as Label
    dialog.configure(Vector2i(1920, 1080))
    dialog.page.row(&"width").drive(2560)
    assert_eq(current.text, "The canvas is 1920 × 1080 px.", "the size as digits and a unit")
    assert_eq(
        said.text,
        "Anchor: Centre. The picture's top-left corner moves to 320, 0 px. The new area is filled with the background.",
        "a grow says where the corner goes and what fills the new area"
    )
    dialog.configure(Vector2i(800, 600))
    dialog.page.row(&"width").drive(400)
    dialog.page.row(&"height").drive(300)
    assert_eq(current.text, "The canvas is 800 × 600 px.", "at a second size too")
    assert_eq(said.text, "Anchor: Centre. The picture's top-left corner moves to -200, -150 px.", "and a crop adds no area")
    dialog.free()


func test_the_open_and_fit_questions_write_both_sizes_in_pixels() -> void:
    var dialog := SaImportFitDialog.new()
    dialog.configure(Vector2i(300, 200), Vector2i(1920, 1080))
    assert_eq(dialog._size_label.text, "The picture is 300 × 200 px and the canvas is 1920 × 1080 px.", "the fit question")
    dialog.configure(Vector2i(4000, 3000), Vector2i(800, 600))
    assert_eq(dialog._size_label.text, "The picture is 4000 × 3000 px and the canvas is 800 × 600 px.", "at a second size")
    dialog.configure_open(Vector2i(300, 200), null, -1)
    assert_eq(
        dialog._size_label.text,
        (
            "The picture opens as a new document of 300 × 200 px. "
            + "It holds 8 bits a channel, so choose below the depth the document keeps it in."
        ),
        "the open question for a file that names no depth"
    )
    dialog.configure_open(Vector2i(4096, 2048), null, SaColorSpace.Depth.F32)
    assert_eq(
        dialog._size_label.text,
        "The picture opens as a new document of 4096 × 2048 px. The file is 32-bit float.",
        "and for one that names it"
    )
    dialog.free()


func test_export_writes_its_size_with_the_multiplication_sign() -> void:
    for size: Vector2i in [Vector2i(64, 48), Vector2i(300, 200)]:
        var canvas := SaCanvas.new()
        canvas.canvas_size = size
        canvas.easel = SaEasel.create_default(canvas.canvas_size, null, SaColorSpace.srgb())
        canvas.add_child(canvas.easel)
        var dialog := ExportDialogScript.new(canvas, &"png")
        assert_eq(dialog._size_label.text, "Size: %d × %d px" % [size.x, size.y], "the Result's size line at %s" % size)
        dialog.free()
        canvas.free()


## The hover on File > Export... and the Author row's hint, both built from the
## dialog's own lists of formats, with the last two joined by a whole pattern.
func test_the_export_sentences_join_their_formats_as_a_list() -> void:
    assert_eq(
        SaExportDialog.menu_sentence(),
        "Save a copy as PNG, JPG, EXR, TIFF or OpenRaster. OpenRaster keeps the layers, the others flatten them.",
        "the File menu's hover"
    )
    assert_eq(
        SaExportDialog.author_sentence(),
        "The author name written into PNG, TIFF or OpenRaster files. Leave empty to write none.",
        "and the Author row's hint"
    )
