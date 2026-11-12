## What the Gradient Map filter hands its page: the ramp editor and a row of
## shortcuts under it, Reverse and the gradient tool's stock ramps.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `ui.custom` row. The bar, the stops, the picker and the alpha slider are
## `SaColorRampControl`, the control the gradient tool's options use, so a ramp
## is edited the same way in both and a stop's alpha means what the control says
## it does. Its library row is put away: the stock rows in it follow the gradient
## tool's own colours and do nothing for a ramp the tool does not hold, and the
## stock ramps are the buttons here instead.
##
## The stock ramps are the two the tool lists, laid across the picked pair as it
## stands now. Foreground to Transparent fits a map as well as it fits a
## gradient: a stop's alpha is how much of the map applies there, so the lights
## keep the picture as it was.
class_name SaGradientMapPanel
extends VBoxContainer

## A stop moved, was recoloured, added or removed, or Reverse or a stock ramp
## replaced the ramp, and the filter should run again.
signal changed

## The ramp the panel edits, which the filter reads whole on every change.
var ramp: SaColorRamp = null

var _control: SaColorRampControl = null
## What puts a stock ramp on the ramp, with no context, so nothing it does is
## remembered between sessions.
var _ends := SaGradientEnds.new()


func _init() -> void:
    name = "GradientMapPanel"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(8))

    _control = SaColorRampControl.new()
    add_child(_control)
    var library := _control.find_child("LibraryRow", true, false)
    if library != null:
        library.visible = false
    _control.ramp_changed.connect(func() -> void: changed.emit())

    var shortcuts := HFlowContainer.new()
    shortcuts.name = "Shortcuts"
    shortcuts.add_theme_constant_override("h_separation", SaUI.px(4))
    shortcuts.add_theme_constant_override("v_separation", SaUI.px(4))
    add_child(shortcuts)

    var reverse_button := Button.new()
    reverse_button.name = "Reverse"
    reverse_button.text = tr("Reverse")
    reverse_button.tooltip_text = tr("Swap the dark and the light ends of the ramp.")
    reverse_button.pressed.connect(reverse)
    shortcuts.add_child(reverse_button)

    for stock: Dictionary in SaGradientEnds.STOCK:
        var stock_id := StringName(String(stock["id"]))
        var button := Button.new()
        button.name = "Stock_%s" % String(stock_id)
        button.text = tr(String(stock["label"]))
        button.tooltip_text = tr("Lay this gradient across the picked colours, replacing the ramp.")
        button.pressed.connect(func() -> void: choose_stock(stock_id))
        shortcuts.add_child(button)


## Points the panel at *colours*, which it edits in place from here on. Nothing
## is announced, since the ramp is what the filter just read.
func set_ramp(colours: SaColorRamp) -> void:
    ramp = colours
    _control.bind_ramp(ramp)


## Runs the ramp from the other end: the dark colour takes the light one's
## place and the stops' alphas go with their colours.
func reverse() -> void:
    if ramp == null:
        return
    var selected := _control.selected
    ramp.stops = SaGradientMapFilter.reversed(ramp)
    _control.select_stop(ramp.size() - 1 - selected)
    ramp.changed.emit()


## Replaces the ramp with the stock gradient *stock*, an `SaGradientEnds` stock
## id, across the picked pair as it is now. False for a name that is no stock.
func choose_stock(stock: StringName) -> bool:
    var pair := SaGradientMapFilter.picked_pair()
    if ramp == null or not _ends.restock(ramp, stock, pair.color_of(0), pair.color_of(1)):
        return false
    _control.select_stop(0)
    ramp.changed.emit()
    return true


## Replaces the ramp with *colours*, hex strings spread evenly from the dark end
## to the light, and selects the first.
func set_colours(colours: Array) -> void:
    if ramp == null:
        return
    ramp.stops = SaGradientMapFilter.evenly(colours).stops
    _control.select_stop(0)
    ramp.changed.emit()


## The `filter` step's door, since the panel is a custom row: `{"colours":
## ["#2040d0", "#f0a030"]}` lays a ramp, `{"reverse": true}` and `{"stock":
## "foreground_to_background"}` press the two kinds of shortcut, and every other
## word goes to the ramp control, which reads `select`, `color`, `alpha`, `add`,
## `move` and `remove`.
func capture_option_edit(spec: Dictionary) -> String:
    var handed := spec.duplicate()
    if handed.has("colours"):
        set_colours(handed["colours"] as Array)
        handed.erase("colours")
    if handed.has("stock"):
        print("SaCapture: ramp stock '%s' -> %s" % [handed["stock"], choose_stock(StringName(String(handed["stock"])))])
        handed.erase("stock")
    if handed.has("reverse"):
        if bool(handed["reverse"]):
            reverse()
        handed.erase("reverse")
    return _control.capture_option_edit(handed)
