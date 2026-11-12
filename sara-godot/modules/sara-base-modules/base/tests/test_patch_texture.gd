## The patch tool's Texture method, and the Smooth method kept beside it.
##
## What the suite is graded on: it fills a hole in a striped texture and holds
## that the stripes continue through it within a tolerance, and that the Smooth
## method still gives its earlier result on a gradient. The stripes are read texel by texel against the
## stripes the picture would have had there, and the earlier result is the texels
## the Smooth fill wrote, written down below.
##
## The canvas is four chunks and the hole sits on the corner where they meet,
## so the gather, the pyramid and the scatter all cross a chunk seam.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const SaPatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch.gd")
const SaPatchMatchScript = preload("res://modules/sara-base-modules/base/patch/sa_patch_match.gd")
const StatePatchScript = preload("res://modules/sara-base-modules/base/patch/state_patch.gd")
const TestPatch = preload("res://modules/sara-base-modules/base/tests/test_patch.gd")
const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")

const SIDE: int = 512

## The hole, on the corner the four chunks share.
const HOLE := Rect2i(232, 228, 48, 56)

## The stripes: their period in pixels and the two colours they alternate.
const PERIOD: int = 10
const INK := Color(0.12, 0.2, 0.55, 1.0)
const PAPER := Color(0.92, 0.85, 0.6, 1.0)

## How far a texel of the filled hole may sit from the stripe it continues, on
## average over the hole and per channel. The fill draws its texels from
## patches of the stripes themselves, so a hole that continued them exactly
## would read zero, and a seam the vote smooths over is what the tolerance is
## for.
const STRIPE_TOLERANCE: float = 0.04

## How far the grain inside a filled hole may sit from the grain outside it, as
## a fraction of the outside's. The mean of patches that point at different
## places, the vote every level but the finest takes, lost a tenth of it, and a
## seam adds to it, so the bound holds both ways.
const GRAIN_TOLERANCE: float = 0.03

## What the Smooth fill wrote, before the Texture method existed, over an
## ellipse on `test_patch.gd`'s spotted ramp: four texels and a weighted sum
## over the rectangle round the ellipse, read on the RTX 3090.
const SMOOTH_ELLIPSE := Rect2i(100, 104, 50, 40)
const SMOOTH_SUM: float = 75774.343113
const SMOOTH_TEXELS := {
    Vector2i(125, 124): Color(0.314624012, 0.320793778, 0.326963663, 1.000000477),
    Vector2i(104, 124): Color(0.392035723, 0.499968529, 0.607901573, 0.999999940),
    Vector2i(140, 110): Color(0.553474903, 0.500000000, 0.446525216, 1.000000238),
    Vector2i(128, 140): Color(0.304899901, 0.307814538, 0.310729206, 0.999999940),
}


## The stripe at *x* and *y*, running diagonally so that neither a row nor a
## column of the hole can be filled by copying its own neighbour across.
static func stripe_at(x: int, y: int) -> Color:
    return INK if posmod(x + y, PERIOD) * 2 < PERIOD else PAPER


## A document of *side* square holding the stripes, with *hole* painted black,
## at *depth*, an `SaColorSpace.Depth`. *grain* is how far a texel's own noise
## moves it off its stripe, which is what keeps a patch from matching another
## exactly and so is what makes a search work for its answer.
static func make_striped_document(
    hole: Rect2i = HOLE, depth: int = SaColorSpace.Depth.F32, side: int = SIDE, grain: float = 0.0
) -> SaDocument:
    var document := SaDocument.new()
    document.setup_default_document(Vector2i(side, side), SaCompositor.new(), SaColorSpace.srgb().with_depth(depth))
    var layer := document.active_layer
    var noise := RandomNumberGenerator.new()
    noise.seed = 58
    @warning_ignore("integer_division")
    var chunks := side / SaChunk.SIZE
    for chunk_y in chunks:
        for chunk_x in chunks:
            var grid_pos := Vector2i(chunk_x, chunk_y)
            var texture: SaTexture = layer.get_or_create_field(grid_pos)
            var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
            var step := 2 if half else 4
            var texels := PackedByteArray()
            texels.resize(SaChunk.SIZE * SaChunk.SIZE * 4 * step)
            for y in SaChunk.SIZE:
                for x in SaChunk.SIZE:
                    var point := grid_pos * SaChunk.SIZE + Vector2i(x, y)
                    var colour := stripe_at(point.x, point.y)
                    if grain > 0.0:
                        var moved := noise.randf_range(-grain, grain)
                        colour = Color(colour.r + moved, colour.g + moved, colour.b + moved, 1.0)
                    if hole.has_point(point):
                        colour = Color(0.0, 0.0, 0.0, 1.0)
                    var at := (y * SaChunk.SIZE + x) * 4 * step
                    for channel in 4:
                        if half:
                            texels.encode_half(at + channel * step, colour[channel])
                        else:
                            texels.encode_float(at + channel * step, colour[channel])
            GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, texels)
    return document


## Every texel of the layer's chunks, keyed by chunk, read once.
static func read_chunks(document: SaDocument) -> Dictionary:
    var read := {}
    var layer := document.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var texture: SaTexture = layer.get_field(grid_pos)
        var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
        read[grid_pos] = [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), half]
    return read


## The texel at *point* out of what [method read_chunks] answered.
static func texel_in(read: Dictionary, point: Vector2i) -> Color:
    var grid_pos := Vector2i(floori(float(point.x) / SaChunk.SIZE), floori(float(point.y) / SaChunk.SIZE))
    var data: PackedByteArray = read[grid_pos][0]
    var half: bool = read[grid_pos][1]
    var step := 2 if half else 4
    var local := point - grid_pos * SaChunk.SIZE
    var at := (local.y * SaChunk.SIZE + local.x) * 4 * step
    var texel := Color()
    for channel in 4:
        texel[channel] = data.decode_half(at + channel * step) if half else data.decode_float(at + channel * step)
    return texel


## The mean distance per channel between *hole* as filled and the stripes it
## should hold, over every texel of it.
static func stripe_error(document: SaDocument, hole: Rect2i = HOLE) -> float:
    var read := read_chunks(document)
    var total := 0.0
    for y in range(hole.position.y, hole.end.y):
        for x in range(hole.position.x, hole.end.x):
            var got := texel_in(read, Vector2i(x, y))
            var wanted := stripe_at(x, y)
            total += absf(got.r - wanted.r) + absf(got.g - wanted.g) + absf(got.b - wanted.b) + absf(got.a - wanted.a)
    return total / float(hole.get_area() * 4)


## How much the texel-to-texel steps over *rect* differ from the clean stripes'
## own, on average in red, which is the grain and nothing else on a picture
## that holds the stripes, and the grain plus every seam inside a fill.
static func grain_in(read: Dictionary, rect: Rect2i) -> float:
    var total := 0.0
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var here := texel_in(read, Vector2i(x, y)).r
            var left := texel_in(read, Vector2i(x - 1, y)).r
            var above := texel_in(read, Vector2i(x, y - 1)).r
            var clean := stripe_at(x, y).r
            total += absf((here - left) - (clean - stripe_at(x - 1, y).r))
            total += absf((here - above) - (clean - stripe_at(x, y - 1).r))
    return total / float(rect.get_area())


## The first clause: the stripes carry on through the hole.
func test_the_stripes_continue_through_the_hole() -> void:
    var document := make_striped_document()
    document.selection.select_rect(HOLE)
    var written := SaPatchScript.new().patch(document, document.active_layer)
    assert_eq(written, 4, "the patch wrote the four chunks the hole lies across")
    var error := stripe_error(document)
    assert_true(
        error < STRIPE_TOLERANCE,
        "the stripes continue through the hole: %.4f per channel off them, under %.2f" % [error, STRIPE_TOLERANCE]
    )
    document.free()


## The same hole by Smooth, which is why Texture is the default: the stripes
## come back as their average, which is half a stripe's contrast off either.
func test_smooth_blurs_the_stripes_texture_keeps() -> void:
    var document := make_striped_document()
    document.selection.select_rect(HOLE)
    SaPatchScript.new().patch(document, document.active_layer, null, SaPatchScript.Method.SMOOTH)
    var error := stripe_error(document)
    assert_true(error > 4.0 * STRIPE_TOLERANCE, "Smooth leaves a blur where the stripes were: %.4f per channel" % error)
    document.free()


## The grain of the picture comes through the hole with the stripes, because
## the finest vote copies the best patch whole rather than averaging every
## patch over the texel.
func test_the_grain_comes_through_the_hole() -> void:
    var hole := Rect2i(200, 180, 120, 90)
    var document := make_striped_document(hole, SaColorSpace.Depth.F32, SIDE, 0.05)
    document.selection.select_rect(hole)
    SaPatchScript.new().patch(document, document.active_layer)
    var read := read_chunks(document)
    var outside := grain_in(read, Rect2i(16, 16, 128, 128))
    # Shrunk by a patch's radius, so a step across the hole's own edge, where
    # the fill meets the picture, is not counted as grain inside it.
    var inside := grain_in(read, hole.grow(-SaPatchMatchScript.RADIUS))
    assert_almost_eq(
        inside / outside,
        1.0,
        GRAIN_TOLERANCE,
        "the grain inside the hole is the grain outside it: %.4f against %.4f" % [inside, outside]
    )
    document.free()


## The second clause: Smooth on the spotted ramp writes what it wrote before
## Texture existed, to the last bits a float carries.
func test_smooth_gives_todays_result_on_a_gradient() -> void:
    var document := TestPatch.make_spotted_document()
    document.selection.select_ellipse(SMOOTH_ELLIPSE)
    SaPatchScript.new().patch(document, document.active_layer, null, SaPatchScript.Method.SMOOTH)
    var data := GlobalShaderCompiler.get_rd().texture_get_data(document.active_layer.get_field(Vector2i.ZERO).rid, 0)
    for point: Vector2i in SMOOTH_TEXELS:
        var at := (point.y * TestPatch.SIDE + point.x) * 16
        var wanted: Color = SMOOTH_TEXELS[point]
        for channel in 4:
            assert_almost_eq(data.decode_float(at + channel * 4), wanted[channel], 0.00001, "channel %d at %s" % [channel, point])
    var total := 0.0
    for y in range(96, 152):
        for x in range(96, 160):
            var at := (y * TestPatch.SIDE + x) * 16
            for channel in 4:
                total += data.decode_float(at + channel * 4) * float((x * 7 + y * 13 + channel) % 17 + 1)
    assert_almost_eq(total, SMOOTH_SUM, 0.05, "and the whole rectangle round the ellipse")
    document.free()


## Hard rule 2: every dispatch of a Texture patch fits the work rectangle, and
## the whole patch costs less than one pass over the canvas would.
func test_the_dispatches_stay_inside_the_work_rectangle() -> void:
    var document := make_striped_document()
    document.selection.select_rect(HOLE)
    var work := SaPatchScript.work_for(HOLE, Vector2i(SIDE, SIDE), SaPatchScript.Method.TEXTURE)
    assert_true(work.size.x < SIDE and work.size.y < SIDE, "the work rectangle is smaller than the canvas: %s" % work)

    SaCompute.reset_counters()
    SaPatchScript.new().patch(document, document.active_layer)
    var over_the_work := SaCompute.groups_for(work.size.x) * SaCompute.groups_for(work.size.y)
    for key: String in SaCompute.kernel_counters():
        var tally: Dictionary = SaCompute.kernel_counters()[key]
        if not key.begins_with("patch_match/"):
            continue
        var workgroups := int(tally["workgroups"])
        var dispatches := int(tally["dispatches"])
        assert_true(
            workgroups <= dispatches * over_the_work,
            "%s stays inside the work rectangle: %d workgroups over %d dispatches" % [key, workgroups, dispatches]
        )
    var over_the_canvas := SaCompute.groups_for(SIDE) * SaCompute.groups_for(SIDE)
    var matched := 0
    for key: String in SaCompute.kernel_counters():
        if key.begins_with("patch_match/"):
            matched += int(SaCompute.kernel_counters()[key]["workgroups"])
    assert_true(matched > 0, "the Texture method ran its own kernels")
    assert_true(
        matched < over_the_canvas,
        "the whole exemplar fill costs fewer workgroups than one canvas-wide pass: %d against %d" % [matched, over_the_canvas]
    )
    document.free()


## A hole against the canvas's corner has a surround on two sides only, and the
## patches the search tries there run off the canvas. The stripes still carry on.
func test_a_hole_in_the_corner() -> void:
    var corner := Rect2i(0, 0, 40, 36)
    var document := make_striped_document(corner)
    document.selection.select_rect(corner)
    SaPatchScript.new().patch(document, document.active_layer)
    var error := stripe_error(document, corner)
    assert_true(error < STRIPE_TOLERANCE, "the stripes continue into the corner: %.4f per channel off them" % error)
    document.free()


## Half floats: the pyramid takes the document's depth, and the fields keep
## full floats whatever it is, since they hold texel positions.
func test_a_half_float_document() -> void:
    var document := make_striped_document(HOLE, SaColorSpace.Depth.F16)
    assert_eq(
        document.active_layer.get_field(Vector2i.ZERO).format,
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
        "the document is half floats"
    )
    document.selection.select_rect(HOLE)
    SaPatchScript.new().patch(document, document.active_layer)
    var error := stripe_error(document)
    assert_true(error < STRIPE_TOLERANCE, "the stripes continue at half floats: %.4f per channel off them" % error)
    document.free()


## Select All leaves Texture no surround, so the patch is Smooth's, which with
## nothing known leaves the paint where it was rather than laying a blank over
## it.
func test_select_all_leaves_the_paint() -> void:
    var document := make_striped_document()
    document.selection.select_all(document.canvas_size)
    SaPatchScript.new().patch(document, document.active_layer)
    var read := read_chunks(document)
    for point: Vector2i in [Vector2i(3, 3), Vector2i(255, 256), HOLE.get_center()]:
        var wanted := stripe_at(point.x, point.y) if not HOLE.has_point(point) else Color(0.0, 0.0, 0.0, 1.0)
        assert_almost_eq(texel_in(read, point).r, wanted.r, 0.0001, "the paint at %s stays" % point)
        assert_almost_eq(texel_in(read, point).a, 1.0, 0.0001, "and stays opaque")
    document.free()


## The Method row: Texture first and the tool's default, Smooth beside it.
func test_the_method_row() -> void:
    var rows := BaseModule.patch_options()
    var method: SaOptionSpec = rows[0]
    assert_eq(method.key, &"patch_method", "the first of the tool's rows is the method")
    assert_eq(method.property, ^"method", "and it sets the tool's method")
    assert_eq(method.choices.size(), 2, "two methods")
    assert_eq(method.choices[0]["id"], SaPatchScript.Method.TEXTURE, "Texture first")
    assert_eq(method.choices[1]["id"], SaPatchScript.Method.SMOOTH, "Smooth second")
    assert_eq(StatePatchScript.new().method, SaPatchScript.Method.TEXTURE, "and Texture is what the tool starts on")


## Outside the selection nothing moves, by either method.
func test_the_picture_outside_the_hole_is_left_alone() -> void:
    var document := make_striped_document()
    document.selection.select_rect(HOLE)
    SaPatchScript.new().patch(document, document.active_layer)
    var read := read_chunks(document)
    for point: Vector2i in [HOLE.position - Vector2i.ONE, HOLE.end, Vector2i(40, 40), Vector2i(400, 300)]:
        var here := texel_in(read, point)
        var wanted := stripe_at(point.x, point.y)
        assert_almost_eq(here.r, wanted.r, 0.0001, "untouched at %s" % point)
        assert_almost_eq(here.b, wanted.b, 0.0001, "in every channel at %s" % point)
    document.free()


## One history step, and undo puts the black back.
func test_undo_puts_the_hole_back() -> void:
    var document := make_striped_document()
    document.selection.select_rect(HOLE)
    SaPatchScript.new().patch(document, document.active_layer)
    assert_true(document.undo_redo.has_undo(), "the patch is one history step")
    document.undo_redo.undo()
    var centre := texel_in(read_chunks(document), HOLE.get_center())
    assert_almost_eq(centre.r, 0.0, 0.0001, "undo puts the black back")
    assert_almost_eq(centre.b, 0.0, 0.0001, "in every channel")
    document.free()


## The pyramid follows Krita's counts: no search on the finest level, and the
## rounds and passes growing to their ceilings above it.
func test_the_rounds_and_passes_are_krita_s() -> void:
    assert_eq(SaPatchMatchScript.rounds_at(0, 5), 0, "the finest level takes the level above's answer")
    assert_eq(SaPatchMatchScript.rounds_at(1, 5), 2, "two rounds one level up")
    assert_eq(SaPatchMatchScript.rounds_at(4, 5), 4, "and four at most")
    assert_eq(SaPatchMatchScript.rounds_at(0, 0), 1, "a pyramid of one level still searches once")
    assert_eq(SaPatchMatchScript.passes_at(1), 2, "two passes a round one level up")
    assert_eq(SaPatchMatchScript.passes_at(7), 5, "and five at most")
    var levels := SaPatchMatchScript.levels_for(Vector2i(768, 768), Rect2i(256, 256, 256, 256))
    assert_eq(levels, 7, "a 256 pixel hole in its surround is halved six times")


## The time a hole of 256 by 256 takes in grained stripes, end to end, said
## aloud for the record. Not a bound: the floor machine is an integrated GPU
## and the figure is read on whichever card the run is on.
func test_a_256_pixel_hole() -> void:
    var hole := Rect2i(384, 384, 256, 256)
    var document := make_striped_document(hole, SaColorSpace.Depth.F32, 1024, 0.05)
    document.selection.select_rect(hole)
    var engine := SaPatchScript.new()
    # Once to compile the kernels, so the figure is the fill and not the driver.
    engine.patch(document, document.active_layer)
    document.undo_redo.undo()
    var rd := GlobalShaderCompiler.get_rd()
    var middle: SaTexture = document.active_layer.get_field(Vector2i(1, 1))
    # A read back is the one way to know the GPU has finished, before and after.
    rd.texture_get_data(middle.rid, 0)
    var started := Time.get_ticks_usec()
    engine.patch(document, document.active_layer)
    var data := rd.texture_get_data(middle.rid, 0)
    var elapsed := Time.get_ticks_usec() - started
    print("  a 256 by 256 hole by Texture: %.1f ms on %s" % [elapsed / 1000.0, RenderingServer.get_video_adapter_name()])
    # The stripes over the part of the hole that lies in the chunk read.
    var off := 0.0
    for y in range(hole.position.y, SaChunk.SIZE * 2):
        for x in range(hole.position.x, SaChunk.SIZE * 2):
            var at := ((y - SaChunk.SIZE) * SaChunk.SIZE + x - SaChunk.SIZE) * 16
            off += absf(data.decode_float(at) - stripe_at(x, y).r)
    off /= float((SaChunk.SIZE * 2 - hole.position.y) * (SaChunk.SIZE * 2 - hole.position.x))
    assert_true(off < 0.1, "and the stripes carry on through it under their grain: %.4f off them in red" % off)
    document.free()
