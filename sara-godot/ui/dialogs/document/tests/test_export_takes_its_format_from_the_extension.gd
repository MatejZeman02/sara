## Export takes its format from the name's extension.
##
## With Format TIFF in the Export dialog and the name
## `srgbdoc.exr` typed into the picker, a TIFF was written under that name,
## because the format was read from the dropdown alone. The name's extension now
## picks the format when it names one, and a name with no extension of a format
## takes the dropdown's.
##
## The first half holds `format_for`, the second writes through `_export_to`
## over a canvas and reads the first bytes of each file.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Needs a RenderingDevice: the export reads the composite back.
const REQUIRES_GPU := true

const ExportDialogScript = preload("res://ui/dialogs/document/export_dialog.gd")

## The first bytes each format's file starts with. TIFF is the little-endian
## order Sara's writer uses.
const MAGIC := {
    &"png": [0x89, 0x50, 0x4E, 0x47],
    &"jpg": [0xFF, 0xD8, 0xFF],
    &"exr": [0x76, 0x2F, 0x31, 0x01],
    &"tiff": [0x49, 0x49, 0x2A, 0x00],
}

## The skeleton's formats with the image formats module's after them, as the
## running app registers them, built again before each test.
var _formats: SaRegistries


func before_each() -> void:
    _formats = Fixtures.make_picture_registries()


func _cleanup(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The format whose first bytes *path* starts with, or an empty name.
func _written_as(path: String) -> StringName:
    var bytes := FileAccess.get_file_as_bytes(path)
    for format_id: StringName in MAGIC:
        var magic: Array = MAGIC[format_id]
        if bytes.size() >= magic.size() and Array(bytes.slice(0, magic.size())) == magic:
            return format_id
    return &""


## A small opaque canvas with its composite done, which every export reads.
func _canvas() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(32, 32)
    canvas.easel = SaEasel.create_default(canvas.canvas_size)
    canvas.add_child(canvas.easel)
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _with_notice() -> Node:
    var host := Node.new()
    host.name = "S65NoticeHost"
    EventBus.add_child(host)
    SaMessage.install(host)
    return host


func test_the_extension_names_the_format_case_ignored() -> void:
    var cases := {
        "a.png": &"png",
        "a.jpg": &"jpg",
        "a.jpeg": &"jpg",
        "a.JPEG": &"jpg",
        "a.exr": &"exr",
        "a.tif": &"tiff",
        "a.TIFF": &"tiff",
        "a.ora": &"ora",
        "/some/dir.exr/a.Png": &"png",
    }
    for path: String in cases:
        assert_eq(ExportDialogScript.format_for(path, &"tiff"), cases[path], "%s names %s" % [path, cases[path]])


func test_no_extension_or_an_unrelated_one_falls_back() -> void:
    for path: String in ["b", "b.txt", "b.sad", "/some/dir.exr/b", "b."]:
        assert_eq(ExportDialogScript.format_for(path, &"png"), &"png", "%s falls back" % path)


## With Format TIFF, `a.exr` writes an OpenEXR, moves the dropdown and its
## Result to EXR, and says so in the notice.
func test_an_exr_name_over_tiff_writes_an_exr_and_says_so() -> void:
    var host := _with_notice()
    var canvas := _canvas()
    var dialog := ExportDialogScript.new(canvas, &"tiff")
    var path := SaDataRoot.path("test_s65_a.exr")
    var written: Array = []
    dialog.exported.connect(func(at: String, error: Error) -> void: written.append([at, error]))
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    assert_eq(written, [[path, OK]], "the file is written under the name given")
    assert_eq(_written_as(path), &"exr", "and it is an OpenEXR")
    assert_eq(dialog.format, &"exr", "the dropdown moved to EXR")
    assert_true(
        dialog._format_label.text.begins_with("Format: EXR"), "and the Result reads EXR's, %s" % dialog._format_label.text
    )
    var notice := SaMessage.notice_widget()
    assert_true(notice != null and notice.showing(), "a notice is up")
    if notice != null:
        assert_eq(notice.label.text, "Exported as EXR, chosen from the file extension.", "saying why")
    _cleanup(path)
    dialog.free()
    canvas.free()
    host.free()


## With PNG, a name with no extension gets `.png`, and no notice goes up.
func test_a_bare_name_gets_the_dropdown_s_extension() -> void:
    var host := _with_notice()
    var canvas := _canvas()
    var dialog := ExportDialogScript.new(canvas, &"png")
    var bare := SaDataRoot.path("test_s65_b")
    var written: Array = []
    dialog.exported.connect(func(at: String, error: Error) -> void: written.append([at, error]))
    dialog._export_to(bare)
    SaExportInTurns.finish_all()
    assert_eq(written, [[bare + ".png", OK]], "the file is written as b.png")
    assert_false(FileAccess.file_exists(bare), "and nothing under the bare name")
    assert_eq(_written_as(bare + ".png"), &"png", "it is a PNG")
    var notice := SaMessage.notice_widget()
    assert_false(notice != null and notice.showing(), "the format did not move, so nothing is said")
    _cleanup(bare + ".png")
    dialog.free()
    canvas.free()
    host.free()


## An unrelated extension keeps itself and takes the format's after it.
func test_an_unrelated_extension_takes_the_format_s_after_it() -> void:
    var canvas := _canvas()
    var dialog := ExportDialogScript.new(canvas, &"tiff")
    var path := SaDataRoot.path("test_s65_d.final")
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    assert_eq(_written_as(path + ".tiff"), &"tiff", "d.final.tiff is a TIFF")
    assert_eq(dialog.format, &"tiff", "and the dropdown stayed")
    _cleanup(path + ".tiff")
    dialog.free()
    canvas.free()


## `c.jpeg` writes a JPEG from any other format.
func test_a_jpeg_name_writes_a_jpeg() -> void:
    var canvas := _canvas()
    var dialog := ExportDialogScript.new(canvas, &"png")
    var path := SaDataRoot.path("test_s65_c.jpeg")
    dialog._export_to(path)
    SaExportInTurns.finish_all()
    assert_eq(_written_as(path), &"jpg", "c.jpeg is a JPEG")
    assert_eq(dialog.format, &"jpg", "and the dropdown is on JPG")
    _cleanup(path)
    dialog.free()
    canvas.free()
