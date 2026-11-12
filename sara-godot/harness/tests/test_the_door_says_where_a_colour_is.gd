## The `find` step answers which pixels hold a colour, their count and
## their bounding box in document pixels, on the composite or on one layer.
##
## A script can build masks of colour ranges over its own exports to know
## where the wall, the stone or the panes were. This paints two
## rectangles of one colour on a live canvas and asks the step where they are.
extends "res://tests/test_framework.gd"

## The canvas is composited and the readback converts through compute kernels.
const REQUIRES_GPU := true

const ColorFind := preload("res://harness/sa_color_find.gd")
const PixelDriver := preload("res://harness/scenario/sa_scenario_pixels.gd")

const SIZE := Vector2i(320, 192)
## Two rectangles of one blue, apart from each other, in document pixels.
const LEFT := Rect2i(20, 30, 40, 25)
const RIGHT := Rect2i(200, 120, 30, 50)
const BLUE := Color(0.1, 0.2, 0.9, 1.0)
const BLUE_HEX := "#1a33e6"
## The colour for the Oklab document, sRGB `0.9, 0.9, 0.1`. Its stored
## Oklab numbers read as bytes are about `232, 0, 46`, its green off by 230
## steps, so a search that took them for sRGB would find none of it.
const YELLOW := Color(0.9, 0.9, 0.1, 1.0)
const YELLOW_HEX := "#e6e61a"
## Wide enough for the eight-bit rounding of a colour sent through a document,
## far narrower than the distance from blue to the ground.
const TOLERANCE := 3

static var scratch_out_dir: String = SaDataRoot.path("test_find")

var _host: Node = null


func before_each() -> void:
    _host = Node.new()
    _host.name = "ColorFindTestHost"
    EventBus.add_child(_host)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_out_dir))


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    for name in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(name))
    DirAccess.remove_absolute(folder)


## A live canvas on its plain default ground, with the two blue rectangles on
## a layer called Panes, composited. In *space* when given, the colour stored as
## that space holds the colour a painter picked, *color*, blue when absent.
func _canvas_with_two_rectangles(space: SaColorSpace = null, color: Color = BLUE) -> SaCanvas:
    if space == null:
        space = SaColorSpace.srgb()
    var stored := space.from_display(color)
    var canvas := SaCanvas.new()
    canvas.canvas_size = SIZE
    canvas.easel = SaEasel.create_default(SIZE, null, space)
    canvas.add_child(canvas.easel)
    _host.add_child(canvas)
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    for rect: Rect2i in [LEFT, RIGHT]:
        var floats := PackedFloat32Array()
        for i in rect.size.x * rect.size.y:
            floats.append_array([stored.r, stored.g, stored.b, stored.a])
        var file := FileAccess.open(folder.path_join("blue.npy"), FileAccess.WRITE)
        file.store_buffer(PixelDriver.Npy.header(rect.size))
        file.store_buffer(floats.to_byte_array())
        file.close()
        var spec := {
            "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
            "file": "blue.npy",
            "new_layer": "Panes",
        }
        var answer := PixelDriver.write_from(canvas.easel.document, spec, folder)
        assert_false(answer.has("error"), "the rectangle is written: %s" % answer)
    canvas.easel.request_full_composite()
    canvas.easel.process_pending_composite()
    return canvas


func _area(rect: Rect2i) -> int:
    return rect.size.x * rect.size.y


func _box(rect: Rect2i) -> Array:
    return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func test_both_rectangles_are_counted_and_boxed_on_the_composite_and_on_their_layer() -> void:
    var canvas := _canvas_with_two_rectangles()
    var both := LEFT.merge(RIGHT)
    for layer: Variant in [null, "Panes"]:
        var spec := {"color": BLUE_HEX, "tolerance": TOLERANCE}
        if layer != null:
            spec["layer"] = layer
        var answer := ColorFind.find_in(canvas, spec, scratch_out_dir)
        assert_false(answer.has("error"), "the find is answered: %s" % answer)
        assert_eq(int(answer.get("count", -1)), _area(LEFT) + _area(RIGHT), "both rectangles' pixels, %s" % layer)
        assert_eq(answer.get("box"), _box(both), "and the box around both, %s" % layer)
    canvas.free()


## The door's default document stores Oklab over sRGB's primaries with a
## cube-root curve, and `find` takes its hex in sRGB, so a layer's texels are
## converted before they are matched. The suite's other cases build in sRGB,
## where the conversion is the identity and a search that skipped it passes.
func test_an_oklab_document_is_searched_in_the_colours_a_painter_picked() -> void:
    var space := SaColorSpace.oklab_srgb_gamma30()
    var canvas := _canvas_with_two_rectangles(space, YELLOW)
    var stored := space.from_display(YELLOW)
    assert_true(absf(stored.g - YELLOW.g) > 0.5, "the stored numbers are far from the hex, %s" % stored)
    var both := LEFT.merge(RIGHT)
    for layer: Variant in [null, "Panes"]:
        var spec := {"color": YELLOW_HEX, "tolerance": TOLERANCE}
        if layer != null:
            spec["layer"] = layer
        var answer := ColorFind.find_in(canvas, spec, scratch_out_dir)
        assert_false(answer.has("error"), "the find is answered: %s" % answer)
        assert_eq(int(answer.get("count", -1)), _area(LEFT) + _area(RIGHT), "every yellow pixel by its hex, %s" % layer)
        assert_eq(answer.get("box"), _box(both), "and the box around both, %s" % layer)
    canvas.free()


func test_a_rect_around_one_rectangle_finds_that_one_alone() -> void:
    var canvas := _canvas_with_two_rectangles()
    var around := LEFT.grow(10)
    var spec := {"color": [BLUE.r, BLUE.g, BLUE.b], "tolerance": TOLERANCE, "rect": _box(around), "mask": "left.png"}

    var answer := ColorFind.find_in(canvas, spec, scratch_out_dir)

    assert_eq(int(answer.get("count", -1)), _area(LEFT), "the left rectangle's pixels alone")
    assert_eq(answer.get("box"), _box(LEFT), "and its box in document pixels")
    var mask := Image.load_from_file(String(answer.get("mask", "")))
    assert_not_null(mask, "the mask was written")
    if mask != null:
        assert_eq(mask.get_size(), around.size, "the rect's size")
        var inside := LEFT.position - around.position
        assert_almost_eq(mask.get_pixel(inside.x, inside.y).r, 1.0, 0.01, "white on the rectangle")
        assert_almost_eq(mask.get_pixel(0, 0).r, 0.0, 0.01, "and black off it")
    canvas.free()


func test_a_colour_nobody_painted_counts_none_and_has_no_box() -> void:
    var canvas := _canvas_with_two_rectangles()
    for layer: Variant in [null, "Panes"]:
        var spec := {"color": "#ff00ff", "tolerance": TOLERANCE}
        if layer != null:
            spec["layer"] = layer
        var answer := ColorFind.find_in(canvas, spec, scratch_out_dir)
        assert_eq(int(answer.get("count", -1)), 0, "no pixel holds magenta, %s" % layer)
        assert_true(answer.has("box") and answer["box"] == null, "and there is no box, %s" % layer)
    canvas.free()


func test_a_faint_texel_of_the_colour_on_a_layer_is_not_found() -> void:
    var canvas := _canvas_with_two_rectangles()
    var folder := ProjectSettings.globalize_path(scratch_out_dir)
    var file := FileAccess.open(folder.path_join("faint.npy"), FileAccess.WRITE)
    file.store_buffer(PixelDriver.Npy.header(Vector2i(1, 1)))
    file.store_buffer(PackedFloat32Array([BLUE.r, BLUE.g, BLUE.b, 0.2]).to_byte_array())
    file.close()
    var faint := {"rect": [100, 100, 1, 1], "file": "faint.npy", "layer": "Panes"}
    assert_false(PixelDriver.write_from(canvas.easel.document, faint, folder).has("error"), "the faint texel is written")

    var answer := ColorFind.find_in(canvas, {"color": BLUE_HEX, "tolerance": TOLERANCE, "layer": "Panes"}, scratch_out_dir)

    assert_eq(int(answer.get("count", -1)), _area(LEFT) + _area(RIGHT), "a texel a fifth opaque is not counted")
    canvas.free()


func test_a_malformed_ask_is_refused_with_a_reason() -> void:
    var canvas := _canvas_with_two_rectangles()
    assert_true(ColorFind.find_in(canvas, {"color": "blue-ish"}, scratch_out_dir).has("error"), "a colour that is no colour")
    var off := {"color": BLUE_HEX, "rect": [1000, 1000, 5, 5]}
    assert_true(ColorFind.find_in(canvas, off, scratch_out_dir).has("error"), "a rect off the canvas")
    var missing := {"color": BLUE_HEX, "layer": "Nowhere"}
    assert_true(ColorFind.find_in(canvas, missing, scratch_out_dir).has("error"), "a layer nobody made")
    canvas.free()
