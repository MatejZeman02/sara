## A simulation's step can be a pixel function, and `step` and
## `t` are names it reads
##
## The fixture module under `tests/fixtures/life-pixel/modules` registers the Game of
## Life, a pixel function of eighteen lines, as a rule through the pixel
## function's own call, and Clock, a pixel function filter whose picture is
## its time. Life steps a glider across a chunk edge, so the halo the rule's
## reach declares is read as the previous state of the chunk beside it, and
## Clock is played through the time row as the other fixture is. A rule that
## writes `step` reads the simulation's count, and a `uniform` that takes one
## of the two names, or one too wide for a step that binds no buffer, is
## refused.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const LifeModule = preload("res://tests/fixtures/life-pixel/modules/life-pixel-fixture/module.gd")
const PixelFunction = preload("res://core/custom-shader/compiler/sa_pixel_function.gd")
const PixelSource = preload("res://core/custom-shader/dialect/sa_pixel_source.gd")

const REQUIRES_GPU := true

const HERE := "res://tests/fixtures/life-pixel/modules/life-pixel-fixture"
const OWNER: StringName = &"life-pixel-fixture"

## Two chunks side by side, so the glider has a chunk edge to cross.
const SIZE := Vector2i(512, 256)
const INK := Color(0.0, 0.0, 0.0, 1.0)
const ROW := 10

## The glider as Conway drew it, heading down and to the right, by cell.
const GLIDER: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]

## Frames as the other suite plays them, unequal, so the sum is no count of one.
const FRAMES: Array[float] = [1.0 / 60.0, 1.0 / 30.0, 0.05, 1.0 / 60.0, 1.0 / 144.0]

## A texel well inside the filtered layer.
const AT := Vector2i(20, 30)

var _registries: SaRegistries = null
var _easels: Array[SaEasel] = []


func before_each() -> void:
    SaProblems.pending = PackedStringArray()
    SaProblems.pending_refusals = PackedStringArray()
    _registries = Fixtures.make_registries()
    var module := LifeModule.new()
    module.register(_registries.context.for_module(module.get_id()))


func after_each() -> void:
    SaProblems.announce = true
    for easel in _easels:
        easel.free()
    _easels.clear()
    _registries = null


## A canvas of two chunks whose background holds both, transparent, active.
func _layer() -> SaLayer:
    var easel := SaEasel.create_default(SIZE)
    _easels.append(easel)
    var layer := easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        _fill(layer.get_or_create_chunk(grid_pos).albedo(), {})
    easel.document.set_active_layer(layer)
    return layer


## *texture* transparent but for the texels of *texels*, position to colour.
func _fill(texture: SaTexture, texels: Dictionary) -> void:
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAH if half else Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 0.0))
    for at: Vector2i in texels:
        image.set_pixelv(at, texels[at])
    GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())


## Every texel holding paint across the layer's two chunks, in layer texels,
## to its colour.
func _painted(layer: SaLayer) -> Dictionary[Vector2i, Color]:
    var out: Dictionary[Vector2i, Color] = {}
    for grid_pos: Vector2i in [Vector2i(0, 0), Vector2i(1, 0)]:
        var texture := layer.get_field(grid_pos)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in texture.size.y:
            for x in texture.size.x:
                var texel := SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)
                if texel.a != 0.0:
                    out[grid_pos * texture.size + Vector2i(x, y)] = texel
    return out


func _texel(layer: SaLayer, grid_pos: Vector2i, at: Vector2i) -> Color:
    var texture := layer.get_field(grid_pos)
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


func _step(layer: SaLayer, count: int) -> void:
    var document := layer.get_parent() as SaDocument
    for _i in count:
        assert_true(SaSimulation.step(document, layer, _registries.simulation_rules), "The step is taken")


func test_life_in_under_twenty_lines_is_a_rule_of_the_rule_form() -> void:
    var text := FileAccess.get_file_as_string(HERE.path_join("life.gmacs"))
    var lines := text.strip_edges(false, true).split("\n").size()
    assert_true(lines < 20, "Life is a pixel function of %d lines, under twenty" % lines)
    var found := _registries.simulation_rules.find(LifeModule.LIFE)
    assert_true(found is PixelFunction.Rule, "It is registered as a rule through the pixel function's call")
    if not found is PixelFunction.Rule:
        return
    assert_eq(found.label, "Life in Pixels", "under the label the module gave it")
    assert_eq(found.shader, "life-pixel-fixture/life_rule", "Its kernel is the rule form, filed under the module")
    assert_eq(found.kernel, "life", "named after the file")
    assert_eq(found.reach, 1, "with the reach the module declared")
    assert_almost_eq(SaTyped.real(found.defaults.get("alive")), 0.5, 1e-6, "Its uniform is a parameter, at its default")
    var rule := found as PixelFunction.Rule
    assert_eq(rule.uniforms.size(), 1, "and the rule keeps the one uniform for the panel's slider")
    var names := PackedStringArray()
    for raw: Variant in GlobalShaderCompiler.push_constant_layout(found.shader):
        names.append(SaTyped.text_at(SaTyped.strings(raw), "name", ""))
    for wanted: String in ["origin", "chunk", "halo", "step", "t", "alive"]:
        assert_true(wanted in names, "The rule form declares `%s`" % wanted)
    assert_false("doc_to_linear_srgb" in names, "and no colour space, since a step is handed no document")


func test_life_moves_a_glider_one_cell_down_and_right_in_four_steps_across_a_chunk_edge() -> void:
    var layer := _layer()
    var side := layer.get_field(Vector2i(0, 0)).size.x
    # The glider's right column on the last texel of the first chunk, so the
    # cell born past it at step four is born from the halo across the edge.
    var corner := Vector2i(side - 3, ROW)
    var glider: Dictionary = {}
    for cell: Vector2i in GLIDER:
        glider[corner + cell] = INK
    _fill(layer.get_field(Vector2i(0, 0)), glider)
    var record := SaSimulation.put_on(layer, _registries.simulation_rules.find(LifeModule.LIFE))
    assert_not_null(record, "The pixel function's rule goes on a paint layer")
    if record == null:
        return
    _step(layer, 4)
    assert_eq(record.steps, 4, "Four steps are counted")
    var painted := _painted(layer)
    var moved: Array[Vector2i] = []
    for cell: Vector2i in GLIDER:
        moved.append(corner + cell + Vector2i(1, 1))
    assert_eq(painted.size(), GLIDER.size(), "Five cells live at step four, and nothing else holds paint")
    for at: Vector2i in moved:
        assert_true(painted.has(at), "%s lives, one down and one right of where it was painted" % at)
        if painted.has(at):
            assert_eq(painted[at], INK, "in black")
    assert_true(painted.has(Vector2i(side, ROW + 3)), "The right column is now the next chunk's first")


func test_a_rule_reads_step_as_the_count_and_t_as_nought() -> void:
    var counted := "\n".join(["def pixel(ivec2 at) -> vec4:", "    return vec4(float(step), t, 0.0, 1.0)"])
    var ctx := _registries.context.for_module(OWNER)
    var made := PixelFunction.register_rule(ctx, HERE.path_join("counted.gmacs"), &"counted", "Counted", 0, counted)
    assert_true(made, "A pixel function that reads `step` is registered as a rule")
    var layer := _layer()
    var record := SaSimulation.put_on(layer, _registries.simulation_rules.find(&"counted"))
    assert_not_null(record, "and goes on a paint layer")
    if record == null:
        return
    _step(layer, 3)
    var texel := _texel(layer, Vector2i(1, 0), Vector2i(5, 5))
    assert_eq(record.steps, 3, "Three steps are counted")
    assert_almost_eq(texel.r, 2.0, 1e-6, "and the third read `step` as 2, the first being nought")
    assert_almost_eq(texel.g, 0.0, 1e-6, "while `t` reads nought, a simulation having no time")


func test_a_filter_that_reads_t_declares_k1s_time_row_and_follows_the_time_it_plays() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    _easels.append(easel)
    easel.compositor.set_registry(_registries.blend_modes)
    var filters := SaFilterRegistry.new()
    var clock := SaPixelFilter.new(HERE.path_join("clock.gmacs"))
    assert_true(clock.pixels.reads_time, "Clock reads `t`")
    assert_false(Bench.threshold().pixels.reads_time, "where Threshold does not, and keeps its dialog as it was")
    filters.register(clock, OWNER)
    var key := SaFilterRegistry.key_for(OWNER, clock)
    easel.compositor.filter_chain.registry = filters
    var doc := easel.document
    doc.active_layer.fill(Color(0.25, 0.25, 0.25, 1.0))
    var record := SaFilterOps.new(doc).attach(doc.active_layer, key, {})
    Bench.composite(easel)
    assert_almost_eq(Bench.texel(easel.output, AT).r, 0.0, 1e-4, "At nought the picture is nought")
    var panel := SaFilterPanel.new(record, filters.get_filter(key), doc)
    var scrubber := panel.find_child(SaTimeRow.Scrubber.NODE_NAME, true, false) as SaTimeRow.Scrubber
    assert_not_null(scrubber, "The attached record's panel holds the scrubber")
    if scrubber != null:
        scrubber.play(true)
        var played := 0.0
        for seconds: float in FRAMES:
            scrubber.advance(seconds)
            panel.dialog.flush_rerun()
            played += seconds
            Bench.composite(easel)
            assert_almost_eq(Bench.texel(easel.output, AT).r, played, 1e-4, "The picture follows the time, at %f" % played)
        scrubber.play(false)
        var recorded := SaTyped.real(record.parameters.get(String(SaTimeRow.KEY)), -1.0)
        assert_almost_eq(recorded, played, 1e-5, "and the record holds the time it stopped at")
    panel.free()


func test_a_uniform_named_step_or_t_is_refused_with_its_line() -> void:
    for taken: String in [PixelSource.STEP_FIELD, PixelSource.TIME_FIELD]:
        var text := "\n".join(
            [
                "# Takes a name the wrapper gives.",
                "",
                "uniform float %s = 1.0" % taken,
                "",
                "def pixel(ivec2 at) -> vec4:",
                "    return src(at)"
            ]
        )
        var function := PixelFunction.new(HERE.path_join("taken.gmacs"), text)
        var said := "line 3 names a uniform `%s`, which the wrapper declares itself." % taken
        assert_true(said in function.problems, "`uniform float %s` is refused: %s" % [taken, function.problems])
    SaProblems.announce = false
    var stepped := "\n".join(["uniform float step = 1.0", "", "def pixel(ivec2 at) -> vec4:", "    return src(at)"])
    var ctx := _registries.context.for_module(OWNER)
    var made := PixelFunction.register_rule(ctx, HERE.path_join("stepped.gmacs"), &"stepped", "Stepped", 1, stepped)
    assert_false(made, "No rule is made of it")
    assert_null(_registries.simulation_rules.find(&"stepped"), "and none is registered")
    assert_true(
        "SaPixelFunction: stepped.gmacs: line 1 names a uniform `step`, which the wrapper declares itself." in SaProblems.pending,
        "The refusal is reported with its line: %s" % [SaProblems.pending]
    )


func test_a_uniform_too_wide_for_the_push_constant_is_refused_as_a_rule() -> void:
    SaProblems.announce = false
    var wide := "\n".join(["uniform float weights[49]", "", "def pixel(ivec2 at) -> vec4:", "    return src(at) * weights[24]"])
    var ctx := _registries.context.for_module(OWNER)
    var made := PixelFunction.register_rule(ctx, HERE.path_join("wide.gmacs"), &"wide", "Wide", 1, wide)
    assert_false(made, "No rule is made of it")
    assert_null(_registries.simulation_rules.find(&"wide"), "and none is registered")
    var said := (
        "SaPixelFunction: wide.gmacs: `weights` is too wide for the push constant,"
        + " and a simulation's step binds no buffer to carry it."
    )
    assert_true(said in SaProblems.pending, "It says which uniform: %s" % [SaProblems.pending])


## A library a student imports may call GLSL's `step()` itself, as the sRGB
## curve does, so every form pastes it above the params block, where the field
## does not yet hide the built-in.
func test_a_library_that_calls_step_compiles_above_the_field() -> void:
    var lines := ["import linear_srgb_color_space", "", "def pixel(ivec2 at) -> vec4:", "    vec4 c = src(at)"]
    lines.append("    return vec4(linear_srgb_to_srgb(c.rgb), c.a)")
    var curved := "\n".join(lines)
    assert_eq(PixelSource.imports(curved), PackedStringArray(["linear_srgb_color_space"]), "The import is read")
    var path := HERE.path_join("curved.gmacs")
    for pass_form: bool in [false, true]:
        var function := PixelFunction.new(path, curved, pass_form)
        var form := "a filter's pass" if pass_form else "the plain kernel"
        assert_true(function.compile(), "It compiles as %s" % form)
        var text := String(function.generated_source)
        var above := text.find("import linear_srgb_color_space") < text.find("params:")
        assert_true(above, "with the import above the params in %s" % form)
    var ctx := _registries.context.for_module(OWNER)
    assert_true(
        PixelFunction.register_rule(ctx, path, &"curved", "Curved", 0, curved), "and as a rule, which imports no curve of its own"
    )


func test_the_glsl_step_a_student_calls_is_the_built_ins_beside_the_field() -> void:
    var body := PixelSource.body("def pixel(ivec2 at) -> vec4:\n    return vec4(step(0.5, src(at).a), c.step(1), 0.0, 1.0)")
    assert_true(body.contains("sa_step(0.5, src(at).a)"), "A call of `step()` is renamed off the field: %s" % body)
    assert_true(body.contains("c.step(1)"), "and a member of that name keeps its own")
    for line: String in ["    int step", "    float t"]:
        var plain := PixelSource.wrap("k", "sara_pixels/k", []).split("\n")
        assert_true(line in plain, "The plain form declares `%s`" % line.strip_edges())
        assert_true(line in PixelSource.wrap_layered("k", "sara_pixels/k", []).split("\n"), "and so does the pass form")
