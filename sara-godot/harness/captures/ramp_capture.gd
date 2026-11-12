## The `ramp` step: finds the colour ramp the Tool Options docker shows and
## hands it the step, or refuses when no ramp is showing there.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `ToolOptionControls.capture_custom`, whose walk the step was. That walk
## handed the step to the first visible control in the whole tree answering
## `capture_option_edit`, and a value row of an open dialog, the filter preview
## and the brush's tip grid all answer it, so a ramp step could reach one of
## them, be answered in its words and leave the ramp the gradient lays as it
## was. This takes only a control answering `stop_report` as well, which is
## the ramp's half of the door, and looks for it in the Tool Options docker
## alone, so the skeleton still knows two methods and not the base module's
## class.
class_name SaRampCapture
extends RefCounted

## The built-in dockers' ids, and where a docker's Window is asked for by one.
const DockerIds := preload("res://ui/main/sa_docker_ids.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")


## Edits the ramp's stops, counted from 0: `{"ramp": {"select": 1, "color":
## "#20c040"}}` colours the far end of a ramp of two stops, the ramp the Tool
## Options docker shows.
##
## The keys are `select`, `add`, `open`, `pick`, `color`, `alpha`, `move`,
## `remove`, `save`, `load`, `stock` and `delete`, each optional and applied in
## that order: `{"select": 1, "add": 0.5, "color": "#20c040", "alpha": 0.0,
## "move": 0.6, "remove": 2, "open": true, "pick": "#204080", "save":
## "Sunset", "load": "Sunset", "stock": "foreground_to_transparent", "delete":
## "Sunset"}`. `add` selects the stop it adds, and `color`, `alpha` and `move`
## edit the selected stop.
##
## The answer is `SaCapture: ramp {...}`, the stops as the ramp holds them
## after the step, with `selected` counted from 0 as well. A stop the ramp does
## not have, `select 2` on a ramp of two, is refused with the count it does
## have, and an edit the ramp the tool lays does not hold is answered as one
## that did not land, naming the stop and the colour it holds. Either is an
## error as well, in a door's `errors`, and no key after it is applied. So is
## a step sent while the docker shows no colour ramp, which is a tool other
## than the gradient or the docker not shown.
##
## The ramp's own control does the editing and the reading back, behind its
## `capture_option_edit`. In a host with no docker registry, a suite's, the
## ramp is looked for in the whole tree.
static func edit(tree: SceneTree, spec: Dictionary) -> String:
    if tree == null:
        return _refused("SaCapture: ramp refused, there is no tree to find a colour ramp in")
    var under: Node = tree.root
    var registry := CaptureRun.DockerLookup.registry_of(tree)
    if registry != null:
        under = CaptureRun.DockerLookup.window_in(registry, DockerIds.TOOL_OPTIONS)
        if under == null:
            return _refused("SaCapture: ramp refused, there is no Tool Options docker to find a colour ramp in")
    var row := ramp_in(under)
    if row == null:
        return _refused(
            "SaCapture: ramp refused, the Tool Options docker shows no colour ramp, choose the gradient tool and show the docker"
        )
    return String(row.call("capture_option_edit", spec))


## The first visible control under *under* answering both halves of a ramp's
## door, or null.
static func ramp_in(under: Node) -> Control:
    for node in under.find_children("*", "Control", true, false):
        var widget := node as Control
        if widget.has_method("capture_option_edit") and widget.has_method("stop_report") and widget.is_visible_in_tree():
            return widget
    return null


## *said* pushed as an error, so a door's answer carries it, and answered for
## the step to print.
static func _refused(said: String) -> String:
    push_error(said)
    return said
