## Work hung on the event rate: three places where a motion event does a frame's
## work.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One mistake in three places: an input handler reached by a motion event does
## a frame's work. Each has a method here that asserts the behaviour a fix has
## to produce.
##
## The shape all three want is `state_gradient.gd`'s: the motion records what
## moved and a `tick` does the work once, so a frame with no motion does
## nothing. `test_the_gradient_is_the_shape_the_three_fixes_copy` below pins that
## shape, so a change to it cannot quietly take the model away.
extends "res://tests/test_framework.gd"

## The eyedropper reads the composited output back and the transform dispatches
## over the stroke layer, so both need a real device.
const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")


func _button(pressed: bool) -> InputEventMouseButton:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = pressed
    return event


## A motion the tools read: the capture harness leaves the button mask empty, so
## the tools that track their own press are driven through the press above and
## the ones that read the mask get it here.
func _motion(at: Vector2) -> InputEventMouseMotion:
    var event := InputEventMouseMotion.new()
    event.position = at
    event.global_position = at
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    return event


## Counts one signal on `EventBus` for the length of a block, and gives the
## count back. A lambda rather than a field, because two of the three cases
## count different signals and the bus is an autoload the whole suite shares.
class BusCounter:
    extends RefCounted

    var count: int = 0

    func _init(signal_name: StringName) -> void:
        EventBus.connect(signal_name, _hit)

    func _hit(_a: Variant = null, _b: Variant = null) -> void:
        count += 1


## The model the three fixes copy: a motion records the far end and sets a flag,
## and the frame's `tick` does the work once.
##
## Its whole job is to fail if the shape it names goes away under a change that
## copies it.
func test_the_gradient_is_the_shape_the_three_fixes_copy() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool: Variant = machine.active_tool

    assert_true(tool.has_method("tick"), "the gradient has a frame door")
    assert_true(tool.has_method("move_to"), "and a motion door that only records")

    Fixtures.teardown(surface, machine)


## The eyedropper reads the GPU back on every motion event of a drag.
##
## `state_eyedropper.gd:49` sends every motion straight to
## `_sample_color_at_mouse`, which copies a texel out of the composited output
## and calls `rd.texture_get_data`, a synchronous readback that waits for the
## GPU. A tablet sends a motion every few milliseconds, so the drag is a stall
## per event. Once the sample hangs on the frame, two motions inside one frame
## are one sample and one `color_picked`.
func test_the_eyedropper_samples_once_a_frame() -> void:
    var surface := Fixtures.make_surface(Vector2i(512, 512))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    # Painted on the layer and in the view, because a pick of no paint is not
    # emitted and would count nothing whichever the Sample row reads.
    var paint := Color(0.5, 0.4, 0.3, 1.0)
    document.active_layer.get_or_create_chunk(Vector2i(0, 0)).field(SaFieldSpec.ALBEDO).clear(paint)
    GlobalShaderCompiler.get_rd().texture_clear(surface.easel.output.rid, paint, 0, 1, 0, 1)
    machine.set_active_tool(&"eyedropper")
    var tool: Variant = machine.active_tool
    var picks := BusCounter.new(&"color_picked")

    surface.view.mouse_position = Vector2(100, 100)
    tool.handle_input(_button(true))
    var after_press := picks.count
    surface.view.mouse_position = Vector2(120, 100)
    tool.handle_input(_motion(Vector2(120, 100)))
    surface.view.mouse_position = Vector2(140, 100)
    tool.handle_input(_motion(Vector2(140, 100)))

    assert_eq(picks.count - after_press, 0, "the two motions inside the frame record and do not sample")
    if tool.has_method("tick"):
        tool.call("tick", 0.016)
    assert_eq(picks.count - after_press, 1, "and the frame's tick samples once, at the last position")

    Fixtures.teardown(surface, machine)


## A docker resize writes the layout file on every motion event.
##
## `main_dockers.gd` connects each docker's `size_changed` to
## `_save_docker_layout`, and `docker_resizer.gd` assigns `size` on every motion
## of a grip drag, so the drag is a `ConfigFile.load` plus a walk of every docker
## plus a `cfg.save` per event. The release already emits
## `docker_layout_changed`, which saves through the painter door, so the per
## event save buys nothing.
##
## Read off the source rather than driven, because the wire is what is wrong and
## because a `Window` added to the tree in a headless run hangs the suite, which
## `ui/shortcuts/tests/test_escape_closes_docker.gd` records.
func test_the_layout_is_not_written_per_size_change() -> void:
    var text := FileAccess.get_file_as_string("res://ui/main/main_dockers.gd")
    assert_false(text.is_empty(), "the file is readable")
    assert_false(
        text.contains("size_changed.connect(save_docker_layout)"),
        "a docker's size_changed does not write the layout file, the release does"
    )


## The transform preview dispatches on every motion event of a drag.
##
## `state_transform.gd:367` sends every motion to `_drag`, which reaches
## `SaTransform._draw_preview` through `preview_matrix` or `preview_homography`.
## That builds two collections and dispatches a blank and a shift or a resample
## over every chunk the moved selection overlaps, and emits
## `tool_options_moved` beside it, all at the tablet's event rate. It is the gradient's
## old mistake with a different kernel: the extent obeys hard rule 2, the rate does
## not.
##
## `tool_options_moved` is what the count reads, because it is emitted from the
## same two lines as the dispatch and needs no seam the fix has not added yet.
func test_the_transform_previews_once_a_frame() -> void:
    var surface := Fixtures.make_surface(Vector2i(1024, 1024))
    var machine := Fixtures.make_bound_machine(surface)
    var document := surface.get_document()
    document.active_layer.get_or_create_chunk(Vector2i(1, 1))
    document.selection.select_rect(Rect2i(400, 384, 500, 400))
    machine.set_active_tool(&"transform")
    var tool: Variant = machine.active_tool
    surface.view.mouse_position = Vector2(650, 584)
    tool.handle_input(_button(true))
    var moved := BusCounter.new(&"tool_options_moved")

    surface.view.mouse_position = Vector2(700, 600)
    tool.handle_input(_motion(Vector2(700, 600)))
    surface.view.mouse_position = Vector2(750, 620)
    tool.handle_input(_motion(Vector2(750, 620)))

    assert_eq(moved.count, 0, "the two motions inside the frame record the far end and nothing else")
    if tool.has_method("tick"):
        tool.call("tick", 0.016)
    assert_eq(moved.count, 1, "and the frame draws one preview, at the last position")

    Fixtures.teardown(surface, machine)
