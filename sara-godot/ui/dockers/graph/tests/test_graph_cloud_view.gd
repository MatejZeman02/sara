## The Oklab cloud as a 3D graph the painter can turn.
##
## It needs rotate, pan and zoom (a real 3D graph) and the coloured Oklab
## wireframe geometry around it instead of a grey wireframe cube, using the
## gamut as the document is in.
##
## The wireframe is asserted by reading the vertices the pass projected rather
## than by looking at a picture, because "the gamut as the document is in" is a
## claim about numbers: an sRGB document and a Display P3 one have to draw
## different shapes, and a photograph of two similar wireframes cannot say they
## do. The turning is proved on the running app by
## scenarios/graph-3d-navigation.json.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const CANVAS := Vector2i(128, 128)


## The same shape `test_graph_plot.gd` uses, and for the reason its own history
## gives: `fill_layer` records an undo step holding a chunk snapshot, and a
## registry built for the test is one nothing frees, so either leaves the run
## failing the leak check rather than an assertion.
func _easel(color: Color) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(color)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


## Every vertex of the wireframe a pass over a document in *space* projects.
##
## The easel and the plot are both let go before this returns, because a suite
## that leaves either alive fails the run on the leak check rather than on an
## assertion.
func _frame(space: SaColorSpace) -> Array:
    var easel := _easel(Color(0.5, 0.4, 0.3, 1.0))
    easel.document.color_space = space
    var plot := SaGraphPlot.new()
    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var frame := plot.read_frame()
    easel.free()
    return frame


## The vertex nearest *rgb* on the cube, which is the one at that corner: the
## corners are the first and last vertex of the edges that meet there, so any of
## them will do and this takes the first.
func _corner(frame: Array, rgb: Color) -> Dictionary:
    var best: Dictionary = {}
    var nearest := 1e9
    for entry: Dictionary in frame:
        var color: Color = entry["color"]
        var away := absf(color.r - rgb.r) + absf(color.g - rgb.g) + absf(color.b - rgb.b)
        if away < nearest:
            nearest = away
            best = entry
    return best


func test_the_wireframe_is_a_cube_of_the_right_size() -> void:
    var frame := _frame(SaColorSpace.srgb())

    assert_eq(frame.size(), SaGraphPlot.FRAME_VERTICES, "Twelve edges at eight segments, and both ends of each")
    assert_eq(SaGraphPlot.FRAME_VERTICES, 108, "which is a hundred and eight vertices")


## Black is the bottom of the lightness axis and white the top, which is what
## says the projection puts lightness up and that the vertices are in the same
## picture the cloud is.
func test_black_is_the_bottom_of_the_axis_and_white_the_top() -> void:
    var frame := _frame(SaColorSpace.srgb())

    var black: Vector2 = _corner(frame, Color.BLACK)["at"]
    var white: Vector2 = _corner(frame, Color.WHITE)["at"]

    assert_true(black.y > white.y, "Black sits below white, the picture's y running down")
    assert_almost_eq(black.x, 0.5, 0.02, "and both are on the neutral axis, black")
    assert_almost_eq(white.x, 0.5, 0.02, "and white")


## The whole point of the matrix. A wider gamut's red is further
## from neutral in Oklab, so it projects further out, and a wireframe that
## ignored the document's matrix would put the two in the same place.
func test_a_wider_gamut_draws_a_wider_shape() -> void:
    var srgb_red: Vector2 = _corner(_frame(SaColorSpace.srgb()), Color.RED)["at"]
    var p3_red: Vector2 = _corner(_frame(SaColorSpace.display_p3()), Color.RED)["at"]

    var srgb_out := absf(srgb_red.x - 0.5)
    var p3_out := absf(p3_red.x - 0.5)
    assert_true(p3_out > srgb_out, "P3's red reaches further from neutral: %f against %f" % [p3_out, srgb_out])


## Every vertex wears the colour it stands for, so the shape reads without a
## legend. The old frame was one grey for all twelve edges.
func test_every_vertex_wears_its_own_colour() -> void:
    var frame := _frame(SaColorSpace.srgb())

    var red: Color = _corner(frame, Color.RED)["color"]
    assert_true(red.r > 0.8, "The red corner is red")
    assert_true(red.g < 0.2 and red.b < 0.2, "and nothing else")
    var green: Color = _corner(frame, Color.GREEN)["color"]
    assert_true(green.g > 0.8 and green.r < 0.2, "and the green corner green")


# --- The viewpoint --------------------------------------------------------------
#
# The three below free the easel and drop the plot before they assert anything.
# A `SaGraphPlot` is `RefCounted` and holds an `SaTexture`, and a local one that
# is still referenced while the assertions run came out of the process alive:
# three of them, three leaked texture RIDs, and `run_tests.sh` exiting 1 under
# `ALL TESTS PASSED`. Reading what is wanted first and letting go before
# asserting is the shape that does not do that.


func test_a_fresh_plot_looks_from_the_default_viewpoint() -> void:
    var plot := SaGraphPlot.new()

    assert_eq(plot.cloud_yaw, SaGraphPlot.CLOUD_YAW, "The yaw the cloud has always opened at")
    assert_eq(plot.cloud_pitch, SaGraphPlot.CLOUD_PITCH, "and the pitch")
    assert_eq(plot.cloud_pan, Vector2.ZERO, "with nothing panned")
    assert_eq(plot.cloud_zoom, 1.0, "and nothing zoomed")


## Turning moves the wireframe, which is what says the rotation is real rather
## than a redraw at one angle.
func test_turning_moves_the_wireframe() -> void:
    var easel := _easel(Color(0.5, 0.4, 0.3, 1.0))
    var plot := SaGraphPlot.new()
    var space := easel.document.color_space

    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var before: Vector2 = _corner(plot.read_frame(), Color.RED)["at"]

    plot.cloud_yaw += 1.0
    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var after: Vector2 = _corner(plot.read_frame(), Color.RED)["at"]

    easel.free()
    plot = null

    assert_true(before.distance_to(after) > 0.05, "The red corner went somewhere else")


## Zoom is about the middle of the picture, so the neutral axis stays put and
## everything else moves away from it.
func test_zoom_pushes_the_shape_out_from_the_middle() -> void:
    var easel := _easel(Color(0.5, 0.4, 0.3, 1.0))
    var plot := SaGraphPlot.new()
    var space := easel.document.color_space

    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var before: Vector2 = _corner(plot.read_frame(), Color.RED)["at"]

    plot.cloud_zoom = 2.0
    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var after: Vector2 = _corner(plot.read_frame(), Color.RED)["at"]

    easel.free()
    plot = null

    var middle := Vector2(0.5, 0.5)
    assert_almost_eq(after.distance_to(middle), before.distance_to(middle) * 2.0, 0.02, "twice as far from the middle")


func test_pan_moves_everything_by_the_same_amount() -> void:
    var easel := _easel(Color(0.5, 0.4, 0.3, 1.0))
    var plot := SaGraphPlot.new()
    var space := easel.document.color_space

    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var before := plot.read_frame()

    plot.cloud_pan = Vector2(0.1, -0.2)
    plot.run_over_document(easel.output, CANVAS, space, "cloud")
    var after := plot.read_frame()

    easel.free()
    plot = null

    for i in mini(before.size(), after.size()):
        var moved: Vector2 = (after[i]["at"] as Vector2) - (before[i]["at"] as Vector2)
        assert_almost_eq(moved.x, 0.1, 1e-5, "vertex %d moved right by the pan" % i)
        assert_almost_eq(moved.y, -0.2, 1e-5, "and up by it")
