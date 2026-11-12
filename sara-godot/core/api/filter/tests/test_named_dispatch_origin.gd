## Where the named dispatch thinks it is running.
##
## `dispatch(name, size)` has a size and nothing else, so the region it folds
## into the params began at the canvas's corner and a kernel that declared
## `origin` was handed `(0, 0)` wherever it really ran. The fixture kernel here
## writes its `origin` into the picture, so every assertion reads a texel back
## and none of them trusts that the call happened.
##
## The readback is `SaExport`'s, the door hard rule 1 permits a test.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")

## The fixture whose kernel paints the rectangle's own position. Its directory
## keeps a `modules` segment, so the shader index files `at_origin` under
## `origin-fixture`, and its id is that same word so that a context with no
## ModuleLoader behind it qualifies the bare name to it.
const FIXTURE_MODULE = preload("res://tests/fixtures/origin/modules/origin-fixture/module.gd")

const OWNER: StringName = &"origin-fixture"
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(2048, 2048))
    _doc = _easel.document
    _layer = _doc.active_layer


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## One chunk, four chunks in from the corner on both axes, so a rectangle that
## begins at zero and one that begins where the paint is are different numbers
## rather than the same one read twice.
func _paint_away_from_the_corner() -> void:
    _layer.get_or_create_chunk(Vector2i(4, 3)).clear(WHITE)


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(texture)
    return image.get_pixel(x, y)


func _dispatched_origin(ctx: SaFilterContext) -> Vector2:
    var src := ctx.layer_pixels(0)
    var dst := ctx.blank_like(src)
    var kernel := ctx.kernel("at_origin")
    kernel.set_image("dst", dst)
    kernel.dispatch("at_origin", src.size)
    var written := _texel(dst, 2, 2)
    return Vector2(written.r, written.g)


# ---------------------------------------------------------------------------
# The defect
# ---------------------------------------------------------------------------


func test_the_named_dispatch_carries_the_runs_own_rectangle() -> void:
    _paint_away_from_the_corner()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER)

    var seen := _dispatched_origin(ctx)

    assert_eq(ctx.rect.position, Vector2i(1024, 768), "The run's rectangle is where the paint is")
    assert_almost_eq(seen.x, 1024.0, 0.5, "and the kernel was told that x, not the canvas's corner")
    assert_almost_eq(seen.y, 768.0, 0.5, "and that y")


func test_a_kernel_asked_for_before_the_pixels_still_learns_the_rectangle() -> void:
    _paint_away_from_the_corner()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER)

    # The order the box blur does not write, and the one that would leave a
    # cached instance dispatching over the previous rerun's rectangle.
    var kernel := ctx.kernel("at_origin")
    var src := ctx.layer_pixels(0)
    var dst := ctx.blank_like(src)
    kernel.set_image("dst", dst)
    kernel.dispatch("at_origin", src.size)

    var written := _texel(dst, 2, 2)
    assert_almost_eq(written.r, 1024.0, 0.5, "The rectangle reached the kernel asked for first")
    assert_almost_eq(written.g, 768.0, 0.5, "on both axes")


func test_a_second_run_over_a_new_rectangle_moves_the_origin() -> void:
    _paint_away_from_the_corner()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER)

    var first := _dispatched_origin(ctx)
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(WHITE)
    var second := _dispatched_origin(ctx)

    assert_almost_eq(first.x, 1024.0, 0.5, "The first run is the one chunk's corner")
    assert_almost_eq(second.x, 256.0, 0.5, "and the second is the wider bounds', not the first's")
    assert_almost_eq(second.y, 256.0, 0.5, "on both axes, so the cached instance was told again")


func test_the_canvas_corner_is_still_zero() -> void:
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(WHITE)
    var ctx := SaFilterContext.new(_doc, _layer, OWNER)

    var seen := _dispatched_origin(ctx)

    assert_almost_eq(seen.x, 0.0, 0.5, "A run that does begin at the corner reads zero")
    assert_almost_eq(seen.y, 0.0, 0.5, "as it always did")


# ---------------------------------------------------------------------------
# What the door promises
# ---------------------------------------------------------------------------


func test_use_region_takes_the_position_and_leaves_the_size_to_the_call() -> void:
    _paint_away_from_the_corner()
    var ctx := SaFilterContext.new(_doc, _layer, OWNER)
    var src := ctx.layer_pixels(0)
    var dst := ctx.blank_like(src)
    var kernel := ctx.kernel("at_origin")

    # A rectangle whose size is nothing like the dispatch's, so a call that
    # took the size from here rather than from its own argument would write a
    # picture of the wrong shape and this readback would be outside it.
    kernel.use_region(Rect2i(Vector2i(64, 32), Vector2i(1, 1)))
    kernel.set_image("dst", dst)
    kernel.dispatch("at_origin", src.size)

    var far := _texel(dst, dst.size.x - 2, dst.size.y - 2)
    assert_almost_eq(far.r, 64.0, 0.5, "The origin is the one that was said")
    assert_almost_eq(far.g, 32.0, 0.5, "on both axes")
    assert_almost_eq(far.a, 1.0, 1e-3, "and the far corner was written, so the size is the call's")
