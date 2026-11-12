## The docker in this fixture set module: a window with one line in it, so a shot
## shows whether the reload's second registration built a Window of its own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
@tool
extends DockerWindow


func _init() -> void:
    _init_docker("R1ProbeDocker", tr("R1 Probe"), Vector2i(240, 120))
    var label := Label.new()
    label.name = "ProbeLabel"
    label.text = tr("Built at %d ms") % Time.get_ticks_msec()
    label.set_anchors_preset(Control.PRESET_FULL_RECT)
    _control_node.add_child(label)
