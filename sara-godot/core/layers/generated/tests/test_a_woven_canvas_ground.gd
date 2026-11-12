## A woven canvas ground that never repeats.
##
## The canvas is a second ground beside the paper: two sets of threads
## crossing over and under, whose place, width, twist and tone wander by noise
## at the document position. The suite reads the ground's height back from the
## relief two weave periods apart and finds it different, and the same with the
## wander turned off, which proves the period is the period. It reads one
## place before and after a pan, the colour across a chunk edge, the weave
## standing whole under thick paint, which a stroke rather than the view
## fills, the swap of a paper for a canvas and its undo,
## and the rows the layers docker shows for each ground.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")

## The canvas's default tooth and spacing, and one weave period, which is two
## threads because a plain weave's over and under takes two to come round.
const TOOTH: float = 1.0
const SPACING: float = 8.0
const PERIOD: int = 16

var _registries: SaRegistries = null
var _easel: SaEasel = null
var _doc: SaDocument = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _easel = SaEasel.create_default(Vector2i(768, 768))
    _easel.compositor.set_registry(_registries.blend_modes)
    _doc = _easel.document
    _easel.process_pending_composite()


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _registries = null


func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


## A ground of *type_id* added under the active layer, which stays active.
func _add_ground(type_id: StringName) -> SaLayer:
    var paint := _doc.active_layer
    var ground := SaLayerOps.new(_doc).add(type_id, _registries.layer_types)
    _doc.set_active_layer(paint)
    _resolve()
    return ground


func _resolve() -> void:
    _doc.update_caches()
    _easel.request_full_composite()
    _easel.process_pending_composite()


## *texture*'s bytes and format, read now.
func _copy(texture: SaTexture) -> Array:
    return [GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0), texture.format, texture.size.x]


func _read(copy: Array, at: Vector2i) -> Color:
    return SaFieldSpec.decode_texel(copy[0], copy[1], at.y * int(copy[2]) + at.x)


func _height(at: Vector2i) -> float:
    return _texel(_easel.relief.heights, at).r


## How many of the places of a row a period apart stand differently high, of
## the places where a thread stands at all.
func _differing_pairs() -> Vector2i:
    var differing := 0
    var counted := 0
    for x in range(8, 700, 13):
        for y: int in [40, 300, 555]:
            var here := _height(Vector2i(x, y))
            var there := _height(Vector2i(x + PERIOD, y))
            if here < 0.01 and there < 0.01:
                continue
            counted += 1
            if absf(here - there) > 0.01:
                differing += 1
    return Vector2i(differing, counted)


func test_the_canvas_is_a_ground_registered_beside_the_paper() -> void:
    assert_true(_registries.layer_types.has(&"canvas"), "The canvas is a registered type")
    var descriptor := _registries.layer_types.get_descriptor(&"canvas")
    assert_eq(descriptor.generator, "canvas", "with its own generator")
    assert_true(SaGeneratedLayer.answers_height(descriptor), "which answers a height")
    assert_eq(descriptor.generator_view, "res://shaders/canvas/canvas.gdshader", "and draws beyond the document")
    assert_true(ResourceLoader.exists(descriptor.generator_view), "from a shader that is there")
    var ids: Array[StringName] = []
    for ground: SaLayerTypeDescriptor in SaGeneratedLayer.grounds(_registries.layer_types):
        ids.append(ground.id)
    var expected: Array[StringName] = [&"background", &"paper", &"canvas"]
    assert_eq(ids, expected, "The grounds are the solid colour, the paper and the canvas")
    var layer := _add_ground(&"canvas")
    assert_almost_eq(SaGeneratedLayer.tooth_of(layer), TOOTH, 0.0001, "A new canvas stands its threads' height")
    assert_eq(layer.chunks.size(), 0, "and stores nothing")


## The canvas's own three reach its kernel by the names its block declares,
## which is the door a module's own parameters take.
func test_the_canvas_hands_its_own_three_by_name() -> void:
    var layer := _add_ground(&"canvas")
    layer.generator_params["thickness"] = 0.7
    layer.generator_params["irregularity"] = 0.4
    layer.generator_params["angle"] = 12.0
    var values := SaGeneratedLayer.params_of(layer, Vector2.ZERO, Rect2i(0, 0, 8, 8))
    assert_eq(GlobalShaderCompiler.push_constant_bytes("canvas"), 96, "The canvas's block is the 96 bytes it declares")
    assert_almost_eq(float(values["thickness"]), 0.7, 0.0001, "the thickness under its own name")
    assert_almost_eq(float(values["irregularity"]), 0.4, 0.0001, "the irregularity under its own")
    assert_almost_eq(float(values["scale"]), SPACING, 0.0001, "the spacing as the scale")
    assert_almost_eq(float(values["weight"]), 1.0, 0.0001, "a weight of one for the colour")
    assert_almost_eq(float(values["angle"]), 12.0, 0.0001, "and the angle under its own")
    var paper := SaLayerOps.new(_doc).add(&"paper", _registries.layer_types)
    var flat := SaGeneratedLayer.params_of(paper, Vector2.ZERO, Rect2i(0, 0, 8, 8))
    assert_false(flat.has("thickness") or flat.has("angle"), "A paper's kernel declares none of them, so none is handed it")


func test_two_places_a_weave_period_apart_stand_differently() -> void:
    var canvas := _add_ground(&"canvas")
    var heights := _easel.relief.heights
    assert_not_null(heights, "A canvas resolves a height with no paint on it")
    if heights == null:
        return
    var wandering := _differing_pairs()
    assert_true(wandering.y > 100, "Threads stand at most of the places read, %d" % wandering.y)
    assert_true(
        wandering.x > wandering.y * 0.6,
        "and %d of %d places a period apart stand differently, so no repeat" % [wandering.x, wandering.y]
    )
    var highest := 0.0
    for x in range(0, 64):
        highest = maxf(highest, _height(Vector2i(x, 100)))
    assert_true(highest > TOOTH * 0.8 and highest <= TOOTH * 1.001, "The crowns stand the tooth high, %.3f" % highest)

    SaGeneratedLayer.set_param(_doc, canvas, SaGeneratedLayer.PARAM_IRREGULARITY, 0.0, "Canvas Irregularity")
    _resolve()
    var machine := _differing_pairs()
    assert_true(
        machine.x <= machine.y * 0.02,
        "With the wander off the weave repeats a period on, %d of %d differ, so the period is the period" % [machine.x, machine.y]
    )


func test_the_canvas_at_one_place_holds_through_a_pan() -> void:
    _easel.shown_rect = func() -> Rect2: return Rect2(0, 0, 100, 100)
    _add_ground(&"canvas")
    var at := Vector2i(290, 280)
    var before := _height(at)
    assert_true(before >= 0.0, "Before the pan the place has its height")
    var far := Vector2i(700, 700)
    assert_almost_eq(_height(far), 0.0, 0.0001, "and a place the window misses waits")
    _easel.shown_rect = func() -> Rect2: return Rect2(260, 250, 500, 500)
    _easel.request_full_composite()
    _easel.process_pending_composite()
    assert_almost_eq(_height(at), before, 0.0001, "After the pan the same place stands as high")
    assert_true(_height(far) >= 0.0, "and the place the pan reached is resolved")


func test_the_colour_agrees_across_a_chunk_edge() -> void:
    var canvas := _add_ground(&"canvas")
    var format := RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
    var whole := Rect2i(Vector2i.ZERO, Vector2i(256, 256))
    # The compositor hands back its one scratch, so the first chunk is copied
    # out before the second is generated over it.
    var left := _copy(_easel.compositor.generate_chunk(canvas, Vector2.ZERO, whole, format))
    var shifted := _easel.compositor.generate_chunk(canvas, Vector2(128.0, 0.0), whole, format)
    var spread := 0.0
    for x in range(0, 120, 7):
        var here := _texel(shifted, Vector2i(x, 50))
        var there := _read(left, Vector2i(x + 128, 50))
        assert_almost_eq(here.r, there.r, 0.0001, "The texel at document x %d is one colour from either chunk" % (x + 128))
        spread = maxf(spread, absf(here.r - _read(left, Vector2i(x, 50)).r))
    assert_true(spread > 0.02, "and the weave is not one colour, %.3f" % spread)


func test_the_weave_stands_whole_under_paint_a_millimetre_thick() -> void:
    _add_ground(&"canvas")
    var bare := PackedFloat32Array()
    for x in range(0, 64):
        bare.append(_height(Vector2i(256 + x, 40)))
    var layer := _doc.active_layer
    SaHeightOps.new(_doc).gain(layer)
    var texture := layer.get_or_create_field(Vector2i(1, 0), SaFieldSpec.HEIGHT)
    var bytes := PackedByteArray()
    bytes.resize(texture.size.x * texture.size.y * 2)
    for i in texture.size.x * texture.size.y:
        bytes.encode_half(i * 2, 1.0)
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, bytes)
    _doc.invalidate_chunks([Vector2i(1, 0)])
    _easel.process_pending_composite()
    for x in range(0, 64):
        var at := Vector2i(256 + x, 40)
        assert_almost_eq(_height(at), 1.0 + bare[x], 0.002, "Paint a millimetre thick at x %d stands on the whole weave" % at.x)
    var span: float = Array(bare).max() - Array(bare).min()
    assert_true(span > TOOTH * 0.5, "and the threads and the gaps between them differ by %.3f mm" % span)


func test_a_paper_swaps_for_a_canvas_in_one_step_and_back() -> void:
    var paper := _add_ground(&"paper")
    var paint := _doc.active_layer
    SaHeightOps.new(_doc).gain(paint)
    var field := paint.get_or_create_field(Vector2i(0, 0), SaFieldSpec.HEIGHT)
    var painted := GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)
    paper.opacity = 0.8
    _resolve()
    var paper_params := paper.generator_params.duplicate()
    var place := paper.get_index()
    var at := Vector2i(333, 211)
    var paper_height := _height(at)
    var paper_row: Array[float] = []
    for x in range(0, 64):
        paper_row.append(_height(Vector2i(x, 100)))
    var steps := _doc.undo_redo.get_history_count()

    SaGeneratedLayer.swap(_doc, paper, _registries.layer_types.get_descriptor(&"canvas"))
    _resolve()
    assert_eq(_doc.undo_redo.get_history_count(), steps + 1, "The swap is one history step")
    assert_eq(paper.layer_type, &"canvas", "The layer is a canvas")
    assert_eq(paper.generator, "canvas", "evaluating the weave")
    assert_true(paper.generator_params.has(SaGeneratedLayer.PARAM_THICKNESS), "with the canvas's own parameters")
    assert_almost_eq(paper.opacity, 0.8, 0.0001, "and its own opacity kept")
    assert_eq(paper.get_index(), place, "in its own place")
    var moved := 0
    for x in range(0, 64):
        if absf(_height(Vector2i(x, 100)) - paper_row[x]) > 0.01:
            moved += 1
    assert_true(moved > 16, "and the relief is the weave's, %d of 64 places moved" % moved)
    assert_eq(GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0), painted, "The paint above is untouched")

    _doc.undo()
    _resolve()
    assert_eq(paper.layer_type, &"paper", "The undo gives the paper back")
    assert_eq(paper.generator, "paper", "and its generator")
    assert_eq(paper.generator_params, paper_params, "with its parameters as they were left")
    assert_almost_eq(_height(at), paper_height, 0.0001, "and its grain in the relief")
    _doc.redo()
    assert_eq(paper.layer_type, &"canvas", "and the redo the canvas")

    var kind := paint.layer_type
    SaGeneratedLayer.swap(_doc, paint, _registries.layer_types.get_descriptor(&"canvas"))
    assert_eq(paint.layer_type, kind, "A layer that stores paint is never swapped")
    assert_false(paint.is_generated(), "and stays a layer that stores")


func test_the_weave_sliders_are_one_step_each() -> void:
    var canvas := _add_ground(&"canvas")
    SaGeneratedLayer.set_param(_doc, canvas, SaGeneratedLayer.PARAM_ANGLE, 10.0, "Canvas Angle")
    SaGeneratedLayer.set_param(_doc, canvas, SaGeneratedLayer.PARAM_ANGLE, 20.0, "Canvas Angle")
    assert_almost_eq(float(canvas.generator_params["angle"]), 20.0, 0.0001, "The angle moves")
    _doc.undo()
    assert_almost_eq(float(canvas.generator_params["angle"]), 0.0, 0.0001, "and a drag undoes in one step")


func test_the_rows_show_the_ground_and_swap_it() -> void:
    var rows := SaGroundRows.new()
    var paper := _add_ground(&"paper")
    rows.show_layer(_doc, paper, _registries.layer_types)
    assert_true(rows.visible, "A paper shows the ground rows")
    assert_true(rows.ground_choice.get_parent().visible, "with the choice of ground")
    var grounds: Array[StringName] = [&"background", &"paper", &"canvas"]
    assert_eq(rows.ground_choice.choice_values(), grounds, "between the solid colour, the paper and the canvas")
    assert_false(rows.weave_sliders["thickness"].get_parent().visible, "and no weave rows for a paper")

    rows.ground_choice.choice_picked.emit(&"canvas")
    assert_eq(paper.layer_type, &"canvas", "A pick swaps the ground")
    rows.show_layer(_doc, paper, _registries.layer_types)
    for key: String in ["scale", "thickness", "irregularity", "angle"]:
        assert_true(rows.weave_sliders[key].get_parent().visible, "The canvas shows its %s row" % key)
    assert_almost_eq(rows.weave_sliders["scale"].value, SPACING, 0.0001, "at the canvas's own value")
    rows.weave_sliders["thickness"].value_changed.emit(0.5)
    assert_almost_eq(float(paper.generator_params["thickness"]), 0.5, 0.0001, "and a slider writes the layer")

    rows.show_layer(_doc, _doc.active_layer, _registries.layer_types)
    assert_false(rows.visible, "A layer that stores paint shows no ground rows")
    rows.free()
