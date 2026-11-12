## Moves the view.
##
## Talks to SaView rather than to a Control, so panning works on any surface and
## the tool can be tested without a scene tree.
extends ToolState

var is_panning: bool = false


func reset() -> void:
    is_panning = false


func handle_input(event: InputEvent) -> void:
    var view: SaView = surface.view if surface != null else null
    if view == null:
        return

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        is_panning = event.pressed
    elif event is InputEventMouseMotion and is_panning:
        view.set_pan(view.get_pan() + event.relative)
