## The `texel` step's own arithmetic, off the GPU rather than through an
## exported TIFF a script then re-parses by hand. The scenario proves the
## step and the dump block against the running app, `read()` and the live
## canvas it needs to find. This is `_read_point` underneath it, which needs
## no window and no easel composite to answer.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const TexelProbe = preload("res://harness/report/sa_texel_probe.gd")

## Needs a RenderingDevice, because the proof is the texel a fill wrote.
const REQUIRES_GPU := true


func test_no_document_answers_both_colours_null() -> void:
    var out := TexelProbe._read_point(null, null, Vector2i(0, 0))
    assert_eq(out["x"], 0, "the point is still named")
    assert_eq(out["y"], 0, "both coordinates")
    assert_eq(out["layer"], null, "with nothing to read a layer's texel from")
    assert_eq(out["composited"], null, "or the canvas's")


func test_a_point_off_the_canvas_answers_null_too() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var doc := surface.easel.document
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel

    var negative := TexelProbe._read_point(doc, canvas, Vector2i(-1, 0))
    assert_eq(negative["layer"], null, "a negative coordinate is off the canvas")
    var past_edge := TexelProbe._read_point(doc, canvas, Vector2i(300, 0))
    assert_eq(past_edge["layer"], null, "and so is one past its far edge")

    canvas.free()
    Fixtures.teardown(surface)


func test_the_layer_colour_is_the_texel_a_fill_wrote() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel

    var was := SaColors.foreground
    SaColors.foreground = Color(1.0, 0.0, 0.0, 1.0)
    assert_true(registries.commands.execute(&"fill_foreground"), "the fill runs")

    var out := TexelProbe._read_point(doc, canvas, Vector2i(0, 0))
    assert_almost_eq(out["layer"]["r"], 1.0, 0.01, "the layer's own texel is the fill")
    assert_almost_eq(out["layer"]["g"], 0.0, 0.01, "with nothing of green in it")
    assert_almost_eq(out["layer"]["b"], 0.0, 0.01, "or of blue")

    canvas.free()
    SaColors.foreground = was
    Fixtures.teardown(surface)


func test_a_point_in_the_second_chunk_reads_its_own_texel() -> void:
    # Two chunks wide, so (256, 0) is chunk (1, 0) rather than (0, 0), and a
    # local-coordinate bug that read the wrong chunk or the wrong offset inside
    # it would answer null or the untouched colour instead of the fill.
    var surface := Fixtures.make_surface(Vector2i(512, 256))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel

    var was := SaColors.foreground
    SaColors.foreground = Color(0.0, 1.0, 0.0, 1.0)
    assert_true(registries.commands.execute(&"fill_foreground"), "the fill runs across both chunks")

    var far := TexelProbe._read_point(doc, canvas, Vector2i(256, 0))
    assert_not_null(far["layer"], "the second chunk answers a texel at all")
    assert_almost_eq(far["layer"]["g"], 1.0, 0.01, "and it is the fill's own colour")

    canvas.free()
    SaColors.foreground = was
    Fixtures.teardown(surface)


func test_no_easel_answers_composited_null_but_still_reads_the_layer() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var registries := Fixtures.make_registries(surface)
    var doc := surface.easel.document
    SaColors.foreground = Color(1.0, 1.0, 1.0, 1.0)
    registries.commands.execute(&"fill_foreground")

    var canvas := SaCanvas.new()
    # No `canvas.easel` set at all, which is the shape the readback sees before
    # the first frame composites anything.
    var out := TexelProbe._read_point(doc, canvas, Vector2i(0, 0))
    assert_eq(out["composited"], null, "nothing to composite from")
    assert_not_null(out["layer"], "but the layer's own texel is still there")

    canvas.free()
    Fixtures.teardown(surface)


## A report of `layer` reporting the pre-cut colour after a Cut, and it is two
## correct answers read as one wrong one.
##
## `shaders/compute/cut_masked.gmacs` scales the alpha by one minus the mask and
## keeps the colour, the way the eraser does, so a feathered cut leaves a feathered
## hole rather than a grey fringe. The texel a cut leaves therefore reads alpha
## zero with its colour still in place, and `composited` at the same point reads
## whatever is under it, because a texel with no alpha contributes nothing.
##
## Here rather than beside the cut in `test_clipboard.gd`, whose cases grade the
## cut on `.a` alone: what this pins is what the `texel` step *answers*, which is
## what that report was read off. A change that zeroed the colour would fail here and pass
## there.
func test_a_cut_answers_alpha_zero_with_its_colour_still_in_place() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var doc := surface.easel.document
    var canvas := SaCanvas.new()
    canvas.easel = surface.easel

    doc.active_layer.fill(Color(0.9, 0.1, 0.1, 1.0))
    doc.selection.select_rect(Rect2i(0, 0, 128, 128))
    assert_true(SaClipboard.new().cut(doc, doc.active_layer), "the cut happens")

    var inside := TexelProbe._read_point(doc, canvas, Vector2i(64, 64))
    assert_almost_eq(inside["layer"]["a"], 0.0, 1e-6, "Inside the cut the layer has no alpha left")
    assert_almost_eq(inside["layer"]["r"], 0.9, 0.01, "and its red is exactly where it was")
    assert_almost_eq(inside["layer"]["g"], 0.1, 0.01, "with its green")
    assert_almost_eq(inside["layer"]["b"], 0.1, 0.01, "and its blue, which is the kernel's own rule")

    var outside := TexelProbe._read_point(doc, canvas, Vector2i(300, 300))
    assert_almost_eq(outside["layer"]["a"], 1.0, 0.01, "Outside it nothing moved")
    assert_almost_eq(outside["layer"]["r"], 0.9, 0.01, "in either column")

    canvas.free()
    Fixtures.teardown(surface)
