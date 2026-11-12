## Sample merged as a toggle: the pickup's second source, the layer being
## painted rather than the composite.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The layer snapshot's copy discipline, and the row that chooses it.** What a
## stroke reads is `scenarios/sample-merged-as-a-toggle.json`, which paints
## across a seam twice and photographs both. What a stroke cannot say is which
## texels the snapshot holds before the stroke starts, so the snapshot is built
## here over a two-layer document and read back, which a test may do and the
## brush never does.
extends "res://tests/test_framework.gd"

const SettingsScript = preload("res://modules/sara-base-modules/stamp-brush/stamp_brush_settings.gd")

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true

const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const NOTHING := Color(0.0, 0.0, 0.0, 0.0)


## A 512 by 512 easel with red on the lower layer's first cell and blue on the
## upper layer's second: the composite and the upper layer differ at the first
## cell, where the lower layer's red shows through, which is the texel that
## tells the two sources apart.
func _two_layer_easel() -> SaEasel:
    var easel := SaEasel.create_default(Vector2i(512, 512))
    var document := easel.document
    var lower := document.active_layer
    lower.get_or_create_chunk(Vector2i(0, 0)).clear(RED)
    var upper := SaLayerOps.new(document).add()
    upper.get_or_create_chunk(Vector2i(1, 0)).clear(BLUE)
    document.invalidate_chunks([Vector2i(0, 0), Vector2i(1, 0)])
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## The test's own readback: one texel of a snapshot, addressed in document space
## through the snapshot's own mapping.
func _texel(snapshot: SaLayerSnapshot, pos: Vector2i) -> Color:
    @warning_ignore("static_called_on_instance")
    var img := SaExport.get_texture_image_float(snapshot.texture)
    if img == null:
        return Color(NAN, NAN, NAN, NAN)
    var local := snapshot.local_of(pos)
    return img.get_pixel(local.x, local.y)


## The same readback off the composite's snapshot, for the one comparison that
## says the layer source is not the merged one.
func _merged_texel(snapshot: SaMergedSnapshot, pos: Vector2i) -> Color:
    @warning_ignore("static_called_on_instance")
    var img := SaExport.get_texture_image_float(snapshot.texture)
    if img == null:
        return Color(NAN, NAN, NAN, NAN)
    var local := snapshot.local_of(pos)
    return img.get_pixel(local.x, local.y)


func _assert_color(actual: Color, expected: Color, what: String) -> void:
    assert_almost_eq(actual.r, expected.r, 0.01, "%s: red" % what)
    assert_almost_eq(actual.g, expected.g, 0.01, "%s: green" % what)
    assert_almost_eq(actual.b, expected.b, 0.01, "%s: blue" % what)
    assert_almost_eq(actual.a, expected.a, 0.01, "%s: alpha" % what)


# --- The row -------------------------------------------------------------------------


## A brush written before the row read the composite, so a new one does and a
## file below the version comes back doing it.
func test_a_new_brush_samples_merged_and_an_older_file_comes_back_doing_it() -> void:
    var settings := SaStampBrushSettings.new()
    assert_true(settings.smudge_sample_merged, "A new brush reads every visible layer, as the stage always did")
    assert_eq(settings.format_version, SettingsScript.FORMAT_VERSION, "and a new object is already at the current version")

    settings.format_version = 9
    settings.smudge_sample_merged = false
    assert_true(settings.migrate(), "A file written below the row migrates")
    assert_true(settings.smudge_sample_merged, "and comes back reading the composite, which is what it painted")
    assert_eq(settings.format_version, SettingsScript.FORMAT_VERSION, "stamped to the version the row landed at")


# --- The snapshot --------------------------------------------------------------------


## The layer snapshot holds the layer it was asked for and not the composite:
## where only the lower layer is painted, the upper layer's snapshot is empty
## and the composite is red.
func test_the_layer_snapshot_holds_the_layer_and_not_the_composite() -> void:
    var easel := _two_layer_easel()
    var upper := easel.document.active_layer

    var snapshot := SaLayerSnapshot.new(upper, Rect2i(0, 0, 512, 256))
    assert_not_null(snapshot.texture, "A rectangle on the canvas gets a texture")
    assert_eq(snapshot.rect, Rect2i(0, 0, 512, 256), "sized to the rectangle asked for")
    assert_eq(snapshot.chunk_copies, 1, "One copy per cell the layer holds a chunk in, and it holds one")

    _assert_color(_texel(snapshot, Vector2i(300, 100)), BLUE, "The cell the layer paints is its blue")
    _assert_color(_texel(snapshot, Vector2i(100, 100)), NOTHING, "and the cell it does not is empty rather than the layer below")

    var merged := easel.snapshot_merged(Rect2i(0, 0, 512, 256))
    assert_eq(merged.chunk_copies, 2, "The composite's own snapshot copies both cells")
    _assert_color(_merged_texel(merged, Vector2i(100, 100)), RED, "and it is red where the layer snapshot is empty")

    easel.free()


## A dab that leaves the snapshot grows it by the cells it reaches, and the part
## already held keeps the picture it was taken with: the stroke reads what stood
## before it, not the paint it has laid since.
func test_a_growth_copies_only_the_new_cells_and_keeps_the_old_picture() -> void:
    var easel := _two_layer_easel()
    var upper := easel.document.active_layer

    var snapshot := SaLayerSnapshot.new(upper, Rect2i(300, 10, 20, 20))
    assert_eq(snapshot.chunk_copies, 1, "One cell to start")

    snapshot.grow(Rect2i(305, 15, 5, 5))
    assert_eq(snapshot.chunk_copies, 1, "A dab inside the snapshot costs no copy")
    assert_eq(snapshot.rect, Rect2i(300, 10, 20, 20), "and moves nothing")

    # The layer changes under the stroke, the way a stroke's own dabs change it.
    # The cell is cleared to green so the old and the new part can be told apart.
    upper.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)

    snapshot.grow(Rect2i(280, 10, 20, 20))
    assert_eq(snapshot.rect, Rect2i(280, 10, 40, 20), "The snapshot is the union of the two rectangles")
    assert_eq(snapshot.chunk_copies, 2, "The growth copied the new strip of the cell and nothing else")

    _assert_color(_texel(snapshot, Vector2i(305, 15)), BLUE, "What was held is still the blue it was taken with")
    _assert_color(_texel(snapshot, Vector2i(285, 15)), GREEN, "and the new strip is what stands now")

    easel.free()


## A rectangle off the canvas holds nothing, the way the composite's snapshot
## does, and the reservoir answers which source the setting asked for.
func test_the_snapshot_is_clipped_and_the_reservoir_holds_the_one_it_was_asked_for() -> void:
    var easel := _two_layer_easel()
    var upper := easel.document.active_layer

    var off := SaLayerSnapshot.new(upper, Rect2i(600, 600, 10, 10))
    assert_null(off.texture, "A rectangle off the canvas holds no texture")
    assert_eq(off.chunk_copies, 0, "and copied nothing")

    var merged := SaSmudgeReservoir.new(easel, upper, true, Rect2i(0, 0, 32, 32))
    assert_true(merged.snapshot is SaMergedSnapshot, "Sample Merged on builds the composite's snapshot")
    var layer_only := SaSmudgeReservoir.new(easel, upper, false, Rect2i(0, 0, 32, 32))
    assert_true(layer_only.snapshot is SaLayerSnapshot, "and off builds the layer's own")

    easel.free()
