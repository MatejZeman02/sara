## A document swap does not free the output while something is still bound to it.
##
## Filed by `tip-image-stamp` as `document-step-freed-texture`. Every
## `document` step raised two lines out of Godot's own canvas batcher, once per
## step:
##
##     ERROR: Texture (binding: 0, index 0) is not a valid texture.
##     ERROR: Failed to create uniform set for batch.
##
## **What it was.** `SaCanvas.resize_canvas` rebinds its own `Texture2DRD` inside
## the call that displaces the output, and holds the old texture in a local until
## it has. Nothing else does. `ui/dockers/minimap/minimap_docker.gd` **polls** for the
## swap, comparing `easel.output.rid` against the one it holds once a frame, and
## its comment says why: "two cheap comparisons a frame against three signals
## from two objects that both get swapped under this docker". So the minimap
## rebinds on its *next* `_process`, and the frame in between drew a
## `Texture2DRD` over an RID that `resize_canvas` had already let go.
##
## That is why the filing's own witness did not reproduce on a fresh checkout:
## `scenarios/fill-feather-edge.json` opens no docker, so nothing but the
## canvas was bound and the canvas rebinds in time. It takes an open Minimap.
##
## **What the fix changed.** `SaEasel` keeps the displaced output alive for one
## frame and drops it at the top of `_process`, before it composites. Every
## poller has had its own `_process` by the time that frame draws, so one frame
## of one output texture buys correctness for any holder rather than for the one
## the fix happened to know about.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice: the assertion is whether an RID is still alive.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func test_a_swap_keeps_the_displaced_output_alive_for_one_frame() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    var before: RID = easel.output.rid
    assert_true(before.is_valid(), "the easel starts with an output")

    # Discarded on purpose. `SaCanvas.resize_canvas` holds this in a local, and
    # what is under test is what happens for everything that does not.
    easel.resize_output(Vector2i(128, 128))

    assert_true(easel.output.rid != before, "the swap really replaced the output")
    assert_true(
        RenderingServer.get_rendering_device().texture_is_valid(before),
        "the displaced texture is still alive on the frame of the swap, so a docker that polls for it can rebind"
    )

    easel._process(0.0)
    assert_false(
        RenderingServer.get_rendering_device().texture_is_valid(before),
        "and it is gone on the next frame, so one swap costs one frame of one texture and not a leak"
    )
    easel.free()


## A document reset is the path a `document` step takes, and it is the one the
## filing measured. The output is re-derived from the reset document, so this is
## also the case where the two textures can differ in format rather than only in
## identity.
func test_a_document_reset_and_its_resize_leave_one_live_output() -> void:
    var easel := SaEasel.create_default(Vector2i(128, 128))
    var before: RID = easel.output.rid

    easel.document.reset_to_default(Vector2i(128, 128), SaEasel.default_space())
    easel.resize_output(Vector2i(128, 128))

    assert_true(easel.output.rid.is_valid(), "the new output is usable")
    assert_true(
        RenderingServer.get_rendering_device().texture_is_valid(before),
        "and the one the reset displaced outlives the step that displaced it"
    )
    easel._process(0.0)
    assert_false(RenderingServer.get_rendering_device().texture_is_valid(before), "for exactly one frame")
    easel.free()
