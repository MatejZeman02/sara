## A scenario's shot holds still under the selection outline.
##
## The marching ants walk on the shader's clock, `TIME * ant_speed` in
## `shaders/canvas/selection.gdshader`, and nothing in the capture harness held
## that clock. Two runs of one scenario shot the outline at two phases, and the
## texels `scripts/shot_diff.py` counted on the ants hid whatever differed
## beside them.
##
## `SaCapture` now stops the ants on every selection overlay in the tree and on
## every one that joins it, through `SaSelectionOverlay.hold_the_ants`, and
## nothing the painter can reach does the same. This suite draws one selection's
## outline twice through the overlay's own material, with a quarter of a second
## of shader clock between the two frames, which at the shader's sixteen pixels
## a second is half a dash. `RenderingServer.force_draw` is handed that step, so
## the clock moves by exactly it and by nothing else.
##
## The runner is synchronous and a Control's `_draw` waits for a deferred call
## no suite ever reaches, so the outline is drawn as the overlay draws it, the
## mask chunk's texture through the overlay's material, on a canvas item of the
## suite's own. The running-app proof is
## `scenarios/a-scenarios-shot-holds-still-under-the-selection-outline.json`,
## shot twice by `scripts/sara_shot.py` and compared with `scripts/shot_diff.py`.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true
const Fixtures = preload("res://tests/fixtures.gd")

## The selection, inside one chunk and away from its edges, so the outline is
## the box's four sides and nothing the chunk's own border adds.
const BOX := Rect2i(40, 48, 96, 64)

## Shader clock between the two frames, in seconds. Half the shader's own
## `ant_period` over its `ant_speed`, so a walking outline is at the opposite
## phase in the second frame and every dash has swapped colour.
const LATER := 0.25

## Where a held capture node would write, which it never does here.
static var scratch_out_dir: String = SaDataRoot.path("n1_ants_still_test")


func test_a_held_outline_is_the_same_to_the_texel_in_two_frames() -> void:
    var frames := _outline_twice(true)
    var drawn := _outline_texels(frames[0])
    assert_true(drawn > 100, "The outline is drawn at all, %d texels" % drawn)
    var differ := _differing_texels(frames[0], frames[1])
    assert_eq(differ, 0, "Under the harness the outline is the same texel for texel a quarter second later")


## The teeth of the test above: without the harness the same two frames differ,
## so a zero there is the hold and not a clock that never moved.
func test_an_outline_nobody_holds_walks_between_the_same_two_frames() -> void:
    var frames := _outline_twice(false)
    var differ := _differing_texels(frames[0], frames[1])
    var drawn := _outline_texels(frames[0])
    assert_true(differ * 2 > drawn, "Half a dash later most of the outline has changed colour, %d of %d" % [differ, drawn])


## The overlay reports the held speed in its state dump, so a shot's own dump
## says whether its ants were still.
func test_the_hold_is_the_speed_the_state_dump_reads() -> void:
    var overlay := SaSelectionOverlay.attach_to(SaCanvas.new())
    var shader_material := overlay.material as ShaderMaterial
    # Never written, so the shader's own default of sixteen pixels a second.
    assert_eq(shader_material.get_shader_parameter("ant_speed"), null, "An overlay walks at the shader's speed by default")
    overlay.hold_the_ants()
    assert_almost_eq(float(shader_material.get_shader_parameter("ant_speed")), 0.0, 0.001, "and stands still once held")
    overlay.get_parent().free()


## Two frames of one selection's outline, a quarter second of shader clock
## apart, drawn by an overlay that joins a tree with a capture node in it
## when *held* and by one that never joins a tree when not.
func _outline_twice(held: bool) -> Array[Image]:
    var capture: SaCapture = null
    if held:
        capture = SaCapture.new(scratch_out_dir)
        EventBus.add_child(capture)
        # The node would otherwise run its settle and then its empty scenario,
        # and an empty scenario ends by quitting the tree the suites run in.
        capture.set_process(false)

    var surface := Fixtures.make_surface(Vector2i(256, 256))
    var selection := surface.get_document().selection
    selection.select_rect(BOX)
    var chunk := selection.chunks[Vector2i.ZERO] as SaChunk
    var side := chunk.pixel_size()

    var viewport := SubViewport.new()
    viewport.size = Vector2i(side, side)
    viewport.transparent_bg = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    EventBus.add_child(viewport)

    # The overlay's own factory, so the material is the one the app draws with.
    # Held, it is moved into the tree after it is built, which is the path a
    # document opened by a scenario's step takes past the capture node. Not
    # held, it stays out of the tree altogether, because a suite that ran
    # earlier in the same frame can leave its own capture node there, freed
    # only at the frame's end, and that node would hold this overlay too.
    var host := SaCanvas.new()
    var overlay := SaSelectionOverlay.attach_to(host)
    if held:
        host.remove_child(overlay)
        viewport.add_child(overlay)

    var mask := Texture2DRD.new()
    mask.texture_rd_rid = chunk.field(SaSelection.FIELD).rid
    var item := RenderingServer.canvas_item_create()
    RenderingServer.canvas_item_set_parent(item, viewport.find_world_2d().canvas)
    RenderingServer.canvas_item_set_material(item, overlay.material.get_rid())
    RenderingServer.canvas_item_set_default_texture_filter(item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    RenderingServer.canvas_item_add_texture_rect(item, Rect2(0, 0, side, side), mask.get_rid())

    # Drawn without a present, which waits on the compositor and hung the full
    # run when several runs shared the card. The viewport
    # renders and the shader clock moves the same either way.
    var frames: Array[Image] = []
    RenderingServer.force_draw(false, 0.0)
    frames.append(viewport.get_texture().get_image())
    RenderingServer.force_draw(false, LATER)
    frames.append(viewport.get_texture().get_image())

    RenderingServer.free_rid(item)
    if held:
        overlay.free()
    host.free()
    viewport.free()
    if capture != null:
        capture.free()
        DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch_out_dir))
    Fixtures.teardown(surface)
    return frames


## The texels of *image* the outline covers, the box's edge grown by two either
## way, where an ant is opaque.
func _outline_texels(image: Image) -> int:
    var count := 0
    for at: Vector2i in _around_the_edge():
        if image.get_pixelv(at).a > 0.5:
            count += 1
    return count


func _differing_texels(first: Image, second: Image) -> int:
    var count := 0
    for at: Vector2i in _around_the_edge():
        if not first.get_pixelv(at).is_equal_approx(second.get_pixelv(at)):
            count += 1
    return count


## Every texel within two of the box's edge, which is the region the outline is
## drawn in and nothing inside or outside it.
func _around_the_edge() -> Array[Vector2i]:
    var outer := BOX.grow(2)
    var inner := BOX.grow(-2)
    var texels: Array[Vector2i] = []
    for y in range(outer.position.y, outer.end.y):
        for x in range(outer.position.x, outer.end.x):
            var at := Vector2i(x, y)
            if not inner.has_point(at):
                texels.append(at)
    return texels
