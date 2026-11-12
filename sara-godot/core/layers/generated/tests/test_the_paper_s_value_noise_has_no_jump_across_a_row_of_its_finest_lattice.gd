## The paper's value noise has no jump across a row of its finest lattice.
## A paper at a scale of 40 over a 1920 by 1080 document
## jumped by about thirty levels of 255 between two texels at rows of its
## finest cell, ten texels, on a desktop GPU, because the float hash read a
## corner two cells share through two expressions. The corners are hashed as
## integers now. This suite draws the paper through its kernel, the fixture's
## noise ground through its own, and both their view shaders past the document,
## and holds that no two neighbouring texels differ by more than value noise can
## change over one texel.
extends "res://tests/test_framework.gd"

## Kernels and view shaders both run on the GPU.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const FIXTURE_MODULE = preload("res://tests/fixtures/noise-ground/modules/noise-ground-fixture/module.gd")

const PAPER_VIEW := "res://shaders/canvas/paper.gdshader"
const GROUND_VIEW := "res://tests/fixtures/noise-ground/modules/noise-ground-fixture/noise_ground.gdshader"

## The document and the scale of the evidence.
const SIZE := Vector2i(1920, 1080)
const SCALE := 40.0

## The paper's three octaves, `sa_value_fbm`'s count.
const PAPER_OCTAVES := 3

## The largest slope of the smoothstep `3f^2 - 2f^3` over a cell, `6f(1 - f)` at
## a half.
const SMOOTHSTEP_SLOPE := 1.5

## What a kernel's float arithmetic may add to a step, read as float texels.
const KERNEL_SLACK := 0.0001

## What a view shader drawn into an eight-bit viewport may add to a step: each
## of the two pixels rounds by up to half a level.
const VIEW_SLACK := 1.0 / 255.0

## How far a view shader's pixel may sit from its kernel's texel: the eight-bit
## rounding and a level more for the float arithmetic of the two sides.
const AGREE := 2.0 / 255.0

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    FIXTURE_MODULE.new().register(_registries.context.for_module(FIXTURE_MODULE.ID))
    _easel = SaEasel.create_default(SIZE)
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


## The largest step between two neighbouring texels of value noise of
## *octaves* octaves whose first cell is *scale* texels wide.
##
## Value noise is `mix(mix(a, b, s(x)), mix(c, d, s(x)), s(y))` with every
## corner in 0 to 1, so along x its slope is `s'(x)` times a blend of `b - a`
## and `d - c`, at most `SMOOTHSTEP_SLOPE` per cell, and along y the same. A
## texel is `1 / scale` of the first octave's cell, and each octave after it is
## twice as fine at half the amplitude, so octave *i* moves by at most
## `amplitude_i * SMOOTHSTEP_SLOPE * 2^i / scale` over a texel. The fbm divides
## the sum by the amplitudes' total, so the bound is divided by it too. By the
## mean value theorem no step over one texel exceeds the largest slope, and a
## jump in the hash, which has no slope to speak of, does.
static func _bound(scale: float, octaves: int) -> float:
    var slope := 0.0
    var weight := 0.0
    var amplitude := 0.5
    var frequency := 1.0
    for i in octaves:
        slope += amplitude * SMOOTHSTEP_SLOPE * frequency / scale
        weight += amplitude
        amplitude *= 0.5
        frequency *= 2.0
    return slope / weight


## A ground of *type*, its first colour black and its second white, so a
## texel's red is the noise itself. A paper's fibres are off, because the
## bound this suite holds is the value noise's and a fibre's crest is steeper.
func _add_ground(type: StringName) -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(type, _registries.layer_types)
    _doc.set_active_layer(paint)
    if ground.generator_params.has("fibre"):
        ground.generator_params["fibre"] = 0.0
    ground.generator_params[SaGeneratedLayer.PARAM_COLOR] = Color.BLACK
    ground.generator_params[SaGeneratedLayer.PARAM_SECOND] = Color.WHITE
    SaGeneratedLayer.set_param(_doc, ground, SaGeneratedLayer.PARAM_SCALE, SCALE, "Scale")
    return ground


## The red of every texel *ground*'s kernel writes over the document, row by
## row, as float texels, through the compositor's door the export takes, a
## chunk at a time.
func _kernel_reds(ground: SaLayer) -> PackedFloat32Array:
    var reds := PackedFloat32Array()
    reds.resize(SIZE.x * SIZE.y)
    var side := SaLayer.CHUNK_SIZE
    for top in range(0, SIZE.y, side):
        for left in range(0, SIZE.x, side):
            var texture := _easel.compositor.generate_chunk(
                ground, Vector2(left, top), Rect2i(0, 0, side, side), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
            )
            var floats := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0).to_float32_array()
            var width: int = texture.size.x
            for y in mini(side, SIZE.y - top):
                for x in mini(side, SIZE.x - left):
                    reds[(top + y) * SIZE.x + left + x] = floats[(y * width + x) * 4]
    return reds


## The red of every pixel *shader* draws over the document's rectangle at 100
## percent, black to white, with *extra* parameters, row by row.
func _view_reds(shader: String, extra: Dictionary) -> PackedFloat32Array:
    var material := ShaderMaterial.new()
    material.shader = load(shader)
    material.set_shader_parameter("color_a", Color.BLACK)
    material.set_shader_parameter("color_b", Color.WHITE)
    material.set_shader_parameter("scale", SCALE)
    material.set_shader_parameter("rect_origin", Vector2.ZERO)
    material.set_shader_parameter("rect_size", Vector2(SIZE))
    for key: String in extra:
        material.set_shader_parameter(key, extra[key])
    var viewport := SubViewport.new()
    viewport.size = SIZE
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, material.get_rid())
    RenderingServer.canvas_item_add_rect(item, Rect2(Vector2.ZERO, Vector2(SIZE)), Color.WHITE)
    RenderingServer.force_draw(false, 0.0)
    var image := viewport.get_texture().get_image()
    RenderingServer.free_rid(item)
    viewport.free()
    image.convert(Image.FORMAT_RGBA8)
    var bytes := image.get_data()
    var reds := PackedFloat32Array()
    reds.resize(SIZE.x * SIZE.y)
    for i in reds.size():
        reds[i] = bytes[i * 4] / 255.0
    return reds


## Every row whose step to the row above it exceeds *bound*, with the largest
## step anywhere along either axis, as `{"rows", "columns", "largest"}`.
static func _steps_over(reds: PackedFloat32Array, bound: float) -> Dictionary:
    var rows: Array[int] = []
    var columns: Array[int] = []
    var largest := 0.0
    for y in SIZE.y:
        var row_over := false
        for x in SIZE.x:
            var at := y * SIZE.x + x
            if x > 0:
                var across := absf(reds[at] - reds[at - 1])
                largest = maxf(largest, across)
                if across > bound and not columns.has(x):
                    columns.append(x)
            if y > 0:
                var down := absf(reds[at] - reds[at - SIZE.x])
                largest = maxf(largest, down)
                row_over = row_over or down > bound
        if row_over:
            rows.append(y)
    return {"rows": rows, "columns": columns, "largest": largest}


## The largest difference between two readings of the same texels.
static func _apart(one: PackedFloat32Array, other: PackedFloat32Array) -> float:
    var largest := 0.0
    for i in one.size():
        largest = maxf(largest, absf(one[i] - other[i]))
    return largest


func _assert_smooth(reds: PackedFloat32Array, bound: float, what: String) -> void:
    var found := _steps_over(reds, bound)
    var rows: Array[int] = found["rows"]
    var columns: Array[int] = found["columns"]
    assert_eq(rows.size(), 0, "%s steps past %.4f at no row, and did at %s" % [what, bound, rows.slice(0, 30)])
    assert_eq(columns.size(), 0, "%s steps past %.4f at no column, and did at %s" % [what, bound, columns.slice(0, 30)])
    assert_true(float(found["largest"]) > bound * 0.3, "and its grain is noise, its largest step %.4f" % float(found["largest"]))


func test_the_papers_kernel_has_no_step_the_noise_cannot_take() -> void:
    var paper := _add_ground(&"paper")
    var bound := _bound(SCALE, PAPER_OCTAVES) + KERNEL_SLACK
    _assert_smooth(_kernel_reds(paper), bound, "The paper's kernel at a scale of 40")


func test_the_noise_ground_fixtures_kernel_has_none_either() -> void:
    var ground := _add_ground(FIXTURE_MODULE.TYPE)
    var octaves := int(SaTyped.float_at(ground.generator_params, FIXTURE_MODULE.PARAM_OCTAVES, 0.0))
    assert_eq(octaves, 5, "The fixture opens with five octaves")
    _assert_smooth(_kernel_reds(ground), _bound(SCALE, octaves) + KERNEL_SLACK, "The noise ground's kernel")


## Past the document the paper is `paper.gdshader`'s copy of the noise, at 100
## percent a texel a pixel, which fades nothing.
func test_the_paper_past_the_document_has_none_and_agrees_with_its_kernel() -> void:
    var paper := _add_ground(&"paper")
    var shown := _view_reds(PAPER_VIEW, {"texels_per_pixel": 1.0, "relief_enabled": false})
    _assert_smooth(shown, _bound(SCALE, PAPER_OCTAVES) + VIEW_SLACK, "The paper past the document")
    var apart := _apart(shown, _kernel_reds(paper))
    assert_true(apart <= AGREE, "and it draws the kernel's texels, %.4f apart at most" % apart)


func test_the_noise_ground_past_the_document_has_none_and_agrees_with_its_kernel() -> void:
    var ground := _add_ground(FIXTURE_MODULE.TYPE)
    var shown := _view_reds(GROUND_VIEW, {"octaves": 5.0, "seed": 0.0})
    _assert_smooth(shown, _bound(SCALE, 5) + VIEW_SLACK, "The noise ground past the document")
    var apart := _apart(shown, _kernel_reds(ground))
    assert_true(apart <= AGREE, "and it draws the kernel's texels, %.4f apart at most" % apart)
