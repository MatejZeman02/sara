## The door's `select` step takes a mask, so a painter never traces an outline.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Tracing a held mask with `cv2.findContours` and sending the outline loses
## every strip one pixel wide. The step now
## takes the mask file. These select two overlapping masks through the step's
## own call, in each of the four modes, and read the coverage back from VRAM at
## a texel of each part: only the first, both, only the second and neither.
## A soft ramp, a float64 array, an array in Fortran order and a picture are
## read as coverage, and a mask of the wrong size and a file that is not there
## leave the selection as it was.
extends "res://tests/test_framework.gd"

## The selection is chunks on the GPU, and the window a display.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const MaskReader := preload("res://harness/drivers/sa_select_mask.gd")
const Npy := preload("res://harness/sa_npy.gd")
const Fixtures = preload("res://tests/fixtures.gd")

## The two masks, overlapping over x 300 to 340, and crossing the seam at 256.
const FIRST := Rect2i(240, 100, 100, 1)
const SECOND := Rect2i(300, 100, 100, 1)
## A texel of each part: only the first, both, only the second, neither.
const ONLY_FIRST := Vector2i(250, 100)
const BOTH := Vector2i(320, 100)
const ONLY_SECOND := Vector2i(390, 100)
const NEITHER := Vector2i(320, 101)

var _host: Node = null
var _canvas: Node = null
var _driver: CanvasDriver = null
var _size := Vector2i.ZERO
## The run's folder, which a relative mask name is read from, under the data root.
var _folder := SaDataRoot.path("select-mask")

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


## Parented to an autoload, because the runner calls this from its own `_ready`
## and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "U197SelectMaskTestHost"
    EventBus.add_child(_host)
    _canvas = MainCanvasScript.new()
    _host.add_child(_canvas)
    DirAccess.make_dir_recursive_absolute(_folder)
    _driver = CanvasDriver.new(CaptureRun.new(_folder))
    _size = (_canvas.canvas as SaCanvas).document.canvas_size
    _front = Fixtures.FrontDocuments.over(_canvas.canvas as SaCanvas)
    _write_bytes("first.npy", [FIRST])
    _write_bytes("second.npy", [SECOND])


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    _driver = null
    if _host != null and is_instance_valid(_host):
        _host.free()
    _host = null
    _canvas = null
    for name: String in DirAccess.get_files_at(_folder):
        DirAccess.remove_absolute(_folder.path_join(name))


## Replace, add, subtract and intersect, each read at the four texels.
func test_the_four_modes_join_a_mask_as_a_shape_does() -> void:
    var cases := {
        "replace": [0.0, 1.0, 1.0, 0.0],
        "add": [1.0, 1.0, 1.0, 0.0],
        "subtract": [1.0, 0.0, 0.0, 0.0],
        "intersect": [0.0, 1.0, 0.0, 0.0],
    }
    for mode: String in cases:
        _driver.select({"mask": "first.npy"})
        _driver.select({"mask": "second.npy", "mode": mode})
        var read := [_at(ONLY_FIRST), _at(BOTH), _at(ONLY_SECOND), _at(NEITHER)]
        assert_eq(read, cases[mode], "A mask in %s mode reads %s at the four texels, read %s" % [mode, cases[mode], read])


## A soft ramp from 0 to 1 is soft coverage, read as it was written.
func test_a_soft_mask_selects_softly() -> void:
    var values := PackedFloat32Array()
    values.resize(_size.x * _size.y)
    for x in 256:
        values[200 * _size.x + 100 + x] = x / 255.0
    _write_npy("ramp.npy", "<f4", values.to_byte_array())
    _driver.select({"mask": "ramp.npy"})
    for x: int in [0, 1, 64, 128, 255]:
        assert_almost_eq(_at(Vector2i(100 + x, 200)), x / 255.0, 1e-6, "The ramp reads %d/255 at %d" % [x, 100 + x])


## NumPy's default float64 and a grey picture are coverage as well.
func test_a_float64_array_and_a_picture_are_read() -> void:
    var values := PackedFloat64Array()
    values.resize(_size.x * _size.y)
    values[50 * _size.x + 600] = 0.5
    _write_npy("doubles.npy", "<f8", values.to_byte_array())
    _driver.select({"mask": "doubles.npy"})
    assert_almost_eq(_at(Vector2i(600, 50)), 0.5, 1e-6, "A float64 half is half selected")
    var picture := Image.create_empty(_size.x, _size.y, false, Image.FORMAT_L8)
    picture.set_pixel(7, 9, Color(1, 1, 1))
    picture.save_png(_folder.path_join("grey.png"))
    _driver.select({"mask": ProjectSettings.globalize_path(_folder.path_join("grey.png"))})
    assert_eq([_at(Vector2i(7, 9)), _at(Vector2i(8, 9))], [1.0, 0.0], "A grey picture's white texel alone is selected")


## An array in Fortran order, which NumPy saves for one broadcast along a row,
## lands as the array and not its transpose.
func test_a_fortran_order_array_is_not_transposed() -> void:
    var values := PackedFloat32Array()
    values.resize(_size.x * _size.y)
    # Column 600, row 50, stored at column times height plus row.
    values[600 * _size.y + 50] = 0.75
    _write_npy("columns.npy", "<f4", values.to_byte_array(), Vector2i.ZERO, true)
    _driver.select({"mask": "columns.npy"})
    assert_almost_eq(_at(Vector2i(600, 50)), 0.75, 1e-6, "Row 50, column 600 is three quarters selected")
    assert_eq(_at(Vector2i(50, 600)), 0.0, "and its transpose's texel is not")


## A mask one texel narrower than the canvas, and a name with no file, each
## named in the reader's answer, and the step leaves the selection alone.
func test_a_wrong_size_and_a_missing_file_select_nothing() -> void:
    _driver.select({"mask": "first.npy"})
    var narrow := PackedByteArray()
    narrow.resize((_size.x - 1) * _size.y)
    _write_npy("narrow.npy", "|u1", narrow, Vector2i(_size.x - 1, _size.y))
    var said: Variant = MaskReader.read({"mask": "narrow.npy"}, _size, _folder)
    assert_true(said is String and "narrow.npy" in said and "nothing was selected" in said, "A wrong size is named: %s" % [said])
    said = MaskReader.read({"mask": "gone.npy"}, _size, _folder)
    assert_true(
        said is String and "gone.npy is not there" in said and "run's folder" in said, "A missing file is named: %s" % [said]
    )
    var changes := _driver.selection_changes
    for name: String in ["narrow.npy", "gone.npy"]:
        _driver.select({"mask": name})
        assert_eq(_driver.selection_changes, changes, "%s rewrites no mask" % name)
        assert_eq([_at(ONLY_FIRST), _at(ONLY_SECOND)], [1.0, 0.0], "and the first mask stays selected after %s" % name)


## Writes a uint8 mask of the canvas's size, 255 inside each of *rects*.
func _write_bytes(name: String, rects: Array) -> void:
    var body := PackedByteArray()
    body.resize(_size.x * _size.y)
    for rect: Rect2i in rects:
        for y in range(rect.position.y, rect.end.y):
            for x in range(rect.position.x, rect.end.x):
                body[y * _size.x + x] = 255
    _write_npy(name, "|u1", body)


## Writes a two-dimensional `.npy` of *descr* holding *body*, of *size* or the
## canvas's, in Fortran order when *fortran* says so.
func _write_npy(name: String, descr: String, body: PackedByteArray, size := Vector2i.ZERO, fortran := false) -> void:
    var shape := _size if size == Vector2i.ZERO else size
    var order := "True" if fortran else "False"
    var text := "{'descr': '%s', 'fortran_order': %s, 'shape': (%d, %d), }" % [descr, order, shape.y, shape.x]
    var pad := 64 - (10 + text.length() + 1) % 64
    text += " ".repeat(pad % 64) + "\n"
    var file := FileAccess.open(_folder.path_join(name), FileAccess.WRITE)
    file.store_buffer(PackedByteArray(Npy.MAGIC))
    file.store_8(1)
    file.store_8(0)
    file.store_16(text.length())
    file.store_buffer(text.to_ascii_buffer())
    file.store_buffer(body)
    file.close()


## The selection's coverage at *texel*, 0 where it holds no chunk, read from VRAM.
func _at(texel: Vector2i) -> float:
    var selection := (_canvas.canvas as SaCanvas).document.selection
    if not selection.active:
        return 1.0
    var edge := SaChunk.SIZE
    var chunk: SaChunk = selection.chunks.get(Vector2i(Vector2(texel) / float(edge)), null)
    if chunk == null:
        return 0.0
    var texture := chunk.field(SaSelection.FIELD)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var local := Vector2i(texel.x % edge, texel.y % edge)
    return bytes.decode_float((local.y * chunk.pixel_size() + local.x) * SaFieldSpec.BYTES_PER_TEXEL[texture.format])
