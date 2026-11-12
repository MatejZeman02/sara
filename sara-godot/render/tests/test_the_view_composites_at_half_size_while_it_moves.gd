## The view composites at half size while it moves.
##
## The spec's two cases: a pan with the setting on draws the picture at half
## size while it moves and at full size once it rests, and a pan with a stroke
## open draws it at full size throughout. The rest hold what the two stand on,
## the setting off, the light mode writing it, and the canvas's own draw handed
## back after the rest.
##
## A frame here is a call to the canvas's `_process`, which is what the engine
## calls once a frame: the runner cannot advance a frame, and an await drops
## every assertion after it.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel composites.
const REQUIRES_GPU := true

const WINDOW := Vector2i(512, 384)
const CANVAS := Vector2i(1024, 1024)
## Half the window, which is even each way.
const HALF := Vector2i(256, 192)

var _host: Node = null
var _setting_before: bool = false


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _setting_before = SaSettings.half_size_view_while_moving
    _host = Node.new()
    _host.name = "L2TestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaSettings.half_size_view_while_moving = _setting_before
    if _host != null:
        _host.free()
        _host = null


func _canvas() -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = WINDOW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = CANVAS
    canvas.easel = SaEasel.create_default(CANVAS, null, SaColorSpace.srgb())
    canvas.add_child(canvas.easel)
    viewport.add_child(canvas)
    canvas.scale = Vector2.ONE
    canvas.position = Vector2.ZERO
    canvas.easel.process_pending_composite()
    # The frame the canvas first sees itself, which is no motion.
    canvas._process(0.0)
    return canvas


static func _view(canvas: SaCanvas) -> Dictionary:
    return canvas.capture_state()["half_size_view"]


## Moves the view by *step* and runs the frame that follows.
static func _pan(canvas: SaCanvas, step: Vector2) -> void:
    canvas.position += step
    canvas._process(0.0)


## Runs *frames* frames with the view standing still.
static func _rest(canvas: SaCanvas, frames: int) -> void:
    for _frame in frames:
        canvas._process(0.0)


func test_a_pan_draws_at_half_size_and_the_rest_at_full_size() -> void:
    SaSettings.half_size_view_while_moving = true
    var canvas := _canvas()
    assert_false(_view(canvas)["active"], "A view that has not moved is drawn at full size")
    assert_eq(_view(canvas)["drawn_size"], [WINDOW.x, WINDOW.y], "the size of the window")

    for _step in 6:
        _pan(canvas, Vector2(-24.0, -12.0))
        var moving := _view(canvas)
        assert_true(moving["active"], "Every frame of the pan is drawn at half size")
        assert_eq(moving["drawn_size"], [HALF.x, HALF.y], "half the window each way")
        assert_eq(canvas.texture, null, "and the canvas draws nothing of its own under it")

    _rest(canvas, SaHalfSizeView.REST_FRAMES - 1)
    assert_true(_view(canvas)["active"], "A frame or two of rest is still the pan")
    _rest(canvas, 1)
    var rested := _view(canvas)
    assert_false(rested["active"], "Once the view has rested it is drawn at full size")
    assert_eq(rested["drawn_size"], [WINDOW.x, WINDOW.y], "the window's size again")
    assert_true(canvas.texture is Texture2DRD, "the canvas draws its output again")
    assert_eq((canvas.texture as Texture2DRD).texture_rd_rid, canvas.easel.output.rid, "the output it was bound to")


func test_a_pan_with_a_stroke_open_stays_at_full_size() -> void:
    SaSettings.half_size_view_while_moving = true
    var canvas := _canvas()
    var document := canvas.document
    document.begin_stroke(1.0, &"normal")
    document.stroke_layer.get_or_create_chunk(Vector2i.ZERO)
    assert_true(SaHalfSizeView.stroke_open(document), "A dab has landed in the stroke buffer")

    for _step in 6:
        _pan(canvas, Vector2(16.0, 8.0))
        assert_false(_view(canvas)["active"], "A frame of the pan with the pen down is drawn at full size")
        assert_eq(_view(canvas)["drawn_size"], [WINDOW.x, WINDOW.y], "at the window's size")
    document.commit_stroke()


func test_a_stroke_that_opens_mid_pan_brings_the_full_size_back_that_frame() -> void:
    SaSettings.half_size_view_while_moving = true
    var canvas := _canvas()
    _pan(canvas, Vector2(-30.0, 0.0))
    assert_true(_view(canvas)["active"], "The pan is at half size")
    canvas.document.begin_stroke(1.0, &"normal")
    canvas.document.stroke_layer.get_or_create_chunk(Vector2i.ZERO)
    _pan(canvas, Vector2(-30.0, 0.0))
    assert_false(_view(canvas)["active"], "The first frame with a dab down is full size")
    assert_true(canvas.texture != null, "and the canvas draws itself")
    canvas.document.commit_stroke()


func test_with_the_setting_off_a_pan_stays_at_full_size() -> void:
    SaSettings.half_size_view_while_moving = false
    var canvas := _canvas()
    for _step in 4:
        _pan(canvas, Vector2(10.0, 10.0))
        assert_false(_view(canvas)["active"], "Off, a pan is drawn as it always was")


func test_a_zoom_and_a_turn_are_moves_too() -> void:
    SaSettings.half_size_view_while_moving = true
    var canvas := _canvas()
    canvas.scale = Vector2(0.5, 0.5)
    canvas._process(0.0)
    assert_true(_view(canvas)["active"], "A zoom is drawn at half size")
    _rest(canvas, SaHalfSizeView.REST_FRAMES)
    assert_false(_view(canvas)["active"], "and rests")
    canvas.rotation = 0.3
    canvas._process(0.0)
    assert_true(_view(canvas)["active"], "A turn is drawn at half size")


func test_the_half_size_viewport_draws_the_canvas_scaled_by_a_half() -> void:
    SaSettings.half_size_view_while_moving = true
    var canvas := _canvas()
    _pan(canvas, Vector2(-40.0, -20.0))
    var viewport := canvas.get_parent().find_child("HalfSizeViewport", true, false) as SubViewport
    assert_true(viewport != null, "The half-size viewport sits beside the canvas")
    assert_eq(viewport.size, HALF, "half the window")
    var expected := Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2.ZERO) * canvas.get_global_transform_with_canvas()
    assert_true(viewport.canvas_transform.is_equal_approx(expected), "the canvas's transform at half scale")
    var proxy := canvas.get_parent().find_child("HalfSizeView", false, false) as TextureRect
    assert_true(proxy != null and proxy.visible, "and the picture it draws is shown")
    assert_eq(proxy.get_index(), canvas.get_index() - 1, "just before the canvas, under its overlays")
    assert_eq(proxy.size, Vector2(WINDOW), "over the whole window")


func test_the_light_mode_turns_it_on_and_the_defaults_off() -> void:
    var before := SaSettingsPerformance.default_values()
    assert_eq(before["half_size_view_while_moving"], false, "A fresh profile draws a pan at full size")
    assert_eq(SaSettingsPerformance.light_values()["half_size_view_while_moving"], true, "and the light mode at half")
    assert_eq(
        SaSettingsKeys.place_of(&"half_size_view_while_moving"),
        ["performance", "half_size_view_while_moving"],
        "stored under performance"
    )
