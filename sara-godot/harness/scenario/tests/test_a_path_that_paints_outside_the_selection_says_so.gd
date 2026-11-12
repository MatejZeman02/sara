## A `path` step sent over an active selection without
## `"inside_selection"` still fills its shape whole, and its answer now says it
## laid paint outside the selection and at how many pixels, where a path painted 51
## outside an ellipse at (985, 860) unnoticed.
##
## The ellipse is selected, a path is sent across its edge, and the count in the
## answer is read against a count made here on the processor from what the GPU
## holds afterwards: the selection's mask, and the layer's alpha, which over an
## empty layer and an opaque colour is the shape's own coverage. A hard square
## over a hard ellipse is checked against the square's pixels the mask leaves
## out, and a soft circle over a soft ellipse against the pixels whose alpha is
## more than the mask lets through, which is the rim's case.
##
## The selection's ellipse reaches four chunks and the shapes reach chunks the
## selection holds none of, so the count is made in more than one chunk and in
## chunks where the kernel reads the selection's stand-in.
##
## Everything goes through `SaScenarioPath.answer`, the door the step itself
## calls once it has found the main canvas, so the suite needs a document and
## no window.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const ScenarioPath = preload("res://harness/scenario/sa_scenario_path.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const GREEN := Color(0.2, 0.6, 0.3, 1.0)

## The ellipse's box, across the corner at (256, 256) where four chunks meet.
const ELLIPSE := Rect2i(120, 140, 280, 220)

## A square from inside the ellipse out past its lower right, into chunks the
## selection holds none of.
const SQUARE: Array = [[300, 300], [560, 300], [560, 560], [300, 560]]
const SQUARE_RECT := Rect2i(300, 300, 260, 260)

## A circle across the ellipse's left edge.
const CIRCLE: Array = [130, 250, 60]

## The kernel's threshold, half a level of an eight-bit channel.
const LEVEL: float = 0.5 / 255.0

## What the answer says when it laid paint outside, up to the count.
const SAYS := "laid paint at "

var _surface: SaSurface = null
var _doc: SaDocument = null
var _kept_foreground: Color


## Three by three chunks.
func before_each() -> void:
    _surface = Fixtures.make_surface(Vector2i(768, 768))
    _doc = _surface.get_document()
    _kept_foreground = SaColors.foreground
    SaColors.foreground = GREEN


func after_each() -> void:
    SaColors.foreground = _kept_foreground
    _doc.free()
    _surface.easel.free()
    _surface = null
    _doc = null


## The count the answer *line* gives, or -1 when it gives none.
func _count_in(line: String) -> int:
    var found := RegEx.create_from_string("laid paint at (\\d+) pixel\\(s\\) outside the selection").search(line)
    return int(found.get_string(1)) if found != null else -1


## The painter's mask, `{grid_pos: PackedByteArray}`, for every chunk it holds.
func _mask_bytes() -> Dictionary:
    var out: Dictionary = {}
    for grid_pos: Vector2i in _doc.selection.chunks:
        var texture: SaTexture = (_doc.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return out


## The mask at document pixel *pixel* in *masks*, zero where no chunk is held.
func _held(masks: Dictionary, pixel: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid_pos := Vector2i(pixel.x / SaChunk.SIZE, pixel.y / SaChunk.SIZE)
    if not masks.has(grid_pos):
        return 0.0
    var side := (_doc.selection.chunks[grid_pos] as SaChunk).pixel_size()
    var local := pixel - grid_pos * SaChunk.SIZE
    return (masks[grid_pos] as PackedByteArray).decode_float((local.y * side + local.x) * 4)


## The pixels of SQUARE_RECT the selection holds nothing at.
func _square_outside() -> int:
    var masks := _mask_bytes()
    var outside := 0
    for y in range(SQUARE_RECT.position.y, SQUARE_RECT.end.y):
        for x in range(SQUARE_RECT.position.x, SQUARE_RECT.end.x):
            if _held(masks, Vector2i(x, y)) <= 0.0:
                outside += 1
    return outside


## The pixels of the layer whose alpha is more than the selection lets through
## by more than LEVEL, read off every chunk the layer holds.
func _alpha_outside() -> int:
    var masks := _mask_bytes()
    var outside := 0
    var layer := _doc.active_layer
    for grid_pos: Vector2i in layer.chunks:
        var chunk := layer.chunks[grid_pos] as SaChunk
        var side := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(chunk.field(SaFieldSpec.ALBEDO).rid, 0)
        for y in side:
            for x in side:
                var alpha := bytes.decode_float((y * side + x) * 16 + 12)
                if alpha - _held(masks, grid_pos * SaChunk.SIZE + Vector2i(x, y)) > LEVEL:
                    outside += 1
    return outside


## The layer's alpha at document pixel *pixel*.
func _alpha(pixel: Vector2i) -> float:
    @warning_ignore("integer_division")
    var grid_pos := Vector2i(pixel.x / SaChunk.SIZE, pixel.y / SaChunk.SIZE)
    var chunk: SaChunk = _doc.active_layer.chunks.get(grid_pos, null)
    if chunk == null:
        return 0.0
    var side := chunk.pixel_size()
    var local := pixel - grid_pos * SaChunk.SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(chunk.field(SaFieldSpec.ALBEDO).rid, 0)
    return bytes.decode_float((local.y * side + local.x) * 16 + 12)


func test_a_hard_square_across_the_edge_says_how_many_pixels_it_laid_outside() -> void:
    _doc.selection.select_ellipse(ELLIPSE)
    var line := ScenarioPath.answer(_doc, {"polygon": SQUARE, "antialias": false})
    var expected := _square_outside()
    var partly := expected > 0 and expected < SQUARE_RECT.get_area()
    assert_true(partly, "The square lies partly outside the ellipse, %d pixels" % expected)
    assert_true(line.contains(SAYS), "The answer says the path laid paint outside the selection: %s" % line)
    assert_eq(_count_in(line), expected, "and counts the square's pixels the selection holds nothing at")
    assert_true(line.contains('"inside_selection": true'), "and names the key that keeps it in")
    assert_true(line.contains("filled 4 chunk(s)"), "and still says the chunks it filled")
    var past := _alpha(Vector2i(550, 550))
    assert_almost_eq(past, 1.0, 1e-6, "The default is unchanged, the square is filled outside the selection")
    assert_almost_eq(_alpha(Vector2i(320, 320)), 1.0, 1e-6, "as well as inside it")


func test_the_same_square_with_the_key_says_nothing_of_outside() -> void:
    _doc.selection.select_ellipse(ELLIPSE)
    var line := ScenarioPath.answer(_doc, {"polygon": SQUARE, "antialias": false, "inside_selection": true})
    assert_false(line.contains(SAYS), "With the key nothing is laid outside, and the answer says nothing of it: %s" % line)
    assert_eq(_count_in(line), -1, "and gives no count")
    assert_true(line.contains("filled"), "It is the fill's line")
    assert_almost_eq(_alpha(Vector2i(550, 550)), 0.0, 1e-6, "and the square stops at the selection")
    assert_almost_eq(_alpha(Vector2i(320, 320)), 1.0, 1e-6, "inside which it is filled")


func test_a_soft_circle_over_a_soft_ellipse_counts_the_rim_it_covers_more_than_the_selection() -> void:
    _doc.selection.select_ellipse(ELLIPSE, SaSelection.Mode.REPLACE, true)
    var line := ScenarioPath.answer(_doc, {"circle": CIRCLE})
    var expected := _alpha_outside()
    assert_true(expected > 0, "The circle lays paint past the ellipse's left edge, %d pixels" % expected)
    var said := _count_in(line)
    assert_eq(said, expected, "and the answer counts every pixel laid more than the selection lets through: %s" % line)

    _doc.undo()
    var kept := ScenarioPath.answer(_doc, {"circle": CIRCLE, "inside_selection": true})
    assert_false(kept.contains(SAYS), "The same circle with the key says nothing of outside: %s" % kept)


func test_a_path_inside_the_selection_says_nothing_of_outside() -> void:
    _doc.selection.select_ellipse(ELLIPSE)
    var line := ScenarioPath.answer(_doc, {"polygon": [[200, 200], [240, 200], [240, 240], [200, 240]], "antialias": false})
    assert_false(line.contains(SAYS), "A square well inside the ellipse lays nothing outside it: %s" % line)
    assert_true(line.contains("filled 1 chunk(s)"), "and fills its one chunk")


func test_with_nothing_selected_a_path_says_nothing_of_outside() -> void:
    var line := ScenarioPath.answer(_doc, {"polygon": SQUARE, "antialias": false})
    assert_false(line.contains(SAYS), "No selection holds everything, so nothing is outside it: %s" % line)
    assert_almost_eq(_alpha(Vector2i(550, 550)), 1.0, 1e-6, "and the square is filled")


func test_the_key_given_false_has_said_what_it_wants_and_is_not_told() -> void:
    _doc.selection.select_ellipse(ELLIPSE)
    var line := ScenarioPath.answer(_doc, {"polygon": SQUARE, "antialias": false, "inside_selection": false})
    assert_false(line.contains(SAYS), "The whole fill was asked for by name: %s" % line)
    assert_almost_eq(_alpha(Vector2i(550, 550)), 1.0, 1e-6, "and it is whole")


func test_the_count_leaves_the_selection_and_the_history_as_they_were() -> void:
    _doc.selection.select_ellipse(ELLIPSE)
    var chunks_before: Dictionary = _doc.selection.chunks
    var bounds_before := _doc.selection.bounds
    var masks_before := _mask_bytes()
    var start := _doc.history.position()
    ScenarioPath.answer(_doc, {"polygon": SQUARE, "antialias": false})
    assert_true(is_same(_doc.selection.chunks, chunks_before), "The selection holds the very chunks it held")
    assert_eq(_doc.selection.bounds, bounds_before, "with the bounds it had")
    assert_eq(_mask_bytes(), masks_before, "and masks the count did not write into")
    assert_eq(_doc.history.position(), start + 1, "and the only step is the paint's")
