## Apply, cancel and the guarded call.
##
## Apply is the only writer in the filter door, so every assertion here reads
## the layer back through `SaExport`: a copy into the wrong chunk or at the
## wrong offset is a plausible picture and not an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")
const ProbeFilter = preload("res://tests/fixtures/filters/probe_filter.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)

## Where the filter runs in every case below: inside chunk (1,1) and well away
## from its edges, so "unchanged outside the rectangle" has room to be read.
const RUN_RECT := Rect2i(300, 300, 100, 40)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(texture)
    return image.get_pixel(x, y)


## One texel of the layer, in document coordinates.
func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


## A context whose run has already produced a flat green result over *rect*.
func _shown_green(rect: Rect2i) -> SaFilterContext:
    _doc.selection.select_rect(rect)
    var ctx := SaFilterContext.new(_doc, _layer)
    var result := ctx.blank_like(ctx.layer_pixels(0))
    result.clear(GREEN)
    ctx.show(result)
    return ctx


# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------


func test_apply_writes_the_result_over_the_rectangle_and_nothing_outside_it() -> void:
    var ctx := _shown_green(RUN_RECT)

    assert_true(SaFilterApply.apply(ctx, "Box blur"), "The apply wrote")
    assert_almost_eq(_layer_texel(350, 320).g, 1.0, 1e-3, "Inside the rectangle the layer is the result")
    assert_almost_eq(_layer_texel(350, 320).r, 0.0, 1e-3, "and not what it was")
    assert_almost_eq(_layer_texel(280, 320).r, 1.0, 1e-3, "Outside it the layer is untouched to the left")
    assert_almost_eq(_layer_texel(350, 280).r, 1.0, 1e-3, "and above")
    assert_almost_eq(_layer_texel(420, 320).r, 1.0, 1e-3, "and to the right")
    assert_almost_eq(_layer_texel(350, 360).r, 1.0, 1e-3, "and below")


func test_apply_records_one_step_named_after_the_filter() -> void:
    var ctx := _shown_green(RUN_RECT)

    SaFilterApply.apply(ctx, "Box blur")

    assert_true(_doc.undo_redo.has_undo(), "One step, and there was none before")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Box blur", "named after the filter and not after the door")


func test_undo_puts_the_pixels_back() -> void:
    var ctx := _shown_green(RUN_RECT)
    SaFilterApply.apply(ctx, "Box blur")

    assert_true(_doc.undo(), "which undoes")

    assert_almost_eq(_layer_texel(350, 320).r, 1.0, 1e-3, "and the layer is red again inside the rectangle")
    assert_almost_eq(_layer_texel(350, 320).g, 0.0, 1e-3, "with none of the result left")
    assert_almost_eq(_layer_texel(280, 320).r, 1.0, 1e-3, "and untouched outside it, as it was all along")


func test_apply_allocates_the_chunks_the_rectangle_reaches() -> void:
    # Across the seam at x = 512, so the run spans an allocated chunk and one
    # that has never been painted.
    var ctx := _shown_green(Rect2i(450, 300, 200, 40))

    assert_true(SaFilterApply.apply(ctx, "Box blur"), "The apply wrote")

    assert_true(_layer.chunks.has(Vector2i(2, 1)), "A chunk was allocated where the rectangle reached and none was")
    assert_almost_eq(_layer_texel(600, 320).g, 1.0, 1e-3, "and the result is in it")
    assert_almost_eq(_layer_texel(600, 400).a, 0.0, 1e-6, "while the rest of that new chunk is still empty")


func test_undo_takes_back_a_chunk_the_apply_allocated() -> void:
    var ctx := _shown_green(Rect2i(450, 300, 200, 40))
    SaFilterApply.apply(ctx, "Box blur")

    assert_true(_doc.undo(), "which undoes")

    assert_false(_layer.chunks.has(Vector2i(2, 1)), "A chunk nobody had painted is gone again, not left empty")
    assert_almost_eq(_layer_texel(500, 320).r, 1.0, 1e-3, "and the chunk that was there is back as it was")


# ---------------------------------------------------------------------------
# Cancel, which is nothing happening
# ---------------------------------------------------------------------------


func test_a_cancelled_dialog_writes_nothing() -> void:
    var ctx := _shown_green(RUN_RECT)
    assert_true(ctx.shown != null, "The run made a result the dialog could have applied")

    # Cancel is the dialog closing and the context going away. There is no call
    # to make, which is the point: nothing but apply can reach a chunk.
    ctx = null

    assert_almost_eq(_layer_texel(350, 320).r, 1.0, 1e-3, "The layer is what it was")
    assert_almost_eq(_layer_texel(350, 320).g, 0.0, 1e-3, "with none of the result in it")
    assert_false(_doc.undo_redo.has_undo(), "and there is no step to undo, because nothing was ever written")


func test_an_apply_with_no_result_writes_nothing() -> void:
    _doc.selection.select_rect(RUN_RECT)
    var ctx := SaFilterContext.new(_doc, _layer)

    SaProblems.announce = false
    var wrote := SaFilterApply.apply(ctx, "Box blur")
    SaProblems.announce = true

    assert_false(wrote, "A run that never showed anything has nothing to apply")
    assert_false(_doc.undo_redo.has_undo(), "and leaves no step behind")


# ---------------------------------------------------------------------------
# The guarded call
# ---------------------------------------------------------------------------


func test_a_filter_that_shows_a_result_runs_clean() -> void:
    var ctx := SaFilterContext.new(_doc, _layer)

    assert_true(SaFilterApply.call_run(ProbeFilter.new(), ctx), "A run that showed a result answers true")
    assert_true(ctx.shown != null, "and the result is on the context for apply to write")


func test_a_run_that_shows_nothing_is_reported_and_the_layer_is_left_alone() -> void:
    var filter := ProbeFilter.new()
    filter.quiet = true
    var ctx := SaFilterContext.new(_doc, _layer)

    SaProblems.announce = false
    var ran := SaFilterApply.call_run(filter, ctx)
    SaProblems.announce = true

    assert_false(ran, "A run that came back with nothing to show is not a run a dialog may apply")
    assert_almost_eq(_layer_texel(350, 320).r, 1.0, 1e-3, "and the layer is untouched, because run has no writer")


func test_a_filter_is_named_by_its_own_file_and_the_line_run_starts_on() -> void:
    var where := SaFilterApply.source_of(ProbeFilter.new())

    assert_true(where.begins_with("res://tests/fixtures/filters/probe_filter.gd:"), "The student's own file, not the door's")
    var line := int(where.split(":")[-1])
    var source := FileAccess.get_file_as_string("res://tests/fixtures/filters/probe_filter.gd").split("\n")
    assert_true(line > 0 and line <= source.size(), "The line is a line the file has")
    assert_true(String(source[line - 1]).begins_with("func run("), "and it is the line run starts on")
