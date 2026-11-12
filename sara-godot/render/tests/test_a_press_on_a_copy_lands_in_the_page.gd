## A press on a copy of the page is taken back into the page
## before the stroke starts, so the pen paints wherever it is.
##
## The ask was "like Krita, the wrap mode": the view shows the document
## repeated in every direction and a stroke on any copy paints the document.
## The draw is `test_the_view_repeats_the_page_around_it_and_composites_what_a_copy_shows.gd`.
##
## The fold is read through `SaWrapRepeat.fold`, which is what
## `SaCanvasView.get_document_mouse_position` calls with the pointer's document
## place, because the pointer itself cannot be moved from a suite under Wayland
## and a scenario is where the real press is driven.
extends "res://tests/test_framework.gd"

## A canvas builds an easel, and an easel needs a RenderingDevice.
const REQUIRES_GPU := true

## The tool descriptor and the tool state behind it.
const Fixtures = preload("res://tests/fixtures.gd")

const PAGE := Vector2i(256, 256)

var _host: Node = null


## Parented to an autoload rather than to the root, because the runner calls
## this from its own `_ready` and a parent mid-`_ready` rejects `add_child`.
func before_each() -> void:
    _host = Node.new()
    _host.name = "CopyPressTestHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


## A canvas of `PAGE` wrapping as *edges* says, with a tool machine beside it
## whose tool in hand paints or does not, as *paints* says.
func _canvas(edges: SaProjection.Wrap, paints: bool = true) -> SaCanvas:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(128, 128)
    _host.add_child(viewport)
    var canvas := SaCanvas.new()
    canvas.canvas_size = PAGE
    viewport.add_child(canvas)
    SaProjection.wrap_flat(canvas.document, edges)
    canvas.add_child(_machine(paints))
    return canvas


## A tool machine with one descriptor, registered and in hand. Bound to no
## surface: the only question asked of it is whether the tool in hand paints.
func _machine(paints: bool) -> ToolMachine:
    var descriptor := Fixtures.make_tool_descriptor(&"brush")
    descriptor.is_painting = paints
    var registry := SaToolRegistry.new()
    registry.register(descriptor)
    var machine := ToolMachine.new()
    machine.name = "ToolMachine"
    machine.registry = registry
    machine.active_tool_name = &"brush"
    return machine


func test_a_press_on_the_copy_to_the_right_lands_in_the_page() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(300.0, 20.0)), Vector2(44.0, 20.0), "A page to the right is the page, modulo the width")
    assert_eq(repeat.fold(Vector2(20.0, 300.0)), Vector2(20.0, 44.0), "and a page below is the page, modulo the height")
    assert_eq(repeat.fold(Vector2(300.0, 300.0)), Vector2(44.0, 44.0), "and the copy off the corner folds on both")


func test_a_press_left_of_the_page_comes_back_from_its_right_edge() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(-12.0, 30.0)), Vector2(244.0, 30.0), "Whole turns, so a point left of nought folds right")
    assert_eq(repeat.fold(Vector2(-260.0, 30.0)), Vector2(252.0, 30.0), "two pages out as readily as one")


func test_a_press_inside_the_page_is_left_where_it_is() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(10.5, 200.25)), Vector2(10.5, 200.25), "The page's own points are untouched")


func test_the_sides_only_folds_across_and_never_down() -> void:
    var canvas := _canvas(SaProjection.Wrap.X)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(300.0, 300.0)), Vector2(44.0, 300.0), "Across is a copy, down is off the page")


func test_a_document_that_does_not_wrap_is_left_alone() -> void:
    var canvas := _canvas(SaProjection.Wrap.NONE)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(300.0, 300.0)), Vector2(300.0, 300.0), "Painting out of bounds stays out of bounds")


## A transform's box, a crop's handles and a marquee are dragged past an edge
## on purpose, and a folded point would jump them a page across.
func test_a_tool_that_does_not_paint_is_left_alone() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY, false)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(300.0, 300.0)), Vector2(300.0, 300.0), "A tool that does not paint drags past the edge")


## The turn is worked out at the press and held through the drag, so a stroke
## dragged from a copy across the seam onto the page is one line rather than a
## jump of a page the moment the pen reaches the edge.
func test_the_turn_is_held_while_a_stroke_is_open() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY)
    var repeat := SaWrapRepeat.of_canvas(canvas)
    assert_eq(repeat.fold(Vector2(300.0, 100.0)), Vector2(44.0, 100.0), "The press lands on the copy to the right")
    canvas.document.stroke_layer.get_or_create_field(Vector2i.ZERO)
    assert_true(SaHalfSizeView.stroke_open(canvas.document), "A dab in the buffer is a stroke under way")
    assert_eq(repeat.fold(Vector2(250.0, 100.0)), Vector2(-6.0, 100.0), "and the drag keeps the turn its press was on")
    canvas.document.stroke_layer.release_chunks()
    assert_eq(repeat.fold(Vector2(250.0, 100.0)), Vector2(250.0, 100.0), "The release reads the turn again")


## The arithmetic alone, with no canvas: whole turns of the page, and nought on
## an axis that does not repeat.
func test_which_turn_a_point_stands_on() -> void:
    assert_eq(SaWrapRepeat.turn_of(Vector2(300.0, 20.0), Vector2(256.0, 256.0)), Vector2i(1, 0), "One page across")
    assert_eq(SaWrapRepeat.turn_of(Vector2(-1.0, 20.0), Vector2(256.0, 256.0)), Vector2i(-1, 0), "A hair left of nought")
    assert_eq(SaWrapRepeat.turn_of(Vector2(300.0, 20.0), Vector2(256.0, 0.0)), Vector2i(1, 0), "and down does not repeat")
    assert_eq(SaWrapRepeat.turn_of(Vector2(300.0, 900.0), Vector2.ZERO), Vector2i.ZERO, "nor does anything with no wrap")


## The door every tool reads the pointer through is the one that folds, so no
## tool has to know a document wraps.
func test_the_view_folds_what_it_answers() -> void:
    var canvas := _canvas(SaProjection.Wrap.XY)
    var view := SaCanvasView.for_canvas(canvas)
    assert_true(view != null, "The canvas has a view")
    assert_eq(view.canvas, canvas, "which answers for this canvas")
    assert_eq(
        SaWrapRepeat.in_the_page(canvas, Vector2(300.0, 20.0)),
        Vector2(44.0, 20.0),
        "and `get_document_mouse_position` hands the pointer's place through this"
    )
