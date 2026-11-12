## A ground's edge shows past a bounded page and never past an infinite one.
##
## The edge of a Paper or a Canvas lies wholly outside the page, so on a
## bounded page the rect past it has to be shown for the edge to draw at all,
## and the shader leaves it transparent past the edge's reach. With the
## infinite canvas on the page's rectangle is never shown, so the rect is told
## to draw no edge. What the view then looks like is held by the scenario of
## the same name, which photographs the bounded page.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, which needs a RenderingDevice.
const REQUIRES_GPU := true

const VIEW := Vector2i(800, 600)
const NONE := 0.0
const DECKLE := 2.0

var _host: Node = null


## Parented to an autoload rather than to the root, for the reason
## test_canvas_view.gd gives: the runner calls this mid-`_ready`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "GroundEdgeTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    _scene().set("stand_in_registries", null)
    if _host != null:
        _host.free()
        _host = null


## A canvas over a page whose only layer is a ground of *type* with *edge*.
func _canvas(type: StringName, edge: float) -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = VIEW
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = Vector2i(256, 192)
    viewport.add_child(canvas)
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    _scene().set("stand_in_registries", registries)
    var doc := canvas.document
    SaLayerOps.new(doc).remove(doc.get_node("Background") as SaLayer)
    var ground := SaLayerOps.new(doc).add(type, registries.layer_types)
    SaLayerOps.new(doc).move(ground, -1)
    ground.generator_params[SaGroundBeyond.EDGE] = edge
    doc.update_caches()
    canvas.view_changed()
    return canvas


## The runner, which stands in for main as the scene a generated layer's view
## reads the registries off.
func _scene() -> Node:
    return (Engine.get_main_loop() as SceneTree).current_scene


func _beyond(canvas: SaCanvas) -> ColorRect:
    return canvas.get_node(SaGroundBeyond.NODE_NAME) as ColorRect


## Every uniform the rect past the page is told, by name.
func _told(canvas: SaCanvas) -> Dictionary:
    var material := _beyond(canvas).material as ShaderMaterial
    var told := {}
    for uniform: Dictionary in material.shader.get_shader_uniform_list():
        var name := str(uniform["name"])
        told[name] = material.get_shader_parameter(name)
    return told


func test_a_bounded_page_with_an_edge_shows_the_rect_that_draws_it() -> void:
    for type: StringName in [&"paper", &"canvas"]:
        var canvas := _canvas(type, DECKLE)
        assert_false(canvas.document.infinite_canvas.on, "A new document is bounded")
        assert_true(_beyond(canvas).visible, "and a %s with an edge shows the rect past the page the edge is drawn on" % type)
        assert_eq(_told(canvas)[SaGroundBeyond.EDGE], DECKLE, "telling it the edge the ground asks for")


func test_a_bounded_page_with_no_edge_ends_at_its_rectangle() -> void:
    var canvas := _canvas(&"paper", NONE)
    assert_false(_beyond(canvas).visible, "A ground with no edge draws nothing past a bounded page")


func test_picking_an_edge_and_none_again_shows_and_hides_the_rect() -> void:
    var canvas := _canvas(&"paper", NONE)
    var ground := SaGeneratedLayer.view_source(canvas.document)
    ground.generator_params[SaGroundBeyond.EDGE] = DECKLE
    assert_true(canvas.view_changed(), "Picking an edge is a draw")
    assert_true(_beyond(canvas).visible, "which shows the rect")
    ground.generator_params[SaGroundBeyond.EDGE] = NONE
    assert_true(canvas.view_changed(), "and picking None again is one too")
    assert_false(_beyond(canvas).visible, "which hides it")


func test_the_infinite_canvas_draws_no_edge_whatever_the_ground_asks() -> void:
    for type: StringName in [&"paper", &"canvas"]:
        var deckled := _canvas(type, DECKLE)
        var plain := _canvas(type, NONE)
        for canvas: SaCanvas in [deckled, plain]:
            SaInfiniteCanvas.turn(canvas.document, true)
            canvas.view_changed()
            assert_true(_beyond(canvas).visible, "With the infinite canvas on the ground runs past the page")
        assert_eq(_told(deckled)[SaGroundBeyond.EDGE], NONE, "and a %s's Deckle is told no edge there" % type)
        assert_eq(_told(deckled), _told(plain), "so a %s with Deckle draws the view past the page as one with None" % type)
        SaInfiniteCanvas.turn(deckled.document, false)
        deckled.view_changed()
        assert_eq(_told(deckled)[SaGroundBeyond.EDGE], DECKLE, "Turning the switch off brings the edge back")
