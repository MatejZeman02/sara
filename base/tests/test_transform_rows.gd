## The transform's rows in the Tool Options docker.
##
## The claim to be shown rather than argued: a number typed in
## a row and a handle pulled to the same place end in the same document. Every
## row is a reading of the one matrix, so the test writes a row and reads the
## matrix back, and writes the matrix and reads the rows back.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

const RED := Color(1.0, 0.0, 0.0, 1.0)


func _tool_on(surface: SaSurface) -> Array:
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"transform")
    return [machine, machine.active_tool]


func test_the_rows_are_declared_and_none_of_them_is_on_the_bar() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptor := registry.get_descriptor(&"transform")

    assert_not_null(descriptor, "The transform is registered")
    var keys: Array = []
    for spec: SaOptionSpec in descriptor.options:
        keys.append(String(spec.key))
        assert_false(spec.bar, "%s stays off the bar, which is full at 1920" % spec.key)
        assert_true(spec.on_tool, "%s reads the tool state rather than a settings resource" % spec.key)
    assert_eq(
        keys,
        [
            # The mode is first, because it decides what every row under it and
            # every handle on the canvas mean.
            "transform_mode",
            "transform_move_x",
            "transform_move_y",
            "transform_scale_x",
            "transform_scale_y",
            "transform_angle",
            "transform_shear",
            "transform_flip_horizontal",
            "transform_flip_vertical",
            "transform_filter",
            "transform_apply",
            "transform_reset",
        ],
        "The mode, position, size, angle, shear, the two flips, the filter and the two buttons"
    )


func test_a_typed_number_moves_the_picture_the_way_a_drag_does() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)

    tool.set("move_x", 120.0)

    assert_true(tool.is_moving(), "Writing a row lifts, because there is no other moment for it to happen at")
    assert_almost_eq(tool.move_x, 120.0, 1e-3, "and the row reads back what was typed")
    assert_eq(tool.move_offset(), Vector2i(120, 0), "which is the same offset a drag of 120 would have made")
    assert_eq(tool.pending_box(), Rect2i(376, 256, 256, 256), "and the box is where that puts it")
    Fixtures.teardown(surface, machine)


func test_every_row_is_a_reading_of_the_one_matrix() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    surface.get_document().active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)

    tool.set("move_x", 40.0)
    tool.set("move_y", -25.0)
    tool.set("scale_x", 1.5)
    tool.set("scale_y", 0.75)
    tool.set("angle_degrees", 30.0)
    tool.set("shear_degrees", 12.0)

    assert_almost_eq(tool.move_x, 40.0, 1e-2, "The position survives everything written after it")
    assert_almost_eq(tool.move_y, -25.0, 1e-2, "on both axes")
    assert_almost_eq(tool.scale_x, 1.5, 1e-3, "and so does the width")
    assert_almost_eq(tool.scale_y, 0.75, 1e-3, "and the height")
    assert_almost_eq(tool.angle_degrees, 30.0, 1e-2, "and the angle")
    assert_almost_eq(tool.shear_degrees, 12.0, 1e-2, "and the shear, which is six numbers out of a matrix that holds six")
    Fixtures.teardown(surface, machine)


func test_apply_and_reset_are_the_two_keys_under_another_name() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)
    var steps := document.history.step_count()

    tool.set("move_x", 90.0)
    assert_true(tool.call("commit_move"), "Apply writes the move down")
    assert_eq(document.history.step_count(), steps + 1, "as one step, the way Enter does")
    assert_false(tool.is_moving(), "and the gesture is over")

    tool.set("move_y", 60.0)
    tool.call("cancel_move")
    assert_false(tool.is_moving(), "Reset ends the second one")
    assert_eq(document.history.step_count(), steps + 1, "without a step of its own, the way Escape does")
    Fixtures.teardown(surface, machine)


func test_the_filter_reaches_the_pass() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var built := _tool_on(surface)
    var machine: ToolMachine = built[0]
    var tool: ToolState = built[1]
    surface.get_document().active_layer.get_or_create_chunk(Vector2i(1, 1)).clear(RED)

    tool.set("filter_mode", SaResampleKernel.Filter.NEAREST)
    tool.set("scale_x", 2.0)

    assert_eq(tool.get("filter_mode"), SaResampleKernel.Filter.NEAREST, "The row holds the choice")
    assert_true(tool.is_moving(), "and a scale after it still lifts")
    Fixtures.teardown(surface, machine)
