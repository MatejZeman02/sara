## The middle of the Environment view, at four yaws, lands on the longitude the
## camera faces, in Blender's orientation and in Godot's, with the horizon level.
##
## The suite maps the centre ray at four yaws to a document pixel and reads the
## longitude, in Blender's orientation and in Godot's. The
## longitude is the document's own, 360 degrees across it from the left edge,
## so Godot's orientation, whose nought is straight ahead, reads the yaw back,
## and Blender's, a quarter turn round from it, reads a quarter more.
##
## The same file holds what the shader draws through: the composed canvas
## shader keeps every one of the flat canvas's uniforms and gains the camera's,
## and the table of the kind's map is what `from_view` answers.
extends "res://tests/test_framework.gd"

const DOCUMENT := Vector2(2048.0, 1024.0)
const VIEW := Vector2(1600.0, 900.0)
const YAWS: Array[float] = [0.0, 90.0, 180.0, -90.0]


func _longitude_at(orientation: StringName, yaw: float) -> Vector2:
    var projection := SaProjection.new(SaProjection.Equirectangular.new(), SaProjection.Heading.new(orientation))
    var camera := SaEnvironmentView.Camera.new(deg_to_rad(yaw))
    var pixel := projection.from_view(camera.ray_at(VIEW * 0.5, Rect2(Vector2.ZERO, VIEW)), DOCUMENT)
    return Vector2(pixel.x / DOCUMENT.x * 360.0, pixel.y)


func _assert_longitude(read: float, expected: float, words: String) -> void:
    var apart := absf(wrapf(read - expected, -180.0, 180.0))
    assert_true(apart < 0.01, "%s: the middle reads longitude %.3f, wanted %.3f" % [words, read, expected])


func test_godots_orientation_reads_the_yaw() -> void:
    for yaw in YAWS:
        var read := _longitude_at(SaProjection.Heading.GODOT, yaw)
        _assert_longitude(read.x, fposmod(yaw, 360.0), "Godot's orientation at yaw %s" % yaw)
        assert_almost_eq(read.y, DOCUMENT.y * 0.5, 0.01, "the horizon is level at yaw %s" % yaw)


func test_blenders_orientation_reads_a_quarter_turn_more() -> void:
    for yaw in YAWS:
        var read := _longitude_at(SaProjection.Heading.BLENDER, yaw)
        _assert_longitude(read.x, fposmod(yaw + 90.0, 360.0), "Blender's orientation at yaw %s" % yaw)
        assert_almost_eq(read.y, DOCUMENT.y * 0.5, 0.01, "the horizon is level at yaw %s" % yaw)


func test_a_drag_to_the_right_brings_what_was_left_into_the_middle() -> void:
    var camera := SaEnvironmentView.Camera.new()
    var left_of_middle := VIEW * 0.5 - Vector2(20.0, 0.0)
    var before := camera.ray_at(left_of_middle, Rect2(Vector2.ZERO, VIEW))
    camera.turn(Vector2(20.0, 0.0), VIEW.y)
    var after := camera.ray_at(VIEW * 0.5, Rect2(Vector2.ZERO, VIEW))
    assert_true(before.angle_to(after) < deg_to_rad(0.05), "the sky moves with the hand, %.4f rad apart" % before.angle_to(after))


func test_a_zoom_in_narrows_the_field_of_view() -> void:
    var camera := SaEnvironmentView.Camera.new()
    var wide := camera.fov
    camera.magnify(2.0)
    assert_almost_eq(tan(camera.fov * 0.5), tan(wide * 0.5) * 0.5, 0.0001, "twice the zoom is half the tangent")
    camera.magnify(1000.0)
    assert_almost_eq(camera.fov, SaEnvironmentView.Camera.FOV_MIN, 0.0001, "the field of view stops at its least")


func test_the_table_is_the_kinds_own_map() -> void:
    var projection := SaProjection.new(SaProjection.Equirectangular.new(), SaProjection.Heading.new(SaProjection.Heading.BLENDER))
    var table := SaEnvironmentView.Lookup.table(projection, DOCUMENT)
    for cell: Vector2i in [Vector2i(0, 0), Vector2i(64, 64), Vector2i(200, 100), Vector2i(255, 127)]:
        var wanted := projection.from_view(SaEnvironmentView.Lookup.direction(Vector2(cell)), DOCUMENT) / DOCUMENT
        var stored := table.get_pixelv(cell)
        assert_almost_eq(stored.r, wanted.x, 0.00001, "the table's across at %s" % cell)
        assert_almost_eq(stored.g, wanted.y, 0.00001, "the table's down at %s" % cell)


func test_the_composed_canvas_shader_keeps_its_uniforms_and_gains_the_cameras() -> void:
    var source: Shader = load("res://shaders/canvas/tonemap.gdshader")
    var composed := SaEnvironmentView.Composer.compose(source)
    assert_false(composed.code.contains("dFdx(UV)"), "the derivatives of UV are the camera's")
    var names: Array[String] = []
    for entry: Dictionary in composed.get_shader_uniform_list():
        names.append(String(entry["name"]))
    for entry: Dictionary in source.get_shader_uniform_list():
        assert_true(names.has(String(entry["name"])), "the composed shader keeps %s" % entry["name"])
    for camera: String in ["sa_env_right", "sa_env_up", "sa_env_forward", "sa_env_centre", "sa_env_reach", "sa_env_lookup"]:
        assert_true(names.has(camera), "the composed shader reads %s" % camera)


func test_a_canvas_with_no_shader_still_shows_the_sky() -> void:
    var composed := SaEnvironmentView.Composer.compose(null)
    var names: Array[String] = []
    for entry: Dictionary in composed.get_shader_uniform_list():
        names.append(String(entry["name"]))
    assert_true(names.has("sa_env_lookup"), "the bare shader is composed over")
