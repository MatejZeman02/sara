## The Graph says what it graphs and its white trace is one channel.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Review sweeps met the same row of controls: a "W" and a Mode row
## "Waveform (W)" that said white and not of what, a source dropdown drawn as
## its arrow alone, scale numbers struck through by their own lines, and a cloud
## that could be turned and never put back. Both the row and the W stay,
## and the trace is one Oklab channel, L, not the coloured lines drawn white. So the trace is binned from Oklab L, the
## two doors to it say so, both dropdowns are as wide as their longest rows in
## a row that wraps rather than clips, the numbers sit on a backing above their
## lines, and a Reset beside the source puts the cloud back.
##
## The layout cases embed the docker and sort its containers by hand, the way
## `test_the_recorder_shows_where_it_writes_and_says_stop.gd` does, since an
## `await` drops every assertion after it. The shots are
## `scenarios/the-graph-says-what-it-graphs-and-its-white-trace-is-one-control.json`.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer, and a picture read back.
const REQUIRES_GPU := true

## Pure red on the left half and pure blue on the right, the pair the ask names:
## their largest channel is the same 1.0 and their lightness is not.
const PAIR := Vector2i(64, 32)

## The picture the docker opens at, about.
const PLOT := Vector2i(304, 232)

## The Graph's width in every shipped layout, `layouts/*.cfg`.
const SHIPPED_WIDTH := 380

var _embedded: bool = false
var _host: Node = null


func after_each() -> void:
    if _host != null and is_instance_valid(_host):
        _host.free()
        (Engine.get_main_loop() as SceneTree).root.gui_embed_subwindows = _embedded
    _host = null


func _red_beside_blue() -> SaTexture:
    var image := Image.create_empty(PAIR.x, PAIR.y, false, Image.FORMAT_RGBAF)
    @warning_ignore("integer_division")
    var half := PAIR.x / 2
    for y in PAIR.y:
        for x in PAIR.x:
            image.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0) if x < half else Color(0.0, 0.0, 1.0, 1.0))
    return SaGraphPlot.upload_image(image, PAIR.x)


## Oklab L of a display colour with the sRGB curve on it, worked out on the CPU
## the way the kernel's `lightness_of` does on the GPU.
func _lightness(colour: Color) -> float:
    var linear := colour.srgb_to_linear()
    return SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b)).x


## The value a row of the picture stands for, the kernel's `wave_value`.
func _row_value(y: int, height: int) -> float:
    return (1.0 - (float(y) + 0.5) / float(height)) / SaGraphPlot.VALUE_TOP


## The row of column *x* the brightest texel is in.
func _brightest_row(image: Image, x: int) -> int:
    var best := -1.0
    var row := -1
    for y in image.get_height():
        var lit := image.get_pixel(x, y).r
        if lit > best:
            best = lit
            row = y
    return row


func _docker() -> GraphDocker:
    var tree := Engine.get_main_loop() as SceneTree
    _embedded = tree.root.gui_embed_subwindows
    tree.root.gui_embed_subwindows = true
    _host = Node.new()
    _host.name = "N117GraphHost"
    EventBus.add_child(_host)
    var docker := GraphDocker.new()
    _host.add_child(docker)
    docker.show()
    var body := Theme.new()
    body.default_font = SaFonts.regular()
    body.default_font_size = SaUI.get_font_size()
    docker._control_node.theme = SaUI.shared_theme if SaUI.shared_theme != null else body
    return docker


## The docker at *width* by its own height, laid out. Only the window is
## sized: the controls in it are anchored to it and follow at once, and a size
## written on one of them is warned about until the deferred `ready` has run.
func _lay_out(docker: GraphDocker, width: int) -> void:
    docker.size = Vector2i(width, GraphDocker.DEFAULT_SIZE.y)
    var column := docker._control_node.get_node("VBoxContainer") as Control
    assert_almost_eq(column.size.x, float(width), 0.5, "The docker's column follows the window to %d" % width)
    _sort(column)
    _sort(column)


## One layout pass from *node* down, the one the engine would run next frame.
func _sort(node: Node) -> void:
    if node is Container:
        (node as Container).notification(Container.NOTIFICATION_SORT_CHILDREN)
    for child: Node in node.get_children():
        _sort(child)


## What *button* needs to show *words* whole beside its arrow.
func _needed(button: Button, words: String) -> float:
    var font := button.get_theme_font(&"font")
    var font_size := button.get_theme_font_size(&"font_size")
    var arrow := 0.0
    if button.icon != null:
        arrow = float(button.icon.get_width())
        var cap := button.get_theme_constant(&"icon_max_width")
        if cap > 0:
            arrow = minf(arrow, float(cap))
        arrow += float(button.get_theme_constant(&"h_separation"))
    var words_width := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    return words_width + arrow + button.get_theme_stylebox(&"normal").get_minimum_size().x


## Both doors stay to the white trace, the list's row and the W, and
## both say what the trace is.
func test_the_list_keeps_the_white_row_and_the_w_reaches_it() -> void:
    var graph := GraphDocker.new()
    var list := graph._mode_button
    assert_true(list.choice_values().has("waveform_white"), "The Mode list still has the white row")
    var row_tip := list.popup.label_button(SaChoiceButton.row_id_of("waveform_white")).tooltip_text
    assert_true(row_tip.contains("Oklab lightness"), "and its tooltip names the channel: '%s'" % row_tip)
    assert_true(graph._white_toggle.tooltip_text.contains("Oklab lightness"), "and so does the W's")

    graph._white_toggle.button_pressed = true
    assert_eq(graph.graph_mode, "waveform_white", "A press on the W shows the white trace")
    assert_eq(list.selected_value(), "waveform_white", "and the list marks its row")
    graph._white_toggle.button_pressed = false
    assert_eq(graph.graph_mode, "waveform", "A second press goes back to the colours")

    assert_true(list.pick_row("Waveform (W)"), "The row takes a press")
    assert_eq(graph.graph_mode, "waveform_white", "and shows the same trace")
    assert_true(graph._white_toggle.button_pressed, "with the W pressed beside it")
    graph.free()


## Red and blue both have a channel at 1.0, so the trace that took the largest
## channel drew both at the top. Their Oklab lightness is 63 and 45 on the
## scale, and the bins and the picture now say so.
func test_red_beside_blue_reads_two_levels_rather_than_one_at_the_top() -> void:
    var texture := _red_beside_blue()
    assert_not_null(texture, "The pair uploads")
    var red_l := _lightness(Color(1.0, 0.0, 0.0))
    var blue_l := _lightness(Color(0.0, 0.0, 1.0))
    assert_almost_eq(red_l * 100.0, 63.0, 0.5, "Red's lightness is 63 on the scale")
    assert_almost_eq(blue_l * 100.0, 45.0, 0.5, "and blue's is 45")

    var plot := SaGraphPlot.new()
    plot.set_plot_size(PLOT)
    assert_true(plot.run_over_document(texture, texture.size, null, "waveform_white"), "The white pass runs")

    # The fixed grid a capture reads, plane by plane, summed over its columns.
    var counts := plot.read_counts()
    var by_level := PackedInt32Array()
    by_level.resize(SaGraphPlot.BINS)
    var other_planes := 0
    for plane in 3:
        for column in SaGraphPlot.COLUMNS:
            for level in SaGraphPlot.BINS:
                var count := counts[(plane * SaGraphPlot.COLUMNS + column) * SaGraphPlot.BINS + level]
                if plane == 0:
                    by_level[level] += count
                else:
                    other_planes += count
    var red_bin := int(red_l * float(SaGraphPlot.BINS - 1) + 0.5)
    var blue_bin := int(blue_l * float(SaGraphPlot.BINS - 1) + 0.5)
    @warning_ignore("integer_division")
    var half := PAIR.x * PAIR.y / 2
    assert_eq(by_level[red_bin], half, "Every red sample is binned at red's lightness, bin %d" % red_bin)
    assert_eq(by_level[blue_bin], half, "and every blue one at blue's, bin %d" % blue_bin)
    assert_eq(by_level[SaGraphPlot.BINS - 1], 0, "and none at the top, where the largest channel put both")
    assert_eq(other_planes, 0, "One channel: the other two planes stay empty")

    # The picture the docker shows, where each half's trace is a row.
    var image := SaExport.get_texture_image_float(plot._plot)
    assert_not_null(image, "The picture reads back")
    var left := int(image.get_width() * 0.25)
    var right := int(image.get_width() * 0.75)
    var red_value := _row_value(_brightest_row(image, left), image.get_height())
    var blue_value := _row_value(_brightest_row(image, right), image.get_height())
    assert_almost_eq(red_value * 100.0, red_l * 100.0, 1.0, "The red half's trace is drawn at %.1f" % (red_value * 100.0))
    assert_almost_eq(blue_value * 100.0, blue_l * 100.0, 1.0, "and the blue half's at %.1f" % (blue_value * 100.0))
    var top_row := int(round((1.0 - SaGraphPlot.VALUE_TOP) * float(image.get_height()) - 0.5))
    for x: int in [left, right]:
        assert_true(image.get_pixel(x, top_row).r < 0.5, "Nothing is drawn at 100 in column %d" % x)


## The colour waveform beside it is untouched: three channels in three planes.
func test_the_colour_waveform_still_bins_three_channels() -> void:
    var texture := _red_beside_blue()
    var plot := SaGraphPlot.new()
    plot.set_plot_size(PLOT)
    assert_true(plot.run_over_document(texture, texture.size, null, "waveform"), "The colour pass runs")
    var counts := plot.read_counts()
    var total := 0
    for index in 3 * SaGraphPlot.PLANE:
        total += counts[index]
    assert_eq(total, 3 * PAIR.x * PAIR.y, "Three channels of every sample")


## The source dropdown read as its arrow alone, because it clips its words and
## the mode button beside it expands. Both dropdowns are as wide as their
## longest rows now, and the row is a flow: at the shipped layouts' width every
## graph's controls are one line, and at the docker's own width what does not
## fit goes to a second line rather than clipping a label.
func test_every_label_of_the_row_reads_whole() -> void:
    var docker := _docker()
    var source := docker._source_button
    var mode := docker._mode_button
    var row := source.get_parent() as Control
    for width: int in [GraphDocker.DEFAULT_SIZE.x, SHIPPED_WIDTH]:
        for mode_id: String in ["waveform", "waveform_white", "histogram", "vectorscope", "cloud"]:
            docker.show_mode(mode_id)
            _lay_out(docker, width)
            var at := "In %s at %d" % [mode_id, width]
            assert_eq(source.text, "Canvas", "%s the source says what is graphed" % at)
            var needed := _needed(source, "Reference")
            var short := "%s the source is %.1f of the %.1f its longest row needs" % [at, source.size.x, needed]
            assert_true(source.size.x + 0.5 >= needed, short)
            var words := _needed(mode, mode.text)
            var cut := "%s the mode is %.1f of the %.1f '%s' needs" % [at, mode.size.x, words, mode.text]
            assert_true(mode.size.x + 0.5 >= words, cut)
            var lines := {}
            for child: Control in row.get_children():
                if not child.visible:
                    continue
                lines[child.position.y] = true
                var right := child.position.x + child.size.x
                var inside := "%s %s ends at %.1f inside the row's %.1f" % [at, child.name, right, row.size.x]
                assert_true(right <= row.size.x + 0.5, inside)
            if width == SHIPPED_WIDTH:
                assert_eq(lines.size(), 1, "%s the row is one line" % at)

    # The fit is what holds it: with its minimum taken away the row gives the
    # source what the mode button leaves, which is less than its longest row.
    source.custom_minimum_size.x = 0.0
    docker.show_mode("waveform")
    _lay_out(docker, GraphDocker.DEFAULT_SIZE.x)
    var bare := _needed(source, "Reference")
    assert_true(source.size.x < bare, "Unfitted, the source is %.1f of the %.1f its rows need" % [source.size.x, bare])


## The backing under each number stops short of the line the number names, and
## the top one carries the unit.
func test_the_scale_numbers_sit_clear_of_their_lines() -> void:
    var labels := SaGraphLabels.new()
    # Off the picture it is drawn over, so its full rect anchors have nothing
    # to follow and the size is written instead.
    labels.set_anchors_preset(Control.PRESET_TOP_LEFT)
    labels.size = Vector2(PLOT)
    var font := SaFonts.regular()
    var marks := labels.value_marks(font, 9)
    assert_eq(marks.size(), 3, "Three numbers")
    assert_eq(String(marks[0]["text"]), "100 %", "and the top one reads 100 %")
    for mark: Dictionary in marks:
        var backing := mark["backing"] as Rect2
        var line_y := float(mark["line_y"])
        var foot := backing.position.y + backing.size.y
        assert_true(foot <= line_y - 1.7, "%s's backing ends at %.1f, clear of its line at %.1f" % [mark["text"], foot, line_y])
        assert_true(backing.position.y >= 0.0, "and starts inside the picture")
        var baseline := (mark["at"] as Vector2).y
        assert_true(baseline < foot and baseline > backing.position.y, "with the number written on it")
    labels.free()


## The cloud could be turned, panned and zoomed and never put back. The Reset
## beside the source is shown for the cloud alone and puts both clouds back.
func test_the_reset_puts_the_cloud_back() -> void:
    var graph := GraphDocker.new()
    var reset := graph._reset_button
    assert_false(reset.visible, "The docker opens on the waveform, with no Reset")
    graph.show_mode("cloud")
    assert_true(reset.visible, "The cloud shows it")
    assert_true(reset.tooltip_text.contains("cloud"), "and it says what it puts back")

    graph.drag_on("canvas", Vector2(80.0, -40.0), false)
    graph.pan_by(Vector2(0.2, -0.1))
    graph.zoom_by(2.0)
    assert_true(absf(graph.plot.cloud_yaw - SaGraphPlot.CLOUD_YAW) > 0.1, "A drag turns the cloud")

    reset.pressed.emit()
    for target: SaGraphPlot in [graph.plot, graph.reference_plot]:
        assert_almost_eq(target.cloud_yaw, SaGraphPlot.CLOUD_YAW, 1e-6, "The press puts the turn back")
        assert_almost_eq(target.cloud_pitch, SaGraphPlot.CLOUD_PITCH, 1e-6, "and the tilt")
        assert_eq(target.cloud_pan, Vector2.ZERO, "and the pan")
        assert_almost_eq(target.cloud_zoom, 1.0, 1e-6, "and the zoom")

    graph.show_mode("vectorscope")
    assert_false(reset.visible, "Another graph has no view to put back, and no Reset")
    graph.free()
