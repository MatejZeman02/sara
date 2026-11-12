## The drag bar's narrow form, its icon alone, for a docker narrower than the
## bar with its maximise and close. A Toolbox one small button wide was floored
## at that row's width, and the strip beside its buttons was empty docker, so
## the narrow form folds the window buttons away and the bar's menu offers them.
## Beside `docker_drag_handle.gd`, which is the bar's pointer and near the limit.
##
## SPDX-License-Identifier: GPL-3.0-or-later
class_name SaNarrowBar
extends RefCounted


## The window buttons a narrow form folds away, the maximise before the close.
static func extras(window: DockerWindow) -> Array[Button]:
    var found: Array[Button] = []
    for button: Button in [window.maximise_button, window.hide_button]:
        if button != null and is_instance_valid(button):
            found.append(button)
    return found


## Whether *button*'s own switch wants it on the bar, whatever the width.
static func wanted(window: DockerWindow, button: Button) -> bool:
    if button == window.hide_button:
        return window.lent or SaSettings.docker_hide_button
    return SaDockerMaximise.button_wanted()


## Draws the bar narrow when *width*, in the bar's units, is under the width it
## asks with every wanted button shown, and whole when it is not. A *width* of 0
## is the narrowest a docker can be, the form its floor is read in.
static func fit(window: DockerWindow, width: float) -> void:
    var full := window.drag_handle.get_combined_minimum_size().x
    for button in extras(window):
        var row := button.get_parent() as BoxContainer
        var room := button.get_combined_minimum_size().x + float(row.get_theme_constant(&"separation"))
        full += (room if wanted(window, button) else 0.0) - (room if button.visible else 0.0)
    for button in extras(window):
        button.visible = wanted(window, button) and width >= full


## The wanted window buttons the narrow form folded away, for the bar's menu.
static func folded(window: DockerWindow) -> Array[Button]:
    var found: Array[Button] = []
    for button in extras(window):
        if wanted(window, button) and not button.visible:
            found.append(button)
    return found
