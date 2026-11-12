## The Oklab cloud and the Graph panel's other graphs draw at the panel's own
## pixel size at UI scale 1 and 2.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The graphs inside the graph docker, the Oklab cloud mainly, have to be sharp. The picture already followed
## the panel in real pixels,
## rounded to eight, and the cloud binned into a fixed 96 cells whatever the
## picture, so a higher UI scale drew the same few logical pixels a point. Now
## the picture is the panel's real pixels to the texel and the cloud's cell is
## two of them. Read here: the docker at its default size at scale 1 and 2, the
## plot it asks for against its picture's real pixels, and the cell
## `cloud_report` gives in logical pixels. The shots are
## `scenarios/the-oklab-cloud-at-ui-scale-1.json` and its scale 2 twin.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer for the counts a capture reads.
const REQUIRES_GPU := true

const KERNEL := "res://shaders/compute/graph.gmacs"

## The widest a cell may come out at the panel's default size, in logical
## pixels, the requirement.
const WIDEST_CELL := 2.0

const SCALES: Array[float] = [1.0, 2.0]

const CANVAS := Vector2i(64, 64)

var _embedded: bool = false
var _host: Node = null
var _saved_override: float = -1.0
var _saved_user: float = 1.0


func before_each() -> void:
    _saved_override = SaUI.os_scale_override
    _saved_user = SaUI.user_scale


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null
    SaUI.os_scale_override = _saved_override
    SaUI.user_scale = _saved_user


## The value of a `const` in the kernel, or NAN when it declares none so named.
func _kernel_const(name: String) -> float:
    for line in FileAccess.get_file_as_string(KERNEL).split("\n"):
        var trimmed := line.strip_edges()
        if not trimmed.begins_with("const "):
            continue
        var halves := trimmed.split("=", true, 1)
        var words := halves[0].strip_edges().split(" ", false)
        if halves.size() == 2 and words.size() >= 3 and words[2] == name:
            return float(halves[1].strip_edges().trim_suffix("u"))
    return NAN


## The docker embedded and laid out at its default size, the way the other graph suites
## do it, since an `await` drops every assertion after it.
func _docker() -> GraphDocker:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "U604GraphHost"
    EventBus.add_child(_host)
    var docker := GraphDocker.new()
    _host.add_child(docker)
    docker.show()
    docker.size = GraphDocker.DEFAULT_SIZE
    var column := docker._control_node.get_node("VBoxContainer") as Control
    _sort(column)
    _sort(column)
    return docker


func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


func test_the_mirrors_match_the_kernel() -> void:
    assert_almost_eq(_kernel_const("CLOUD_CELL_TEXELS"), SaGraphPlot.CLOUD_CELL_TEXELS, 1e-6, "two texels a cell, both sides")
    assert_eq(int(_kernel_const("CLOUD_FIXED_CELLS")), SaGraphPlot.CLOUD_FIXED_CELLS, "the capture's 96, both sides")
    assert_eq(SaGraphPlot.CLOUD_MAX_CELLS, SaGraphPlot.COLUMNS, "and the most cells is the plane's side")


## Even, so a grey's 0.5 is the middle of a cell and never a seam, two texels a
## cell or a little under wherever the plane has room, and held inside it where
## it has not.
func test_the_cells_follow_the_picture() -> void:
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(380, 196)), 98, "a picture 196 high is 98 cells")
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(760, 392)), 196, "and twice it twice as many")
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(302, 302)), 152, "151 rounds up to even, so a cell is under two texels")
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(153, 300)), 78, "and 76.5 up to 78")
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(2048, 2048)), SaGraphPlot.CLOUD_MAX_CELLS, "a 4K panel stops at the plane")
    assert_eq(SaGraphPlot.cloud_cells_for(Vector2i(SaGraphPlot.MIN_PLOT, 900)), 32, "and the smallest is still points")
    for side in range(SaGraphPlot.MIN_PLOT, 2 * SaGraphPlot.CLOUD_MAX_CELLS + 1, 7):
        var cells := SaGraphPlot.cloud_cells_for(Vector2i(side, side))
        assert_eq(cells % 2, 0, "%d texels is an even count" % side)
        assert_true(float(side) / float(cells) <= SaGraphPlot.CLOUD_CELL_TEXELS, "of cells no wider than two texels at %d" % side)


## The main case: at either scale the plot is the picture's real pixels
## and a cell is at most two logical pixels across at the default size.
func test_at_scale_1_and_2_the_plot_is_the_pictures_pixels_and_a_cell_is_small() -> void:
    for factor in SCALES:
        SaUI.os_scale_override = 1.0
        SaUI.user_scale = factor
        var docker := _docker()
        docker._resize_plot()
        var picture := docker._picture.size
        assert_true(picture.x > 100.0 and picture.y > 100.0, "the picture is laid out, %s at %.0fx" % [picture, factor])
        var physical := Vector2i((picture * factor).round())
        assert_eq(docker.plot.plot_size, physical, "at %.0fx the plot is the picture's %s real pixels" % [factor, physical])
        var report := docker.plot.cloud_report()
        var logical_cell := float(report["texels_per_cell"]) / factor
        assert_true(logical_cell <= WIDEST_CELL, "at %.0fx a cell is %.2f logical pixels, %s" % [factor, logical_cell, report])
        _host.free()
        _host = null


## A capture still reads the cloud on the 96 cells it always read, so a
## scenario's numbers are the same at any panel size and any scale.
func test_a_capture_reads_the_same_cloud_at_every_picture_size() -> void:
    var easel := SaEasel.create_default(CANVAS)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(Color(0.5, 0.5, 0.5, 1.0))
    easel.request_full_composite()
    easel.process_pending_composite()
    var first := PackedInt32Array()
    for size: Vector2i in [Vector2i(380, 196), Vector2i(760, 392), Vector2i(128, 128)]:
        var plot := SaGraphPlot.new()
        plot.set_plot_size(size)
        assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "cloud"), "the pass at %s" % size)
        var counts := plot.read_counts().slice(0, SaGraphPlot.PLANE)
        var filled := -1
        for index in counts.size():
            if counts[index] > 0:
                filled = index
                break
        @warning_ignore("integer_division")
        var neutral: int = SaGraphPlot.CLOUD_FIXED_CELLS / 2
        assert_eq(filled % SaGraphPlot.CLOUD_FIXED_CELLS, neutral, "the grey is the fixed grid's neutral column at %s" % size)
        if first.is_empty():
            first = counts
        else:
            assert_true(counts == first, "and the counts at %s are the counts at the first size" % size)
    easel.free()
