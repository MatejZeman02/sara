## The ground reaches past the page only while the infinite canvas is on.
##
## A bounded page ends where the painting ends, so the ground drawn beyond its
## rectangle stays hidden and the backdrop shows round it. With the infinite
## canvas on the page grows under the paint and its edge is never shown, so the
## ground beyond covers the view. What the view then looks like is held by the
## scenario of the same name, which photographs both.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const VIEW := Vector2i(800, 600)

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "GroundBeyondTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A canvas over a document whose bottom layer is *type*, a generated ground,
## or with no ground at all when *type* is empty.
func _canvas(type: StringName) -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = VIEW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 256)
    viewport.add_child(canvas)
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var doc := canvas.document
    SaLayerOps.new(doc).remove(doc.get_node("Background") as SaLayer)
    if type != &"":
        var ground := SaLayerOps.new(doc).add(type, registries.layer_types)
        SaLayerOps.new(doc).move(ground, -1)
    doc.update_caches()
    canvas.view_changed()
    return canvas


func _beyond(canvas: SaCanvas) -> ColorRect:
    return canvas.get_node(SaGroundBeyond.NODE_NAME) as ColorRect


## The viewport's rectangle in the canvas's own document pixels, which is what
## the ground beyond has to cover to leave no edge anywhere in the view.
func _view_in_document(canvas: SaCanvas) -> Rect2:
    var to_view := canvas.get_global_transform_with_canvas()
    var back := to_view.affine_inverse()
    var view := Rect2(back * Vector2.ZERO, Vector2.ZERO)
    for corner: Vector2 in [Vector2(VIEW.x, 0), Vector2(0, VIEW.y), Vector2(VIEW)]:
        view = view.expand(back * corner)
    return view


func test_a_bounded_page_draws_no_ground_past_its_edge() -> void:
    var canvas := _canvas(&"background")
    assert_false(canvas.document.infinite_canvas.on, "A new document is bounded")
    assert_false(_beyond(canvas).visible, "and its ground is drawn inside the page only")
    assert_not_null(_beyond(canvas).material, "though the rect is kept ready, so turning the switch on shows it at once")
    assert_eq(canvas.capture_state()["ground_beyond"], {"reaches_past_page": false, "visible": false}, "The dump says so")


func test_the_infinite_canvas_draws_the_ground_over_the_whole_view() -> void:
    var canvas := _canvas(&"background")
    SaInfiniteCanvas.turn(canvas.document, true)
    assert_true(canvas.view_changed(), "Turning the switch on is a draw")
    assert_false(canvas.view_changed(), "once")
    var beyond := _beyond(canvas)
    assert_true(beyond.visible, "With the infinite canvas on the ground reaches past the page")
    for zoom: float in [0.05, 0.5, 4.0]:
        canvas.scale = Vector2(zoom, zoom)
        canvas.view_changed()
        var covered := beyond.get_rect().encloses(_view_in_document(canvas))
        assert_true(covered, "and covers the view at %d percent" % roundi(zoom * 100.0))
    assert_eq(canvas.capture_state()["ground_beyond"], {"reaches_past_page": true, "visible": true}, "The dump says so")


func test_turning_it_off_again_ends_the_page_where_it_has_grown_to() -> void:
    var canvas := _canvas(&"background")
    SaInfiniteCanvas.turn(canvas.document, true)
    canvas.view_changed()
    canvas.resize_canvas(Vector2i(768, 512))
    canvas.view_changed()
    assert_true(_beyond(canvas).visible, "A grown page still shows no edge while the switch is on")
    SaInfiniteCanvas.turn(canvas.document, false)
    assert_true(canvas.view_changed(), "Turning it off is a draw")
    assert_false(_beyond(canvas).visible, "and the ground stops at the page again")
    assert_eq(canvas.size, Vector2(768, 512), "which is the page as it grew, so no paint is cut")


func test_with_no_ground_nothing_is_drawn_past_the_page_either_way() -> void:
    var canvas := _canvas(&"")
    SaInfiniteCanvas.turn(canvas.document, true)
    canvas.view_changed()
    assert_false(_beyond(canvas).visible, "A page with no ground shows the backdrop round it even when infinite")
