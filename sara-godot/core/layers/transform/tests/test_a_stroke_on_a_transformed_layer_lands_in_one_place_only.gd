## A brush stroke on a layer drawn through a live transform
## shows where the pointer drew it and nowhere else, during the stroke and
## after it, and the same once Layer > Convert to Ordinary Layer has baked the map.
##
## The fault was a stroke painted in two places at once
## until the bake. A tap, which the earlier suite paints, is a dab laid
## outside a walk, and lands right. The dabs of a walk wait in
## `SaWalkBatch` for the frame and go as one dispatch a chunk, and those are
## what this suite paints, a frame per motion as in the running app.
##
## The painting is four chunks across and four down, the grey background
## hidden, with one empty layer turned, scaled and moved about the middle of the
## canvas. The canvas is read every few texels and the layer's own chunks at
## every texel, and a painted texel further from the stroke's path than the dab
## reaches is a second copy.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 1024)
const MIDDLE := Vector2(512.0, 512.0)
const MOVE := Vector2(60.0, 40.0)
const TURN := 30.0
const SCALE := Vector2(1.5, 1.5)
## The stroke's path in document pixels, a frame a step.
const FROM := Vector2(600.0, 300.0)
const STEP := Vector2(16.0, 0.0)
const STEPS := 14
## The step the canvas is read at mid-stroke.
const HALF := 7
## What counts as paint at a dab's soft edge.
const VISIBLE := 0.05
## How far past the dab's half width a painted texel may stray, for the soft
## edge and the bilinear read of the cache.
const SLACK := 4.0
## How many texels apart the canvas is read.
const STRIDE := 4


## The map of the header.
static func _map() -> Basis:
    return SaLiveTransform.composed(MOVE, TURN, SCALE, MIDDLE)


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _button(machine: ToolMachine, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.position = machine.surface.view.mouse_position
    machine.active_tool.handle_input(event)


static func _move(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = at
    motion.pressure = 1.0
    machine.active_tool.handle_input(motion)


## One frame of the running app: the tool's tick, the brush's held dabs sent at
## `process_frame`, and the pending composite.
static func _frame(surface: SaSurface, machine: ToolMachine) -> void:
    machine._process(1.0 / 60.0)
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    surface.easel.process_pending_composite()


## How far *point* lies from the segment *from* to *to*.
static func _distance(point: Vector2, from: Vector2, to: Vector2) -> float:
    var along := to - from
    var t := clampf((point - from).dot(along) / along.length_squared(), 0.0, 1.0) if along.length_squared() > 0.0 else 0.0
    return point.distance_to(from + along * t)


## The painted texels of *texture* read every *stride* texels whose place,
## through *place*, lies further than *reach* from the segment *from* to *to*,
## as up to four places and their count, and how many texels were painted.
static func _strays(
    texture: SaTexture, origin: Vector2, stride: int, place: Callable, from: Vector2, to: Vector2, reach: float
) -> Dictionary:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var found: Array[Vector2] = []
    var count := 0
    var painted := 0
    for y in range(0, texture.size.y, stride):
        for x in range(0, texture.size.x, stride):
            if SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).a <= VISIBLE:
                continue
            painted += 1
            var at: Vector2 = place.call(origin + Vector2(x, y) + Vector2(0.5, 0.5))
            if _distance(at, from, to) > reach:
                count += 1
                if found.size() < 4:
                    found.append(at)
    return {"count": count, "painted": painted, "at": found}


## Whether the canvas shows paint at *at*.
static func _shows(surface: SaSurface, at: Vector2) -> bool:
    var output := surface.easel.output
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(output.rid, 0)
    var texel := Vector2i(at)
    return SaFieldSpec.decode_texel(bytes, output.format, texel.y * output.size.x + texel.x).a > 0.5


## Every painted texel of the canvas, read every STRIDE, lies under the stroke
## from FROM to *to*, the stroke shows at its two ends, and *when* names the moment.
func _canvas_holds_one_stroke(surface: SaSurface, to: Vector2, reach: float, when: String) -> void:
    var found := _strays(surface.easel.output, Vector2.ZERO, STRIDE, func(p: Vector2) -> Vector2: return p, FROM, to, reach)
    assert_true(int(found["painted"]) > 0, "%s the canvas shows the stroke" % when)
    assert_eq(int(found["count"]), 0, "%s the canvas shows paint nowhere off the stroke's path, %s" % [when, found])
    for at: Vector2 in [FROM + STEP, to - STEP]:
        assert_true(_shows(surface, at), "%s the canvas shows the stroke under the pointer at %s" % [when, at])


## Every painted texel *layer* holds lies, through *live*, under the stroke from
## FROM to *to*. Through no map once the layer is baked.
func _layer_holds_one_stroke(layer: SaLayer, live: SaLiveTransform, to: Vector2, reach: float, when: String) -> void:
    var place := func(p: Vector2) -> Vector2: return live.map_point(p) if live != null else p
    var count := 0
    var painted := 0
    var at: Array = []
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks[grid_pos]
        var found := _strays(chunk.albedo(), Vector2(grid_pos * chunk.pixel_size()), 1, place, FROM, to, reach)
        count += int(found["count"])
        painted += int(found["painted"])
        at.append_array(found["at"])
    assert_true(painted > 0, "%s the layer holds the stroke" % when)
    assert_eq(count, 0, "%s the layer holds paint nowhere the map does not show under the path, at %s" % [when, at.slice(0, 4)])


## The half width of one dab of the default brush on a plain layer, in the
## document's pixels, read off a tap.
func _half_width() -> float:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var doc := surface.get_document()
    surface.view.mouse_position = FROM
    _button(machine, true)
    _button(machine, false)
    var reach := 0.0
    var layer := doc.active_layer
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var texture := (layer.chunks[grid_pos] as SaChunk).albedo()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in range(texture.size.y):
            for x in range(texture.size.x):
                if SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).a > VISIBLE:
                    var at := Vector2(grid_pos * texture.size.x) + Vector2(x, y) + Vector2(0.5, 0.5)
                    reach = maxf(reach, at.distance_to(FROM))
    Fixtures.teardown(surface, machine)
    return reach


func test_a_stroke_on_a_turned_and_moved_layer_shows_under_its_path_alone_before_and_after_the_bake() -> void:
    var reach := _half_width() + SLACK
    assert_true(reach > SLACK, "A tap of the default brush paints, %s wide" % reach)
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var doc := surface.get_document()
    var layer := doc.active_layer
    assert_true(SaLiveTransform.put(doc, layer, _map()), "The map is put on")
    var live := SaLiveTransform.of(layer)
    _frame(surface, machine)
    surface.view.mouse_position = FROM
    _button(machine, true)
    for i in range(1, HALF + 1):
        _move(machine, FROM + STEP * i)
        _frame(surface, machine)
    _canvas_holds_one_stroke(surface, FROM + STEP * HALF, reach, "Mid-stroke")
    for i in range(HALF + 1, STEPS + 1):
        _move(machine, FROM + STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)
    var to := FROM + STEP * STEPS
    _canvas_holds_one_stroke(surface, to, reach, "After the release")
    _layer_holds_one_stroke(layer, live, to, reach, "After the release")
    assert_true(SaLiveTransform.bake(doc, layer), "Layer > Convert to Ordinary Layer bakes the map")
    _frame(surface, machine)
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    _canvas_holds_one_stroke(surface, to, reach, "After the bake")
    _layer_holds_one_stroke(layer, null, to, reach, "After the bake")
    Fixtures.teardown(surface, machine)
