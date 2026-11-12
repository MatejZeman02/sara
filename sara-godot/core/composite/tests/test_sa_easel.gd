## A document must be buildable and compositable with no UI node in sight.
##
## SaCanvas is a TextureRect and was once built to construct and own the document, so
## every test that needed one had to build a Control, and export had to be handed
## a view. SaEasel is that ownership without the UI.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_easel_builds_a_document_without_any_ui() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))

    assert_not_null(easel.document, "A easel owns a document")
    assert_not_null(easel.compositor, "A easel owns a compositor")
    assert_not_null(easel.output, "A easel owns the texture it composites into")
    assert_eq(easel.document.canvas_size, Vector2i(256, 256), "The document takes the requested size")
    assert_true(easel.output.rid.is_valid(), "The output texture is a real GPU resource")
    assert_true(easel.document.get_child_count() > 0, "The default document has layers")

    easel.free()


## The document must composite against the same blend-mode registry as the view
## showing it, or a module-registered mode works in one and silently falls back
## to Normal in the other.
func test_document_uses_the_injected_compositor() -> void:
    var shared := SaCompositor.new()
    var easel := SaEasel.create_default(Vector2i(256, 256), shared)

    assert_eq(easel.compositor, shared, "An injected compositor is used as-is")
    assert_eq(easel.document.compositor, shared, "The document composites against that same instance")

    easel.free()


## An empty dirty set means nothing changed. It must not fall through to a
## full-canvas composite, so any stray request re-flattened every allocated chunk
## of all four tiers.
func test_empty_dirty_set_does_not_trigger_a_full_composite() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))

    # Drain the invalidation that setup queued.
    easel.process_pending_composite()
    easel.document.consume_dirty_chunks()

    easel.request_composite()
    easel.process_pending_composite()
    assert_true(easel.document.consume_dirty_chunks().is_empty(), "Nothing should have been marked dirty")

    easel.free()


func test_full_composite_is_explicit() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.process_pending_composite()

    easel.request_full_composite()
    # A full composite must run even with an empty dirty set. That is the whole
    # reason it is a separate request.
    easel.process_pending_composite()
    assert_true(easel.output.rid.is_valid(), "The output survives a full composite")

    easel.free()


## Painting invalidates chunks, and the easel must notice through its own
## document rather than only through the global EventBus.
func test_document_invalidation_schedules_a_composite() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.process_pending_composite()
    assert_false(easel.needs_composite, "Nothing pending after a composite")

    easel.document.invalidate_chunks([Vector2i(0, 0)])
    assert_true(easel.needs_composite, "Invalidating a chunk should schedule a composite")

    easel.free()


## Resizing hands the old texture back rather than dropping it, because `output`
## is its only strong reference and the view's Texture2DRD still points at that
## RID until it rebinds.
func test_resize_output_hands_back_the_displaced_texture() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.process_pending_composite()

    var displaced := easel.resize_output(Vector2i(512, 384))

    assert_not_null(displaced, "The displaced texture must be returned, not freed")
    assert_eq(displaced.size, Vector2i(256, 256), "The displaced texture should be the old one")
    assert_true(displaced.rid.is_valid(), "The displaced RID must still be alive for the view to rebind off")
    assert_eq(easel.output.size, Vector2i(512, 384), "The new output should be the requested size")
    assert_eq(easel.canvas_size, Vector2i(512, 384), "The easel should agree with its output")
    assert_true(easel.needs_full_composite, "A resize invalidates everything, so a full composite is due")

    easel.free()
