## The blend mode a preset that erases took off the brush, and the giving of it back.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `tool_options_presets.gd` for the reason `SaBrushPresetStars` is out of
## the chooser: the preset group owns which preset is in hand, and this owns the
## one fact a load of the shipped Eraser leaves behind. Erase is a blend mode the
## preset writes onto the brush's settings, and nothing else ever writes it
## back, so the Pop-up Palette's Eraser slot, then the Paint tool, left a brush
## that erased and a dropdown that said Erase. The Erase toggle is a second
## switch on the tool and cannot undo a mode the settings hold.
##
## **A load that took the brush to Erase from another mode is remembered**, the
## settings it landed on, the mode they had and the tool that paints on them.
## The brush gets that mode back when the painter picks that tool again, which is
## `EventBus.tool_picked` and not `tool_changed`, since a pick of the tool
## already in hand changes nothing and a held Space is no choice of tool. The
## Eraser tool paints on settings of its own, so a pick of it is no one's
## business here. The brush gets the mode back too when the Erase toggle goes
## off. A painter who picks a blend mode by hand has decided, so the memory goes,
## and a load that found Erase already there (chosen by hand, then kept by Keep
## Blend Mode) remembers nothing and is never undone.
##
## **Keep Blend Mode changes none of this.** It keeps the painter's mode across
## presets that paint, but an erasing preset sets Erase whatever the switch says
## (`SaPresetStore.apply_preset`), so the load lands here as it would with the switch
## off and the mode it took is owed back the same way. A painting preset loaded
## after it pays the debt as well, since Keep Blend Mode would keep the Erase.
##
## The preset group hears `gave_back` and puts the brush on no preset, the way
## New does, so the Pop-up Palette's slot and the grid stop claiming it.
class_name SaBrushPresetErase
extends RefCounted

## The blend mode went back, so the preset that erased is not in hand.
signal gave_back

## The settings a load took to Erase, null while none is owed.
var _settings: Resource = null
## The blend mode those settings had before that load.
var _before: StringName = &""
## The tool that paints on those settings.
var _tool_id: StringName = &""


## Starts listening, which the preset group does while it is in the tree.
func attach() -> void:
    if not EventBus.tool_picked.is_connected(_on_tool_picked):
        EventBus.tool_picked.connect(_on_tool_picked)
    if not EventBus.brush_eraser_toggled.is_connected(_on_eraser_toggled):
        EventBus.brush_eraser_toggled.connect(_on_eraser_toggled)


func detach() -> void:
    if EventBus.tool_picked.is_connected(_on_tool_picked):
        EventBus.tool_picked.disconnect(_on_tool_picked)
    if EventBus.brush_eraser_toggled.is_connected(_on_eraser_toggled):
        EventBus.brush_eraser_toggled.disconnect(_on_eraser_toggled)


## A preset was applied to *settings*, whose blend mode was *before* it, while
## *shown_tool* answered the descriptor of the tool the surface shows. Null
## *before* is settings with no blend mode. *erasing* is whether the preset
## carries Erase itself.
##
## **A painting preset gives the mode back.** Under Keep Blend Mode it leaves
## the brush's mode alone, which after the Eraser is the Erase the Eraser set,
## so Eraser and then Paint would erase.
## The mode owed goes back to the same settings without `gave_back`, because the
## preset just loaded is the one in hand. Erase the painter chose by hand is no
## debt and stays.
func loaded(settings: Resource, before: Variant, shown_tool: Callable, erasing: bool) -> void:
    var now: Variant = settings.get("blend_mode") if settings != null else null
    if now != SaLayer.BLEND_MODE.ERASE:
        forget()
        return
    if not erasing:
        if _settings == settings:
            settings.set("blend_mode", _before)
        forget()
        return
    if before == null or before == SaLayer.BLEND_MODE.ERASE:
        return
    var shown := shown_tool.call() as SaToolDescriptor if shown_tool.is_valid() else null
    _settings = settings
    _before = StringName(before)
    _tool_id = shown.id if shown != null else &""


## The painter wrote a blend mode by hand, or the brush was reset: nothing is
## owed any more.
func forget() -> void:
    _settings = null
    _before = &""
    _tool_id = &""


## Puts the blend mode back and says so. A brush that does not read Erase now is
## left as it is.
func _give_back() -> void:
    if _settings == null:
        return
    var settings := _settings
    var before := _before
    forget()
    if settings.get("blend_mode") != SaLayer.BLEND_MODE.ERASE:
        return
    settings.set("blend_mode", before)
    gave_back.emit()


func _on_tool_picked(tool_name: String) -> void:
    if _settings != null and StringName(tool_name) == _tool_id:
        _give_back()


func _on_eraser_toggled(active: bool) -> void:
    if not active:
        _give_back()
