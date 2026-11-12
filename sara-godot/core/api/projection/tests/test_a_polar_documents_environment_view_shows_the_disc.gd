## A polar document's Environment view shows the document as a
## disc, the angle round the centre and the radius outwards, through the flat
## view's own pan and zoom, and the pointer maps back through the same map.
##
## The requirement: "A new suite maps the disc's centre and four rim
## points to document pixels and back." Each point is read the way a tool reads
## it, through the canvas view's `get_document_mouse_position`, and held
## against the pixel worked out here from where the point stands on the disc:
## the centre is the top row, the rim the last, and the angle runs right round
## from where each preset points it, up for Godot's and left for Blender's.
## Back is the kind's `to_view` of the read pixel placed on the disc the same
## way, which lands on the point the pointer stood on. The disc is worked out
## from the flat canvas alone, its centre the canvas's middle and its rim the
## canvas's height out, so the view's own map is never asked for the answer.
##
## The same file reads the rest of the polar build list: the pan and zoom of the flat
## view, a stroke round the disc painting one row, a dab at the centre folding
## as at a pole, a dab painted halfway out round on the disc inside the ring,
## and the table the shader reads laid over the disc. The surface is the real
## one, as in the other environment suites, so it asks for a GPU.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

## Twice as wide as tall, a panorama assigned polar, so a row is shorter round
## the rim than it is across the document and longer near the centre.
const SIZE := Vector2i(1024, 512)
## The dab's radius in texels.
const RADIUS := 8.0
## How near a read pixel must be to the one worked out, in document pixels.
const NEAR := 0.01
## How near a point mapped back must land, in pixels of the view.
const BACK := 0.01
## How far apart a round dab's width and height may be.
const ROUND := 0.1
## What counts as paint at a dab's soft edge.
const VISIBLE := 0.05
## The rim's four points, up, right, down and left on the screen, and the
## fraction across the document each preset puts there: angle nought up for
## Godot's, a quarter turn back, to the left, for Blender's, and the angle
## running right round, clockwise on the screen, under both.
const RIM: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const ACROSS: Dictionary[StringName, Array] = {
    SaProjection.Heading.GODOT: [0.0, 0.25, 0.5, 0.75],
    SaProjection.Heading.BLENDER: [0.25, 0.5, 0.75, 0.0],
}

var _host: Control = null
var _main: Node = null
var _view: SaEnvironmentView = null
## The canvas's factory lists as the suite found them, put back after each test.
var _overlays_found: Array[Callable] = []
var _surface_overlays_found: Array[Callable] = []


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaCursorPolicy.forget_pointer_device()
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "H7Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _canvas().canvas_size = SIZE
    _plant_the_factories()
    _host.add_child(_main)
    _main.call("bind_tools", Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _view = SaEnvironmentView.of_canvas(_canvas())
    _machine().set_active_tool(&"brush")
    _machine().get_tool(&"brush").settings.radius = RADIUS / float(mini(SIZE.x, SIZE.y))


## The surface factory main.gd's `_init` registers, the view's, and no other,
## set here rather than read off whatever an earlier suite left. A Main any
## suite built before this one leaves its factories on `SaCanvas`, so the
## canvas attaches a view of its own, and a second one attached by hand is the
## one `of_canvas` never finds.
func _plant_the_factories() -> void:
    _overlays_found = SaCanvas.overlay_factories
    _surface_overlays_found = SaCanvas.surface_overlay_factories
    var none: Array[Callable] = []
    var the_view: Array[Callable] = [SaEnvironmentView.attach_to]
    SaCanvas.overlay_factories = none
    SaCanvas.surface_overlay_factories = the_view


func after_each() -> void:
    SaCanvas.overlay_factories = _overlays_found
    SaCanvas.surface_overlay_factories = _surface_overlays_found
    SaPointerDevice.suite_pointer = null
    SaCursorPolicy.forget_pointer_device()
    if _view != null and _view.on:
        _view.set_on(false)
    if _host != null:
        var machine := _machine()
        machine.registered_tools.clear()
        machine.active_tool = null
        machine.registry = null
        _host.free()
    _host = null
    _main = null
    _view = null
    ToolMachine.pointer_holder = &""


func _canvas() -> SaCanvas:
    return _main.get("canvas")


func _machine() -> ToolMachine:
    return _main.get("tool_machine")


## The document assigned polar in *preset*, and the view on over it.
func _disc_on(preset: StringName = SaProjection.Heading.BLENDER) -> void:
    var turned := SaProjection.Heading.new(preset)
    _canvas().document.projection = SaProjection.new(SaProjection.Polar.new(), turned)
    assert_true(_view.set_on(true), "The view goes on over a polar document in %s" % preset)


## The disc's centre and radius in the view's own space, worked out from the
## flat canvas: its middle, and the canvas's height out from it.
func _disc() -> Array:
    var to_view := _view.get_global_transform().affine_inverse() * _canvas().get_global_transform()
    var centre := to_view * (Vector2(SIZE) * 0.5)
    var radius := to_view.basis_xform(Vector2(0.0, SIZE.y)).length()
    return [centre, radius]


## *local*, a point in the view's own space, in the main window's.
func _in_window(local: Vector2) -> Vector2:
    return _view.get_global_transform() * local


## What a tool reads with the pointer at *local*, a point in the view's space.
func _read_at(local: Vector2) -> Vector2:
    var root := (Engine.get_main_loop() as SceneTree).root
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(root) * _in_window(local)
    return _canvas().view().get_document_mouse_position()


## Where the kind's `to_view` of *pixel* stands in the view's space, on the
## disc of centre *centre* and radius *radius*, up the disc up the screen.
func _back(pixel: Vector2, centre: Vector2, radius: float) -> Vector2:
    var on_disc := _canvas().document.projection.to_view(pixel, Vector2(SIZE))
    return centre + Vector2(on_disc.x, -on_disc.y) * radius


## A left press, motion or release at *local*, handed to the main window the way
## a window hands one the display server delivered.
func _hand(event: InputEventMouse, local: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var at := _in_window(local)
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(root) * at
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    root.push_input(event)


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    return event


func _motion() -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    event.pressure = 1.0
    return event


## A fresh layer, active, for one dab or stroke.
func _layer() -> SaLayer:
    var document := _canvas().document
    var layer := SaLayerOps.new(document).add()
    document.set_active_layer(layer)
    return layer


## Every texel of *layer* with paint above nought, its position to its alpha.
static func _paint(layer: SaLayer) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        for y in range(edge):
            for x in range(edge):
                var alpha := SaFieldSpec.decode_texel(bytes, texture.format, y * edge + x).a
                if alpha > 0.0:
                    out[grid_pos * edge + Vector2i(x, y)] = alpha
    return out


## How far *x* lies from *wanted* round a document *width* wide.
static func _round_the_seam(x: float, wanted: float, width: float) -> float:
    return absf(wrapf(x - wanted, -width * 0.5, width * 0.5))


func test_the_centre_and_four_rim_points_map_to_document_pixels_and_back_under_both_presets() -> void:
    for preset: StringName in ACROSS:
        _disc_on(preset)
        var disc := _disc()
        var centre: Vector2 = disc[0]
        var radius: float = disc[1]
        var middle := _read_at(centre)
        assert_true(middle.y < NEAR, "In %s the disc's centre reads the top row, %s" % [preset, middle])
        assert_true(_back(middle, centre, radius).distance_to(centre) < BACK, "and maps back to the centre")
        for at in RIM.size():
            var point := centre + RIM[at] * radius
            var read := _read_at(point)
            var wanted: float = ACROSS[preset][at] * SIZE.x
            var words := "In %s the rim %s of the centre reads %s" % [preset, RIM[at], read]
            assert_true(_round_the_seam(read.x, wanted, SIZE.x) < NEAR, "%s, %s across" % [words, wanted])
            assert_almost_eq(read.y, float(SIZE.y), NEAR, "%s, the last row" % words)
            var back := _back(read, centre, radius)
            assert_true(back.distance_to(point) < BACK, "and maps back to %s, %s" % [point, back])
        _view.set_on(false)


## The view fits the whole disc in the frame when it goes on, the pan and the
## zoom of the flat view then move the disc as they move the flat picture, and
## the flat view is put back when it goes off.
func test_the_flat_views_pan_and_zoom_move_the_disc() -> void:
    var flat := _canvas().view()
    var before := [flat.get_pan(), flat.get_zoom()]
    _disc_on()
    var free := flat.get_free_rect()
    var disc := _disc()
    var to_view: Transform2D = _view.get_global_transform().affine_inverse() * _main.get("control_node").get_global_transform()
    var centre: Vector2 = to_view * free.get_center()
    assert_true((disc[0] as Vector2).distance_to(centre) < 0.5, "The disc stands in the middle of the frame, %s" % disc[0])
    assert_almost_eq(float(disc[1]) * 2.0, minf(free.size.x, free.size.y), 0.5, "as wide as the frame is short")
    flat.zoom_at(flat.get_zoom() * 1.5, centre + Vector2(60.0, -30.0))
    flat.set_pan(flat.get_pan() + Vector2(40.0, -25.0))
    var moved := _disc()
    assert_almost_eq(float(moved[1]), float(disc[1]) * 1.5, 0.01, "A zoom enlarges the disc")
    var middle := _read_at(moved[0])
    assert_true(middle.y < NEAR, "and its moved centre still reads the top row, %s" % middle)
    var rim := _read_at((moved[0] as Vector2) + Vector2.RIGHT * float(moved[1]))
    assert_true(_round_the_seam(rim.x, SIZE.x * 0.5, SIZE.x) < NEAR, "and its rim to the right half across, %s" % rim)
    assert_almost_eq(rim.y, float(SIZE.y), NEAR, "on the last row")
    _view.set_on(false)
    assert_eq(flat.get_pan(), before[0], "The flat view's pan is put back")
    assert_eq(flat.get_zoom(), before[1], "and its zoom")


## A stroke round the disc's centre is a horizontal stroke in the document: the
## pointer reads one row all the way round, and the brush paints that row from
## edge to edge, crossing the seam the short way, and nothing far above or below.
func test_a_stroke_round_the_disc_paints_one_row_of_the_document() -> void:
    _disc_on()
    var disc := _disc()
    var centre: Vector2 = disc[0]
    var half: float = disc[1] * 0.5
    var layer := _layer()
    var steps := 48
    for step in range(steps + 1):
        var turn := TAU * step / steps
        var local := centre + Vector2(sin(turn), -cos(turn)) * half
        var event: InputEventMouse = _motion()
        if step == 0:
            event = _button(true)
        _hand(event, local)
        var read := _read_at(local)
        assert_almost_eq(read.y, SIZE.y * 0.5, NEAR, "Step %d round the disc reads the middle row, %s" % [step, read])
    _hand(_button(false), centre + Vector2(0.0, -half))
    var paint := _paint(layer)
    var row := SIZE.y >> 1
    var missing := PackedInt32Array()
    for x in range(SIZE.x):
        if float(paint.get(Vector2i(x, row), 0.0)) <= VISIBLE:
            missing.append(x)
    assert_eq(missing.size(), 0, "Every column of the middle row is painted, missing %s" % missing.slice(0, 8))
    var far := 0
    for texel: Vector2i in paint:
        if paint[texel] > VISIBLE and absi(texel.y - row) > int(RADIUS) + 2:
            far += 1
    assert_eq(far, 0, "and nothing more than the dab's radius above or below it")


## A dab at the disc's centre lands on the top row, which is one point, and
## folds over it as at a pole: the top row is painted at every column, and no
## chunk past the canvas is touched.
func test_a_dab_at_the_centre_folds_as_at_a_pole() -> void:
    _disc_on()
    var centre: Vector2 = _disc()[0]
    var layer := _layer()
    var at := _read_at(centre)
    assert_true(at.y < NEAR, "The press reads the top row, %s" % at)
    _hand(_button(true), centre)
    _hand(_button(false), centre)
    var paint := _paint(layer)
    var missing := PackedInt32Array()
    for x in range(SIZE.x):
        if float(paint.get(Vector2i(x, 0), 0.0)) <= VISIBLE:
            missing.append(x)
    assert_eq(missing.size(), 0, "Every column of the top row is painted, missing %s" % missing.slice(0, 8))
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var edge := (layer.chunks[grid_pos] as SaChunk).pixel_size()
        var inside := Rect2i(Vector2i.ZERO, SIZE).encloses(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
        assert_true(inside, "The chunk at %s is inside the canvas" % grid_pos)


## A round dab halfway out, where a document pixel is drawn wider round the
## disc than it is tall, is narrowed across by the kind's stretch and comes out
## round on the disc, and the ring is drawn at its size.
func test_a_dab_halfway_out_is_round_on_the_disc_and_the_ring_holds_it() -> void:
    _disc_on()
    var disc := _disc()
    var local: Vector2 = (disc[0] as Vector2) + Vector2(1.0, -1.0).normalized() * float(disc[1]) * 0.5
    var layer := _layer()
    var at := _read_at(local)
    var size := Vector2(SIZE)
    var projection := _canvas().document.projection
    assert_almost_eq(projection.stretch(at, size), SIZE.x / (TAU * SIZE.y * 0.5), 0.001, "The stretch halfway out is under one")
    _hand(_button(true), local)
    _hand(_button(false), local)
    var paint := _paint(layer)
    assert_true(paint.size() > 0, "The dab paints")
    # The spread of the paint on the disc along the radius and round it, every
    # texel weighted by its alpha and by the part of the disc it covers, which
    # grows with its radius.
    var middle := projection.to_view(at, size)
    var out := Vector2(middle.x, middle.y).normalized()
    var round_it := Vector2(out.y, -out.x)
    var total := 0.0
    var sums := Vector2.ZERO
    var squares := Vector2.ZERO
    for texel: Vector2i in paint:
        var centre := Vector2(texel) + Vector2(0.5, 0.5)
        var point := projection.to_view(centre, size)
        var flat := Vector2(point.x, point.y)
        var along := Vector2(flat.dot(round_it), flat.dot(out))
        var weight: float = paint[texel] * centre.y
        total += weight
        sums += along * weight
        squares += along * along * weight
    var mean := sums / total
    var spread := squares / total - mean * mean
    var across := 4.0 * sqrt(spread.x) * SIZE.y
    var down := 4.0 * sqrt(spread.y) * SIZE.y
    var words := "The dab is %.3f rows round the disc and %.3f along the radius" % [across, down]
    assert_true(absf(across / down - 1.0) <= ROUND, words)
    var ring := SaEnvironmentView.ring_scale(_canvas(), _in_window(local))
    assert_almost_eq(ring, 1.0, 0.01, "The ring is drawn at the flat dab's size, since a row is a pixel of the flat canvas")


## The table the shader reads is the kind's own map over a grid of the disc in
## angle and radius, and the shader is told the view is a plane.
func test_the_shader_reads_the_kinds_map_over_the_disc() -> void:
    var projection := SaProjection.new(SaProjection.Polar.new())
    var table := SaEnvironmentView.Lookup.table(projection, Vector2(SIZE))
    for cell: Vector2i in [Vector2i(0, 0), Vector2i(64, 64), Vector2i(200, 100), Vector2i(255, 127)]:
        var position := SaEnvironmentView.Lookup.direction(Vector2(cell), SaProjection.View.DISC)
        assert_almost_eq(position.z, 0.0, 0.00001, "The cell %s is a point of the disc" % cell)
        var radius := (cell.y + 0.5) / SaEnvironmentView.Lookup.DOWN
        assert_almost_eq(Vector2(position.x, position.y).length(), radius, 0.00001, "at its fraction of the radius")
        var wanted := projection.from_view(position, Vector2(SIZE)) / Vector2(SIZE)
        var stored := table.get_pixelv(cell)
        assert_almost_eq(stored.r, wanted.x, 0.00001, "the table's across at %s" % cell)
        assert_almost_eq(stored.g, wanted.y, 0.00001, "the table's down at %s" % cell)
    _disc_on()
    var material: ShaderMaterial = _view.get("_composer").material
    assert_eq(material.get_shader_parameter(&"sa_env_plane"), true, "The shader is told the view is a plane")
    _view.set_on(false)
    _canvas().document.projection = SaProjection.new(SaProjection.Equirectangular.new())
    assert_true(_view.set_on(true), "and over a panorama")
    assert_eq(material.get_shader_parameter(&"sa_env_plane"), false, "that it is a sphere")
