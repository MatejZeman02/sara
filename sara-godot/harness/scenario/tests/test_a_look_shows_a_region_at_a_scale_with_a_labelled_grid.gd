## A `look` shows a region of the canvas at a scale, with a grid labelled
## in document coordinates drawn over the written picture and never on a layer.
##
## A client cropped and scaled its own exports and drew its own grid on
## them 92 times in one session to know where things were. This drives the step
## itself on a live canvas, so what it holds is the file the step writes.
extends "res://tests/test_framework.gd"

## The canvas is composited and the readback converts through compute kernels.
const REQUIRES_GPU := true

const ScenarioDocument := preload("res://harness/scenario/sa_scenario_document.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const SIZE := Vector2i(320, 192)
## The dot, in document pixels.
const DOT := Vector2i(130, 70)
## The region asked for: from (100, 40), 100 across and 80 down, so the grid of
## 50 has lines at x 100 and 150 and at y 50 and 100 inside it.
const RECT := [100, 40, 100, 80]
const SCALE := 2
const GRID := 50
const RED := Color(1.0, 0.0, 0.0, 1.0)
const NAME := "region.png"

static var scratch_out_dir: String = SaDataRoot.path("test_look")

var _host: Node = null

## The suite's canvas, held as the document in front, which is where a
## harness step and a door line look.
var _front: Fixtures.FrontDocuments = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "LookRegionTestHost"
    EventBus.add_child(_host)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_out_dir))


func after_each() -> void:
    if _front != null:
        _front.put_back()
        _front = null
    if _host != null:
        _host.free()
        _host = null
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


## A live canvas in the tree the step looks through, with one red pixel at
## [constant DOT] on the layer a stroke lands on, composited.
func _canvas_with_a_dot() -> SaCanvas:
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = SaEasel.create_default(SIZE, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    var file := FileAccess.open(folder.path_join("dot.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(Vector2i(1, 1)))
    file.store_buffer(PackedFloat32Array([RED.r, RED.g, RED.b, RED.a]).to_byte_array())
    file.close()
    var spec := {"rect": [DOT.x, DOT.y, 1, 1], "file": "dot.npy", "name": "Dot"}
    var answer := PixelDriver.write_from(canvas.easel.document, spec, folder)
    assert_false(answer.has("error"), "the dot is written: %s" % answer)
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    _front = Fixtures.FrontDocuments.over(canvas)
    return canvas


## Every layer's float texels over the region, read as the door reads them.
func _layers_over_the_region(document: SaDocument) -> Array:
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    var bodies := []
    var count := SaLayerOps.new(document).layers().size()
    for index in count:
        var spec := {"layer": index, "rect": RECT, "file": "layer-%d.npy" % index}
        var answer := PixelDriver.read_into(document, spec, folder)
        bodies.append(FileAccess.get_file_as_bytes(String(answer.get("path", ""))))
    return bodies


func _written() -> Image:
    return Image.load_from_file(ProjectSettings.globalize_path(scratch_out_dir.path_join(NAME)))


func test_the_region_is_written_at_the_scale_with_the_dot_where_they_put_it() -> void:
    var canvas := _canvas_with_a_dot()
    var document := ScenarioDocument.new(SaCaptureRun.new(scratch_out_dir))

    document.look({"path": NAME, "rect": RECT, "scale": SCALE, "grid": GRID})

    var written := _written()
    assert_not_null(written, "the look step wrote its file")
    if written == null:
        canvas.free()
        return
    assert_eq(written.get_size(), Vector2i(RECT[2], RECT[3]) * SCALE, "the rect's size times the scale")
    var at := (DOT - Vector2i(RECT[0], RECT[1])) * SCALE
    for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
        var texel := written.get_pixel(at.x + offset.x, at.y + offset.y)
        assert_almost_eq(texel.r, 1.0, 0.02, "the dot is red at %s" % (at + offset))
        assert_almost_eq(texel.g, 0.0, 0.02, "and not green at %s" % (at + offset))
    var beside := written.get_pixel(at.x + SCALE, at.y)
    assert_true(beside.g > 0.2, "and the next document pixel is the ground, not the dot: %s" % beside)
    canvas.free()


func test_the_grid_stands_where_the_scale_puts_it_and_the_layers_are_untouched() -> void:
    var canvas := _canvas_with_a_dot()
    var before := _layers_over_the_region(canvas.easel.document)
    var document := ScenarioDocument.new(SaCaptureRun.new(scratch_out_dir))

    document.look({"path": NAME, "rect": RECT, "scale": SCALE, "grid": GRID})

    var written := _written()
    assert_not_null(written, "the look step wrote its file")
    if written == null:
        canvas.free()
        return
    # x 150 is a multiple of 50 inside the rect, at (150 - 100) * 2 = 100 out.
    var column := (150 - int(RECT[0])) * SCALE
    # y 50 is one too, at (50 - 40) * 2 = 20 out.
    var row := (50 - int(RECT[1])) * SCALE
    for point: Vector2i in [Vector2i(column, 90), Vector2i(150, row)]:
        var line := written.get_pixel(point.x, point.y)
        var next := Vector2i(point.x + 1, point.y) if point.x == column else Vector2i(point.x, point.y + 1)
        var ground := written.get_pixel(next.x, next.y)
        assert_true(line == Color.BLACK or line == Color.WHITE, "the line at %s is black or white: %s" % [point, line])
        assert_true(absf(line.get_luminance() - ground.get_luminance()) >= 0.4, "and stands off the paint beside it")
    # The label of y 50 sits on a black box just under its line, its first
    # figure's top row white.
    assert_eq(written.get_pixel(2, row + 2), Color.BLACK, "the label's box is black")
    assert_eq(written.get_pixel(4, row + 4), Color.WHITE, "and its figure is white")

    assert_eq(_layers_over_the_region(canvas.easel.document), before, "every layer's pixels are as they were")
    canvas.free()


func test_without_the_new_keys_the_step_is_as_it_was() -> void:
    var canvas := _canvas_with_a_dot()
    var document := ScenarioDocument.new(SaCaptureRun.new(scratch_out_dir))

    document.look({"path": NAME})

    var written := _written()
    assert_not_null(written, "the look step wrote its file")
    if written != null:
        assert_eq(written.get_size(), SIZE, "the whole canvas at its own size")
        assert_almost_eq(written.get_pixel(DOT.x, DOT.y).r, 1.0, 0.02, "with the dot where the document has it")
        assert_true(written.get_pixel(DOT.x + 1, DOT.y).g > 0.2, "and no grid drawn")
    canvas.free()
