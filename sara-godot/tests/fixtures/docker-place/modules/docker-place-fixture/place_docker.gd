@tool
## A docker holding its own title in a label, 220 by 180, the one the docker
## fixture module registers twice.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends DockerWindow


func _init(docker_id: StringName, heading: String) -> void:
    _init_docker(docker_id, heading, Vector2i(220, 180), Vector2i(120, 100))
    var column := SaMake.column(_control_node, "VBoxContainer")
    column.set_anchors_preset(Control.PRESET_FULL_RECT)
    drag_handle = DockerUtils.make_drag_bar(heading)
    column.add_child(drag_handle)
    var label := Label.new()
    label.text = heading
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(label)


func _ready() -> void:
    _setup_docker_ready()
