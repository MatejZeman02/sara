## GPU integration tests for SaDocument and layer stack.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_document_setup_and_history() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(500, 500), SaCompositor.new())

    assert_eq(doc.canvas_size, Vector2i(500, 500), "Canvas size should match requested")
    assert_eq(doc.get_child_count(), 2, "Default document should have 2 child layers (Background and Layer 1)")
    var bg := doc.get_child(0)
    assert_eq(bg.name, "Background", "First layer should be Background")
    assert_not_null(doc.active_layer, "Active layer should not be null")
    if doc.active_layer != null:
        assert_eq(doc.active_layer.name, "Layer 1", "Active layer should be Layer 1")

    assert_not_null(doc.stroke_layer, "Stroke buffer should be initialized")
    assert_not_null(doc.fold.bottom_cache, "Bottom cache should be initialized")
    assert_not_null(doc.fold.top_cache, "Top cache should be initialized")
    assert_not_null(doc.undo_redo, "UndoRedo manager should be initialized")

    # Test commit stroke and undo
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0))
    doc.commit_stroke(1.0)

    assert_true(doc.stroke_layer.chunks.is_empty(), "Stroke buffer should be cleared after commit")
    assert_true(doc.undo_redo.has_undo(), "UndoRedo should have an undo action after commit")

    doc.undo_redo.undo()
    # After undo, layer state should revert
    assert_true(doc.undo_redo.has_redo(), "UndoRedo should have redo action after undo")

    doc.free()


func test_commit_stroke_erase_and_blend_modes() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    doc.active_layer.fill(Color.RED)
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.ERASE)
    doc.capture_direct_stroke_chunk(doc.active_layer, Vector2i(0, 0))
    doc.active_layer.fill(Color.TRANSPARENT)
    doc.commit_stroke()

    assert_true(doc.stroke_transaction.before_chunks.is_empty(), "stroke transaction should be cleared after commit")
    assert_true(doc.undo_redo.has_undo(), "UndoRedo should have undo after erase commit")

    doc.undo_redo.undo()
    var restored: SaChunk = doc.active_layer.chunks.get(Vector2i(0, 0))
    assert_not_null(restored, "chunk should be restored after erase undo")

    doc.stroke_layer.blend_mode = SaLayer.BLEND_MODE.MULTIPLY
    doc.stroke_layer.get_or_create_chunk(Vector2i(0, 0))
    doc.commit_stroke(1.0)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.NORMAL, "stroke layer blend mode should reset to normal")

    doc.free()


## A build-up erase paints straight onto the active layer, so the stroke buffer
## must not carry ERASE there: composite.gmacs has a real destination-out kernel,
## and a stroke layer tagged ERASE with nothing in it to carve with would carve
## the canvas during preview.
##
## The brush is what decides, and it asks for the tag by name when it
## routes a wash erase or a wash alpha-locked stroke through the buffer. The
## brush's own half is `modules/sara-base-modules/stamp-brush/tests/test_erase_and_alpha_lock_obey_the_mode.gd`.
func test_begin_stroke_tags_the_buffer_only_when_the_brush_asks() -> void:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new())

    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.ERASE)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.NORMAL, "ERASE must not reach the buffer on its own")

    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.MULTIPLY)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.MULTIPLY, "other blend modes should still reach the stroke buffer")

    doc.begin_stroke(0.5, SaLayer.BLEND_MODE.ERASE, SaLayer.BLEND_MODE.ERASE)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.ERASE, "A wash eraser asks for the tag and gets it")

    doc.begin_stroke(0.5, SaLayer.BLEND_MODE.NORMAL, SaLayer.BLEND_MODE.ALPHA_LOCK)
    assert_eq(doc.stroke_layer.blend_mode, SaLayer.BLEND_MODE.ALPHA_LOCK, "and so does a wash stroke on a locked layer")

    doc.free()


## File > New has to leave the document as clean as a fresh one, and the caches
## and stroke buffer are the trap: they are deliberately not children, so freeing
## the children alone leaves three orphan layers behind on every reset.
func test_reset_to_default_rebuilds_the_document() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    var layers_before := doc.get_children().size()

    doc.reset_to_default(Vector2i(512, 384), SaColorSpace.acescg())

    assert_eq(doc.canvas_size, Vector2i(512, 384), "The new size should be in effect")
    assert_eq(doc.get_children().size(), layers_before, "A reset document should hold the same default layers")
    assert_not_null(doc.stroke_layer, "The stroke buffer should be rebuilt")
    assert_not_null(doc.fold.bottom_cache, "The bottom cache should be rebuilt")
    assert_not_null(doc.fold.top_cache, "The top cache should be rebuilt")
    assert_not_null(doc.active_layer, "A reset document needs a layer to paint into")
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_ACESCG), "The chosen colour space should be applied")

    # Omitting the space keeps whatever the document already had, rather than
    # quietly reverting it to sRGB.
    doc.reset_to_default(Vector2i(64, 64))
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_ACESCG), "A reset with no space should keep the current one")

    easel.free()


## What a document allocates must match what its header will claim.
##
## This is the assertion that was missing when File > New shipped a 16-bit float
## option: the descriptor recorded F16, the .sad header recorded F16, and every
## chunk was RGBA32F. Nothing compared the two, so nothing failed.
func test_allocation_matches_the_descriptor_the_header_records() -> void:
    for depth: int in SaColorSpace.storage_depths():
        var space := SaColorSpace.srgb()
        space.depth = depth as SaColorSpace.Depth

        var doc := SaDocument.new()
        doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)

        # A paint layer holds no chunks until paint lands, so ask for one: the
        # depth it is made at is what this test is about.
        var chunk: SaChunk = doc.active_layer.get_or_create_chunk(Vector2i(0, 0))
        assert_eq(
            chunk.albedo().format,
            space.texel_format(),
            "A %s document must allocate the format its descriptor asks for" % SaColorSpace.depth_name(depth)
        )
        assert_true(SaFieldSpec.BYTES_PER_TEXEL.has(chunk.albedo().format), "and that format must have a known texel size")
        doc.free()


# ---------------------------------------------------------------------------
# Colour space conversion
# ---------------------------------------------------------------------------


## A chunk that was never allocated is transparent, which is what an unpainted
## layer reads as everywhere.
func _first_texel(layer: SaLayer) -> Color:
    var texture := layer.get_field(Vector2i(0, 0))
    if texture == null:
        return Color(0, 0, 0, 0)
    @warning_ignore("static_called_on_instance")
    var image := SaExport.get_texture_image_float(texture)
    return image.get_pixel(0, 0)


func _document_in(space: SaColorSpace) -> SaDocument:
    var doc := SaDocument.new()
    doc.setup_default_document(Vector2i(256, 256), SaCompositor.new(), space)
    return doc


func test_conversion_refuses_what_it_cannot_honour() -> void:
    var doc := _document_in(SaColorSpace.srgb())

    assert_false(SaColorConversion.new(doc).blocked_reason(null).is_empty(), "A null target is not convertible")
    assert_false(
        SaColorConversion.new(doc).blocked_reason(SaColorSpace.srgb()).is_empty(),
        "Converting to the space it is already in is a no-op"
    )
    assert_true(
        SaColorConversion.new(doc).blocked_reason(SaColorSpace.acescg()).is_empty(), "A genuinely different space is convertible"
    )

    # A target naming a different depth is not refused, it is ignored: converting
    # changes what the numbers mean and never how many bits they get, so an
    # ACEScg preset cannot silently reallocate an F16 document as F32.
    var f16_target := SaColorSpace.acescg().with_depth(SaColorSpace.Depth.F16)
    assert_true(SaColorConversion.new(doc).blocked_reason(f16_target).is_empty(), "A target naming another depth still converts")
    assert_true(SaColorConversion.new(doc).convert_to(f16_target), "and the conversion runs")
    assert_eq(doc.color_space.depth, SaColorSpace.Depth.F32, "with the document's own depth kept")
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_ACESCG), "while the colour space did change")

    doc.free()


func test_an_unspecified_document_must_be_assigned_not_converted() -> void:
    # The whole point of is_specified. There is no source space to convert from,
    # so converting would transform pixels nobody ever described.
    var doc := _document_in(SaColorSpace.unspecified())
    assert_false(
        SaColorConversion.new(doc).blocked_reason(SaColorSpace.acescg()).is_empty(), "An undescribed document cannot be converted"
    )
    assert_false(SaColorConversion.new(doc).convert_to(SaColorSpace.acescg()), "and the attempt refuses rather than guessing")

    assert_true(SaColorConversion.new(doc).assign(SaColorSpace.srgb()), "Assigning is what it needs instead")
    assert_true(doc.color_space.is_specified, "and afterwards the document has been told what it is")
    assert_true(SaColorConversion.new(doc).blocked_reason(SaColorSpace.acescg()).is_empty(), "so now it can be converted")

    doc.free()


func test_assign_changes_the_label_and_not_the_pixels() -> void:
    var doc := _document_in(SaColorSpace.unspecified())
    var before := _first_texel(doc.active_layer)
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    before = _first_texel(doc.active_layer)

    SaColorConversion.new(doc).assign(SaColorSpace.acescg())

    var after := _first_texel(doc.active_layer)
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_ACESCG), "The label changed")
    assert_almost_eq(after.r, before.r, 0.0, "and not one channel moved")
    assert_almost_eq(after.g, before.g, 0.0, "and not one channel moved")
    assert_almost_eq(after.b, before.b, 0.0, "and not one channel moved")

    doc.free()


func test_conversion_rewrites_colour_and_undoes_as_one_entry() -> void:
    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(0.4, 0.6, 0.8, 1.0))
    var before := _first_texel(doc.active_layer)
    var background: SaLayer = doc.get_child(0)
    var background_before := _first_texel(background)

    assert_true(SaColorConversion.new(doc).convert_to(SaColorSpace.acescg()), "sRGB to ACEScg is a real conversion")

    var after := _first_texel(doc.active_layer)
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_ACESCG), "The descriptor moved with the pixels")
    assert_true(absf(after.r - before.r) > 1e-4, "and the pixels actually changed")
    assert_almost_eq(after.a, before.a, 0.0, "while alpha is coverage and is never converted")

    # Every layer, not just the active one. A conversion that skipped the
    # background would leave one layer in the old space with no record of it.
    assert_true(
        absf(_first_texel(background).r - background_before.r) > 1e-4, "Every layer is converted, not just the active one"
    )

    # One entry covering the whole document, descriptor included. Undoing only
    # the pixels would leave converted-back values wearing the new label.
    assert_true(doc.undo(), "The conversion is undoable")
    assert_eq(str(doc.color_space.id), str(SaColorSpace.ID_SRGB), "and undo restores the descriptor too")
    assert_almost_eq(_first_texel(doc.active_layer).r, before.r, 1e-5, "and the original pixels")
    assert_almost_eq(_first_texel(background).r, background_before.r, 1e-5, "on every layer")

    assert_false(doc.undo(), "One conversion is exactly one undo entry, not one per layer")

    doc.free()


func test_a_transfer_only_conversion_leaves_the_gamut_untouched() -> void:
    # sRGB and Linear sRGB share primaries and white, so the matrix must be the
    # exact identity rather than whatever M.inverse() * M rounds to.
    var space := SaColorSpace.srgb()
    assert_eq(
        space.conversion_matrix(SaColorSpace.linear_srgb()), Basis.IDENTITY, "A shared gamut yields the exact identity matrix"
    )

    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(0.5, 0.5, 0.5, 1.0))

    SaColorConversion.new(doc).convert_to(SaColorSpace.linear_srgb())
    var linear := _first_texel(doc.active_layer)
    # 0.5 sRGB-encoded decodes to roughly 0.2140 in light-linear terms.
    assert_almost_eq(linear.r, 0.21404114, 1e-5, "Removing the curve is the whole conversion")
    assert_almost_eq(linear.g, linear.b, 1e-6, "A neutral stays neutral")

    doc.free()


func test_conversion_round_trips_and_keeps_out_of_range_values() -> void:
    # The no-clamp invariant across the new pass. Nothing in the conversion may
    # discard a negative or a value above 1.0.
    var doc := _document_in(SaColorSpace.srgb())
    doc.active_layer.fill(Color(-0.25, 1.75, 0.5, 1.0))
    var before := _first_texel(doc.active_layer)

    SaColorConversion.new(doc).convert_to(SaColorSpace.acescg())
    var converted := _first_texel(doc.active_layer)
    assert_true(is_finite(converted.r) and is_finite(converted.g), "No NaN survives the transfer pair")

    SaColorConversion.new(doc).convert_to(SaColorSpace.srgb())
    var back := _first_texel(doc.active_layer)
    assert_almost_eq(back.r, before.r, 1e-4, "A negative round-trips through the conversion")
    assert_almost_eq(back.g, before.g, 1e-4, "and so does a value above 1.0")
    assert_almost_eq(back.b, before.b, 1e-4, "and an ordinary one")

    doc.free()


func test_non_colour_fields_are_not_converted() -> void:
    # SaFieldSpec.is_color is what decides this, so a height field is untouched
    # by construction rather than by a per-layer special case.
    var doc := _document_in(SaColorSpace.srgb())
    var layer: SaLayer = doc.active_layer
    var height := SaFieldSpec.create(&"height", RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, false)
    var schema: Array[SaFieldSpec] = [SaFieldSpec.albedo(), height]
    layer.schema = schema
    layer.chunks.clear()
    layer.allocate_grid(doc.canvas_size)
    layer.fill(Color(0.4, 0.6, 0.8, 1.0))

    @warning_ignore("static_called_on_instance")
    var height_before := SaExport.get_texture_image_float(layer.get_field(Vector2i(0, 0), &"height")).get_pixel(0, 0)

    SaColorConversion.new(doc).convert_to(SaColorSpace.acescg())

    @warning_ignore("static_called_on_instance")
    var height_after := SaExport.get_texture_image_float(layer.get_field(Vector2i(0, 0), &"height")).get_pixel(0, 0)
    assert_almost_eq(height_after.r, height_before.r, 0.0, "A non-colour field is not a colour and is not converted")
    assert_almost_eq(height_after.g, height_before.g, 0.0, "on any channel")
    assert_true(absf(_first_texel(layer).r - 0.4) > 1e-4, "while the albedo beside it was")

    doc.free()


## Every route that changes the painting target has to say so, including the two
## that never call set_active_layer().
##
## The layers docker rebuilds itself from the document's child_entered_tree, which
## fires while a rebuild is still adding layers and active_layer is null. Pointing
## the field at the new layer afterwards used to be a silent assignment, so the
## docker's last word on the subject was "nothing is active" and no row came back
## highlighted after File > New. Loading a .sad picks its first layer the same way.
func test_pointing_the_document_at_a_layer_announces_it() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document

    var heard: Array = []
    doc.active_layer_changed.connect(func(layer: SaLayer) -> void: heard.append(layer))

    doc.reset_to_default(Vector2i(256, 256))
    assert_false(heard.is_empty(), "A rebuilt document has to announce its new painting target")
    assert_eq(heard[-1], doc.active_layer, "and the last thing it announced is the layer it actually points at")
    assert_not_null(heard[-1], "which is a layer, not the null it passes through mid-rebuild")

    # The method route still works and still does its extra half: the assignment
    # announces, and set_active_layer adds the cache rebuild on top.
    heard.clear()
    var other: SaLayer = doc.get_children()[0]
    doc.set_active_layer(other)
    assert_eq(heard.size(), 1, "set_active_layer announces exactly once, not twice")
    assert_eq(heard[0], other, "and it announces the layer it was handed")

    easel.free()


## The dirty set records how much of each chunk changed, and never loses any of it.
##
## Two dabs can land in one chunk between two composites, and the compositor sees
## the dirty set once. Replacing rather than unioning would redraw the second dab
## and leave the first one showing whatever was underneath.
func test_the_dirty_set_unions_the_regions_it_is_given() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    doc.consume_dirty_chunks()

    doc.invalidate_chunk_regions({Vector2i(0, 0): Rect2i(8, 8, 16, 16)})
    doc.invalidate_chunk_regions({Vector2i(0, 0): Rect2i(64, 64, 16, 16)})
    var dirty := doc.consume_dirty_chunks()
    assert_eq(dirty.size(), 1, "One chunk was touched twice, not two chunks")
    assert_eq(dirty[Vector2i(0, 0)], Rect2i(8, 8, 72, 72), "and the region covers both dabs, not just the last")

    assert_true(doc.consume_dirty_chunks().is_empty(), "Consuming clears, so a frame reads it once")

    # Everything that is not a dab still means all of the chunk.
    doc.invalidate_chunks([Vector2i(1, 1)])
    assert_eq(doc.consume_dirty_chunks()[Vector2i(1, 1)], SaDocument.WHOLE_CHUNK, "A whole-chunk caller still gets one")

    easel.free()


## Undo and redo put the actual pixels back, repeatedly.
##
## The existing coverage asked whether an undo entry *existed*. That passes against
## a swap that installs the wrong side, which is the failure mode of holding one
## snapshot instead of two: both directions share one
## Dictionary, so getting the handover backwards is silent everywhere except in the
## image. Going round twice matters as much as going round once, because a swap
## that is its own inverse only shows a mistake on the second pass.
func test_undo_and_redo_restore_the_pixels_not_just_the_flags() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document

    doc.fill_layer(Color(0.2, 0.2, 0.2, 1.0))
    var first := _first_texel(doc.active_layer)
    doc.fill_layer(Color(0.8, 0.4, 0.1, 1.0))
    var second := _first_texel(doc.active_layer)
    assert_true(first.r != second.r, "The two fills have to differ or this test cannot fail")

    doc.undo_redo.undo()
    assert_almost_eq(_first_texel(doc.active_layer).r, first.r, 0.001, "Undo puts the earlier fill back")
    doc.undo_redo.redo()
    assert_almost_eq(_first_texel(doc.active_layer).r, second.r, 0.001, "Redo puts the later one back")
    doc.undo_redo.undo()
    assert_almost_eq(_first_texel(doc.active_layer).r, first.r, 0.001, "and around again, which is where a bad swap shows")
    doc.undo_redo.redo()
    assert_almost_eq(_first_texel(doc.active_layer).r, second.r, 0.001, "and again the other way")

    easel.free()


## A step costs one copy of what it touched, not two.
##
## The whole of the first move toward one snapshot. A stroke used to hold the chunk as it was
## before *and* as it was after, so the second one was a copy of what the layer
## already had. Measured rather than asserted structurally, because the point is
## bytes of VRAM.
func test_a_history_step_holds_one_snapshot_of_each_chunk() -> void:
    var easel := SaEasel.create_default(Vector2i(256, 256))
    var doc := easel.document
    doc.fill_layer(Color(0.1, 0.1, 0.1, 1.0))

    var chunk_bytes: int = (
        SaChunk.SIZE * SaChunk.SIZE * int(SaFieldSpec.BYTES_PER_TEXEL[RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT])
    )
    var layer_chunks := doc.active_layer.chunks.size()
    assert_true(layer_chunks > 0, "There has to be something to snapshot")

    var before := SaTexture.allocated_bytes
    doc.fill_layer(Color(0.9, 0.9, 0.9, 1.0))
    var grew := SaTexture.allocated_bytes - before

    # One chunk copy per touched chunk. Two would be the old behaviour, and the
    # bound is generous enough to survive a layer schema gaining a second field.
    assert_true(grew > 0, "A reversible step does hold a snapshot")
    assert_true(
        grew < layer_chunks * chunk_bytes * 2, "but one per chunk, not two: %d bytes for %d chunks" % [grew, layer_chunks]
    )

    easel.free()


## Dragging a slider costs one cache rebuild, not one per pixel it travels.
##
## Rebuilding both caches walks every visible chunk. `SaLayerOps.set_opacity` did it
## synchronously and the slider emits `value_changed` for every pixel of travel, so
## a drag across a docker was dozens of full rebuilds for a value the user had not
## finished choosing The one that
## runs folds again over the layer's own chunks alone, so it costs no more than a
## rebuild and something, because the layer holds paint.
func test_a_run_of_opacity_changes_rebuilds_the_caches_once() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document
    # Two layers below the active one, so a rebuild folds them into the bottom
    # cache. One layer below is walked directly and a rebuild dispatches nothing.
    var layer := doc.active_layer
    doc.fill_layer(Color(0.3, 0.5, 0.7, 1.0), layer)
    SaLayerOps.new(doc).add()

    # One rebuild, measured rather than assumed, so the comparison below is against
    # the real cost of the thing being coalesced.
    SaCompute.reset_counters()
    doc.update_caches()
    var one_rebuild := int(SaCompute.counters()["dispatches"])
    assert_true(one_rebuild > 0, "A rebuild does dispatch something")

    SaCompute.reset_counters()
    for i in 20:
        SaLayerOps.new(doc).set_opacity(layer, 0.5 + float(i) * 0.02)
    assert_eq(int(SaCompute.counters()["dispatches"]), 0, "Twenty ticks of a slider dispatch nothing on their own")

    # The work still happens, once, when the frame ends.
    doc._flush_cache_update()
    var flushed := int(SaCompute.counters()["dispatches"])
    assert_true(
        flushed > 0 and flushed <= one_rebuild, "and then once, %d dispatches against a rebuild's %d" % [flushed, one_rebuild]
    )

    SaCompute.reset_counters()
    doc._flush_cache_update()
    assert_eq(int(SaCompute.counters()["dispatches"]), 0, "and the queue is empty after it")

    SaCompute.reset_counters()
    easel.free()


## An explicit rebuild absorbs a queued one rather than being followed by it.
func test_rebuilding_explicitly_cancels_the_queued_rebuild() -> void:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var doc := easel.document

    SaLayerOps.new(doc).set_opacity(doc.active_layer, 0.4)
    doc.update_caches()

    SaCompute.reset_counters()
    doc._flush_cache_update()
    assert_eq(int(SaCompute.counters()["dispatches"]), 0, "The queued rebuild had already been done")

    easel.free()
