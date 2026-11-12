## The selection mask: one document-wide sparse set of r32f chunks that the
## paint and fill kernels read.
##
## The rule under test is the unit's own: a dab outside the mask writes
## nothing. Everything here reads pixels back, because a mask that is bound at
## the wrong format returns plausible numbers rather than an error.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const PaintKernel = preload("res://tests/fixtures/paint_kernel.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)

var _easel: SaEasel = null
var _doc: SaDocument = null


## Two by two chunks, so a selection can leave whole chunks out.
func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null


## One texel of a chunk field, read back.
func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


## One hard red dab straight into the active layer, the way an erase or an
## alpha-locked stroke lands, so the result can be read off the layer itself.
func _dab(pos: Vector2, radius: float) -> SaPaintContext:
    var compute := PaintKernel.compute()
    var region := Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
    var paint := SaPaintContext.for_region(_doc, region, true)
    paint.dispatch_batch(
        compute,
        "paint",
        func(target: SaPaintContext.Target) -> void:
            compute.set_texture(0, target.texture.rid)
            compute.set_push_constant_float_array(
                PaintKernel.pack_params(paint.local_point(target, pos), target.render_offset, RED, radius, 1.0, 1.0, 1.0)
            )
    )
    paint.commit_invalidation()
    return paint


func _layer_texel(x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := _doc.active_layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    return _texel(texture, x - grid.x * SaChunk.SIZE, y - grid.y * SaChunk.SIZE)


func test_both_kernels_declare_the_mask_at_its_own_format() -> void:
    PaintKernel.compile()
    for kernel: String in [PaintKernel.NAME, "fill"]:
        var layout := GlobalShaderCompiler.binding_layout(kernel)
        assert_eq(layout.get(SaSelection.BINDING, {}).get("kind", ""), "image", "%s binds the mask as an image" % kernel)
        assert_eq(layout.get(SaSelection.BINDING, {}).get("format", ""), "r32f", "at r32f whatever the canvas is")


## No selection is not a flag, it is a 1 by 1 mask that reads as 1.0 everywhere.
func test_without_a_selection_a_dab_paints_through_the_everything_stand_in() -> void:
    assert_false(_doc.selection.active, "A fresh document has no selection")
    var paint := _dab(Vector2(100, 100), 20.0)

    assert_eq(paint.targets.size(), 1, "One chunk")
    assert_eq(paint.targets[0].mask, _doc.selection.everything(), "bound to the stand-in")
    assert_eq(_doc.selection.everything().size, Vector2i(1, 1), "which is one texel")
    assert_almost_eq(_layer_texel(100, 100).r, 1.0, 1e-4, "and the dab painted")
    assert_almost_eq(_layer_texel(100, 100).a, 1.0, 1e-4, "fully")


## The unit's own line: a dab outside the mask writes nothing.
func test_a_dab_outside_the_selection_writes_nothing() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))

    _dab(Vector2(200, 100), 20.0)
    assert_almost_eq(_layer_texel(200, 100).a, 0.0, 1e-6, "Outside the rectangle the layer is untouched")

    _dab(Vector2(100, 100), 20.0)
    assert_almost_eq(_layer_texel(100, 100).r, 1.0, 1e-4, "Inside it the dab lands")


## A dab straddling the edge is cut at the edge, to the pixel.
func test_a_dab_across_the_edge_stops_at_the_edge() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))

    _dab(Vector2(128, 64), 20.0)

    assert_almost_eq(_layer_texel(127, 64).a, 1.0, 1e-4, "The last selected column is painted")
    assert_almost_eq(_layer_texel(128, 64).a, 0.0, 1e-6, "and the first unselected one is not")


## A chunk the selection leaves out is not even a target: nothing is dispatched
## there and no chunk is allocated where paint could not land.
func test_a_chunk_the_selection_leaves_out_is_not_a_target() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))

    var paint := _dab(Vector2(384, 384), 20.0)

    assert_true(paint.is_empty(), "No target in an unselected chunk")
    assert_null(_doc.active_layer.get_field(Vector2i(1, 1)), "and no chunk was allocated for it")


func test_a_rectangle_allocates_only_the_chunks_it_touches_and_is_exact() -> void:
    _doc.selection.select_rect(Rect2i(10, 10, 50, 50))
    assert_eq(_doc.selection.chunks.size(), 1, "A small rectangle is one chunk")
    var mask := _doc.selection.texture_for(Vector2i(0, 0))
    assert_almost_eq(_texel(mask, 30, 30).r, 1.0, 1e-6, "selected inside")
    assert_almost_eq(_texel(mask, 59, 59).r, 1.0, 1e-6, "up to its last pixel")
    assert_almost_eq(_texel(mask, 60, 60).r, 0.0, 1e-6, "and not one pixel further, whatever the workgroup alignment")
    assert_almost_eq(_texel(mask, 9, 30).r, 0.0, 1e-6, "nor before it starts")

    _doc.selection.select_rect(Rect2i(200, 200, 200, 200))
    assert_eq(_doc.selection.chunks.size(), 4, "A rectangle over the chunk seams touches all four")
    assert_almost_eq(
        _texel(_doc.selection.texture_for(Vector2i(1, 1)), 0, 0).r, 1.0, 1e-6, "with the far chunk's corner selected"
    )


func test_select_all_and_deselect() -> void:
    _doc.selection.select_all(_doc.canvas_size)
    assert_eq(_doc.selection.chunks.size(), 4, "Select all covers every chunk of the canvas")
    assert_almost_eq(_texel(_doc.selection.texture_for(Vector2i(1, 0)), 100, 100).r, 1.0, 1e-6, "fully")

    _doc.selection.deselect()
    assert_false(_doc.selection.active, "Deselect ends the selection")
    assert_eq(_doc.selection.chunks.size(), 0, "and frees its chunks")
    assert_eq(_doc.selection.texture_for(Vector2i(1, 0)), _doc.selection.everything(), "so everything is selected again")


## A fill is a clear today, and a clear cannot leave the unselected pixels
## alone, so a selection turns it into the kernel with the mask bound.
func test_a_fill_respects_the_selection() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 128, 128))

    _doc.active_layer.fill(RED)

    assert_almost_eq(_layer_texel(64, 64).r, 1.0, 1e-4, "Inside the selection the fill lands")
    assert_almost_eq(_layer_texel(300, 300).a, 0.0, 1e-6, "outside it the layer keeps what it had")
    assert_almost_eq(_layer_texel(200, 64).a, 0.0, 1e-6, "even inside a chunk the selection only partly covers")


func test_a_new_document_starts_without_the_old_selection() -> void:
    _doc.selection.select_rect(Rect2i(0, 0, 64, 64))
    _doc.reset_to_default(Vector2i(256, 256))
    assert_false(_doc.selection.active, "File > New drops the selection")


## The overlay's shader is loaded at runtime and compiled by the renderer, so a
## mistake in it is a console line and a selection with no ants, which no other
## check here sees: gdformat, gdlint and the LSP all ignore `.gdshader`. One met
## this the short way, with `const float TAU` where the shading language already
## has one, and the app ran with the outline gone. An empty uniform list is what
## a shader that failed to compile answers.
func test_the_selection_shader_compiles_and_declares_its_ant_uniforms() -> void:
    var shader: Shader = load("res://shaders/canvas/selection.gdshader")
    var declared: Array[String] = []
    for entry: Dictionary in shader.get_shader_uniform_list():
        declared.append(String(entry["name"]))

    assert_false(declared.is_empty(), "An empty uniform list means the shader failed to compile")
    for written: String in ["quick_mask", "tint", "ant_dark", "ant_light", "ant_period", "ant_speed"]:
        assert_true(declared.has(written), "The selection shader declares %s" % written)
