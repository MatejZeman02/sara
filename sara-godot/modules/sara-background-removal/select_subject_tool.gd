## The Select Subject tool: a click on the canvas selects the subject of the
## picture, Shift adding to the selection and Alt subtracting, as the wand's
## click does.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tool machine makes one of these a surface and hands each the module's
## [Click] through [member SaToolDescriptor.shared_settings], the door's way to
## give every surface's tool one thing. The click is the module's, because the
## weights, the dialog and the network are the module's and are made once a
## session rather than once a surface.
extends ToolState


## What a click runs, held by the descriptor and handed to every surface's tool.
class Click:
    extends Resource

    ## Called with the press's mode, a `SaSelection.Mode`, whether the merged
    ## picture is read, and the surface the tool is on.
    var run: Callable = Callable()

    func _init(on_click: Callable = Callable()) -> void:
        run = on_click


## The descriptor's [Click], set by the tool machine.
var settings: Resource = null
## Whether the network reads every layer as shown or the active one alone.
## The `sample_merged` option, the wand's.
var sample_merged: bool = true


## A press of the left button runs the module's click in the mode Shift and Alt
## make of a plain replace. Nothing else reaches it.
func handle_input(event: InputEvent) -> void:
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
        return
    click(SaSelection.mode_for_press(SaSelection.Mode.REPLACE, button.shift_pressed, button.alt_pressed))


## Runs the click in *press_mode*. Public so a suite and a capture step click
## without a pointer.
func click(press_mode: int = SaSelection.Mode.REPLACE) -> void:
    var given := settings as Click
    if given != null and given.run.is_valid():
        given.run.call(press_mode, sample_merged, surface)
