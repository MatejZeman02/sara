## A hidden brush editor preview draws nothing.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## "Once in six runs, the Intel card's first, the first smudge stroke of a
## session laid 1538 dabs instead of 184, 1358 of them in one frame." The
## stroke laid its own 184 in every run. The rest were the closed brush
## editor's strip, drawing the ask that waited when the editor closed at the
## radius the canvas had moved to since, 1354 dabs in one frame on its own
## easel. Every one of twenty runs on the Intel card drew it, and once it
## landed inside the stroke. The claim is a count, so the suite counts: the
## compressor's draws, and the dabs the stroke ledger saw.
##
## The previews here live under a `Control` added to the running tree, because
## hidden is a question only a tree answers, and a compressor outside one draws
## as it always did.
extends "res://tests/test_framework.gd"

const BrushSettingsScript = preload("res://modules/sara-base-modules/stamp-brush/tools/brush_settings.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")

## The strip paints a real stroke on an easel of its own.
const REQUIRES_GPU := true

## The radius the scenario's canvas moved to after the editor closed.
const SMALL_RADIUS: float = 0.01

var _host: Control = null
var _draws: int = 0


func before_each() -> void:
    _draws = 0
    _host = Control.new()
    _host.name = "Q17PreviewHost"
    EventBus.add_child(_host)


func after_each() -> void:
    if _host != null:
        _host.free()
        _host = null


func _draw() -> void:
    _draws += 1


## A preview that is a plain `Control` under the host, with a compressor that
## counts rather than paints.
func _counted() -> SaPreviewCompressor:
    var preview := Control.new()
    _host.add_child(preview)
    var compressor := SaPreviewCompressor.new(_draw)
    preview.add_child(compressor)
    return compressor


func test_an_ask_while_hidden_waits_for_the_preview_to_be_shown() -> void:
    var compressor := _counted()
    _host.hide()
    compressor.request()
    assert_eq(_draws, 0, "A hidden preview asked to draw draws nothing")
    assert_true(compressor.pending, "and keeps the ask")

    _host.show()
    assert_eq(_draws, 1, "Shown again, it draws the ask it kept")
    assert_false(compressor.pending, "and has nothing waiting")


## The editor's own case: an ask folded into the window, then the editor
## closed before the window did.
func test_the_window_closing_on_a_hidden_preview_draws_nothing() -> void:
    var compressor := _counted()
    compressor.request()
    compressor.request()
    assert_eq(_draws, 1, "The first ask draws and the second waits for the window")
    _host.hide()
    compressor.timeout.emit()
    assert_eq(_draws, 1, "The window closing while the preview is hidden draws nothing")
    assert_true(compressor.pending, "and the ask still waits")

    _host.show()
    assert_eq(_draws, 2, "It is drawn when the preview comes back")


func test_a_shown_preview_draws_as_it_did() -> void:
    var compressor := _counted()
    compressor.request()
    assert_eq(_draws, 1, "A preview on screen draws its first ask at once")
    _host.hide()
    _host.show()
    assert_eq(_draws, 1, "and a hide and a show with nothing waiting draw nothing more")


func test_a_compressor_outside_the_tree_still_draws() -> void:
    var compressor := SaPreviewCompressor.new(_draw)
    compressor.request()
    assert_eq(_draws, 1, "A suite's detached compressor has no screen to be hidden from")
    compressor.free()


## The count the burst was read by: the stroke ledger's dabs, with the strip
## bound to a brush at the scenario's radius.
func test_a_hidden_strip_lays_no_dabs() -> void:
    var strip := SaBrushPreviewStrip.new()
    var settings := BrushSettingsScript.new()
    settings.radius = SMALL_RADIUS
    strip.bind_source(StateBrushScript, settings)
    _host.add_child(strip)
    _host.hide()

    var dabs_before := SaStrokeLedger.dabs
    strip.request()
    strip.compressor.timeout.emit()
    assert_eq(SaStrokeLedger.dabs, dabs_before, "A hidden strip lays no dab")
    assert_eq(strip.renders, 0, "and draws nothing")

    _host.show()
    assert_eq(strip.renders, 1, "Shown, it draws once")
    assert_true(SaStrokeLedger.dabs > dabs_before, "and the dabs it lays are its own stroke's")
