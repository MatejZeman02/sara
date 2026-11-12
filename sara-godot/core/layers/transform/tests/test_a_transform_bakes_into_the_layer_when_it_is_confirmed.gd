## A transform bakes into the layer when it is confirmed,
## unless the layer is smart.
##
## The maintainers' ruling of 2026-10-14 made a live transform opt in: the
## Transform tool's Enter on an ordinary layer resamples its paint once, as one
## history step, and leaves no transform pending, so there is no step between
## the box and the pixels for a stroke to land in twice. A layer that carries a
## live transform, which a file saved under the old rule brings, is a smart
## layer and keeps it, and Layer > Convert to Ordinary Layer is lit for it alone.
##
## The painting is four chunks across and four down, the grey background
## hidden, with one layer painted over STROKE. The drive is the one
## `test_a_stroke_on_a_transformed_layer_lands_in_one_place_only.gd` uses for
## its brush, a frame per motion, and the Transform tool's body and corner
## drags of the sibling suite.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(1024, 1024)
const PAINT := Color(0.8, 0.3, 0.1, 1.0)
const STROKE := Rect2i(300, 300, 200, 160)
## The body drag's move and the corner drag's pull after it.
const MOVE := Vector2(200.0, 100.0)
const PULL := Vector2(100.0, 80.0)
## Where the two drags take STROKE: moved by MOVE and pulled wider and taller
## by PULL from its far corner.
const MOVED := Rect2i(500, 400, 300, 240)
## The brush stroke's path after the bake, clear of STROKE and of MOVED, a
## frame a step.
const FROM := Vector2(150.0, 750.0)
const STEP := Vector2(16.0, 0.0)
const STEPS := 14
## What counts as paint at a dab's soft edge.
const VISIBLE := 0.05
## How far past the dab's half width a painted texel may stray.
const SLACK := 4.0
## How many texels apart the canvas is read.
const STRIDE := 4


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


static func _surface() -> SaSurface:
    var surface := Fixtures.make_surface(SIZE)
    surface.easel.compositor.set_registry(Fixtures.make_registries().blend_modes)
    (surface.get_document().get_node("Background") as SaLayer).visible = false
    return surface


static func _image_format(texture: SaTexture) -> Image.Format:
    return Image.FORMAT_RGBAH if texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else Image.FORMAT_RGBAF


## *rect*, in document pixels, painted on the active layer through an upload,
## since the brush is not what the first half of the suite is about.
static func _paint(document: SaDocument, rect: Rect2i) -> void:
    var layer := document.active_layer
    var device := GlobalShaderCompiler.get_rd()
    for grid_pos: Vector2i in SaChunkWalk.positions_in(rect):
        var chunk := layer.get_or_create_chunk(grid_pos)
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), device.texture_get_data(texture.rid, 0))
        image.fill_rect(SaChunkWalk.local_rect(grid_pos, rect, edge), PAINT)
        device.texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)
    document.invalidate_chunks(layer.chunks.keys())


## Every chunk's colour bytes, by grid position.
static func _texels(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in layer.chunks:
        out[grid_pos] = GlobalShaderCompiler.get_rd().texture_get_data(layer.chunks[grid_pos].albedo().rid, 0)
    return out


## The alpha of the layer's own texel at *at*, zero where it has no chunk.
static func _alpha_at(layer: SaLayer, at: Vector2i) -> float:
    var texel := Rect2i(at, Vector2i.ONE)
    for grid_pos: Vector2i in SaChunkWalk.positions_in(texel):
        if not layer.chunks.has(grid_pos):
            return 0.0
        var texture: SaTexture = layer.chunks[grid_pos].albedo()
        var edge: int = layer.chunks[grid_pos].pixel_size()
        var data := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var image := Image.create_from_data(edge, edge, false, _image_format(texture), data)
        return image.get_pixelv(SaChunkWalk.local_rect(grid_pos, texel, edge).position).a
    return 0.0


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


static func _enter(machine: ToolMachine) -> void:
    var event := InputEventKey.new()
    event.keycode = KEY_ENTER
    event.physical_keycode = KEY_ENTER
    event.pressed = true
    machine.active_tool.handle_input(event)


## One frame of the running app: the tool's tick, the brush's held dabs sent at
## `process_frame`, and the pending composite.
static func _frame(surface: SaSurface, machine: ToolMachine) -> void:
    machine._process(1.0 / 60.0)
    (Engine.get_main_loop() as SceneTree).process_frame.emit()
    surface.easel.process_pending_composite()


## A press at *from*, a motion to *to* and a release with the active tool,
## then a frame.
static func _drag(surface: SaSurface, machine: ToolMachine, from: Vector2, to: Vector2) -> void:
    surface.view.mouse_position = from
    _button(machine, true)
    _move(machine, to)
    _button(machine, false)
    _frame(surface, machine)


## The Transform tool's body drag by MOVE and its far corner's pull by PULL,
## and Enter, on the active layer, whose paint over STROKE shows *shift* away.
static func _transform(surface: SaSurface, machine: ToolMachine, shift: Vector2 = Vector2.ZERO) -> void:
    machine.set_active_tool(&"transform")
    var centre := Vector2(STROKE.get_center()) + shift
    _drag(surface, machine, centre, centre + MOVE)
    var corner := Vector2(STROKE.end) + shift + MOVE
    _drag(surface, machine, corner, corner + PULL)
    _enter(machine)
    _frame(surface, machine)


## How far *point* lies from the segment *from* to *to*.
static func _distance(point: Vector2, from: Vector2, to: Vector2) -> float:
    var along := to - from
    var t := clampf((point - from).dot(along) / along.length_squared(), 0.0, 1.0) if along.length_squared() > 0.0 else 0.0
    return point.distance_to(from + along * t)


## The painted texels of *texture*, its first texel at *origin* in document
## pixels, read every *stride*, that lie outside MOVED and further than *reach*
## from the segment *from* to *to*, as a count, up to four places, and how many
## texels were painted off MOVED.
static func _strays(texture: SaTexture, origin: Vector2, stride: int, from: Vector2, to: Vector2, reach: float) -> Dictionary:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var found: Array[Vector2] = []
    var count := 0
    var painted := 0
    var kept := Rect2(MOVED).grow(2.0)
    for y in range(0, texture.size.y, stride):
        for x in range(0, texture.size.x, stride):
            if SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x).a <= VISIBLE:
                continue
            var at := origin + Vector2(x, y) + Vector2(0.5, 0.5)
            if kept.has_point(at):
                continue
            painted += 1
            if _distance(at, from, to) > reach:
                count += 1
                if found.size() < 4:
                    found.append(at)
    return {"count": count, "painted": painted, "at": found}


## The half width of one dab of the default brush on a plain layer, in the
## document's pixels, read off a tap.
func _half_width() -> float:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    surface.view.mouse_position = FROM
    _button(machine, true)
    _button(machine, false)
    var reach := 0.0
    var layer := surface.get_document().active_layer
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


## The Done clause of the ordinary layer: the body and corner drags and Enter
## resample the paint to the mapped place, leave no transform, and one undo
## returns every byte. A stroke afterwards lands under the pointer alone.
func test_the_tool_bakes_an_ordinary_layer_at_enter_and_a_stroke_lands_once() -> void:
    var reach := _half_width() + SLACK
    assert_true(reach > SLACK, "A tap of the default brush paints, %s wide" % reach)
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    _paint(doc, STROKE)
    var painted := _texels(layer)
    var steps := doc.history.step_count()

    _transform(surface, machine)
    assert_eq(doc.history.step_count(), steps + 1, "The two drags and Enter are one step")
    assert_null(layer.live_transform, "which leaves the ordinary layer no transform pending")
    for at: Vector2i in [MOVED.position + Vector2i(2, 2), MOVED.get_center(), MOVED.end - Vector2i(3, 3)]:
        assert_almost_eq(_alpha_at(layer, at), 1.0, 0.01, "The paint is in the layer at the mapped place, %s" % at)
    for at: Vector2i in [STROKE.position + Vector2i(2, 2), Vector2i(STROKE.position.x + 100, STROKE.position.y + 50)]:
        assert_almost_eq(_alpha_at(layer, at), 0.0, 0.01, "and gone from the old place, %s" % at)
    var lines := SaProblems.pending_refusals
    assert_eq(lines.size(), 0, "and nothing was refused, %s" % [lines])
    var moved := _texels(layer)

    assert_true(doc.undo(), "One undo")
    assert_eq(_texels(layer), painted, "returns the layer as it was painted, byte for byte")
    assert_null(layer.live_transform, "with no transform")
    assert_true(doc.redo(), "and a redo")
    assert_eq(_texels(layer), moved, "moves it again")

    assert_false(SaLiveTransform.can_bake(doc.active_layer), "Convert, which asks can_bake, is dimmed after the bake")

    machine.set_active_tool(&"brush")
    _frame(surface, machine)
    surface.view.mouse_position = FROM
    _button(machine, true)
    for i in range(1, STEPS + 1):
        _move(machine, FROM + STEP * i)
        _frame(surface, machine)
    _button(machine, false)
    _frame(surface, machine)
    var to := FROM + STEP * STEPS
    var count := 0
    var on_layer := 0
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks[grid_pos]
        var found := _strays(chunk.albedo(), Vector2(grid_pos * chunk.pixel_size()), 1, FROM, to, reach)
        count += int(found["count"])
        on_layer += int(found["painted"])
    assert_true(on_layer > 0, "The stroke is in the layer")
    assert_eq(count, 0, "and nowhere off its path but the moved paint")
    for at: Vector2 in [FROM + STEP, to - STEP]:
        assert_true(_alpha_at(layer, Vector2i(at)) > 0.5, "under the pointer at %s" % at)
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()
    var shown := _strays(surface.easel.output, Vector2.ZERO, STRIDE, FROM, to, reach)
    assert_true(int(shown["painted"]) > 0, "The canvas shows the stroke")
    assert_eq(int(shown["count"]), 0, "in one place only, %s" % [shown])
    Fixtures.teardown(surface, machine)


## The Done clause of the old file: a layer saved carrying a map opens carrying
## it over its untransformed chunks, a smart layer, so no saved picture changes
## on opening, and the Transform tool on it ends in `SaLiveTransform.put` with
## no pixel written. Convert to Ordinary Layer is lit for it, and the sentence a refused
## tool hears names that row.
func test_a_file_whose_layer_carries_a_map_opens_smart_and_stays_live() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var layer := doc.active_layer
    _paint(doc, STROKE)
    var shift := Vector2(60.0, 40.0)
    var map: Basis = SaLiveTransform.composed(shift, 0.0, Vector2.ONE, Vector2.ZERO)
    assert_true(SaLiveTransform.put(doc, layer, map), "The layer carries a map")
    var painted := _texels(layer)
    var path := ProjectSettings.globalize_path(SaDataRoot.path("smart_layer.sad"))
    assert_eq(SaExport.save_sad(doc, path), OK, "It saves")
    var name := String(layer.name)
    Fixtures.teardown(surface, machine)

    surface = _surface()
    machine = Fixtures.make_bound_machine(surface)
    doc = surface.get_document()
    assert_eq(SaExport.load_sad(doc, path, surface.easel.compositor), OK, "It opens")
    DirAccess.remove_absolute(path)
    var opened := doc.get_node(name) as SaLayer
    assert_not_null(opened, "with its layer")
    if opened == null:
        Fixtures.teardown(surface, machine)
        return
    doc.set_active_layer(opened)
    var live := SaLiveTransform.of(opened)
    assert_not_null(live, "The layer still carries the map")
    if live != null:
        assert_true(live.matrix.is_equal_approx(map), "the same map")
    assert_eq(_texels(opened), painted, "over its untransformed chunks, byte for byte")

    assert_true(SaLiveTransform.can_bake(opened), "Convert, which asks can_bake, is lit on the smart layer")
    var refused := SaContext.paint_refusal_line(opened, "stroke")
    assert_true(refused.contains("Convert to Ordinary Layer"), "and a refused tool hears that row named, %s" % refused)
    assert_true(refused.contains("smart layer"), "and the layer called smart")

    var steps := doc.history.step_count()
    _transform(surface, machine, shift)
    assert_eq(doc.history.step_count(), steps + 1, "The Transform tool's drags and Enter are one step")
    var after := SaLiveTransform.of(opened)
    assert_not_null(after, "which keeps the layer smart")
    if after != null:
        assert_false(after.matrix.is_equal_approx(map), "under a new map")
    assert_eq(_texels(opened), painted, "and writes no pixel")
    assert_true(doc.undo(), "One undo")
    assert_true(SaLiveTransform.of(opened).matrix.is_equal_approx(map), "puts the map back")
    Fixtures.teardown(surface, machine)
