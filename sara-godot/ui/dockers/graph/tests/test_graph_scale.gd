## The Graph docker's scale toggle and hue labels, and the claim the unit
## was held to: the bin grid did not move, so a log and a linear pass over
## the same picture count the same numbers and only draw them differently.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(256, 128)


func _easel() -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(Color(0.7, 0.35, 0.2, 1.0))
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


func test_the_flags_word_packs_the_passthrough_and_the_scale() -> void:
    var plot := SaGraphPlot.new()
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 1, "An sRGB document passes through on the log scale")
    assert_eq(plot.flags_for(SaColorSpace.linear_srgb()), 0, "A linear document is decoded")
    plot.scale = "linear"
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 3, "and the linear scale is the second bit")
    assert_eq(plot.flags_for(SaColorSpace.acescg()), 2, "on its own when nothing passes through")


## The stored choice still answers the same numbers, which is the whole of
## the unit's constraint: the scale changes the picture and not the counts.
func test_the_scale_changes_the_picture_and_not_the_counts() -> void:
    var easel := _easel()
    for mode_id: String in ["histogram", "vectorscope"]:
        var plot := SaGraphPlot.new()
        assert_true(
            plot.run_over_document(easel.output, CANVAS, easel.document.color_space, mode_id), "The log %s runs" % mode_id
        )
        # The bins and the busiest slot, and not the wireframe's vertices past
        # them, which the vectorscope projects through the scale on purpose.
        var on_log := plot.read_counts().slice(0, SaGraphPlot.MAX_SLOT + 1)
        plot.scale = "linear"
        assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, mode_id), "and the linear one")
        var on_linear := plot.read_counts().slice(0, SaGraphPlot.MAX_SLOT + 1)
        assert_true(on_linear == on_log, "The %s bins the same on both scales, busiest slot included" % mode_id)
    easel.free()


func test_the_toggle_shows_for_the_two_graphs_with_a_scale() -> void:
    var docker := GraphDocker.new()
    var toggle := docker.find_child("ScaleToggle", true, false) as Button
    assert_not_null(toggle, "The toggle is on the row")
    for mode_id: String in ["histogram", "vectorscope"]:
        docker.show_mode(mode_id)
        assert_true(toggle.visible, "and shown for the %s" % mode_id)
    for mode_id: String in ["waveform", "parade", "cloud"]:
        docker.show_mode(mode_id)
        assert_false(toggle.visible, "and hidden for the %s, which has no scale" % mode_id)
    docker.show_scale("linear")
    assert_eq(docker.scale, "linear", "The docker holds the scale")
    assert_eq(docker.plot.scale, "linear", "and the canvas's plot takes it")
    assert_eq(docker.reference_plot.scale, "linear", "and the reference's with it")
    assert_true(toggle.button_pressed, "and the button shows it")
    docker.show_scale("anything else")
    assert_eq(docker.scale, "log", "A word nothing knows is the default")
    docker.free()


## A grey is the middle of the square on either scale, and a red sits to the
## right of it and above, further out on the linear scale than on the log, because the
## log pulls the small chromas near neutral outwards and squeezes the rim.
func test_a_hue_label_lands_where_the_kernel_puts_its_node() -> void:
    var space := SaColorSpace.srgb()
    var grey := SaGraphLabels.scope_unit(Color(0.5, 0.5, 0.5), space, "log")
    assert_true(grey.distance_to(Vector2(0.5, 0.5)) < 1e-4, "A grey is the middle")
    var red_log := SaGraphLabels.scope_unit(Color(1, 0, 0), space, "log")
    var red_linear := SaGraphLabels.scope_unit(Color(1, 0, 0), space, "linear")
    assert_true(red_log.x > 0.5, "A red is to the right of neutral")
    assert_true(red_log.y < 0.5, "and above it, because up is more b and Oklab's red has some")
    assert_true(red_linear.distance_to(Vector2(0.5, 0.5)) < red_log.distance_to(Vector2(0.5, 0.5)), "The log spreads it outwards")
    assert_true(red_log.distance_to(Vector2(0.5, 0.5)) <= 0.5, "and it is still inside the disc")
    var blue := SaGraphLabels.scope_unit(Color(0, 0, 1), space, "log")
    assert_true(blue.y > 0.5 and blue.x < 0.5, "A blue is below and left, where Oklab puts it")
