## A Sphere docker shows the panorama from outside.
##
## The docker is hidden until asked as the pop-up palette is, draws the output
## on a ball seen from outside through a shader of the sphere maths, mirror-like
## so the picture reads, turned by a drag inside it and following the document
## as it is painted. On a flat document it says in a sentence that it shows
## panoramas.
##
## The ball's own sum is read here on the CPU, `Ball.ray_at`, the one the
## shader's `sa_ball_ray` makes, against the document position the projection
## gives it. The composed material and the easel's output are read off a real
## canvas in a viewport, as the sphere maths suite builds one, so the suite asks for a GPU.
## The running app is `scenarios/a-sphere-docker-shows-the-panorama-from-outside.json`.
##
## The docker lives in `modules/sara-base-modules/sphere`, registered by its
## module through the door every module's docker uses, so the suite reaches the
## docker and the module by a path and the registration through a context.
extends "res://tests/test_framework.gd"

const SphereDocker = preload("res://modules/sara-base-modules/sphere/sphere_docker.gd")
const SphereModule = preload("res://modules/sara-base-modules/sphere/module.gd")
const Fixtures = preload("res://tests/fixtures.gd")

const REQUIRES_GPU := true

## A degree, in radians, which is as near as the ball's sum and the view's
## turn agree away from the middle of the disc.
const NEAR: float = PI / 180.0

var _host: Node = null
var _canvas: SaCanvas = null
var _docker: SphereDocker = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "SphereDockerTestHost"
    EventBus.add_child(_host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(400, 300)
    _host.add_child(viewport)
    var surface := Control.new()
    surface.size = Vector2(400.0, 300.0)
    viewport.add_child(surface)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(256, 128)
    surface.add_child(_canvas)
    _docker = SphereDocker.new(SaSurface.create(&"sphere", _canvas.ensure_easel(), SaCanvasView.for_canvas(_canvas)))
    _docker.ball.size = Vector2(208.0, 208.0)


func after_each() -> void:
    if _docker != null:
        _docker.free()
        _docker = null
    if _host != null:
        _host.free()
        _host = null


func _make_a_panorama() -> void:
    var godot := SaProjection.Heading.new(SaProjection.Heading.GODOT)
    _canvas.document.projection = SaProjection.new(SaProjection.Equirectangular.new(), godot)


## The longitude the ball shows at *offset* pixels from the middle of its
## disc, in degrees east of nought and between minus and plus 180, read
## through the document position the projection gives the ball's direction.
func _longitude_at(offset: Vector2) -> float:
    var shape := Vector2(_canvas.document.canvas_size)
    var middle := _docker.ball.disc().get_center()
    var pixel := _canvas.document.projection.from_view(_docker.ball.ray_at(middle + offset), shape)
    return wrapf(pixel.x / shape.x * 360.0, -180.0, 180.0)


func test_the_sphere_is_a_module_s_docker_hidden_until_asked() -> void:
    var registries := Fixtures.make_registries()
    var module: SaModule = SphereModule.new()
    var ctx := registries.context.for_module(module.get_id())
    assert_false(registries.ui.has_docker(SphereDocker.DOCKER_ID), "The skeleton's own registrations hold no Sphere")
    module.register(ctx)
    assert_true(registries.ui.has_docker(SphereDocker.DOCKER_ID), "The Sphere module registers it")
    var entry: Dictionary = registries.ui.get_docker_entry(SphereDocker.DOCKER_ID)
    assert_eq(entry["title"], "Sphere", "under the title the Window menu lists")
    assert_eq(entry["module"], module.get_id(), "as the module's own docker")
    assert_false(String(entry["sentence"]).is_empty(), "with the sentence its row says on hover")
    var built: Window = (entry["factory"] as Callable).call()
    assert_true(built is SphereDocker, "and its factory builds the docker")
    built.free()
    assert_eq(SphereDocker.DOCKER_ID, &"SphereDocker", "under the id it had as a built-in, so a saved layout opens it")
    assert_true(DockerLayoutStore.HIDDEN_UNTIL_ASKED.has(SphereDocker.DOCKER_ID), "kept hidden until asked")
    assert_true(DockerLayoutStore.HIDDEN_UNTIL_ASKED.has(SaDockerIds.PALETTE), "as the pop-up palette is")
    ctx.remove_all_registrations()
    assert_false(_docker.visible, "and built, it is closed")


func test_a_flat_document_is_told_the_sphere_shows_panoramas() -> void:
    _docker.sync()
    assert_true(_docker.sentence.visible, "On a flat document the docker shows its sentence")
    assert_false(_docker.ball.visible, "in place of the ball")
    assert_true(_docker.sentence.text.contains("shows panoramas"), "which says it shows panoramas: %s" % _docker.sentence.text)
    assert_true(_docker.sentence.tooltip_text.contains("Image > Projection..."), "and its tooltip where to make it one")
    assert_eq(_docker.sentence.text_overrun_behavior, SaTheme.TEXT_CUT, "A docker too small for it cuts it with the mark")

    var polar := SaProjection.Heading.new(SaProjection.Heading.GODOT)
    _canvas.document.projection = SaProjection.new(SaProjection.Polar.new(), polar)
    _docker.sync()
    assert_true(_docker.sentence.visible, "A polar document is refused as well")
    assert_true(_docker.sentence.text.contains("is polar"), "and named: %s" % _docker.sentence.text)

    _make_a_panorama()
    _docker.sync()
    assert_false(_docker.sentence.visible, "An equirectangular one hides the sentence")
    assert_true(_docker.ball.visible, "and shows the ball")


func test_the_middle_faces_longitude_nought_and_the_picture_reads_left_to_right() -> void:
    _make_a_panorama()
    _docker.sync()
    assert_almost_eq(_longitude_at(Vector2.ZERO), 0.0, 0.01, "At turn nought the middle of the ball faces longitude nought")
    var half := _docker.ball.disc().size.x * 0.25
    var right := _longitude_at(Vector2(half, 0.0))
    var left := _longitude_at(Vector2(-half, 0.0))
    # Half the radius out is thirty degrees round a ball, the arcsine of a half.
    assert_almost_eq(right, 30.0, 0.01, "Half the radius right of the middle is thirty degrees east")
    assert_almost_eq(left, -30.0, 0.01, "and half the radius left of it thirty west")
    assert_true(left < right, "so the longitude climbs left to right, as the document's x does, and not backwards as on a globe")


func test_a_drag_inside_turns_the_ball_and_the_middle_follows_the_hand() -> void:
    _make_a_panorama()
    _docker.sync()
    var middle := _docker.ball.disc().get_center()
    var under_the_hand := _docker.ball.ray_at(middle + Vector2(20.0, 10.0))

    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = middle + Vector2(20.0, 10.0)
    _docker.ball._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.position = middle
    motion.relative = Vector2(-20.0, -10.0)
    _docker.ball._gui_input(motion)

    var off := rad_to_deg(_docker.ball.ray_at(middle).angle_to(under_the_hand))
    assert_true(off < rad_to_deg(NEAR), "The point the hand pressed is at the middle after the drag, %.3f degrees off" % off)
    assert_true(_docker.ball.camera.yaw > 0.0, "a drag to the left turns the ball east")
    assert_true(_docker.ball.camera.pitch < 0.0, "and one up brings the point below the middle to it, looking down")
    var forward: Vector3 = _docker.ball.composer.material.get_shader_parameter(&"sa_env_forward")
    assert_true(forward.angle_to(-_docker.ball.camera.basis().z) < 1e-4, "and the shader reads the turned camera")


func test_a_press_off_the_disc_turns_nothing() -> void:
    _make_a_panorama()
    _docker.sync()
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.position = Vector2(1.0, 1.0)
    _docker.ball._gui_input(press)
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(40.0, 30.0)
    _docker.ball._gui_input(motion)
    assert_eq(_docker.ball.camera.yaw, 0.0, "A drag from the corner off the disc leaves the yaw")
    assert_eq(_docker.ball.camera.pitch, 0.0, "and the pitch")


func test_the_ball_draws_the_easel_output_through_the_canvas_shader_and_the_view_s_maths() -> void:
    _make_a_panorama()
    _docker.sync()
    var material := _docker.ball.material as ShaderMaterial
    assert_true(material == _docker.ball.composer.material, "The ball draws through the composed material")
    var code := material.shader.code
    assert_true(code.contains('#include "%s"' % _docker.include_path), "composed with the ball's include")
    assert_true(code.contains("sa_ball_unwrapped(UV)"), "which reads the ball's position in place of the camera's")
    assert_false(code.contains("sa_env_unwrapped(UV)"), "and not the view's through the screen")
    var names: Array[String] = []
    for entry: Dictionary in material.shader.get_shader_uniform_list(true):
        names.append(String(entry["name"]))
    for wanted: String in ["sa_env_right", "sa_env_up", "sa_env_forward", "sa_env_lookup", "sa_env_wraps"]:
        assert_true(names.has(wanted), "The composed shader has the view's uniform %s" % wanted)
    var canvas_material := _canvas.material as ShaderMaterial
    for entry: Dictionary in canvas_material.shader.get_shader_uniform_list():
        assert_true(names.has(String(entry["name"])), "and keeps the canvas's own %s" % entry["name"])
    var output := _canvas.easel.output.rid
    assert_eq(_docker.ball._bound_rid, output, "It reads the easel's output, the texture a stroke is composited into")
    var include := FileAccess.get_file_as_string(_docker.include_path)
    var of_the_view := '#include "%s"' % SaEnvironmentView.Composer.INCLUDE
    assert_true(include.contains(of_the_view), "and its include is the view's maths with the ball's ray beside it")


## "It costs screen pixels and no dispatch": what the docker does each frame it
## is open, and a turn, issue no compute pass and no compute list. Its pixels
## are the polygon `_draw` gives the canvas_item shader, which this cannot
## count, and the scenario's shots show.
func test_a_frame_of_the_open_docker_and_a_turn_dispatch_nothing() -> void:
    _make_a_panorama()
    _docker.sync()
    var dispatches := SaCompute.dispatches
    var lists := SaCompute.lists
    for i in 5:
        _docker.sync()
    _docker.ball.turn(Vector2(-30.0, 12.0))
    _docker.sync()
    assert_eq(SaCompute.dispatches, dispatches, "Six frames' syncs and a turn dispatch no compute pass")
    assert_eq(SaCompute.lists, lists, "and open no compute list")
