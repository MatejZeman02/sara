## The Sphere docker shows no seam.
##
## A painter, 2026-10-26: "sphere - visible seam." The ball handed the shader
## its `sa_env_wraps` as an Array, which the renderer reads as nought for a
## `bvec2`, so the lookup's cell beside the seam was blended across the whole
## document and drew a band of the canvas's middle down the ball where the
## wrap faced the viewer. The Environment view had met the same fault and hands
## the flag as a whole number's low bits, and the ball now does the same.
##
## The running app is `scenarios/the-sphere-docker-shows-no-seam.json`,
## whose shots before and after are read by the unit's measure.
extends "res://tests/test_framework.gd"

const SphereDocker = preload("res://modules/sara-base-modules/sphere/sphere_docker.gd")

const REQUIRES_GPU := true

var _host: Node = null
var _canvas: SaCanvas = null
var _docker: SphereDocker = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "SphereSeamTestHost"
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


func _wraps() -> Variant:
    return _docker.ball.composer.material.get_shader_parameter(&"sa_env_wraps")


func test_the_ball_is_told_the_panorama_joins_at_the_seam() -> void:
    var godot := SaProjection.Heading.new(SaProjection.Heading.GODOT)
    _canvas.document.projection = SaProjection.new(SaProjection.Equirectangular.new(), godot)
    _docker.sync()
    assert_eq(typeof(_wraps()), TYPE_INT, "The wrap reaches the ball's shader as a whole number")
    assert_eq(_wraps(), 1, "with the bit for across set and the one for down clear")
