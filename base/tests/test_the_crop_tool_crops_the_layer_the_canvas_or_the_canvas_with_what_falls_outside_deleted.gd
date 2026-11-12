## The Crop tool's Crop option crops the active layer, the
## canvas keeping what falls outside, or the canvas with it deleted.
##
## The painting: two layers over the whole 512 by 512 canvas, Paint with colour
## only and Relief with colour and a height field, each texel holding a value
## of its own position, so a texel read after the crop says where it came
## from. BOX sits in the middle, where Canvas Size's centred anchor puts the
## old picture back when the document grows to its old size again.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Fixtures = preload("res://tests/fixtures.gd")
const StateCropScript = preload("res://modules/sara-base-modules/base/tools/state_crop.gd")

const SIZE := Vector2i(512, 512)
const GRID: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## Centred, so `SaCrop.offset_for` with the anchor (1, 1) is its position.
const BOX := Rect2i(156, 181, 200, 150)
const CENTRE := Vector2i(1, 1)
## Places inside BOX, in the old document's pixels.
const INSIDE: Array[Vector2i] = [Vector2i(156, 181), Vector2i(355, 330), Vector2i(250, 256), Vector2i(300, 200)]
## Places outside BOX: in chunks wholly outside its grid, which the old crop
## dropped, and in the overhang of the chunk it keeps, past its new edge.
const OUTSIDE: Array[Vector2i] = [Vector2i(10, 10), Vector2i(500, 500), Vector2i(10, 500), Vector2i(380, 200), Vector2i(200, 420)]


func before_each() -> void:
    SaProblems.pending_refusals = PackedStringArray()


## The colour Paint holds at *at*.
static func _paint_at(at: Vector2i) -> Color:
    return Color(float(at.x) / 512.0, float(at.y) / 512.0, 0.3, 1.0)


## The colour Relief holds at *at*.
static func _relief_at(at: Vector2i) -> Color:
    return Color(0.6, float(at.x) / 512.0, float(at.y) / 512.0, 1.0)


## The height Relief holds at *at*.
static func _height_at(at: Vector2i) -> Color:
    return Color(0.1 + float(at.x + 2 * at.y) / 2048.0, 0.0, 0.0, 1.0)


## A bound machine on the crop tool over the painting, Relief active.
func _set_up() -> Array:
    var surface := Fixtures.make_surface(SIZE)
    var machine := Fixtures.make_bound_machine(surface)
    var doc := surface.get_document()
    var paint := doc.active_layer
    paint.name = "Paint"
    _fill(paint, SaFieldSpec.ALBEDO, _paint_at)
    var relief := SaLayerOps.new(doc).add()
    relief.name = "Relief"
    relief.add_field(SaFieldSpec.height())
    _fill(relief, SaFieldSpec.ALBEDO, _relief_at)
    _fill(relief, SaFieldSpec.HEIGHT, _height_at)
    doc.set_active_layer(relief)
    machine.set_active_tool(&"crop")
    var tool := machine.active_tool as StateCropScript
    # The engines are the skeleton's, reached through the role registry a bare
    # machine does not hand the tool.
    tool.roles = Fixtures.make_registries().roles
    return [surface, machine, tool]


## Fills *field_id* of *layer* over the whole canvas with *value*, uploaded
## whole, since the brush is not what this suite is about.
static func _fill(layer: SaLayer, field_id: StringName, value: Callable) -> void:
    for grid_pos: Vector2i in GRID:
        var texture := layer.get_or_create_field(grid_pos, field_id)
        var image := Image.create_empty(texture.size.x, texture.size.y, false, Image.FORMAT_RGBAF)
        for y in texture.size.y:
            for x in texture.size.x:
                image.set_pixel(x, y, value.call(grid_pos * texture.size.x + Vector2i(x, y)))
        match texture.format:
            RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
                image.convert(Image.FORMAT_RGBAH)
            RenderingDevice.DATA_FORMAT_R16_SFLOAT:
                image.convert(Image.FORMAT_RH)
            RenderingDevice.DATA_FORMAT_R32_SFLOAT:
                image.convert(Image.FORMAT_RF)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, image.get_data())
        layer.mark_unresolved(grid_pos)


## What *field_id* of *layer* holds at *at* in document pixels, nothing where
## the layer holds no chunk or the chunk no such field.
static func _at(layer: SaLayer, at: Vector2i, field_id: StringName = SaFieldSpec.ALBEDO) -> Color:
    var side := SaLayer.CHUNK_SIZE
    var grid_pos := Vector2i(floori(float(at.x) / side), floori(float(at.y) / side))
    var texture := layer.get_field(grid_pos, field_id)
    if texture == null:
        return Color(0, 0, 0, 0)
    return Bench.texel(texture, at - grid_pos * side)


## *layer*'s colour and height at *at*, for comparing.
static func _reading(layer: SaLayer, at: Vector2i) -> Array[Color]:
    return [_at(layer, at), _at(layer, at, SaFieldSpec.HEIGHT)]


## The bytes of every field of every chunk *layer* holds, by position.
static func _bytes_of(layer: SaLayer) -> Dictionary:
    var found := {}
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        for field_id: StringName in chunk.fields:
            found["%s %s" % [grid_pos, field_id]] = GlobalShaderCompiler.get_rd().texture_get_data(chunk.fields[field_id].rid, 0)
    return found


## The readings of both layers at every place of INSIDE and OUTSIDE, before
## a crop, keyed by place.
static func _before(doc: SaDocument) -> Dictionary:
    var found := {}
    for at: Vector2i in INSIDE + OUTSIDE:
        found[at] = [_reading(doc.get_node("Paint"), at), _reading(doc.get_node("Relief"), at)]
    return found


static func _drag_box(tool: StateCropScript, view: SaView) -> void:
    (view as Fixtures.FakeView).mouse_position = Vector2(BOX.position)
    tool.handle_input(_button(true))
    (view as Fixtures.FakeView).mouse_position = Vector2(BOX.end)
    tool.handle_input(InputEventMouseMotion.new())
    tool.handle_input(_button(false))


func test_a_fresh_tool_crops_the_canvas() -> void:
    var made := _set_up()
    var tool: StateCropScript = made[2]
    assert_eq(tool.mode, StateCropScript.Mode.CANVAS, "A fresh tool's Crop option is Canvas")
    Fixtures.teardown(made[0], made[1])


## The first clause: the canvas at the box's size, both layers' paint
## and the relief moved by its origin, the paint outside shown again by a
## Canvas Size back to the old size, and one undo giving back the size and
## every byte.
func test_canvas_keeps_what_falls_outside_for_canvas_size_to_show() -> void:
    var made := _set_up()
    var surface: SaSurface = made[0]
    var tool: StateCropScript = made[2]
    var doc := surface.get_document()
    var paint := doc.get_node("Paint") as SaLayer
    var relief := doc.get_node("Relief") as SaLayer
    var was := _before(doc)
    var bytes := [_bytes_of(paint), _bytes_of(relief)]
    var steps := doc.history.step_count()
    _drag_box(tool, surface.view)
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(doc.history.step_count(), steps + 1, "Enter writes one step")
    assert_eq(doc.canvas_size, BOX.size, "and the canvas is the box's size")
    for at: Vector2i in INSIDE:
        var moved := at - BOX.position
        assert_eq(_reading(paint, moved), was[at][0], "Paint's texel at %s is at %s now" % [at, moved])
        assert_eq(_reading(relief, moved), was[at][1], "and Relief's colour and height alike")
        assert_true(_at(relief, moved, SaFieldSpec.HEIGHT).r > 0.0, "the height a real one at %s" % moved)
    assert_true(SaProblems.pending_refusals.is_empty(), "with nothing said in the corner")

    assert_true(doc.undo(), "Undo")
    assert_eq(doc.canvas_size, SIZE, "gives back the size")
    assert_eq(_bytes_of(paint), bytes[0], "and every byte of Paint")
    assert_eq(_bytes_of(relief), bytes[1], "and of Relief, its height included")
    assert_true(doc.redo(), "Redo crops again")
    assert_eq(doc.canvas_size, BOX.size, "to the box")

    assert_true(SaCrop.new(doc).resize_to(SIZE, CENTRE), "Canvas Size grows the document back")
    assert_eq(doc.canvas_size, SIZE, "to its old size")
    for at: Vector2i in INSIDE + OUTSIDE:
        assert_eq(_reading(paint, at), was[at][0], "Paint shows what it held at %s again" % at)
        assert_eq(_reading(relief, at), was[at][1], "and Relief its colour and height")
    Fixtures.teardown(surface, made[1])


## The second clause: the same crop deleting outside leaves, after the
## grow back, nothing outside the box on either layer, the height included.
func test_canvas_and_delete_outside_leaves_nothing_outside() -> void:
    var made := _set_up()
    var surface: SaSurface = made[0]
    var tool: StateCropScript = made[2]
    var doc := surface.get_document()
    var paint := doc.get_node("Paint") as SaLayer
    var relief := doc.get_node("Relief") as SaLayer
    var was := _before(doc)
    tool.mode = StateCropScript.Mode.CANVAS_DELETE
    _drag_box(tool, surface.view)
    assert_true(tool.crop_now(), "The crop runs")
    assert_eq(doc.canvas_size, BOX.size, "to the box's size")
    for at: Vector2i in INSIDE:
        assert_eq(_reading(relief, at - BOX.position), was[at][1], "Relief's texel at %s is moved with the box" % at)
    assert_true(SaCrop.new(doc).resize_to(SIZE, CENTRE), "Canvas Size grows the document back")
    for at: Vector2i in OUTSIDE:
        for layer: SaLayer in [paint, relief]:
            assert_eq(_at(layer, at).a, 0.0, "%s holds no colour at %s" % [layer.name, at])
        assert_eq(_at(relief, at, SaFieldSpec.HEIGHT).r, 0.0, "and Relief no height at %s" % at)
    for at: Vector2i in INSIDE:
        assert_eq(_reading(paint, at), was[at][0], "Paint is back where it was inside at %s" % at)
    Fixtures.teardown(surface, made[1])


## The third clause: Layer on an ordinary relief layer writes the crop
## into its colour and its height, leaves the canvas and Paint as they were,
## and says nothing. One undo gives every byte back.
func test_layer_crops_a_relief_layer_in_its_chunks() -> void:
    var made := _set_up()
    var surface: SaSurface = made[0]
    var tool: StateCropScript = made[2]
    var doc := surface.get_document()
    var paint := doc.get_node("Paint") as SaLayer
    var relief := doc.get_node("Relief") as SaLayer
    var was := _before(doc)
    var bytes := _bytes_of(relief)
    var steps := doc.history.step_count()
    tool.mode = StateCropScript.Mode.LAYER
    _drag_box(tool, surface.view)
    assert_true(tool.holds_session(), "The drag opens a session on the relief layer")
    tool.handle_input(_key(KEY_ENTER))
    assert_eq(doc.history.step_count(), steps + 1, "Enter writes one step")
    assert_true(SaProblems.pending_refusals.is_empty(), "and nothing is said in the corner: %s" % SaProblems.pending_refusals)
    assert_eq(doc.canvas_size, SIZE, "The canvas keeps its size")
    assert_null(relief.live_transform, "and the layer stays ordinary")
    for at: Vector2i in INSIDE:
        assert_eq(_reading(relief, at), was[at][1], "Relief keeps its colour and height inside at %s" % at)
    for at: Vector2i in OUTSIDE:
        assert_eq(_at(relief, at).a, 0.0, "and holds no colour outside at %s" % at)
        assert_eq(_at(relief, at, SaFieldSpec.HEIGHT).r, 0.0, "and no height at %s" % at)
        assert_eq(_reading(paint, at), was[at][0], "while Paint is untouched at %s" % at)
    assert_true(doc.undo(), "Undo")
    assert_eq(_bytes_of(relief), bytes, "gives every byte back")
    Fixtures.teardown(surface, made[1])


## And a smart layer that carries a relief takes a live crop like any smart
## layer, since its height moves with its colour.
func test_layer_crops_a_smart_relief_layer_live() -> void:
    var made := _set_up()
    var surface: SaSurface = made[0]
    var tool: StateCropScript = made[2]
    var doc := surface.get_document()
    var paint := doc.get_node("Paint") as SaLayer
    doc.set_active_layer(paint)
    SaLiveTransform.put(doc, paint, Basis.IDENTITY)
    paint.add_field(SaFieldSpec.height())
    tool.mode = StateCropScript.Mode.LAYER
    _drag_box(tool, surface.view)
    assert_true(SaProblems.pending_refusals.is_empty(), "The press says nothing: %s" % SaProblems.pending_refusals)
    assert_true(tool.crop_now(), "and Enter crops")
    assert_true((paint.live_transform as SaLiveTransform).crop.any(), "leaving the layer's crop live")
    Fixtures.teardown(surface, made[1])


static func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


static func _key(code: Key) -> InputEventKey:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    return event
