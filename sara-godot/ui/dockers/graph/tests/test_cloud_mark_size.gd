## How big a point in the Oklab cloud is drawn.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The points inside the 3D graph have to be big enough to see, and the size is decided in the kernel rather than in
## GDScript: `cloud_mark_radius` in `shaders/compute/libs/graph_cloud.gmacs` answers a
## radius in cells and `draw_cloud` scans its neighbours for a mark that
## covers this texel. What a shot proves is that the cloud reads, and
## `scenarios/the-points-in-the-cloud-can-be-seen.json` is that shot. What
## it cannot prove is that the three numbers behind it still agree with each
## other, which is this file: the mirror in `sa_graph_plot.gd` against the
## kernel's own text, and the scan against the largest radius the kernel can
## answer. A mirror that drifts draws a cloud that still looks fine and
## reports texel counts that are a lie.
extends "res://tests/test_framework.gd"

const KERNEL := "res://shaders/compute/libs/graph_cloud.gmacs"


## The value of a `const float` or `const int` in the dialect, or NAN when the
## kernel does not declare one under that name.
func _kernel_const(name: String) -> float:
    var text := FileAccess.get_file_as_string(KERNEL)
    for line in text.split("\n"):
        var trimmed := line.strip_edges()
        if not trimmed.begins_with("const "):
            continue
        var halves := trimmed.split("=", true, 1)
        if halves.size() < 2:
            continue
        var words := halves[0].strip_edges().split(" ", false)
        if words.size() >= 3 and words[2] == name:
            return float(halves[1].strip_edges())
    return NAN


func test_the_kernel_declares_the_three_numbers_rather_than_spelling_them_out() -> void:
    var floor_of := _kernel_const("CLOUD_MARK_MIN")
    var span := _kernel_const("CLOUD_MARK_SPAN")
    var scan := _kernel_const("CLOUD_MARK_SCAN")

    assert_false(is_nan(floor_of), "the kernel names the floor a lone sample's mark gets")
    assert_false(is_nan(span), "and the span its count adds on top")
    assert_false(is_nan(scan), "and how far draw_cloud scans for one")


func test_the_gdscript_mirror_matches_the_kernel() -> void:
    assert_almost_eq(
        _kernel_const("CLOUD_MARK_MIN"),
        SaGraphPlot.CLOUD_MARK_MIN,
        1e-6,
        "the floor the dump reports is the floor the kernel draws"
    )
    assert_almost_eq(_kernel_const("CLOUD_MARK_SPAN"), SaGraphPlot.CLOUD_MARK_SPAN, 1e-6, "and so is the span")


## A scan narrower than the largest disc clips that disc square at its corners,
## which is a bug nobody would read off a screenshot of a busy cloud.
func test_the_scan_reaches_at_least_as_far_as_the_largest_mark() -> void:
    var largest := SaGraphPlot.CLOUD_MARK_MIN + SaGraphPlot.CLOUD_MARK_SPAN
    assert_true(
        _kernel_const("CLOUD_MARK_SCAN") >= ceilf(largest),
        "a scan of %d cells covers a mark of %.2f" % [int(_kernel_const("CLOUD_MARK_SCAN")), largest]
    )


## The floor is what matters here, and half a cell was too small to see.
## A larger one was a bit too large, so the floor sits between the two
## sizes: above 0.5 and below 1.25.
func test_a_lone_sample_is_no_longer_half_a_cell() -> void:
    assert_true(SaGraphPlot.CLOUD_MARK_MIN > 0.5, "a cell holding one sample reaches past the 0.5 that could not be seen")
    assert_true(SaGraphPlot.CLOUD_MARK_MIN < 1.25, "and stays under the 1.25 that was a bit too large")


## Sizing by count shipped a span of 1.6 cells, and it was widened to change size
## when clustered, so a crowded cell stands further above a lone one
## than it did and never less.
func test_the_log_scale_by_count_did_not_shrink() -> void:
    assert_true(SaGraphPlot.CLOUD_MARK_SPAN > 1.6, "the span is wider than the first one's")


## The two numbers, which is what the dump has to carry: no shot
## says how many texels across a point came out, and the answer changes with
## the docker's size.
func test_the_dump_names_both_radii_in_texels() -> void:
    var plot := SaGraphPlot.new()
    plot.set_plot_size(Vector2i(384, 384))

    var report := plot.cloud_report()

    var per_cell: float = float(report["plot_side"]) / float(report["cells"])
    assert_almost_eq(
        float(report["lone_mark_texels"]),
        SaGraphPlot.CLOUD_MARK_MIN * per_cell,
        0.02,
        "a one-count cell, in texels of the plot it is drawn in"
    )
    assert_almost_eq(
        float(report["busiest_mark_texels"]),
        (SaGraphPlot.CLOUD_MARK_MIN + SaGraphPlot.CLOUD_MARK_SPAN) * per_cell,
        0.02,
        "and the busiest cell in the same units"
    )
    assert_true(
        2.0 * float(report["lone_mark_texels"]) > float(report["texels_per_cell"]),
        "and a lone point's disc is wider than the cell it sits in, which is what stands against the wireframe"
    )
