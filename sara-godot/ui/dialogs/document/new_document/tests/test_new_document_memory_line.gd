## The New document dialog says what a size costs.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The figure is worked out here a second time from the chunk grid and the
## texel width, rather than by calling the line's own arithmetic, so a line that
## assumed 256 or 16 would disagree with this file the day either changed.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## Three sizes: one that fits the grid exactly, one that leaves a part chunk on
## both axes, and the largest the dialog takes.
const SIZES: Array[Vector2i] = [Vector2i(1024, 512), Vector2i(1920, 1080), Vector2i(16384, 16384)]

const DEPTHS: Array[String] = ["16-bit float", "32-bit float"]


func test_the_line_reads_the_arithmetic_at_three_sizes_and_both_depths() -> void:
    var dialog := NewDocumentDialog.new()
    # A discrete card, so the figure is read without the warning in its way.
    dialog.memory_line.device_bytes = 0
    for depth: String in DEPTHS:
        assert_true(dialog.select_row(&"depth", depth), "The depth row takes %s" % depth)
        for size: Vector2i in SIZES:
            dialog.page.row(&"width").drive(size.x)
            dialog.page.row(&"height").drive(size.y)
            var wanted := _expected(size, dialog.selected_space())
            var text := dialog.memory_line.text
            assert_true(
                text.contains(NewDocumentDialog.MemoryLine.size_text(wanted)),
                (
                    "%d x %d at %s reads %s, and the line says %s"
                    % [size.x, size.y, depth, NewDocumentDialog.MemoryLine.size_text(wanted), text]
                )
            )
    assert_true(
        dialog.page.row(&"memory").explanation.contains("only where it is painted"),
        "and the row says a layer costs only where it is painted"
    )
    dialog.free()


func test_the_figures_themselves() -> void:
    # Written out once, so the arithmetic above is not only checked against a
    # copy of itself. 1920 by 1080 is 8 by 5 chunks, 40 of 65536 texels.
    var f16 := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F16)
    var f32 := SaColorSpace.srgb().with_depth(SaColorSpace.Depth.F32)
    if SaLayer.CHUNK_SIZE == 256:
        assert_eq(
            NewDocumentDialog.MemoryLine.layer_bytes(Vector2i(1920, 1080), f16), 40 * 65536 * 8, "1920 x 1080 at F16 is 21 MB"
        )
        assert_eq(NewDocumentDialog.MemoryLine.layer_bytes(Vector2i(1920, 1080), f32), 40 * 65536 * 16, "and 42 MB at F32")
        assert_eq(NewDocumentDialog.MemoryLine.size_text(40 * 65536 * 8), "21 MB", "in decimal megabytes")
        assert_eq(NewDocumentDialog.MemoryLine.size_text(4096 * 65536 * 16), "4.3 GB", "and decimal gigabytes past 1000 of them")
        assert_eq(NewDocumentDialog.MemoryLine.size_text(65536 * 8), "0.5 MB", "with a tenth below 10 MB")


func test_a_layer_over_a_quarter_of_the_device_warns() -> void:
    var dialog := NewDocumentDialog.new()
    dialog.page.row(&"width").drive(16384)
    dialog.page.row(&"height").drive(16384)
    var bytes := _expected(Vector2i(16384, 16384), dialog.selected_space())
    dialog.memory_line.device_bytes = bytes * 4 - 1
    dialog.memory_line.show_cost(dialog.selected_size(), dialog.selected_space())
    assert_true(
        dialog.memory_line.text.contains("more than a quarter"),
        "A layer over a quarter of the device warns: %s" % dialog.memory_line.text
    )
    dialog.memory_line.device_bytes = bytes * 4
    dialog.memory_line.show_cost(dialog.selected_size(), dialog.selected_space())
    assert_false(dialog.memory_line.text.contains("more than a quarter"), "and one at a quarter does not")
    dialog.memory_line.device_bytes = 0
    dialog.memory_line.show_cost(dialog.selected_size(), dialog.selected_space())
    assert_false(dialog.memory_line.text.contains("more than a quarter"), "and a device Godot names no memory for never warns")
    dialog.free()


func test_a_discrete_device_is_named_no_memory() -> void:
    var kind := RenderingServer.get_video_adapter_type()
    var named := NewDocumentDialog.MemoryLine.device_memory()
    if kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or kind == RenderingDevice.DEVICE_TYPE_CPU:
        assert_true(named > 0, "A shared-memory device is named the machine's memory")
    else:
        assert_eq(named, 0, "Godot names no memory for a discrete card, so the line never warns there")


func _expected(size: Vector2i, space: SaColorSpace) -> int:
    var side := SaLayer.CHUNK_SIZE
    var texel := 0
    for spec: SaFieldSpec in SaFieldSpec.schema_for_space(space):
        texel += int(SaFieldSpec.BYTES_PER_TEXEL[spec.format])
    return ceili(size.x / float(side)) * ceili(size.y / float(side)) * side * side * texel
