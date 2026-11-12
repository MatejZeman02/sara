## Input must reach the tools across the whole canvas area, not just the document.
##
## SaCanvas is a TextureRect sized to the document, so its rect covers only the
## painted area. gui_input was connected there, which meant tools stopped
## receiving events the moment the pointer left the document: panning and zooming
## died in the surrounding grey, which is exactly where you reach for them when
## zoomed in. Routing from the full-rect Control fixes that.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const MainCanvasScript = preload("res://render/main_canvas.gd")


func test_input_is_routed_from_the_full_rect_control() -> void:
    var main_canvas := MainCanvasScript.new()
    main_canvas._ready()

    assert_true(
        main_canvas.control_node.gui_input.get_connections().size() > 0,
        "Input must be routed from the full-rect Control that spans the whole canvas area"
    )
    assert_eq(
        main_canvas.canvas.gui_input.get_connections().size(),
        0,
        "Routing from the document-sized TextureRect loses every event outside the document"
    )

    main_canvas.free()


## The canvas must keep passing events up, or the Control above it never sees the
## ones that land on the document.
func test_canvas_passes_events_up_to_the_router() -> void:
    var main_canvas := MainCanvasScript.new()
    main_canvas._ready()

    assert_true(
        main_canvas.canvas.mouse_filter != Control.MOUSE_FILTER_STOP,
        "A STOP filter on the canvas would swallow events before the routing Control sees them"
    )
    assert_true(
        main_canvas.control_node.mouse_filter != Control.MOUSE_FILTER_IGNORE,
        "An IGNORE filter on the routing Control would stop it receiving gui_input at all"
    )

    main_canvas.free()
