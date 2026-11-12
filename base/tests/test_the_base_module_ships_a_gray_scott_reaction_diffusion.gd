## The base module ships Gray-Scott, a reaction-diffusion whose
## state is a field of its own rather than the paint, registered through the
## call a stranger's rule makes (hard rule 6).
##
## A disc of paint seeds the field from its cover. A thousand steps on, two
## documents seeded alike read the same texels to the byte, the field and the
## colour resolved from it, because the step binds no buffer and the seed's
## jitter is a hash of the cell. The layer's schema carries the field while the
## record is on and not after, every chunk's size is the sum of its fields'
## texels read through `SaFieldSpec.BYTES_PER_TEXEL`, and taking the record off
## leaves the colour last resolved as the paint. A saved document opens as that
## paint with the field beside it, and steps on from the field the file kept.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## One chunk, so a step is one dispatch and the pattern meets the canvas's edge.
const SIZE := Vector2i(256, 256)
## Three chunks in a row, the disc in the middle one, so the first step's ring
## grows the two beside it.
const ROW := Vector2i(768, 256)
const FIELD := &"gray_scott"
const STEP_SHADER := "sara-base-modules/gray_scott"
const COLOUR_SHADER := "sara-base-modules/gray_scott_colour"
## Sums of halves, so the painted colour's mean over the disc is exact.
const ORANGE := Color(0.75, 0.375, 0.125, 1.0)
const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const RADIUS := 24.0

var _registries: SaRegistries
var _base: BaseModule
var _easels: Array[SaEasel] = []
var _paths: Array[String] = []


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    _base = BaseModule.new()
    _base.register(_registries.context.for_module(_base.get_id()))


func after_each() -> void:
    for easel in _easels:
        easel.free()
    _easels.clear()
    for path in _paths:
        DirAccess.remove_absolute(path)
    _paths.clear()


## A canvas of *size* whose background holds only the chunk at *disc_at*, a
## disc of orange round its middle on transparent. A *soft* disc is a brush's
## dab, its cover a half in the middle falling to nought at its rim.
func _layer(size: Vector2i = SIZE, disc_at: Vector2i = Vector2i.ZERO, soft: bool = false) -> SaLayer:
    var easel := SaEasel.create_default(size)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    var albedo := layer.get_or_create_chunk(disc_at).albedo()
    var image := Image.create_empty(albedo.size.x, albedo.size.y, false, _image_format(albedo))
    image.fill(CLEAR)
    var middle := Vector2(albedo.size) / 2.0
    for y in albedo.size.y:
        for x in albedo.size.x:
            var apart := Vector2(x + 0.5, y + 0.5).distance_to(middle)
            if apart <= RADIUS:
                image.set_pixel(x, y, Color(ORANGE, 0.5 * (1.0 - apart / RADIUS)) if soft else ORANGE)
    GlobalShaderCompiler.get_rd().texture_update(albedo.rid, 0, image.get_data())
    easel.document.set_active_layer(layer)
    return layer


func _image_format(texture: SaTexture) -> Image.Format:
    match texture.format:
        RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
            return Image.FORMAT_RGBAH
        _:
            return Image.FORMAT_RGBAF


func _put(layer: SaLayer, values: Dictionary = {}) -> SaSimulationRecord:
    var found := _registries.simulation_rules.find(&"gray_scott")
    assert_not_null(found, "Gray-Scott is registered")
    return SaSimulation.put_on(layer, found, values)


func _step(layer: SaLayer, count: int = 1) -> void:
    var document := layer.get_parent() as SaDocument
    for _i in count:
        if not SaSimulation.step(document, layer, _registries.simulation_rules):
            assert_true(false, "The step is taken")
            return


## *field_id* of every chunk *layer* holds, in the order of its grid positions,
## as bytes.
func _bytes(layer: SaLayer, field_id: StringName) -> PackedByteArray:
    var out := PackedByteArray()
    var positions: Array = layer.chunks.keys()
    positions.sort()
    for grid_pos: Vector2i in positions:
        out.append_array(GlobalShaderCompiler.get_rd().texture_get_data(layer.get_field(grid_pos, field_id).rid, 0))
    return out


## The chunk at *grid_pos* of *layer*'s *field_id* as an image of floats.
func _image(layer: SaLayer, field_id: StringName, grid_pos: Vector2i = Vector2i.ZERO) -> Image:
    var texture := layer.get_field(grid_pos, field_id)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return Image.create_from_data(texture.size.x, texture.size.y, false, _image_format(texture), bytes)


## How many spots *image*'s alpha holds, each a patch of texels over a half
## joined side by side, and how many texels they cover.
func _spots(image: Image) -> Vector2i:
    var seen: Dictionary[Vector2i, bool] = {}
    var spots := 0
    var covered := 0
    for y in image.get_height():
        for x in image.get_width():
            var start := Vector2i(x, y)
            if seen.has(start) or image.get_pixelv(start).a <= 0.5:
                continue
            spots += 1
            var open: Array[Vector2i] = [start]
            seen[start] = true
            while not open.is_empty():
                var at: Vector2i = open.pop_back()
                covered += 1
                for beside: Vector2i in [at + Vector2i.LEFT, at + Vector2i.RIGHT, at + Vector2i.UP, at + Vector2i.DOWN]:
                    var inside := Rect2i(Vector2i.ZERO, image.get_size()).has_point(beside)
                    if inside and not seen.has(beside) and image.get_pixelv(beside).a > 0.5:
                        seen[beside] = true
                        open.append(beside)
    return Vector2i(spots, covered)


func test_gray_scott_comes_from_the_base_module_with_a_field_of_its_own() -> void:
    var found := _registries.simulation_rules.find(&"gray_scott")
    assert_not_null(found, "The base module registers Gray-Scott")
    assert_eq(found.label, "Gray-Scott", "under the name the painter reads")
    assert_eq(found.shader, "sara-base-modules/gray_scott", "its step in the base module's own file")
    assert_eq(found.reach, 1, "reading its eight neighbours, a reach of one")
    assert_eq(
        found.defaults,
        {"feed": 0.0367, "kill": 0.0649, "diffusion_u": 1.0, "diffusion_v": 0.5},
        "with Karl Sims's rates for spots that split"
    )
    assert_not_null(found.state, "Its state is a field of its own")
    assert_eq(found.state.field.id, FIELD, "called gray_scott")
    assert_false(found.state.field.is_color, "which holds concentrations and not colour")
    for kernel: String in [found.state.seed_kernel, found.state.colour_kernel]:
        assert_true(GlobalShaderCompiler.get_kernel_index(found.state.shader, kernel) >= 0, "%s compiles" % kernel)
    assert_true(GlobalShaderCompiler.get_kernel_index(found.shader, found.kernel) >= 0, "and so does the step")
    _registries.simulation_rules.unregister_module(_base.get_id())
    assert_null(_registries.simulation_rules.find(&"gray_scott"), "It goes with the module, as a stranger's rule does")


func test_a_rule_cannot_declare_a_field_the_layer_has_already() -> void:
    var stranger := _registries.context.for_module(&"k7-suite")
    var cases := [
        [SaFieldSpec.create(SaFieldSpec.ALBEDO, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false), "albedo"],
        [SaFieldSpec.mask(), "the mask"],
        [SaFieldSpec.height(), "height, which is sparse"],
        [SaFieldSpec.create(&"mine", RenderingDevice.DATA_FORMAT_R32G32_SFLOAT, false), "a depth no kernel stores"],
    ]
    for case: Array in cases:
        var state := {"field": case[0], "shader": COLOUR_SHADER, "seed": "gray_scott_seed", "colour": "gray_scott_colour"}
        var key := StringName("k7_%s" % (case[0] as SaFieldSpec).id)
        var taken := stranger.register_simulation_rule(key, "Mine", STEP_SHADER, "gray_scott", 1, {}, state)
        assert_false(taken, "%s is refused" % case[1])
        assert_null(_registries.simulation_rules.find(key), "and nothing is registered for %s" % case[1])
    var mine := SaFieldSpec.create(&"mine", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false)
    var unnamed := {"field": mine, "shader": COLOUR_SHADER}
    var refused := stranger.register_simulation_rule(&"k7_unnamed", "Mine", STEP_SHADER, "gray_scott", 1, {}, unnamed)
    assert_false(refused, "and so is a field whose kernels go unnamed")


func test_a_disc_steps_to_a_thousand_and_reads_the_same_texels_on_two_runs() -> void:
    var runs: Array[Array] = []
    for _run in 2:
        var layer := _layer()
        var record := _put(layer)
        assert_not_null(record, "Gray-Scott goes on a paint layer")
        _step(layer, 1000)
        assert_eq(record.steps, 1000, "A thousand steps are counted")
        layer.resolve_pending()
        runs.append([_bytes(layer, FIELD), _bytes(layer, SaFieldSpec.ALBEDO), _spots(_image(layer, SaFieldSpec.ALBEDO))])
    assert_true(runs[0][0] == runs[1][0], "The field is the same to the byte on the second run")
    assert_true(runs[0][1] == runs[1][1], "and so is the colour resolved from it")
    var spots: Vector2i = runs[0][2]
    assert_true(spots.x >= 4, "The disc has split into spots, %d of them" % spots.x)
    assert_true(2 * spots.y < SIZE.x * SIZE.y, "which cover less than half the canvas, %d texels" % spots.y)
    var soft := _layer(SIZE, Vector2i.ZERO, true)
    _put(soft)
    _step(soft, 1000)
    soft.resolve_pending()
    var dabbed := _spots(_image(soft, SaFieldSpec.ALBEDO))
    assert_true(dabbed.x >= 2, "A soft dab half covered in its middle splits too, into %d spots" % dabbed.x)


func test_the_colour_is_a_ramp_from_the_painted_colour() -> void:
    var layer := _layer()
    _put(layer)
    _step(layer, 400)
    layer.resolve_pending()
    var colour := _image(layer, SaFieldSpec.ALBEDO)
    var field := _image(layer, FIELD)
    var strongest := CLEAR
    var weakest := 1.0
    var others := 0
    var first_other := ""
    for y in range(0, SIZE.y, 4):
        for x in range(0, SIZE.x, 4):
            var shown := colour.get_pixel(x, y)
            var painted := Color(shown, 1.0).is_equal_approx(ORANGE)
            if not painted:
                others += 1
                if first_other.is_empty():
                    first_other = "(%d, %d) %s" % [x, y, shown]
            if shown.a > strongest.a:
                strongest = shown
            if field.get_pixel(x, y).g < 0.05:
                weakest = minf(weakest, shown.a)
    assert_eq(others, 0, "Every texel is the painted colour, the first other %s" % first_other)
    assert_eq(strongest.a, 1.0, "whole where the catalyst stands")
    assert_eq(weakest, 0.0, "and nought where it is spent")


func test_the_schema_holds_the_field_while_the_record_is_on_and_not_after() -> void:
    var layer := _layer()
    var painted := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    assert_null(SaFieldSpec.find(layer.schema, FIELD), "Before the record the schema has no field of the rule's")
    _put(layer)
    var field := SaFieldSpec.find(layer.schema, FIELD)
    assert_not_null(field, "With the record on, the schema holds the field")
    var albedo := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    assert_eq(albedo.derived_from, [FIELD] as Array[StringName], "beside an albedo worked out from it")
    assert_eq(albedo.format, painted.format, "at the document's depth")
    assert_true(layer.has_derived, "so the layer resolves before anyone reads its colour")
    assert_true(layer.chunks[Vector2i.ZERO].has_field(FIELD), "and the chunk holds a texture of it")
    assert_eq(SaSimulation.refusal(layer), "", "A rule put on in its place is not refused for the colour its field works out")
    _step(layer, 300)
    # Stale on purpose: taking the record off resolves it first.
    var kept := _image(layer, SaFieldSpec.ALBEDO).get_data()
    var twin := _layer()
    _put(twin)
    _step(twin, 300)
    twin.resolve_pending()
    var resolved := _image(twin, SaFieldSpec.ALBEDO).get_data()
    assert_false(kept == resolved, "Three hundred steps on, the colour is stale until resolved")
    SaSimulation.take_off(layer)
    assert_null(SaFieldSpec.find(layer.schema, FIELD), "Taking the record off takes the field out of the schema")
    assert_eq(SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO), painted, "and puts back the albedo as it was declared")
    assert_false(layer.has_derived, "painted again")
    assert_false(layer.chunks[Vector2i.ZERO].has_field(FIELD), "The chunk holds the field no more")
    assert_true(_image(layer, SaFieldSpec.ALBEDO).get_data() == resolved, "and its paint is the colour last resolved")
    layer.resolve_pending()
    assert_true(_image(layer, SaFieldSpec.ALBEDO).get_data() == resolved, "which nothing resolves over afterwards")


func test_every_chunks_byte_size_is_read_through_bytes_per_texel() -> void:
    var layer := _layer(ROW, Vector2i(1, 0))
    var record := _put(layer)
    var albedo := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    var field := SaFieldSpec.find(layer.schema, FIELD)
    var paint_texel: int = SaFieldSpec.BYTES_PER_TEXEL[albedo.format]
    var field_texel: int = SaFieldSpec.BYTES_PER_TEXEL[field.format]
    _step(layer)
    assert_eq(record.steps, 1, "One step is counted")
    assert_eq(layer.chunks.size(), 3, "and its ring grew the chunks either side of the disc")
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texels := chunk.pixel_size() * chunk.pixel_size()
        assert_eq(chunk.byte_size(), texels * (paint_texel + field_texel), "%s holds its paint and its field" % grid_pos)
    SaSimulation.take_off(layer)
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texels := chunk.pixel_size() * chunk.pixel_size()
        assert_eq(chunk.byte_size(), texels * paint_texel, "%s holds its paint alone once the record is off" % grid_pos)


func test_reset_seeds_the_field_again_and_another_rule_takes_its_place() -> void:
    var layer := _layer()
    _put(layer)
    var seeded := _bytes(layer, FIELD)
    _step(layer, 50)
    assert_false(_bytes(layer, FIELD) == seeded, "Fifty steps move the field")
    assert_true(SaSimulation.reset(layer.get_parent() as SaDocument, layer), "Reset is taken")
    assert_true(_bytes(layer, FIELD) == seeded, "and seeds the field again from the paint, to the byte")
    var spread := SaSimulation.put_on(layer, _registries.simulation_rules.find(&"spread"))
    assert_not_null(spread, "Spread goes on in its place")
    assert_null(SaFieldSpec.find(layer.schema, FIELD), "taking the field with Gray-Scott")
    var spread_reads := SaFieldSpec.find(layer.schema, SaFieldSpec.ALBEDO)
    assert_false(spread_reads.is_derived(), "and leaving the paint painted for Spread to step")


## A file keeps the field with the record: the layer opens as paint showing
## the colour last resolved, the field beside it, and the first step takes the
## field up where the file left it, so it reads what the saved document's own
## next step reads, the field and the colour, to the byte.
func test_a_saved_document_opens_as_paint_and_steps_on_from_the_field_it_kept() -> void:
    var layer := _layer()
    layer.name = "Simulated"
    _put(layer)
    _step(layer, 100)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("k7_gray_scott_reopened.sad"))
    _paths.append(path)
    assert_eq(SaExport.save_sad(layer.get_parent() as SaDocument, path, 0), OK, "The document is saved")
    var resolved := _bytes(layer, SaFieldSpec.ALBEDO)
    _step(layer)
    layer.resolve_pending()
    var stepped := _bytes(layer, FIELD)
    var coloured := _bytes(layer, SaFieldSpec.ALBEDO)
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    assert_eq(SaExport.load_sad(easel.document, path, easel.compositor), OK, "and opened")
    var back := easel.document.get_node_or_null("Simulated") as SaLayer
    var record := SaSimulation.record_of(back)
    assert_not_null(record, "with its record")
    if record == null:
        return
    assert_eq(record.steps, 100, "at the step it was saved at")
    assert_false(SaFieldSpec.find(back.schema, SaFieldSpec.ALBEDO).is_derived(), "The colour opens as paint")
    assert_eq(SaSimulation.refusal(back), "", "which takes a simulation")
    assert_false(SaFieldSpec.find(back.schema, FIELD).is_color, "beside the field, which a brush does not paint")
    assert_true(_bytes(back, SaFieldSpec.ALBEDO) == resolved, "showing the colour last resolved")
    _step(back)
    assert_true(record.colours(back), "The first step takes the field up again")
    assert_true(_bytes(back, FIELD) == stepped, "where the file left it, as the saved document steps on")
    back.resolve_pending()
    assert_true(_bytes(back, SaFieldSpec.ALBEDO) == coloured, "and colours it alike")
