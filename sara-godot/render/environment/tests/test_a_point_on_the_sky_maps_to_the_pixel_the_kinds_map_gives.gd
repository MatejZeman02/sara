## A point on the Environment view is the document pixel the camera's ray
## through it lands on, the pixel a tool reads, and a painting tool's stroke
## across the seam reads the short way round it.
##
## The suite maps four screen points at two field-of-view settings to document
## pixels and reads the pixels the kind's map gives. The
## points are read the way a tool reads them, through the canvas view's
## `get_document_mouse_position` with the suite's place for the pointer, and
## each is held against the pixel worked out here from the angles of the ray
## and against `from_view`, the kind's own map. The same file holds the rest of
## the rest of its list: the short way round, the ring and the seam's guide on the
## flat view. Its corner sentence, that the sky takes the flat dab, went with
## the round dab, which is read in `core/api/projection/tests`.
##
## The surface is the real one, the main canvas with its tool machine and the
## Environment view beside its canvas, in the main window, so it asks for a GPU.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const MainCanvasScript = preload("res://render/main_canvas.gd")

const SIZE := Vector2i(1024, 512)
## The points, as fractions of the uncovered frame: the middle, one on the
## horizon to the left, one above and right, one below and left.
const POINTS: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.1, 0.5), Vector2(0.8, 0.25), Vector2(0.3, 0.9)]
## The two fields of view, in degrees: the camera's own and a narrower one.
const FIELDS: Array[float] = [75.0, 40.0]
## How near a read pixel must be to the one worked out, in document pixels.
const NEAR: float = 0.01

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
    _host.name = "SkyHost"
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


## The surface factory main.gd's `_init` registers, the view's, and no other,
## set here rather than read off whatever an earlier suite left. A Main built
## by any suite before this one, the freeze suite's among them, leaves its
## factories on `SaCanvas`, and a view attached by hand on top of the one its
## factory built was a second view, the one `of_canvas` never finds.
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


func _panorama() -> void:
    _canvas().document.projection = SaProjection.new(SaProjection.Equirectangular.new())


## The view on over an equirectangular document, at the camera's start.
func _sky() -> void:
    _panorama()
    assert_true(_view.set_on(true), "The view goes on over a panorama")


## *local*, a point in the view's own space, in the main window's.
func _in_window(local: Vector2) -> Vector2:
    return _view.get_global_transform() * local


## What a tool reads with the pointer at *local*, a point in the view's space.
func _read_at(local: Vector2) -> Vector2:
    var root := (Engine.get_main_loop() as SceneTree).root
    var to_desktop: Transform2D = SaPointerDevice.desktop_transform(root)
    SaPointerDevice.suite_pointer = to_desktop * _in_window(local)
    return _canvas().view().get_document_mouse_position()


## The pixel an equirectangular document in Blender's orientation gives the
## ray through *local* at yaw and pitch nought, worked out from its angles
## here rather than asked of the kind: a field of view *fov* tall over the
## frame *shown*, longitude from straight ahead turning right, nought a
## quarter of the way across, and latitude up from the middle row.
func _worked_out(local: Vector2, shown: Rect2, fov: float) -> Vector2:
    var reach := 2.0 * tan(fov * 0.5) / shown.size.y
    var off := (local - shown.get_center()) * reach
    var ray := Vector3(off.x, -off.y, -1.0).normalized()
    var longitude := atan2(ray.x, -ray.z)
    var latitude := asin(ray.y)
    return Vector2(fposmod(longitude / TAU + 0.25, 1.0) * SIZE.x, (0.5 - latitude / PI) * SIZE.y)


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


## Turns the camera to face the seam, which Blender's orientation puts a
## quarter turn to the left of where it starts.
func _face_the_seam() -> void:
    var height := _view.frame().size.y
    _view.camera.turn(Vector2(PI * 0.5 / _view.camera.per_pixel(height), 0.0), height)
    assert_almost_eq(_view.camera.yaw, -PI * 0.5, 0.0001, "The camera faces the seam")


## A stroke from 200 screen pixels left of the middle to 200 right of it, in
## steps of 20, and every reading the tool would take of it, the press's first.
func _stroke_across_the_middle() -> PackedVector2Array:
    var middle := _view.frame().get_center()
    var readings := PackedVector2Array()
    _hand(_button(true), middle - Vector2(200.0, 0.0))
    readings.append(_read_at(middle - Vector2(200.0, 0.0)))
    for step in range(-180, 201, 20):
        var at := middle + Vector2(float(step), 0.0)
        _hand(_motion(), at)
        readings.append(_read_at(at))
    _hand(_button(false), middle + Vector2(200.0, 0.0))
    return readings


## The main surface holds one Environment view, the one its factory built, and
## it is the one a tool's reading goes through.
func test_the_main_surface_holds_one_view_and_a_tool_reads_through_it() -> void:
    var views := 0
    for child: Node in (_main.get("control_node") as Control).get_children():
        if child is SaEnvironmentView:
            views += 1
    assert_eq(views, 1, "One Environment view beside the canvas")
    assert_true(_view != null and _view == SaEnvironmentView.of_canvas(_canvas()), "and it is the canvas's own")


func test_four_points_at_two_fields_of_view_read_the_pixels_the_kinds_map_gives() -> void:
    _sky()
    var shown := _view.frame()
    assert_true(shown.size.x > 100.0 and shown.size.y > 100.0, "The frame is a view to look through, %s" % shown)
    var projection := _canvas().document.projection
    for degrees in FIELDS:
        _view.camera.magnify(tan(_view.camera.fov * 0.5) / tan(deg_to_rad(degrees) * 0.5))
        assert_almost_eq(rad_to_deg(_view.camera.fov), degrees, 0.0001, "The field of view is %s degrees" % degrees)
        for fraction in POINTS:
            var local := shown.position + shown.size * fraction
            var words := "At %s degrees, the point %s of the frame" % [degrees, fraction]
            var read := _read_at(local)
            var worked := _worked_out(local, shown, _view.camera.fov)
            var mapped := projection.from_view(_view.camera.ray_at(local, shown), Vector2(SIZE))
            assert_true(read.distance_to(worked) < NEAR, "%s reads %s, and its angles give %s" % [words, read, worked])
            assert_true(read.distance_to(mapped) < NEAR, "%s reads %s, and the kind's map gives %s" % [words, read, mapped])
    # The middle at either field of view is the longitude yaw nought faces.
    assert_almost_eq(_read_at(shown.get_center()).x, SIZE.x * 0.25, NEAR, "The middle is a quarter across")


## The brush, the eyedropper and the bucket fill each read the pointer through
## the tool state's own `get_document_mouse_position`, which the fill floors to
## its seed, and each reads the pixel the kind's map gives the ray.
func test_the_brush_the_eyedropper_and_the_fill_read_the_sky() -> void:
    _sky()
    var shown := _view.frame()
    var local := shown.position + shown.size * Vector2(0.7, 0.35)
    var mapped := _canvas().document.projection.from_view(_view.camera.ray_at(local, shown), Vector2(SIZE))
    _read_at(local)
    for tool_id: StringName in [&"brush", &"eyedropper", &"bucket_fill"]:
        _machine().set_active_tool(tool_id)
        assert_eq(_machine().active_tool_name, tool_id, "The %s is the active tool" % tool_id)
        var read := _machine().active_tool.get_document_mouse_position()
        assert_true(read.distance_to(mapped) < NEAR, "The %s reads %s, and the kind's map gives %s" % [tool_id, read, mapped])


func test_a_flat_view_reads_the_pointer_through_the_pan_and_zoom() -> void:
    _panorama()
    var local := _view.frame().get_center() + Vector2(37.0, -21.0)
    var flat := _canvas().get_global_transform_with_canvas().affine_inverse() * _in_window(local)
    assert_true(_read_at(local).distance_to(flat) < NEAR, "With the view off the reading is the flat canvas's")


func test_a_painting_stroke_across_the_seam_reads_the_short_way_round() -> void:
    _sky()
    _face_the_seam()
    var readings := _stroke_across_the_middle()
    assert_true(readings[0].x > SIZE.x * 0.9 and readings[0].x < SIZE.x, "The press is left of the seam, %s" % readings[0])
    for at in range(1, readings.size()):
        var stride := readings[at].x - readings[at - 1].x
        assert_true(stride > 0.0 and stride < 20.0, "Reading %d moves %.2f to the right, through the seam" % [at, stride])
    var last := readings[readings.size() - 1]
    assert_true(last.x > SIZE.x and last.x < SIZE.x * 1.1, "The release is past the right edge, its copy at the left, %s" % last)
    # A new stroke starts inside the canvas again.
    var middle := _view.frame().get_center()
    _hand(_button(true), middle + Vector2(100.0, 0.0))
    var again := _read_at(middle + Vector2(100.0, 0.0))
    assert_true(again.x >= 0.0 and again.x < SIZE.x * 0.1, "The next press reads inside the canvas, %s" % again)
    _hand(_button(false), middle + Vector2(100.0, 0.0))


func test_the_eyedropper_reads_inside_the_canvas_across_the_seam() -> void:
    _sky()
    _face_the_seam()
    _machine().set_active_tool(&"eyedropper")
    var readings := _stroke_across_the_middle()
    var crossed := false
    for at in readings.size():
        var inside := readings[at].x >= 0.0 and readings[at].x < SIZE.x
        assert_true(inside, "Reading %d is a pixel of the canvas, %s" % [at, readings[at]])
        crossed = crossed or (at > 0 and readings[at].x < readings[at - 1].x)
    assert_true(crossed, "and the readings go from the right edge to the left")


func test_a_shift_clicks_line_ends_the_short_way_round_the_seam() -> void:
    _sky()
    var view := _canvas().view()
    var from := Vector2(SIZE.x - 10.0, 256.0)
    var through := Vector2(SIZE.x + 12.0, 256.0)
    assert_eq(view.line_towards(from, Vector2(12.0, 256.0)), through, "A brush's line goes through the seam")
    assert_eq(view.line_towards(from, Vector2(600.0, 256.0)), Vector2(600.0, 256.0), "and a nearer end stays where it is")
    _view.set_on(false)
    assert_eq(view.line_towards(from, Vector2(12.0, 256.0)), Vector2(12.0, 256.0), "The flat view's line goes across the canvas")


## The ring holds the dab the pointer lands. At the middle of a level view a
## document pixel is drawn the same size every way, and looking at a pole it is
## drawn narrower across but not down, so the ring keeps the size it had.
func test_the_ring_is_the_size_of_the_dab_under_the_pointer() -> void:
    _sky()
    var shown := _view.frame()
    var middle := _in_window(shown.get_center())
    var zoom := _canvas().view().get_zoom()
    var per_pixel := _view.camera.per_pixel(shown.size.y)
    var level := SaEnvironmentView.ring_scale(_canvas(), middle)
    var wanted := 1.0 / (zoom * SIZE.x / TAU * per_pixel)
    assert_almost_eq(level, wanted, wanted * 0.001, "At the middle the ring is a document pixel's size on screen")
    _view.camera.turn(Vector2(0.0, deg_to_rad(80.0) / per_pixel), shown.size.y)
    var high := SaEnvironmentView.ring_scale(_canvas(), middle)
    var said := "Near the pole the ring holds the dab's height, %.4f against %.4f" % [high, level]
    assert_almost_eq(high, level, level * 0.02, said)
    _view.set_on(false)
    assert_eq(SaEnvironmentView.ring_scale(_canvas(), middle), 1.0, "The flat view's ring is the tool's own")


func test_the_view_covers_the_pointer_anywhere_on_the_sky() -> void:
    _sky()
    var corner := _in_window(Vector2(2.0, 2.0))
    assert_true(_view.covers(corner), "The sky's corner is the canvas's to draw a ring over")
    _view.set_on(false)
    assert_false(_view.covers(corner), "and the flat view leaves it to the canvas")


## The overlay is given the ring over the sky. The Control the pointer hovers
## there is the view, which stands beside the canvas rather than inside it, and
## read as the interface the ring was not drawn over until the pen run of the
## proof found the ring missing.
func test_the_overlay_is_given_the_ring_over_the_sky() -> void:
    _sky()
    var root := (Engine.get_main_loop() as SceneTree).root
    var middle := _view.frame().get_center()
    _hand(InputEventMouseMotion.new(), middle)
    var hovered := root.gui_get_hovered_control()
    var on_sky := hovered == _view or (hovered != null and _view.is_ancestor_of(hovered))
    assert_true(on_sky, "The pointer over the sky hovers the view, %s" % hovered)
    var at := _in_window(middle)
    assert_true(_canvas().cursor_ring_radius >= 0.0, "The brush asks for a ring")
    var wanted := _canvas().cursor_ring_radius * SaEnvironmentView.ring_scale(_canvas(), at)
    var given := SaCursorPolicy.cursor_ring_radius_at(root, at)
    assert_almost_eq(given, wanted, 0.0001, "and the overlay is given the sky's ring there")


## The shader is told the document joins across its left and right edges in the
## form the renderer reads a `bvec2` in, a whole number's low bits. An Array read
## as nought, and the sky drew a cell's width of the whole canvas at the seam
## where the scenario's stroke crossed it.
func test_the_sky_is_told_the_document_joins_at_the_seam() -> void:
    _sky()
    var wraps: Variant = _view.get("_composer").material.get_shader_parameter(&"sa_env_wraps")
    assert_eq(typeof(wraps), TYPE_INT, "The wrap reaches the shader as a whole number")
    assert_eq(wraps, 1, "with the bit for across set and the one for down clear")


func test_the_flat_view_draws_the_seam_of_a_wrapping_document() -> void:
    var seam := _canvas().get_node(SaEnvironmentView.Seam.NODE_NAME) as SaEnvironmentView.Seam
    assert_not_null(seam, "The canvas carries the seam's guide")
    assert_eq(seam.lines().size(), 0, "A flat document has no seam to draw")
    _panorama()
    var lines := seam.lines()
    assert_eq(lines.size(), 2, "A panorama is drawn joined at its left and right edges")
    var inset := 0.5 / _canvas().view().get_zoom()
    assert_almost_eq(lines[0][0].x, inset, 0.0001, "the left one half a screen pixel inside")
    assert_almost_eq(lines[1][0].x, SIZE.x - inset, 0.0001, "the right one too")
    assert_almost_eq(lines[0][1].y - lines[0][0].y, float(SIZE.y), 0.0001, "each the canvas's height")
