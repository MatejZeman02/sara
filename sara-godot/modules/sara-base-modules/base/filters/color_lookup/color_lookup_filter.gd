## Filter > Colour Lookup, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every pixel moves towards the nearest colour of a palette in Oklab, by the
## shadows, midtones and highlights each colour carries. The palette is
## `SaPalettePanel`, one custom row, and the run records the `palette` point
## pass over what it holds, so the preview is the compositor's and Apply is one
## history step.
##
## The kernel, the step, the id and the command read `palette` where the
## painter reads Colour Lookup: a palette is the list of colours, and the
## lookup is what this filter does with it. One word for the painter and
## another for the machine keeps a scenario, a saved chord and a module that
## replaces this filter by its id all working.
class_name SaColorLookupFilter
extends SaFilter

var _engine := SaPointAdjust.new()


func title() -> String:
    return "Colour Lookup"


## Listed under Colour in the Filter menu and the browser.
func family() -> StringName:
    return &"color"


func sentence() -> String:
    return "Move the shadows, the midtones and the highlights towards the nearest colour of a palette, each by its own amount."


func id() -> StringName:
    return SaPointAdjust.PALETTE


## The command this has always answered to, so a rebound chord survives. It
## ships with no chord of its own, as it always has.
func action_name() -> StringName:
    return &"filter_palette"


func build(ui: SaDialog) -> void:
    # The chosen colours as hex strings and each one's bands beside them, the
    # shape `SaPointAdjust.palette_chips` reads.
    ui.parameter_value(&"palette", [])
    ui.parameter_value(&"bands", [])
    ui.custom("", _make_panel).named(&"palette")
    ui.thumbnail()
    ui.canvas_preview()
    ui.apply_cancel()
    ui.apply_button.tooltip_text = tr("Apply to the active layer.")


func run(ctx: SaFilterContext) -> void:
    # The descriptor and not the name `ctx.color_space()` answers, because the
    # kernel wants the matrices.
    var recorded := _engine.record(SaPointAdjust.PALETTE, values(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## The palette as the kernel takes it, which is what a read prints and what
## Apply commits: the chips with their own bands, over the default bands, so
## no colour is the picture unchanged.
func values() -> Dictionary:
    var out := parameters()
    out.merge(SaPointAdjust.BAND_DEFAULTS)
    return out


## The `adjust` step's door, over *document*'s active layer as one step with
## no dialog, *spec* in the units the pass takes. Reached by name so the
## harness names no module class.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null:
        return false
    return _engine.apply(document, document.active_layer, SaPointAdjust.PALETTE, spec, title())


## What `ui.custom` calls: the panel, which writes the palette and asks for a
## rerun whenever it moves.
func _make_panel(rerun: Callable) -> Control:
    var panel := SaPalettePanel.new()
    panel.set_parameters(parameters())
    panel.changed.connect(
        func() -> void:
            set_parameters(panel.parameters())
            rerun.call()
    )
    return panel
