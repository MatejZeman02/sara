## What a filter's `run` is handed.
##
## Every assertion here reads pixels back, because a copy from the wrong chunk
## or into the wrong corner of the texture returns a plausible picture rather
## than an error. The readback is `SaExport`'s, which is the door hard rule 1
## permits a test: nothing the context itself does leaves VRAM.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SaExportScript = preload("res://core/export/sa_export.gd")

## The fixture module, whose whole purpose is to own `one_line.gmacs` under a
## directory the shader index files as its owner.
const FIXTURE_MODULE = preload("res://tests/fixtures/modules/filter-fixture/module.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null
var _layer: SaLayer = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(1024, 1024))
    _doc = _easel.document
    _layer = _doc.active_layer


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _layer = null


## Two chunks of the active layer, side by side and each a flat colour, so a
## copy that reaches the wrong one says so in the colour rather than in a size.
func _paint_two_chunks() -> void:
    _layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)
    _layer.get_or_create_chunk(Vector2i(2, 1)).clear(GREEN)


func _context(module_id: StringName = &"") -> SaFilterContext:
    return SaFilterContext.new(_doc, _layer, module_id)


## One texel of *texture*, read the way an export reads it.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var image := SaExportScript.get_texture_image_float(texture)
    return image.get_pixel(x, y)


# ---------------------------------------------------------------------------
# The rectangle
# ---------------------------------------------------------------------------


func test_the_rectangle_is_the_allocated_bounds_grown_by_the_margin() -> void:
    _paint_two_chunks()

    var ctx := _context()

    assert_eq(ctx.rect_for(0), Rect2i(256, 256, 512, 256), "Two chunks side by side is what the layer has allocated")
    assert_eq(ctx.rect_for(8), Rect2i(248, 248, 528, 272), "and a margin grows it on every side, not just past the end")


func test_the_margin_is_clamped_to_the_canvas() -> void:
    _layer.get_or_create_chunk(Vector2i(0, 0)).clear(RED)

    var ctx := _context()

    assert_eq(ctx.rect_for(16), Rect2i(0, 0, 272, 272), "A margin off the top left corner stops at the canvas")


func test_a_selection_replaces_the_allocated_bounds() -> void:
    _paint_two_chunks()
    _doc.selection.select_rect(Rect2i(300, 300, 100, 40))

    var ctx := _context()

    assert_eq(ctx.rect_for(0), Rect2i(300, 300, 100, 40), "An active selection is the rectangle, whatever is allocated")
    assert_eq(ctx.rect_for(4), Rect2i(296, 296, 108, 48), "and the margin grows the selection")


func test_a_layer_with_nothing_allocated_answers_the_canvas() -> void:
    var ctx := _context()

    assert_eq(ctx.rect_for(0), Rect2i(0, 0, 1024, 1024), "A filter that generates has no painted bounds to work from")


# ---------------------------------------------------------------------------
# The pixels
# ---------------------------------------------------------------------------


func test_layer_pixels_copies_the_chunks_into_one_texture() -> void:
    _paint_two_chunks()

    var ctx := _context()
    var pixels := ctx.layer_pixels(8)

    assert_eq(pixels.size, Vector2i(528, 272), "The texture is the size of the rectangle it covers")
    assert_eq(ctx.rect, Rect2i(248, 248, 528, 272), "and the context says where that rectangle is")
    # Chunk (1,1) starts at 256,256, which is 8,8 in a texture whose origin is
    # 248,248. The two colours are what say the second chunk did not land on
    # the first.
    assert_almost_eq(_texel(pixels, 100, 100).r, 1.0, 1e-3, "The first chunk lands where the rectangle puts it")
    assert_almost_eq(_texel(pixels, 100, 100).g, 0.0, 1e-3, "and it is the red one")
    assert_almost_eq(_texel(pixels, 400, 100).g, 1.0, 1e-3, "The second chunk lands beside it")
    assert_almost_eq(_texel(pixels, 400, 100).r, 0.0, 1e-3, "and it is the green one")


func test_the_margin_past_the_painted_edge_reads_transparent() -> void:
    _paint_two_chunks()

    var pixels := _context().layer_pixels(8)

    assert_almost_eq(_texel(pixels, 2, 2).a, 0.0, 1e-6, "No chunk covers the margin, so a neighbourhood read finds nothing")
    assert_almost_eq(_texel(pixels, 8, 8).a, 1.0, 1e-3, "and the first painted texel is right against it")


func test_blank_like_is_the_same_size_and_depth_and_starts_empty() -> void:
    _paint_two_chunks()
    var ctx := _context()
    var pixels := ctx.layer_pixels(0)

    var blank := ctx.blank_like(pixels)

    assert_eq(blank.size, pixels.size, "A blank is the same size")
    assert_eq(blank.format, pixels.format, "and the same depth")
    assert_almost_eq(_texel(blank, 10, 10).a, 0.0, 1e-6, "and empty, which an allocation on its own is not")


# ---------------------------------------------------------------------------
# The module's own kernel
# ---------------------------------------------------------------------------


func test_a_bare_kernel_name_is_qualified_with_the_module() -> void:
    var module := FIXTURE_MODULE.new()
    var ctx := _context(module.get_id())

    assert_eq(ctx.kernel("one_line").shader_name, "filter-fixture/one_line", "A module's kernel is its own, not Sara's")
    assert_eq(ctx.kernel("sara/thumbnail").shader_name, "sara/thumbnail", "and a name already qualified is taken as written")


func test_the_same_name_answers_the_same_instance() -> void:
    var ctx := _context(FIXTURE_MODULE.new().get_id())

    var first := ctx.kernel("one_line")
    var again := ctx.kernel("one_line")

    assert_true(first == again, "A rerun per keystroke must not recompile the kernel")


func test_a_modules_kernel_dispatches_into_a_blank() -> void:
    _paint_two_chunks()
    var ctx := _context(FIXTURE_MODULE.new().get_id())
    var src := ctx.layer_pixels(0)
    var dst := ctx.blank_like(src)

    var kernel := ctx.kernel("one_line")
    kernel.run("one_line", {"dst": dst}, {"value": Color(0.25, 0.5, 0.75, 1.0)}, Rect2i(Vector2i.ZERO, dst.size))

    var written := _texel(dst, 5, 5)
    assert_almost_eq(written.r, 0.25, 1e-3, "The kernel a module owns resolved, compiled and ran")
    assert_almost_eq(written.g, 0.5, 1e-3, "and wrote what it was handed")
    assert_almost_eq(written.b, 0.75, 1e-3, "in every channel")
    assert_almost_eq(_texel(src, 5, 5).r, 1.0, 1e-3, "The source it read from is untouched")


# ---------------------------------------------------------------------------
# What show keeps
# ---------------------------------------------------------------------------


func test_show_keeps_the_texture_and_the_rectangle_it_belongs_to() -> void:
    _paint_two_chunks()
    var ctx := _context()
    var pixels := ctx.layer_pixels(4)
    var result := ctx.blank_like(pixels)

    ctx.show(result)

    assert_true(ctx.shown == result, "Apply writes what was last shown")
    assert_eq(ctx.shown_rect, Rect2i(252, 252, 520, 264), "over the rectangle the run that made it covered")
