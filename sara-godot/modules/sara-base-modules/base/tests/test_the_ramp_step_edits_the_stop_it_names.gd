## The `ramp` step edits the stop it names, counted from 0, and
## says when an edit did not land.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A `select` of stop 2 on a ramp of two
## stops has to refuse rather than choose stop 1 and answer success. The step
## must not hand itself to the first visible control in the tree answering
## `capture_option_edit`, which a dialog's value row answers as well, and the
## ramp row must refuse a stop it does not have rather than clamp it and read
## nothing back.
##
## The step runs here through a real step table and its driver, with the ramp
## row bound to a gradient tool the way the module's binder binds it and a
## dialog's value row showing ahead of it in the tree. The first case lays the
## gradient on the GPU and reads it back. The shots are
## `scenarios/the-ramp-step-edits-the-stop-it-names-and-says-when-an-edit-did-not-land.json`.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const StateGradientScript = preload("res://modules/sara-base-modules/base/gradient/state_gradient.gd")
const StepTable := preload("res://harness/sa_step_table.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")
const DoorErrors := preload("res://harness/report/sa_door_errors.gd")

const NEAR := "#c02010"
const FAR := "#1040c0"

static var scratch_run_folder: String = SaDataRoot.path("d27-ramp-step-run")

var _was_pair: Array[Color] = []
var _host: Node = null


## The pair is shared with the rest of the run, so it is set to black and
## white, which is what a probe laying a black to white ramp needs, and put back after.
func before_each() -> void:
    _was_pair = [SaColors.foreground, SaColors.background]
    SaColors.foreground = Color.BLACK
    SaColors.background = Color.WHITE
    # Under an autoload, because the runner calls this from its own `_ready` and
    # a parent mid-`_ready` rejects `add_child`.
    _host = Node.new()
    _host.name = "D27RampStepHost"
    EventBus.add_child(_host)


func after_each() -> void:
    SaColors.foreground = _was_pair[0]
    SaColors.background = _was_pair[1]
    _host.free()
    _host = null


## The ramp row bound to *tool* through the signal the option names, under a
## value row of the kind a dialog shows, which answers the capture door too and
## stands first in the tree. Ends that remember nothing, so no case writes the
## painter's profile and both ends open opaque.
func _row_for(tool: StateGradientScript) -> SaColorRampControl:
    var ends := SaGradientEnds.new()
    tool.settings = ends
    var holder := VBoxContainer.new()
    _host.add_child(holder)
    holder.add_child(SaValueControl.new(0.5, 0.0, 1.0, 0.1))
    var row := SaColorRampControl.new(null, ends)
    holder.add_child(row)
    row.follow_tool(tool.following_changed)
    # Reseated on the pair with opaque ends, whatever the tool read before
    # its settings were swapped.
    tool.follow_stock(SaGradientEnds.TO_BACKGROUND)
    return row


func _tree() -> SceneTree:
    return Engine.get_main_loop() as SceneTree


## The first clause: both stops of a ramp of two set through the step, and the
## drag lays the gradient between those two colours rather than the black to
## white the pair would. Without the fix the step went to the value row and
## the drag laid black to white.
func test_both_stops_set_through_the_step_lay_the_gradient_between_them() -> void:
    if GlobalShaderCompiler.get_rd() == null:
        skip("no RenderingDevice, the drag needs one")
        return
    var surface := Fixtures.make_surface()
    var machine := Fixtures.make_bound_machine(surface)
    machine.set_active_tool(&"gradient")
    var tool: StateGradientScript = machine.get_tool(&"gradient")
    var row := _row_for(tool)
    var table := StepTable.new(CaptureRun.new(scratch_run_folder))

    table.run({"ramp": {"select": 0, "color": NEAR}})
    table.run({"ramp": {"select": 1, "color": FAR}})
    assert_eq(tool.ramp.color_of(0).to_html(false), NEAR.trim_prefix("#"), "Stop 0 of the tool's ramp is the near colour")
    assert_eq(tool.ramp.color_of(1).to_html(false), FAR.trim_prefix("#"), "and stop 1 the far one")
    assert_eq(row.ramp, tool.ramp, "the ramp the row shows")

    var document: SaDocument = surface.get_document()
    var width := float(document.canvas_size.x)
    assert_true(tool.draw_between(Vector2(0.0, 10.0), Vector2(width, 10.0)), "The drag lands")
    var near := _texel_of(document.active_layer, 1, 10)
    var middle := _texel_of(document.active_layer, int(width / 2.0), 10)
    var far := _texel_of(document.active_layer, int(width) - 2, 10)
    assert_true(near.r > near.b + 0.3 and near.a > 0.9, "It starts red, got %s" % near)
    assert_true(far.b > far.r + 0.3 and far.a > 0.9, "and ends blue, got %s" % far)
    assert_true(near.r > middle.r and middle.r > far.r, "and its red falls between them, got %s" % middle)
    assert_true(near.b < middle.b and middle.b < far.b, "while its blue rises, got %s" % middle)
    Fixtures.teardown(surface, machine)


## The second clause: stop 2 of a ramp of two is refused, counted from 0, the
## refusal is an error a door's answer carries, and the colour it asked for
## goes on no stop.
func test_a_stop_past_the_last_is_refused() -> void:
    var tool := StateGradientScript.new()
    var row := _row_for(tool)
    var errors := DoorErrors.new()
    OS.add_logger(errors)
    var said := SaRampCapture.edit(_tree(), {"select": 2, "color": NEAR})
    OS.remove_logger(errors)

    assert_true(said.begins_with("SaCapture: ramp refused"), "The step refuses, got %s" % said)
    assert_true(said.contains("no stop 2 on a ramp of 2 stops, counted from 0 to 1"), "and says why, got %s" % said)
    var raised: Array = errors.take()["errors"]
    assert_true(raised.any(func(line: String) -> bool: return line.contains(said)), "an error as well, got %s" % [raised])
    assert_eq(tool.ramp.color_of(1).to_html(false), Color.WHITE.to_html(false), "Stop 1 keeps its colour")
    assert_eq(tool.ramp.color_of(0).to_html(false), Color.BLACK.to_html(false), "and so does stop 0")
    assert_eq(row.selected, 0, "and the selection stays where it was")

    said = SaRampCapture.edit(_tree(), {"remove": 1})
    assert_true(said.contains("a ramp keeps at least 2 stops"), "A remove from two stops is refused, got %s" % said)
    assert_eq(tool.ramp.size(), 2, "and both stay")


## The read back: an edit the ramp the tool lays does not hold, here a ramp put
## back on following the pair under the step, is answered as a failure naming
## the stop and the colour it holds, rather than as the stops the row showed.
func test_an_edit_the_tool_does_not_lay_is_answered_as_one() -> void:
    var tool := StateGradientScript.new()
    _row_for(tool)
    var follow_again := func() -> void: tool.follow_stock(SaGradientEnds.TO_BACKGROUND)
    tool.ramp.changed.connect(follow_again, CONNECT_ONE_SHOT)

    var said := SaRampCapture.edit(_tree(), {"select": 0, "color": NEAR})
    assert_true(said.begins_with("SaCapture: ramp edit did not land"), "The step says so, got %s" % said)
    var named := said.contains("stop 0 of the ramp the tool lays holds 000000 at alpha 1.000")
    assert_true(named, "naming the stop and the colour it holds, got %s" % said)

    said = SaRampCapture.edit(_tree(), {"select": 0, "color": NEAR})
    assert_true(said.begins_with("SaCapture: ramp {"), "Sent again it lands, got %s" % said)
    assert_eq(tool.ramp.color_of(0).to_html(false), NEAR.trim_prefix("#"), "on the ramp the tool lays")


## The texel at *x*, *y* of *layer*, or transparent where it holds no chunk. A
## readback, which is a test's to make and never a stroke's.
func _texel_of(layer: SaLayer, x: int, y: int) -> Color:
    @warning_ignore("integer_division")
    var grid := Vector2i(x / SaChunk.SIZE, y / SaChunk.SIZE)
    var texture := layer.get_field(grid)
    if texture == null:
        return Color.TRANSPARENT
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(
        bytes, texture.format, (y - grid.y * SaChunk.SIZE) * texture.size.x + (x - grid.x * SaChunk.SIZE)
    )
