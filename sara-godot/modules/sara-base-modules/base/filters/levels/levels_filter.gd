## Filter > Levels, registered through the door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## As Photoshop's: the handles and the histogram are `SaLevelsPanel`, one
## custom row, and the run records the `levels` point pass over the numbers it
## holds, so the preview is the compositor's and Apply is one history step.
## Nothing clamps, so paint outside the input range lands outside the output
## range rather than pinned to its ends.
##
## **Equalize** is an adjustment inside Levels rather than a control on the
## read-only Graph docker, which shows a picture and changes none. The panel's
## button reads the chosen channel's row of the histogram it already draws,
## once, and [method cdf_map] turns that into a map from input level to the
## layer's cumulative share, held under "equalize" beside the channel it came
## from. The kernel runs the map before the handles, and Reset empties it.
##
## **Equalize moves lightness alone**: the map is counted on Oklab L whatever
## channel the handles are on and read on Oklab L with a and b kept, so chroma
## and hue stay as they were. The channel row still chooses what the handles
## move. **And it is found by its name**: Filter > Equalize, `SaEqualizeFilter`
## beside this file, is an entry over Levels that opens this page with the map
## taken, so the menu and the browser's search reach it by the word a painter
## looks for while the adjustment itself stays here.
##
## This filter is the facade of `filters/levels`, the feature folder Levels
## lives in: the panel, its bar, the node histogram Equalize reads and the
## Equalize entry sit beside it, and the module preloads this file only and
## reaches the entry through [method equalize_entry].
class_name SaLevelsFilter
extends SaFilter

var _engine := SaPointAdjust.new()

## Whether the panel presses Equalize once it stands in a window, which is
## what the Equalize entry opens this page for. Set by the constructor only.
var _equalize_on_open := false


## Levels, or with *equalize_on_open* the page the Equalize entry opens.
func _init(equalize_on_open := false) -> void:
    _equalize_on_open = equalize_on_open


func title() -> String:
    return "Levels"


## Listed under Tone in the Filter menu and the browser.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return (
        "Move the input and output black and white points, and the gamma between them, per channel or for all channels. "
        + "Equalize spreads the lightness evenly over the range."
    )


func id() -> StringName:
    return SaPointAdjust.LEVELS


## The command this has always answered to, so a rebound chord survives.
func action_name() -> StringName:
    return &"filter_levels"


## Ctrl+L, which is both Photoshop's and Krita's.
func chord() -> Array[InputEvent]:
    return SaAdjustFilter.ctrl_chord(KEY_L)


func build(ui: SaDialog) -> void:
    for row: Dictionary in SaLevelsPanel.ROWS:
        ui.parameter(StringName(String(row["key"])), float(row["default"]), float(row["min"]), float(row["max"]))
    ui.parameter_value(&"channel", "master")
    # The Equalize map and the channel it was taken from, empty for none.
    ui.parameter_value(&"equalize", [])
    ui.parameter_value(&"equalize_channel", "")
    ui.custom("", _make_panel).named(&"levels")
    ui.thumbnail()
    ui.canvas_preview()
    ui.apply_cancel()
    # Every control a painter points at says what it does, and the two
    # buttons are the window's now rather than the dialog's own.
    ui.cancel_button.tooltip_text = tr("Close and leave the layer as it was. The preview goes with it.")
    ui.apply_button.tooltip_text = tr("Apply to the active layer.")


func run(ctx: SaFilterContext) -> void:
    # The descriptor and not the name `ctx.color_space()` answers, because the
    # kernel wants the matrices.
    var recorded := _engine.record(SaPointAdjust.LEVELS, values(), ctx.document.color_space)
    if recorded != null:
        ctx.point_pass(recorded.shader, recorded.kernel, recorded.push, recorded.buffers, recorded.origin_slot)


## The handles as the kernel takes them, which is what a read prints and what
## Apply commits, and what a record keeps. A channel the kernel does not know
## reads as the lot.
func values() -> Dictionary:
    var out := parameters()
    if not SaPointAdjust.CHANNELS.has(String(out.get("channel", ""))):
        out["channel"] = "master"
    return out


## The `adjust` step's door, over *document*'s active layer as one step with
## no dialog, *spec* in the units the pass takes. Reached by name so the
## harness names no module class.
func capture_apply(document: SaDocument, spec: Dictionary) -> bool:
    if document == null:
        return false
    return _engine.apply(document, document.active_layer, SaPointAdjust.LEVELS, spec, title())


## The Equalize map for one row of histogram *counts*, a count per level from
## black to white: each level goes to the share of the painted texels at or
## below it, so the layer's levels spread evenly over the range. The share
## is taken above the darkest painted level, so that level comes out black
## rather than at its own small share, which is how Photoshop's Equalize
## reads. Empty when the row holds one level or none, since there is no
## spread to make of it.
##
## **An empty level just under a painted one takes the painted one's share.**
## The graph rounds a value to its nearest level and the kernel reads the map
## between two entries, so a value in the lower half of its level's bin read
## partly the entry under it, the share of the paint below. Flat paint whose
## lightness sat there came out short of its place, the brightest short of
## white, and a picked colour is rarely on a level of Oklab L. With the empty
## entry under it raised to its own, every value in a painted bin reads its own
## share. An entry with paint on both sides keeps the share under it, and a
## smooth layer, with no empty levels among its paint, gets the same map.
static func cdf_map(counts: PackedInt32Array) -> Array:
    var total := 0
    var darkest := -1
    for count in counts:
        if darkest < 0 and count > 0:
            darkest = count
        total += count
    if darkest < 0 or total <= darkest:
        return []
    var out: Array = []
    var running := 0
    for count in counts:
        running += count
        out.append(maxf(float(running - darkest), 0.0) / float(total - darkest))
    for level in counts.size() - 1:
        var painted_below := level > 0 and counts[level - 1] > 0
        if counts[level] == 0 and counts[level + 1] > 0 and not painted_below:
            out[level] = out[level + 1]
    return out


## Filter > Equalize, the entry the module registers beside this one, so the
## module names the facade alone.
static func equalize_entry() -> SaFilter:
    return SaEqualizeFilter.new()


## What `ui.custom` calls: the panel, which writes the handles and asks for a
## rerun whenever it moves. For the Equalize entry it presses Equalize once it
## is ready, which is when it stands in the window and finds the canvas and
## the layer the press reads, and before the window's first run, so the page
## opens on the equalized layer. A probe the browser builds for its preview is
## never realized, so it presses nothing.
func _make_panel(rerun: Callable) -> Control:
    var panel := SaLevelsPanel.new()
    panel.set_parameters(parameters())
    panel.changed.connect(
        func() -> void:
            set_parameters(panel.parameters())
            rerun.call()
    )
    if _equalize_on_open:
        panel.ready.connect(panel.equalize, CONNECT_ONE_SHOT)
    return panel
