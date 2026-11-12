## The Levels histogram, read against Photoshop's and Krita's.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The dialog has a kernel of its own and not the Graph docker's scope, which
## would inherit darktable's three answers: a logarithmic count axis, all three
## channels drawn whatever the Channel dropdown says, and curves normalised
## against a luma row nothing draws.
##
## What a shot can show is the shape, and
## `scenarios/the-levels-histogram-reads-as-photoshops.json` shows it. What
## it cannot show is that the docker's own picture did not move with it, which
## is most of this file: the flags word, the counts, and the fact that a
## `SaGraphPlot` nobody tells about a channel behaves exactly as it did.
extends "res://tests/test_framework.gd"

## Real dispatches into a real buffer.
const REQUIRES_GPU := true

const CANVAS := Vector2i(256, 128)

## The bit the kernel reads each row's selection on, as `FLAG_ROW_*` declares
## them. Written out rather than read from `HISTOGRAM_ROW_FLAGS`, because a
## test that compares the table to itself would let the whole table move away
## from the kernel.
const ROW_R := 4
const ROW_G := 8
const ROW_B := 16
const ROW_LUMA := 32
## The bit that turns the luma row into Oklab L, for the Lightness channel.
const ROW_OKLAB_L := 128


func _easel(colour: Color) -> SaEasel:
    var easel := SaEasel.create_default(CANVAS)
    var layer := easel.document.get_node_or_null("Layer 1") as SaLayer
    layer.fill(colour)
    easel.request_full_composite()
    easel.process_pending_composite()
    return easel


func test_the_chosen_rows_ride_above_the_passthrough_and_the_scale() -> void:
    var plot := SaGraphPlot.new()
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 1, "A docker plot names no rows, so the word is what F7 packed")

    plot.histogram_channel = "master"
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 1 + ROW_LUMA, "Master is the composite, which is what Photoshop draws")
    plot.histogram_channel = "red"
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 1 + ROW_R, "and a channel is one bit")
    plot.histogram_channel = "lightness"
    assert_eq(
        plot.flags_for(SaColorSpace.srgb()),
        1 + ROW_LUMA + ROW_OKLAB_L,
        "and Lightness is that same row counted as Oklab L, a graph of its own"
    )
    assert_eq(
        (
            int(SaGraphPlot.HISTOGRAM_ROW_FLAGS["red"])
            + int(SaGraphPlot.HISTOGRAM_ROW_FLAGS["green"])
            + int(SaGraphPlot.HISTOGRAM_ROW_FLAGS["blue"])
        ),
        ROW_R + ROW_G + ROW_B,
        "and the three colour rows are three separate bits, so a fourth channel could be added without renumbering"
    )
    plot.scale = "linear"
    assert_eq(plot.flags_for(SaColorSpace.acescg()), 2 + ROW_LUMA + ROW_OKLAB_L, "beside the scale bit and above it")


## An unknown name is the docker's picture rather than a blank graph, because a
## channel this file has never heard of is a caller to fix and not a run to
## lose.
func test_a_channel_nobody_declares_falls_back_to_the_dockers_own_rows() -> void:
    var plot := SaGraphPlot.new()
    plot.histogram_channel = "cyan"
    assert_eq(plot.flags_for(SaColorSpace.srgb()), 1, "no row bits, which the kernel reads as the docker's three")


## The constraint the Graph docker is held to and this dialog is held to as
## well: choosing rows changes what is drawn and never what is counted. The
## one exception is Lightness, whose grey row counts Oklab L rather than luma,
## so it is held to the colour rows and their own largest bins, and
## `test_the_levels_lightness_counts_oklab_l.gd` reads the row it changes.
func test_choosing_a_channel_moves_no_count() -> void:
    var easel := _easel(Color(0.7, 0.35, 0.2, 1.0))
    var docker := SaGraphPlot.new()
    assert_true(docker.run_over_document(easel.output, CANVAS, easel.document.color_space, "histogram"), "The docker's pass runs")
    var was := docker.read_counts().slice(0, SaGraphPlot.MAX_SLOT + 1)

    var colour_rows := 3 * SaGraphPlot.BINS
    var colour_maxima := docker.read_counts().slice(SaGraphPlot.MAX_SLOT + 1, SaGraphPlot.MAX_SLOT + 4)
    for channel: String in ["master", "red", "green", "blue", "lightness"]:
        var plot := SaGraphPlot.new()
        plot.scale = "linear"
        plot.histogram_channel = channel
        assert_true(
            plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "histogram"), "The %s pass runs" % channel
        )
        var counts := plot.read_counts()
        if channel == "lightness":
            assert_eq(counts.slice(0, colour_rows), was.slice(0, colour_rows), "and lightness counts the docker's colour rows")
            assert_eq(
                counts.slice(SaGraphPlot.MAX_SLOT + 1, SaGraphPlot.MAX_SLOT + 4), colour_maxima, "with their own largest bins"
            )
            continue
        assert_eq(counts.slice(0, SaGraphPlot.MAX_SLOT + 1), was, "and %s counts what the docker counts" % channel)
    easel.free()


## The four spare slots the normaliser reads. A flat colour puts every texel of
## a channel in one bin, so each row's own maximum is the sample count, and the
## luma row's is too.
func test_each_histogram_row_keeps_its_own_largest_bin() -> void:
    var easel := _easel(Color(0.7, 0.35, 0.2, 1.0))
    var plot := SaGraphPlot.new()
    assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "histogram"), "The pass runs")

    var counts := plot.read_counts()
    var overall: int = counts[SaGraphPlot.MAX_SLOT]
    for row in 4:
        assert_eq(counts[SaGraphPlot.MAX_SLOT + 1 + row], overall, "row %d of a flat colour is one full bin" % row)
    assert_true(overall > 0, "and something was counted at all")
    easel.free()


## The parade shares the three planes and bins per column, so it has no single
## largest bin per row and must leave the four slots alone. A stale maximum
## there would scale a later histogram against a number from another mode.
func test_a_per_column_mode_writes_no_row_maximum() -> void:
    var easel := _easel(Color(0.7, 0.35, 0.2, 1.0))
    var plot := SaGraphPlot.new()
    assert_true(plot.run_over_document(easel.output, CANVAS, easel.document.color_space, "parade"), "The parade runs")

    var counts := plot.read_counts()
    for row in 4:
        assert_eq(counts[SaGraphPlot.MAX_SLOT + 1 + row], 0, "row %d is untouched by the parade" % row)
    easel.free()


## The dialog's graph asks for the linear axis itself rather than leaving the
## docker's default, and the docker is not changed under it.
func test_the_dialog_asks_for_the_linear_axis_and_the_docker_keeps_the_log() -> void:
    assert_eq(SaGraphPlot.new().scale, "log", "A fresh plot is darktable's log, which the docker opens on")

    var source := FileAccess.get_file_as_string("res://modules/sara-base-modules/base/filters/sa_adjust_graph.gd")
    assert_true(source.contains('_plot.scale = "linear"'), "and the Levels graph sets linear on every pass")
    assert_true(source.contains("_plot.histogram_channel = channel"), "and hands the dropdown's channel down with it")


## The dropdown reaches the graph. Read off the panel's source rather than by
## building one, because the graph needs an easel to draw and the claim is
## about the wiring: the handler must do more than announce.
func test_the_channel_dropdown_reaches_the_graph() -> void:
    var source := FileAccess.get_file_as_string("res://modules/sara-base-modules/base/filters/levels/sa_levels_panel.gd")
    var at := source.find("func _on_channel_selected")
    assert_true(at >= 0, "the handler is there")

    var body := source.substr(at, 400)
    assert_true(body.contains("_histogram.channel"), "and it tells the graph which channel")
    assert_true(body.contains("refresh_histogram()"), "and asks for the pass rather than waiting for a composite")
