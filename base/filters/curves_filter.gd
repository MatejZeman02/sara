## Filter > Curves, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A curve per channel over the active layer's histogram, the graph being
## `SaCurvesPanel`, one custom row. The run records the `curves` point pass over
## the five lookups, so the preview is the compositor's and Apply is one history
## step. Outside 0 to 1 a value rides on the offset of the nearest end rather
## than being clamped away.
class_name SaCurvesFilter
extends SaFilter

var _engine := SaPointAdjust.new()

## The panel the last `build` made. A control goes with the dialog that held
## it, so every read asks whether it is still there.
var _panel: SaCurvesPanel = null


func title() -> String:
    return "Curves"


## Listed under Tone in the Filter menu and the browser.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return "Map input to output along a curve you draw, over the histogram, per channel or for all channels."


func id() -> StringName:
    return SaPointAdjust.CURVES


## The command this has always answered to, so a rebound chord survives.
func action_name() -> StringName:
    return &"filter_curves"


## Ctrl+M, Photoshop's and Krita's.
func chord() -> Array[InputEvent]:
    return SaAdjustFilter.ctrl_chord(KEY_M)


func build(ui: SaDialog) -> void:
    ui.parameter_value(&"curves", {})
    ui.custom("", _make_panel).named(&"curves")
    ui.thumbnail()
    ui.canvas_preview()
    ui.apply_cancel()
    ui.apply_button.tooltip_text = tr("Apply to the active layer.")


## The first run of an open is where the histogram is taken, because it is the
## first moment the panel and the layer are both known.
func run(ctx: SaFilterContext) -> void:
    var panel := _open_panel()
    if panel != null and not panel.has_histogram():
        panel.take_histogram(ctx.layer, ctx.document.color_space)
    var recorded := _engine.record(SaPointAdjust.CURVES, values(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## The five lookups, `{"curves": {channel: samples}}`, sampled from the
## points a record keeps, `{"curves": {channel: [[x, y], ...]}}`. A channel
## with no points is the diagonal.
func values() -> Dictionary:
    var points := SaCurvesPanel.points_of(parameters())
    var curves: Dictionary = {}
    for channel_id: String in points:
        curves[channel_id] = SaCurveEditor.sample_curve(points[channel_id], SaCurveEditor.SAMPLES)
    return {"curves": curves}


## The `adjust` step's door, over *document*'s active layer as one step with
## no dialog. *spec* holds the lookups as `values` answers them.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null:
        return false
    return _engine.apply(document, document.active_layer, SaPointAdjust.CURVES, spec, title())


func _open_panel() -> SaCurvesPanel:
    if _panel == null or not is_instance_valid(_panel):
        return null
    return _panel


## What `ui.custom` calls: the panel, which writes the points and asks for a
## rerun whenever it moves.
func _make_panel(rerun: Callable) -> Control:
    var panel := SaCurvesPanel.new()
    panel.set_parameters(parameters())
    panel.changed.connect(
        func() -> void:
            set_parameters(panel.parameters())
            rerun.call()
    )
    _panel = panel
    return panel
