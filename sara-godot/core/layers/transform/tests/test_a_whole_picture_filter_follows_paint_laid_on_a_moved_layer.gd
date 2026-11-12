## Paint laid on a layer drawn through a live transform reaches
## every whole-picture filter and effect layer that reads it at the next frame,
## as paint on a layer drawn where it was painted does.
##
## Found beside P3 of the same plan: the active layer's cache was brought up to
## date only once the frame's dirty set had been consumed, in
## `SaLiveTransform.refresh`, and where it changed went to the walk alone and
## never to `SaDocument.painted` or `beneath_root`, which is what a kept gather
## copies again by. So a kaleidoscope on the root, on an effect layer reading
## the layer and on the layer itself kept the chunks it gathered before an undo
## or a redo of a stroke. `SaDocument.consume_dirty_chunks` now brings the
## active layer's cache up to date first, through `SaLiveTransform.paint_of`,
## which invalidates where the cache changed as paint on any layer is.
##
## The painting is four chunks across and three down, the grey background
## hidden, and a layer named Source holding a tint of its own in every chunk,
## moved 300 pixels right as the hunt moved its photo. Under an effect layer's
## kaleidoscope Source is drawn at no opacity, so its paint shows through the
## effect alone and the brush still takes a press on it. Every composite after
## the first is the pending one, one a frame as in the running app, and each
## frame of the stroke flushes its dabs at `process_frame` as the app does. A
## fresh render lets the cache go, builds the fold again and composites every
## chunk, so it reads nothing an earlier frame kept.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const GRID := Vector2i(4, 3)
const KALEIDOSCOPE: StringName = &"kaleidoscope.kaleidoscope"
const EIGHT_MIRRORS := {"mirrors": 8, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}
## The hunt's move, 300 pixels right.
const MOVE := Vector2(300.0, 0.0)
## Where the stroke starts and how far each frame takes it, inside the wedge
## eight mirrors fold from, right of the middle and just below it.
const STROKE_FROM := Vector2(640.0, 400.0)
const STROKE_STEP := Vector2(6.0, 2.0)
const STROKE_FRAMES := 12
## A channel further than this from the fresh render counts, six levels of
## eight bits, the measure every scenario of the hunt reads its looks by.
const OVER := 6.0 / 255.0

## Where the kaleidoscope is: on the root, on an effect layer reading Source,
## or on Source itself.
enum On { ROOT, EFFECT, SOURCE }


## The tint of the chunk at *grid_pos*, opaque.
static func _tint(grid_pos: Vector2i) -> Color:
    return Color(float(grid_pos.x) / GRID.x, float(grid_pos.y) / GRID.y, 0.5, 1.0)


## The painting of the header with the kaleidoscope *on* the root, an effect
## layer or Source, and with *invert* an effect layer inverting Source under
## the root's kaleidoscope as well. Composited whole, then Source moved and the
## move composited as the frame after it does.
func _painting(on: On, invert: bool = false) -> SaSurface:
    var surface := Fixtures.make_surface(GRID * SaChunk.SIZE)
    var easel := surface.easel
    easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    var filters := SaFilterRegistry.new()
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    filters.register(Kaleidoscope.new(), &"kaleidoscope")
    filters.register(Bench.InvertFilter.new(), Bench.OWNER)
    easel.compositor.filter_chain.registry = filters
    var doc := easel.document
    (doc.get_node("Background") as SaLayer).visible = false
    var source := doc.get_node("Layer 1") as SaLayer
    source.name = "Source"
    for y in GRID.y:
        for x in GRID.x:
            source.get_or_create_chunk(Vector2i(x, y)).clear(_tint(Vector2i(x, y)))
    var ops := SaFilterOps.new(doc)
    if on == On.EFFECT or invert:
        var effect := SaLayerOps.new(doc).add(SaEffectLayer.TYPE_ID, Fixtures.make_registries().layer_types)
        effect.name = "Effect"
        assert_true(SaEffectLayer.input_of(effect) == source, "The effect layer made above Source reads it")
        assert_not_null(ops.attach(effect, Bench.INVERT if invert else KALEIDOSCOPE, {} if invert else EIGHT_MIRRORS))
        # Source shows only through the effect layer when the effect is the
        # kaleidoscope. It is drawn at no opacity,
        # because a paint tool's press on a hidden layer is turned away, so it is
        # now: the effect reads its input before the input's opacity.
        source.opacity = 1.0 if invert else 0.0
    var node: SaLayer = source if on == On.SOURCE else null
    if on != On.EFFECT:
        assert_not_null(ops.attach(node, KALEIDOSCOPE, EIGHT_MIRRORS), "The kaleidoscope attaches")
    doc.set_active_layer(source)
    Bench.composite(easel)
    assert_true(SaLiveTransform.put(doc, source, SaLiveTransform.composed(MOVE, 0.0, Vector2.ONE, Vector2.ZERO)), "Source moves")
    easel.process_pending_composite()
    return surface


static func _button(machine: ToolMachine, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = machine.surface.view.mouse_position
    machine.active_tool.handle_input(event)


## A motion to *at* with the button held, at full pressure.
static func _move(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = at
    motion.pressure = 1.0
    machine.active_tool.handle_input(motion)


## One frame of the running app: the tool's tick, the brush's dabs sent at
## `process_frame`, and the pending composite.
static func _frame(surface: SaSurface, machine: ToolMachine) -> void:
    machine._process(1.0 / 60.0)
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    surface.easel.process_pending_composite()


## A stroke of the default round brush across the wedge, a frame per motion,
## and the frame after the release.
static func _stroke(surface: SaSurface, machine: ToolMachine) -> void:
    surface.view.mouse_position = STROKE_FROM
    _button(machine, true)
    for i in STROKE_FRAMES:
        _move(machine, STROKE_FROM + STROKE_STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)


static func _bytes(texture: SaTexture) -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)


## How many texels of *texture* differ between *one* and *other* by more than
## OVER in a channel, the largest difference, and where it is.
static func _over(one: PackedByteArray, other: PackedByteArray, texture: SaTexture) -> Array:
    if one == other:
        return [0, 0.0, Vector2i(-1, -1)]
    var count := 0
    var worst := 0.0
    var at := Vector2i(-1, -1)
    for y in texture.size.y:
        for x in texture.size.x:
            var index := y * texture.size.x + x
            var p := SaFieldSpec.decode_texel(one, texture.format, index)
            var q := SaFieldSpec.decode_texel(other, texture.format, index)
            var d := maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a)))
            count += 1 if d > OVER else 0
            if d > worst:
                worst = d
                at = Vector2i(x, y)
    return [count, worst, at]


## Reads the canvas the frame left against a fresh render of the same document,
## and answers the canvas the frame left.
func _against_a_fresh_render(surface: SaSurface, what: String) -> PackedByteArray:
    var easel := surface.easel
    var pending := _bytes(easel.output)
    SaLiveTransform.of(easel.document.get_node("Source") as SaLayer).release()
    Bench.composite(easel)
    var found := _over(pending, _bytes(easel.output), easel.output)
    assert_eq(found[0], 0, "%s: texels over 6 against a fresh render, the worst %f at %s" % [what, found[1], found[2]])
    return pending


## A stroke of *tool*, its undo and its redo on the moved Source, each read
## against a fresh render at the frame after it.
func _follows(surface: SaSurface, where: String, tool: StringName = &"brush") -> void:
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(tool)
    var doc := surface.get_document()
    var before := _against_a_fresh_render(surface, "The move under %s" % where)
    _stroke(surface, machine)
    var stroked := _against_a_fresh_render(surface, "The stroke under %s" % where)
    assert_true(stroked != before, "The stroke shows under %s" % where)
    assert_true(doc.undo(), "The stroke is one step")
    surface.easel.process_pending_composite()
    var undone := _against_a_fresh_render(surface, "Its undo under %s" % where)
    assert_true(undone == before, "and the undo gives back the canvas before the stroke, byte for byte")
    assert_true(doc.redo(), "The stroke comes back")
    surface.easel.process_pending_composite()
    var redone := _against_a_fresh_render(surface, "Its redo under %s" % where)
    assert_true(redone == stroked, "and the redo gives back the stroked canvas, byte for byte")
    Fixtures.teardown(surface, machine)


func test_paint_on_a_moved_layer_reaches_the_kaleidoscope_on_the_whole_picture() -> void:
    _follows(_painting(On.ROOT), "the root's kaleidoscope")


func test_paint_on_a_moved_layer_reaches_an_effect_layer_under_the_whole_picture_s_kaleidoscope() -> void:
    _follows(_painting(On.ROOT, true), "an effect layer inverting Source under the root's kaleidoscope")


func test_paint_on_a_moved_layer_reaches_the_kaleidoscope_of_an_effect_layer_reading_it() -> void:
    _follows(_painting(On.EFFECT), "an effect layer's kaleidoscope")


func test_paint_on_a_moved_layer_reaches_the_kaleidoscope_on_the_layer_itself() -> void:
    _follows(_painting(On.SOURCE), "Source's own kaleidoscope")


func test_the_eraser_on_a_moved_layer_reaches_the_kaleidoscope_on_the_whole_picture() -> void:
    _follows(_painting(On.ROOT), "the root's kaleidoscope, erased", &"eraser")


## Source's colour derived from a field of its own, the way a mixing
## layer's is from its concentrations, and a change of that field at one chunk marked
## and invalidated as an undo marks it. The cache reads the colour the change
## resolves to, since the walk resolves every layer before it reads one.
func test_a_moved_layer_whose_colour_is_derived_is_resolved_before_its_cache_reads_it() -> void:
    var surface := _painting(On.ROOT)
    var doc := surface.get_document()
    var source := doc.get_node("Source") as SaLayer
    var colours: Dictionary[Vector2i, Color] = {}
    for grid_pos: Vector2i in source.chunks:
        colours[grid_pos] = _tint(grid_pos)
    var sources: Array[StringName] = [&"thickness"]
    var derived: Array[SaFieldSpec] = [
        SaFieldSpec.create(SaFieldSpec.ALBEDO, source.schema[0].format, true, sources),
        SaFieldSpec.create(&"thickness", RenderingDevice.DATA_FORMAT_R32_SFLOAT, false),
    ]
    source.resolve_hook = func(_owner: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> void:
        chunk.albedo().clear(colours.get(grid_pos, Color.TRANSPARENT))
    source.schema = derived
    for y in GRID.y:
        for x in GRID.x:
            source.get_or_create_chunk(Vector2i(x, y))
    SaLiveTransform.of(source).release()
    Bench.composite(surface.easel)
    var before := _bytes(surface.easel.output)
    var changed := Vector2i(1, 1)
    colours[changed] = Color(1.0, 0.0, 0.0, 1.0)
    source.mark_unresolved(changed)
    doc.invalidate_chunks([changed], source)
    surface.easel.process_pending_composite()
    var after := _against_a_fresh_render(surface, "A change of the field the colour is derived from")
    assert_true(after != before, "and the change shows")
    source.resolve_hook = Callable()
    Fixtures.teardown(surface)
