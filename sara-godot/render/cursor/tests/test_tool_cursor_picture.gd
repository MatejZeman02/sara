## A tool may name its own cursor picture, and the eyedropper does.
##
## The note of 2026-09-03 08:37:14 offered three answers, "system mouse,
## crosshair or the eyedropper", and remarked "but eyedropper icon would be
## better". The crosshair was taken because a `Control.CursorShape` is one of
## Godot's stock arrows and a descriptor could not ask for a drawing. It can
## now, and the crosshair is the fallback rather than the answer.
##
## Every assertion here is bookkeeping rather than a picture, because the
## compositor draws the OS cursor and no capture has ever held one. The scenario
## `eyedropper-cursor` is the half that runs on the app.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")


func teardown() -> void:
    # Or a run leaves the desktop's own pointer replaced, which outlives Godot.
    SaCursorPolicy.clear_tool_cursor()


## The eyedropper names a picture and a tip. Read off the registry rather than
## written out, so a tool that stops naming one fails here.
func test_the_eyedropper_names_a_picture_and_a_tip() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptor := registry.get_descriptor(&"eyedropper")
    assert_not_null(descriptor, "the eyedropper is registered")
    assert_not_null(descriptor.cursor_texture, "and carries a cursor picture")
    assert_eq(descriptor.cursor_shape, Control.CURSOR_CROSS, "with the crosshair still behind it as the fallback")
    var tip: Vector2 = descriptor.cursor_hotspot
    assert_true(tip.x > 0.0 and tip.x < 0.5, "the tip is on the left half: %s" % tip)
    assert_true(tip.y > 0.5 and tip.y < 1.0, "and the lower half, which is where an eyedropper points")


## The hotspot is a fraction, not pixels, because the picture is resized to the
## display's own cursor size and pixels would drift off the tip.
func test_the_hotspot_is_a_fraction_of_the_picture() -> void:
    var registry := Fixtures.make_tool_registry()
    for tool_id: StringName in registry.list_ids():
        var descriptor := registry.get_descriptor(tool_id)
        if descriptor.cursor_texture == null:
            continue
        var tip: Vector2 = descriptor.cursor_hotspot
        assert_true(tip.x >= 0.0 and tip.x <= 1.0, "%s's hotspot x is a fraction: %s" % [tool_id, tip])
        assert_true(tip.y >= 0.0 and tip.y <= 1.0, "%s's hotspot y is a fraction: %s" % [tool_id, tip])


## Only the tool that named a picture holds a slot, and giving it up is what a
## tool change does. Seven tools share `CURSOR_CROSS`, so a slot left held
## would put the eyedropper under the lasso and the brush as well.
func test_a_slot_is_held_by_one_tool_and_given_back() -> void:
    var registry := Fixtures.make_tool_registry()
    var dropper := registry.get_descriptor(&"eyedropper")
    var lasso := registry.get_descriptor(&"lasso")
    assert_null(lasso.cursor_texture, "the lasso names no picture, and shares the eyedropper's shape")

    SaCursorPolicy.apply_tool_cursor(null, dropper, dropper.cursor_shape)
    var held := SaCursorPolicy.tool_cursor_state()
    assert_true(held["custom"], "the eyedropper takes a slot")
    assert_eq(held["tool"], "eyedropper", "under its own name")
    assert_eq(held["shape"], Control.CURSOR_CROSS, "which is the shape it declares")

    SaCursorPolicy.apply_tool_cursor(null, lasso, lasso.cursor_shape)
    var freed := SaCursorPolicy.tool_cursor_state()
    assert_false(freed["custom"], "and gives it back to a tool that names no picture")
    assert_eq(freed["shape"], -1, "holding no slot at all")


## The canvas the picture was put up over gives the slot back when it leaves
## the tree, and only that canvas does. The app's shutdown is
## the case: a picture still standing in a slot at exit outlives the rendering
## server's leak count, because the display server that holds it is torn down
## after. Two Controls stand in for two surfaces.
func test_the_canvas_that_holds_the_picture_gives_it_back_on_exit() -> void:
    var registry := Fixtures.make_tool_registry()
    var dropper := registry.get_descriptor(&"eyedropper")
    var main_canvas := Control.new()
    var other_canvas := Control.new()

    SaCursorPolicy.apply_tool_cursor(main_canvas, dropper, dropper.cursor_shape)
    assert_true(SaCursorPolicy.tool_cursor_state()["custom"], "the eyedropper's picture is up over the main canvas")

    SaCursorPolicy.release_tool_cursor_of(other_canvas)
    assert_true(SaCursorPolicy.tool_cursor_state()["custom"], "another surface leaving does not take it down")
    SaCursorPolicy.release_tool_cursor_of(null)
    assert_true(SaCursorPolicy.tool_cursor_state()["custom"], "and neither does nothing at all")

    SaCursorPolicy.release_tool_cursor_of(main_canvas)
    var freed := SaCursorPolicy.tool_cursor_state()
    assert_false(freed["custom"], "the canvas it was put up over gives the slot back")
    assert_eq(freed["shape"], -1, "holding no slot at all")

    main_canvas.free()
    other_canvas.free()


## A picture a tool asks for by position stands in the slot of the shape it
## asked for, in place of the descriptor's, and goes when the tool stops asking,
## the Transform's rotate arrow beside a corner. The
## Eyedropper's own picture lends the texture, so this needs no module.
func test_a_picture_by_position_stands_in_the_slot_and_goes() -> void:
    var registry := Fixtures.make_tool_registry()
    var lasso := registry.get_descriptor(&"lasso")
    var drawn: Texture2D = registry.get_descriptor(&"eyedropper").cursor_texture
    var picture := SaCursorPicture.new(&"arrow", drawn, Vector2(0.5, 0.5))

    SaCursorPolicy.apply_tool_cursor(null, lasso, Control.CURSOR_MOVE, picture)
    var held := SaCursorPolicy.tool_cursor_state()
    assert_true(held["custom"], "A tool with no picture of its own takes a slot for one it asks for by position")
    assert_eq(held["tool"], "lasso", "under its own name")
    assert_eq(held["picture"], "arrow", "with the picture named beside it")
    assert_eq(held["shape"], Control.CURSOR_MOVE, "in the slot of the shape it asked for")

    SaCursorPolicy.apply_tool_cursor(null, lasso, Control.CURSOR_MOVE)
    var freed := SaCursorPolicy.tool_cursor_state()
    assert_false(freed["custom"], "and gives it back when it stops asking")
    assert_eq(freed["picture"], "", "naming no picture")

    var dropper := registry.get_descriptor(&"eyedropper")
    SaCursorPolicy.apply_tool_cursor(null, dropper, dropper.cursor_shape, picture)
    assert_eq(SaCursorPolicy.tool_cursor_state()["picture"], "arrow", "It wins over a descriptor's own picture")
    SaCursorPolicy.apply_tool_cursor(null, dropper, dropper.cursor_shape)
    var own := SaCursorPolicy.tool_cursor_state()
    assert_true(own["custom"], "which comes back when the tool stops asking")
    assert_eq(own["picture"], "", "as the descriptor's, which names none")

    var made := SaCursorPolicy._tool_cursor_texture(&"lasso/arrow", drawn)
    assert_eq(made.get_width(), SaCursorPolicy.tool_cursor_edge, "The picture is drawn at the edge every tool picture is")
    assert_false(
        made == SaCursorPolicy._tool_cursor_texture(&"eyedropper", drawn),
        "and kept apart from the descriptor's copy, under the tool and the picture together"
    )


## A picture asked for while a gesture is held stays up wherever the pointer is,
## over a docker as well as the canvas, because the gesture goes on there, and
## one that says what a press would do stands over the canvas alone. A Control
## far off the window, where no canvas is, stands in for a docker's ground.
func test_a_held_picture_stays_off_the_canvas_and_a_hovered_one_does_not() -> void:
    var registry := Fixtures.make_tool_registry()
    var lasso := registry.get_descriptor(&"lasso")
    var drawn: Texture2D = registry.get_descriptor(&"eyedropper").cursor_texture
    # Under an autoload, since the runner calls this from its own `_ready` and
    # a parent mid-`_ready` rejects `add_child`.
    var canvas := Control.new()
    EventBus.add_child(canvas)
    canvas.position = Vector2(-4000.0, -4000.0)
    canvas.size = Vector2(8.0, 8.0)
    var mode_was := SaSettings.software_cursor
    SaSettings.software_cursor = "auto"

    SaCursorPolicy.apply_tool_cursor(canvas, lasso, Control.CURSOR_MOVE, SaCursorPicture.new(&"arrow", drawn))
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "Off the canvas a hovered picture is not put up")
    SaCursorPolicy.apply_tool_cursor(canvas, lasso, Control.CURSOR_MOVE, SaCursorPicture.new(&"arrow", drawn, Vector2.ZERO, true))
    var held := SaCursorPolicy.tool_cursor_state()
    assert_true(held["custom"], "and a held one is")
    assert_eq(held["picture"], "arrow", "naming it")
    SaSettings.software_cursor = "never"
    SaCursorPolicy.sync_tool_cursor()
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "except under Never, where no tool picture shows")

    SaSettings.software_cursor = mode_was
    SaCursorPolicy.clear_tool_cursor()
    canvas.free()


## A tool with no descriptor at all must not leave the last one's picture up,
## which is what happens on a surface with no tool bound.
func test_no_descriptor_gives_the_slot_back() -> void:
    var registry := Fixtures.make_tool_registry()
    SaCursorPolicy.apply_tool_cursor(null, registry.get_descriptor(&"eyedropper"), Control.CURSOR_CROSS)
    assert_true(SaCursorPolicy.tool_cursor_state()["custom"], "held first")

    SaCursorPolicy.apply_tool_cursor(null, null, Control.CURSOR_ARROW)
    assert_false(SaCursorPolicy.tool_cursor_state()["custom"], "and released by a null descriptor")


## The picture is resized rather than handed over as it is: the SVG import
## rasterises at `svg/scale=4.0`, so a 16 pixel icon arrives as 64 and a 64
## pixel cursor is three times the arrow beside it.
func test_the_picture_is_resized_to_the_cursor_size() -> void:
    var registry := Fixtures.make_tool_registry()
    var descriptor := registry.get_descriptor(&"eyedropper")
    var source: Texture2D = descriptor.cursor_texture
    var made := SaCursorPolicy._tool_cursor_texture(&"eyedropper", source)
    assert_not_null(made, "a cursor texture is built")
    var edge := SaUI.px(SaCursorPolicy.TOOL_CURSOR_EDGE)
    assert_eq(made.get_width(), edge, "at the cursor edge, not the icon's own %d" % source.get_width())
    assert_eq(made.get_height(), edge, "square, the way every stock arrow is")
    assert_true(
        SaCursorPolicy._tool_cursor_texture(&"eyedropper", source) == made,
        "and cached, or every press of the tool's chord rasterises it again"
    )


## The canvas still gets the stock shape, which is what a painter sees when the
## picture fails to load and what every tool naming none has always got.
func test_the_stock_shape_still_reaches_the_canvas() -> void:
    var registry := Fixtures.make_tool_registry()
    var host := Control.new()
    host.mouse_default_cursor_shape = Control.CURSOR_ARROW

    SaCursorPolicy.apply_tool_cursor(host, registry.get_descriptor(&"eyedropper"), Control.CURSOR_CROSS)
    assert_eq(host.mouse_default_cursor_shape, Control.CURSOR_CROSS, "the fallback shape is written whatever the picture does")

    SaCursorPolicy.apply_tool_cursor(host, registry.get_descriptor(&"pan"), Control.CURSOR_POINTING_HAND)
    assert_eq(host.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "and follows the next tool")
    host.free()
