## ToolState: the contract every tool inherits before it does anything.
##
## Tools are constructed before a document necessarily exists, and a tool switch
## asks the new tool for its cursor radius immediately. So the base class is
## asked questions with nothing behind it, on a path that runs during startup,
## and every one of them has to answer rather than fail.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")

## Building a real surface allocates chunks.
const REQUIRES_GPU := true

# --- A tool with nothing behind it ---------------------------------------------------


## The toolbox is built from the registry before any document is loaded, and a
## tool switch asks for a radius as it happens. Reaching through a null surface
## here is a startup crash, not a wrong number.
func test_a_tool_with_no_surface_answers_instead_of_reaching_through() -> void:
    var tool := ToolState.new()

    assert_null(tool.surface, "No surface means no document and no view")
    assert_eq(tool.get_document_mouse_position(), Vector2.ZERO, "and the pointer is at the origin, not a crash")


## A surface exists before its view does when a document is built headless, as
## the export path and every GPU test do.
func test_a_surface_without_a_view_still_answers() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var tool := ToolState.new()
    tool.surface = SaSurface.create(&"viewless", easel, null)

    assert_not_null(tool.surface.get_document(), "The document is reachable without a view")
    assert_null(tool.surface.view, "The view is honestly absent")
    assert_eq(tool.get_document_mouse_position(), Vector2.ZERO, "rather than being asked for a position")

    easel.free()


## The base class must not claim a brush ring. The OS cursor is hidden while a
## ring is drawn, so a tool that inherits a positive radius without drawing
## anything leaves the user with no pointer at all.
func test_the_base_class_wants_no_brush_ring() -> void:
    assert_true(ToolState.new().get_cursor_radius() < 0.0, "Non-painting tools get an OS cursor shape")


## Both are called by the machine on tools that may not override them.
func test_the_default_handlers_do_nothing_quietly() -> void:
    var tool := ToolState.new()

    tool.handle_input(InputEventMouseMotion.new())
    tool.reset()

    assert_null(tool.surface, "Neither invents a surface to work on")
