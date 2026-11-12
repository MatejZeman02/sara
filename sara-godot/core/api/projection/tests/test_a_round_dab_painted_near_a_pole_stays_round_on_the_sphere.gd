## A round dab painted in the Environment view comes out round on
## the sphere. The brush stretches each dab in the document's x by the kind's
## stretch at its centre, one over the cosine of the latitude on an
## equirectangular document, and a dab that reaches past the top row lands
## folded across the pole at the longitude half a turn away, read downward.
##
## The requirement: "A new suite paints one round dab in the
## Environment view at latitudes nought, sixty and eighty-five degrees, maps the
## painted texels back to directions, and reads each dab's angular width and
## height within a tenth of each other below the cap", and "The same suite
## paints a dab centred on the north pole and reads paint on the top row at all
## longitudes, and none past the canvas."
##
## The surface is the real one, as in the suites under `render/environment`:
## the main canvas with its tool machine and the Environment view beside it in
## the main window, so it asks for a GPU. A dab's width and height are read on
## the plane that touches the sphere at its centre, as four times the spread of
## its paint each way, every texel weighted by its alpha and by the part of the
## sphere it covers. A dab eight texels in radius read by its edge would be a
## texel off at either side, a tenth of its height between them.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")
const TipScript = preload("res://core/api/tip/sa_brush_tip.gd")

## Twice as wide as tall, so a texel at the equator is as wide as it is tall.
const SIZE := Vector2i(2048, 1024)
## The dab's radius in texels, about a degree and a half, small enough that the
## stretch at its centre holds across it at eighty-five degrees.
const RADIUS := 8.0
## The latitudes the round dab is painted at, in degrees.
const LATITUDES: Array[float] = [0.0, 60.0, 85.0]
## How far apart a round dab's width and height may be.
const ROUND := 0.1
## What counts as paint at a dab's soft edge.
const VISIBLE := 0.05
## How far a press may read from the pixel the camera's middle looks at.
const NEAR := 0.01

var _host: Control = null
var _main: Node = null
var _view: SaEnvironmentView = null


func before_each() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    SaCursorPolicy.forget_pointer_device()
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    _host = Control.new()
    _host.name = "H6Host"
    _host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _host.size = Vector2(tree.root.size)
    EventBus.add_child(_host)
    _main = MainCanvasScript.new()
    _canvas().canvas_size = SIZE
    _host.add_child(_main)
    _main.call("bind_tools", Fixtures.make_tool_registry())
    _main.notification(Container.NOTIFICATION_SORT_CHILDREN)
    _view = SaEnvironmentView.attach_to(_main.get("control_node"), _canvas())
    _machine().set_active_tool(&"brush")
    _machine().get_tool(&"brush").settings.radius = RADIUS / float(mini(SIZE.x, SIZE.y))
    _canvas().document.projection = SaProjection.new(SaProjection.Equirectangular.new())


func after_each() -> void:
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


## *local*, a point in the view's own space, in the main window's.
func _in_window(local: Vector2) -> Vector2:
    return _view.get_global_transform() * local


## What a tool reads with the pointer at *local*, a point in the view's space.
func _read_at(local: Vector2) -> Vector2:
    var root := (Engine.get_main_loop() as SceneTree).root
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(root) * _in_window(local)
    return _canvas().view().get_document_mouse_position()


## A left press or release at *local*, handed to the main window the way a
## window hands one the display server delivered.
func _hand(pressed: bool, local: Vector2) -> void:
    var root := (Engine.get_main_loop() as SceneTree).root
    var at := _in_window(local)
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    SaPointerDevice.suite_pointer = SaPointerDevice.desktop_transform(root) * at
    event.position = root.get_final_transform() * at
    event.global_position = event.position
    root.window_input.emit(event)
    root.push_input(event)


## One dab, a press and its release at *local*, on a layer of its own, which
## it returns with the pixel the press read.
func _dab(local: Vector2) -> Array:
    var document := _canvas().document
    var layer := SaLayerOps.new(document).add()
    document.set_active_layer(layer)
    var at := _read_at(local)
    _hand(true, local)
    _hand(false, local)
    return [layer, at]


## Turns the camera at yaw nought to look *degrees* above the horizon.
func _look_up(degrees: float) -> void:
    var height := _view.frame().size.y
    var drag := (deg_to_rad(degrees) - _view.camera.pitch) / _view.camera.per_pixel(height)
    _view.camera.turn(Vector2(0.0, drag), height)
    assert_almost_eq(rad_to_deg(_view.camera.pitch), degrees, 0.0001, "The camera looks %s degrees up" % degrees)


## Every texel of *layer* with paint above nought, its position to its alpha.
## Only the rows above *rows* are read, every row when it is nought.
static func _paint(layer: SaLayer, rows: int = 0) -> Dictionary:
    var out := {}
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var chunk: SaChunk = layer.chunks[grid_pos]
        var texture := chunk.albedo()
        var edge := chunk.pixel_size()
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
        var down := edge if rows <= 0 else clampi(rows - grid_pos.y * edge, 0, edge)
        for y in range(down):
            for x in range(edge):
                var alpha := SaFieldSpec.decode_texel(bytes, texture.format, y * edge + x).a
                if alpha > 0.0:
                    out[grid_pos * edge + Vector2i(x, y)] = alpha
    return out


## The box around every texel of *paint* above VISIBLE.
static func _box(paint: Dictionary) -> Rect2:
    var box := Rect2()
    var found := false
    for texel: Vector2i in paint:
        if paint[texel] <= VISIBLE:
            continue
        var cell := Rect2(Vector2(texel), Vector2.ONE)
        box = cell if not found else box.merge(cell)
        found = true
    return box


## The angular width and height of *paint*, in radians, on the plane touching
## the sphere at the direction of *centre*: four times the spread of its paint
## across and down, which for a disc of even paint is its diameter.
func _angular_size(paint: Dictionary, centre: Vector2) -> Vector2:
    var projection := _canvas().document.projection
    var size := Vector2(SIZE)
    var middle := projection.to_view(centre, size)
    var east := projection.to_view(centre + Vector2(0.5, 0.0), size) - projection.to_view(centre - Vector2(0.5, 0.0), size)
    east = (east - middle * east.dot(middle)).normalized()
    var north := middle.cross(east).normalized()
    var total := 0.0
    var sums := Vector2.ZERO
    var squares := Vector2.ZERO
    for texel: Vector2i in paint:
        var at := Vector2(texel) + Vector2(0.5, 0.5)
        var ray := projection.to_view(at, size)
        var flat := Vector2(ray.dot(east), ray.dot(north)) / ray.dot(middle)
        var weight: float = paint[texel] * cos(PI * (0.5 - at.y / size.y))
        total += weight
        sums += flat * weight
        squares += flat * flat * weight
    var mean := sums / total
    var spread := squares / total - mean * mean
    return Vector2(4.0 * sqrt(spread.x), 4.0 * sqrt(spread.y))


func test_a_round_dab_is_round_on_the_sphere_at_nought_sixty_and_eighty_five_degrees() -> void:
    assert_true(_view.set_on(true), "The view goes on over a panorama")
    var middle := _view.frame().get_center()
    var level := 0.0
    for degrees in LATITUDES:
        _look_up(degrees)
        var dabbed := _dab(middle)
        var layer: SaLayer = dabbed[0]
        var at: Vector2 = dabbed[1]
        var row := (0.5 - degrees / 180.0) * SIZE.y
        assert_true(at.distance_to(Vector2(SIZE.x * 0.25, row)) < NEAR, "At %s degrees the press reads %s" % [degrees, at])
        var wanted := 1.0 / cos(deg_to_rad(degrees))
        var said := _canvas().document.projection.stretch(at, Vector2(SIZE))
        assert_almost_eq(said, wanted, 0.001, "and the kind's stretch there is one over the cosine")
        var paint := _paint(layer)
        assert_true(_box(paint).has_area(), "The dab at %s degrees paints, %s" % [degrees, _box(paint)])
        var angles := _angular_size(paint, at)
        var degrees_across := Vector2(rad_to_deg(angles.x), rad_to_deg(angles.y))
        var words := "and on the sphere it is %.3f degrees wide and %.3f tall" % [degrees_across.x, degrees_across.y]
        assert_true(absf(angles.x / angles.y - 1.0) <= ROUND, words)
        if is_zero_approx(degrees):
            level = angles.y
        assert_true(absf(angles.y / level - 1.0) <= ROUND, "as tall as the dab at the equator, %s" % degrees_across)


func test_a_dab_on_the_north_pole_paints_the_top_row_at_every_longitude_and_nothing_past_the_canvas() -> void:
    assert_true(_view.set_on(true), "The view goes on over a panorama")
    _look_up(90.0)
    var dabbed := _dab(_view.frame().get_center())
    var layer: SaLayer = dabbed[0]
    var at: Vector2 = dabbed[1]
    assert_true(at.y < NEAR, "The press reads the top row, %s" % at)
    var top := _paint(layer, 1)
    var missing := PackedInt32Array()
    for x in range(SIZE.x):
        if float(top.get(Vector2i(x, 0), 0.0)) <= VISIBLE:
            missing.append(x)
    assert_eq(missing.size(), 0, "Every longitude of the top row is painted, missing %s" % missing.slice(0, 8))
    for grid_pos: Vector2i in SaTyped.positions(layer.chunks):
        var edge := (layer.chunks[grid_pos] as SaChunk).pixel_size()
        var inside := Rect2i(Vector2i.ZERO, SIZE).encloses(Rect2i(grid_pos * edge, Vector2i(edge, edge)))
        assert_true(inside, "The chunk at %s is inside the canvas" % grid_pos)


## The flat view paints the dab the painter sees there, neither stretched nor
## folded across the pole, however near the top row it lands.
func test_a_dab_painted_in_the_flat_view_is_round_in_texels_and_not_folded() -> void:
    var pixel := Vector2(SIZE.x * 0.25, 3.0)
    var window := _canvas().get_global_transform_with_canvas() * pixel
    var local := _view.get_global_transform().affine_inverse() * window
    var dabbed := _dab(local)
    var at: Vector2 = dabbed[1]
    assert_true(at.distance_to(pixel) < 0.5, "The press reads %s near the top row" % at)
    assert_eq(_canvas().view().dab_stretch(at), 0.0, "and the flat view asks for the flat dab")
    var box := _box(_paint(dabbed[0]))
    assert_true(box.has_area(), "The dab paints")
    assert_true(box.size.x <= 2.0 * RADIUS + 2.0, "no wider than its own size, %s" % box)
    assert_true(absf(box.get_center().x - at.x) <= 1.5, "and nothing of it lands half a turn away, %s" % box)


## A round dab's stretch is the one asked for and its axes stay level, and a
## dab painted flat, asked for no stretch, is the dab it was.
func test_the_stretch_widens_a_round_dab_in_x_and_leaves_a_flat_one() -> void:
    var tip := TipScript.new()
    var flat := SaProjection.Stretched.new(Vector2(8.0, 8.0), 0.3, 0.0, tip, 2048.0)
    assert_eq(flat.half_extent, Vector2(8.0, 8.0), "A dab asked for no stretch keeps its size")
    assert_eq(flat.radians, 0.3, "and its turn")
    var even := SaProjection.Stretched.new(Vector2(8.0, 8.0), 0.3, 2.0, tip, 2048.0)
    assert_almost_eq(even.stretch, 2.0, 0.0001, "A round dab takes the stretch asked for")
    assert_true(even.half_extent.distance_to(Vector2(16.0, 8.0)) < 0.0001, "twice as wide, %s" % even.half_extent)
    assert_almost_eq(even.radians, 0.0, 0.0001, "with its axes level")


## The stretched ellipse is the flat one's image exactly: every point of the
## flat outline, stretched, lies on the outline the kernel is handed.
func test_a_turned_ellipse_stretched_is_the_ellipse_the_kernel_draws() -> void:
    var tip := TipScript.new()
    for turn: float in [0.0, 0.4, 1.2, -2.0]:
        var drawn := SaProjection.Stretched.new(Vector2(10.0, 4.0), turn, 3.0, tip, 2048.0)
        for step in range(12):
            var t := TAU * step / 12.0
            var point := Vector2(10.0 * cos(t), 4.0 * sin(t)).rotated(turn) * Vector2(3.0, 1.0)
            var local := point.rotated(-drawn.radians) / drawn.half_extent
            var words := "At a turn of %s the point %s lies on the outline, %.5f" % [turn, point, local.length()]
            assert_almost_eq(local.length(), 1.0, 0.0001, words)


## The cap: a dab whose stretch would run past half the canvas's width either
## side of its centre stops there, and a picture tip's x axis takes it.
func test_the_stretch_stops_at_half_the_canvas_either_side() -> void:
    var tip := TipScript.new()
    var capped := SaProjection.Stretched.new(Vector2(8.0, 8.0), 0.0, INF, tip, 2048.0)
    assert_almost_eq(capped.stretch, 128.0, 0.0001, "The pole's stretch stops at the canvas's half width over the radius")
    assert_almost_eq(capped.half_extent.x, 1024.0, 0.001, "so the dab reaches half the canvas either side")
    tip.shape = TipScript.Shape.RECTANGLE
    var square := SaProjection.Stretched.new(Vector2(8.0, 4.0), 0.0, 3.0, tip, 2048.0)
    assert_true(square.half_extent.distance_to(Vector2(24.0, 4.0)) < 0.0001, "A rectangle widens, %s" % square.half_extent)
    tip.shape = TipScript.Shape.CIRCLE
    tip.spikes = 5
    var spiked := SaProjection.Stretched.new(Vector2(8.0, 8.0), 0.0, 3.0, tip, 2048.0)
    assert_eq(spiked.half_extent, Vector2(8.0, 8.0), "A spiked tip keeps its flat shape")


## Past the top row the fold is the top row half a turn away, read downward,
## past the bottom one the bottom row likewise, and a flat document has none.
## A polar document's radius nought is its pole, and folds the same way.
func test_a_region_past_a_pole_folds_half_a_turn_away() -> void:
    var size := Vector2(SIZE)
    var projection := SaProjection.new(SaProjection.Equirectangular.new())
    var top := projection.pole_folds(Rect2(100.0, -6.0, 20.0, 20.0), size)
    assert_eq(top.size(), 1, "A region past the top row folds once")
    assert_eq(top[0] * Vector2(110.0, -3.0), Vector2(110.0 + size.x * 0.5, 3.0), "to the far side, read downward")
    assert_eq(top[0] * Vector2(110.0, -3.0), projection.fold(Vector2(110.0, -3.0), size), "where the kind folds a point")
    var bottom := projection.pole_folds(Rect2(100.0, size.y - 10.0, 20.0, 20.0), size)
    assert_eq(bottom.size(), 1, "A region past the bottom row folds once")
    assert_eq(bottom[0] * Vector2(110.0, size.y + 4.0), Vector2(110.0 + size.x * 0.5, size.y - 4.0), "likewise")
    assert_eq(projection.pole_folds(Rect2(100.0, 10.0, 20.0, 20.0), size).size(), 0, "A region inside does not fold")
    assert_eq(SaProjection.new().pole_folds(Rect2(100.0, -6.0, 20.0, 20.0), size).size(), 0, "nor does a flat document")
    var polar := SaProjection.new(SaProjection.Polar.new())
    var centre := polar.pole_folds(Rect2(100.0, -6.0, 20.0, 20.0), size)
    assert_eq(centre.size(), 1, "A polar region past radius nought folds through the centre")
    assert_eq(centre[0] * Vector2(110.0, -3.0), polar.fold(Vector2(110.0, -3.0), size), "where the kind folds a point")
    assert_eq(polar.pole_folds(Rect2(100.0, size.y - 10.0, 20.0, 20.0), size).size(), 0, "and its rim does not fold")
    assert_eq(polar.stretch(Vector2(10.0, 0.0), size), INF, "Its stretch at radius nought is infinite, as at a pole")


## A copy landing folded is drawn turned over: its turn's sine and its mirror
## down change, and an unfolded copy's dab is the one asked for.
func test_a_folded_copy_draws_its_dab_turned_over() -> void:
    var context := SaPaintContext.new()
    var data := PackedFloat32Array()
    data.resize(32)
    data[SaPaintContext.TURN_SINE] = 0.5
    data[SaDabGeometry.MIRROR_INDEX] = 1.0
    var straight := SaPaintContext.Target.new()
    assert_eq(context.dab(data, straight), data, "An unfolded copy draws the dab asked for")
    var folded := SaPaintContext.Target.new()
    folded.landing = SaProjection.Kind.pole_map(Vector2(SIZE))
    var drawn := context.dab(data, folded)
    assert_eq(drawn[SaPaintContext.TURN_SINE], -0.5, "A folded copy's turn runs the other way")
    assert_eq(drawn[SaDabGeometry.MIRROR_INDEX], 3.0, "and it is mirrored down")
    assert_eq(data[SaPaintContext.TURN_SINE], 0.5, "while the dab asked for is left as it was")
