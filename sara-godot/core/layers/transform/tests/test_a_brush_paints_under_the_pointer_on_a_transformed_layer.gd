## A brush on a layer with a live move, scale or rotation paints
## under the pointer. The stroke's points go back through the map into the
## layer's own pixels and so do each dab's size and turn, the canvas shows the
## paint where the pointer was, and a perspective is still refused with the
## same sentence.
##
## The painting: two chunks across and two down, the grey background hidden.
## One tap of the default round brush on the plain layer says how wide a dab is
## in the document's pixels, and the same tap on a layer turned a quarter about
## the canvas's middle, scaled twice and moved has to land in that layer's own
## chunks where the map takes the pointer back, half as wide.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

const SIZE := Vector2i(512, 512)
const MIDDLE := Vector2(256.0, 256.0)
const MOVE := Vector2(24.0, -16.0)
const POINTER := Vector2(300.0, 210.0)
## What counts as paint at a dab's soft edge.
const VISIBLE := 0.05
## How far a measured centre or half width may stray, a texel and a half.
const NEAR := 1.5

var _heard: PackedStringArray = PackedStringArray()


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()
    _heard = PackedStringArray()


func _hear(line: String) -> void:
    _heard.append(line)


## The map of the header.
static func _map() -> Basis:
    return SaLiveTransform.composed(MOVE, 90.0, Vector2(2.0, 2.0), MIDDLE)


## A surface over the painting of the header, its compositor holding the blend
## modes the app gives it, and a machine holding the brush.
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


## A motion to *at* with the button held, at full pressure.
static func _move(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    var motion := InputEventMouseMotion.new()
    motion.button_mask = MOUSE_BUTTON_MASK_LEFT
    motion.position = at
    motion.pressure = 1.0
    machine.active_tool.handle_input(motion)


## A press at *at* and the release, which lays one dab.
static func _tap(machine: ToolMachine, at: Vector2) -> void:
    machine.surface.view.mouse_position = at
    _button(machine, true)
    _button(machine, false)


## The box around every texel of *layer*'s own chunks whose alpha is above
## VISIBLE, in the layer's pixels.
static func _painted_box(layer: SaLayer) -> Rect2:
    var box := Rect2()
    var found := false
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in range(edge):
            for x in range(edge):
                if SaFieldSpec.decode_texel(bytes, texture.format, y * edge + x).a <= VISIBLE:
                    continue
                var texel := Rect2(Vector2(grid_pos * edge + Vector2i(x, y)), Vector2.ONE)
                box = texel if not found else box.merge(texel)
                found = true
    return box


static func _texel(texture: SaTexture, at: Vector2i) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, at.y * texture.size.x + at.x)


static func _show(surface: SaSurface) -> void:
    surface.get_document().update_caches()
    surface.easel.request_full_composite()
    surface.easel.process_pending_composite()


func test_a_tap_on_a_turned_scaled_and_moved_layer_lands_in_its_own_pixels_under_the_pointer() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    EventBus.paint_refused.connect(_hear)
    var doc := surface.get_document()
    var plain := doc.active_layer
    _tap(machine, POINTER)
    var flat := _painted_box(plain)
    assert_true(flat.has_area(), "The tap paints the plain layer")
    assert_true(flat.get_center().distance_to(POINTER) <= NEAR, "under the pointer, %s" % flat)
    plain.visible = false
    var turned := SaLayerOps.new(doc).add()
    doc.set_active_layer(turned)
    assert_true(SaLiveTransform.put(doc, turned, _map()), "The map is put on")
    assert_false(turned.refuses_paint(true), "and the layer takes a stroke painted through it")
    _tap(machine, POINTER)
    EventBus.paint_refused.disconnect(_hear)
    assert_eq(_heard.size(), 0, "The brush says nothing: %s" % "\n".join(_heard))
    var live := SaLiveTransform.of(turned)
    var held := live.unmap_point(POINTER)
    var landed := _painted_box(turned)
    assert_true(landed.has_area(), "The tap paints the transformed layer")
    assert_true(
        landed.get_center().distance_to(held) <= NEAR,
        "in its own pixels where the map takes the pointer back, %s against %s" % [landed.get_center(), held]
    )
    var half := landed.size * 0.5
    var expected := flat.size * 0.25
    assert_true(
        absf(half.x - expected.x) <= NEAR and absf(half.y - expected.y) <= NEAR,
        "half as wide as on the plain layer, half extent %s against %s" % [half, expected]
    )
    _show(surface)
    var shown := _texel(surface.easel.output, Vector2i(POINTER))
    assert_true(shown.a > 0.5, "The canvas shows the dab under the pointer, %s" % shown)
    var elsewhere := _texel(surface.easel.output, Vector2i(held))
    assert_true(elsewhere.a <= VISIBLE, "and nothing where the layer holds it, %s" % elsewhere)
    Fixtures.teardown(surface, machine)


## The press's dab is laid at the first motion and at once, the walk's dabs
## after it wait for the frame, so that dab is what a suite with no frame sees
## mid-stroke. The buffer is in the layer's pixels and hidden from the walk, so what shows at
## the pointer is the cache drawing the buffer over the layer.
func test_a_stroke_shows_under_the_pointer_while_it_is_painted() -> void:
    var surface := _surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"brush")
    var doc := surface.get_document()
    var layer := doc.active_layer
    assert_true(SaLiveTransform.put(doc, layer, _map()), "The map is put on")
    var held := SaLiveTransform.of(layer).unmap_point(POINTER)
    surface.view.mouse_position = POINTER
    _button(machine, true)
    _move(machine, POINTER)
    _show(surface)
    assert_false(doc.stroke_layer.visible, "Mid-stroke the walk does not draw the buffer")
    assert_true(layer.chunks.is_empty(), "and the layer holds nothing yet")
    var shown := _texel(surface.easel.output, Vector2i(POINTER))
    assert_true(shown.a > 0.5, "The canvas shows the first dab under the pointer, %s" % shown)
    var elsewhere := _texel(surface.easel.output, Vector2i(held))
    assert_true(elsewhere.a <= VISIBLE, "and nothing where the buffer holds it, %s" % elsewhere)
    for i in range(1, 9):
        _move(machine, POINTER + Vector2(4.0 * i, 0.0))
    _button(machine, false)
    _show(surface)
    for at: Vector2 in [POINTER, POINTER + Vector2(16.0, 0.0), POINTER + Vector2(32.0, 0.0)]:
        var kept := _texel(surface.easel.output, Vector2i(at))
        assert_true(kept.a > 0.5, "After the release the canvas shows the stroke at %s, %s" % [at, kept])
    assert_true(doc.stroke_layer.visible, "and the buffer is drawn again once the stroke is in")
    Fixtures.teardown(surface, machine)


## The dab's frame taken back through the map and forward again is the frame it
## was: a turn, a scale and a mirror exactly, and a skew as the ellipse it draws.
func test_a_dab_taken_back_through_the_map_and_forward_is_the_dab_it_was() -> void:
    var maps: Array[Basis] = [
        SaLiveTransform.composed(MOVE, 33.0, Vector2(2.0, 2.0), MIDDLE),
        SaLiveTransform.composed(MOVE, -120.0, Vector2(-1.5, 1.5), MIDDLE),
        Basis(Vector3(1.0, 0.4, 0.0), Vector3(0.2, 1.3, 0.0), Vector3(5.0, 7.0, 1.0)),
    ]
    for index in range(maps.size()):
        var live := SaLiveTransform.new(maps[index])
        for bits in range(4):
            var data := PackedFloat32Array()
            data.resize(32)
            data[8] = 10.0
            data[9] = 4.0
            data[10] = cos(0.3)
            data[11] = sin(0.3)
            data[SaDabGeometry.MIRROR_INDEX] = float(bits)
            var tip := _tip(data)
            var back := _tip(live.dab(data))
            var m := maps[index]
            var forward := Transform2D(Vector2(m.x.x, m.x.y), Vector2(m.y.x, m.y.y), Vector2.ZERO) * back
            var what := "Map %d, mirror %d" % [index, bits]
            if index < 2:
                for column in range(2):
                    var gap := forward[column].distance_to(tip[column])
                    assert_true(gap < 1.0e-3, "%s: column %d is %s, %s" % [what, column, forward[column], tip[column]])
            else:
                var drawn := _ellipse(forward)
                var asked := _ellipse(tip)
                for column in range(2):
                    var gap := drawn[column].distance_to(asked[column])
                    assert_true(gap < 1.0e-2, "%s: the ellipse's form %s against %s" % [what, drawn, asked])


## The frame a packed dab draws, from the kernel's reading of its turn, half
## extent and mirror.
static func _tip(data: PackedFloat32Array) -> Transform2D:
    var bits := int(data[SaDabGeometry.MIRROR_INDEX] + 0.5)
    var across := data[8] * (-1.0 if (bits & 1) != 0 else 1.0)
    var down := data[9] * (-1.0 if (bits & 2) != 0 else 1.0)
    return Transform2D(Vector2(data[10], data[11]) * across, Vector2(-data[11], data[10]) * down, Vector2.ZERO)


## The ellipse a frame takes the unit circle to, as its form, the frame times
## its own transpose.
static func _ellipse(frame: Transform2D) -> Transform2D:
    var transposed := Transform2D(Vector2(frame.x.x, frame.y.x), Vector2(frame.x.y, frame.y.y), Vector2.ZERO)
    return frame * transposed


func test_a_brush_on_a_perspective_layer_is_refused_with_a_sentence() -> void:
    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var machine := Fixtures.make_bound_machine(surface)
    EventBus.paint_refused.connect(_hear)
    var doc := surface.get_document()
    var layer := doc.active_layer
    # w is 1 + x / 2000, so the horizon is far off the canvas.
    var perspective := Basis(Vector3(1.0, 0.0, 0.0005), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
    assert_true(SaLiveTransform.put(doc, layer, perspective), "A perspective is put on")
    assert_true(layer.refuses_paint(true), "The layer refuses even a stroke painted through it")
    machine.set_active_tool(&"brush")
    surface.view.mouse_position = Vector2(40, 40)
    _button(machine, true)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 0.6
    surface.view.mouse_position = Vector2(150, 110)
    machine.active_tool.handle_input(motion)
    _button(machine, false)
    EventBus.paint_refused.disconnect(_hear)
    assert_eq(_heard.size(), 1, "The brush says one line")
    var expected := SaContext.paint_refusal_line(layer, "stroke")
    assert_true(expected.contains("Convert to Ordinary Layer"), "which says to apply the transform first: %s" % expected)
    assert_eq(_heard[0] if _heard.size() > 0 else "", expected, "and is the refusal sentence")
    assert_true(layer.chunks.is_empty(), "The layer holds no paint")
    Fixtures.teardown(surface, machine)
