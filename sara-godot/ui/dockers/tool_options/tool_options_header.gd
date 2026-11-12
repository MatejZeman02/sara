## The strip above the Tool Options docker's rows: the Advanced check, at hand
## on the docker it acts on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One switch seen from two places.** The check writes
## `SaSettings.advanced_options`, the setting Preferences > General's Advanced
## options row writes, and follows `EventBus.advanced_options_changed`, which
## every write of that setting emits. So the docker's rows, this check and the
## Preferences row move together whichever of the two a painter clicks, and a
## painter looking for the switch finds it on the docker it acts on rather than
## three clicks away on a page the docker never names.
##
## **Its own class rather than lines in `tool_options_docker.gd`**, because it
## owns the strip and the docker owns the rows.
class_name ToolOptionsHeader
extends MarginContainer

## The check's own node name, which a scenario clicks by and which is unique in
## the tree: Preferences' row is `AdvancedOptionsCheck`.
const CHECK_NAME := "ToolOptionsAdvancedCheck"

var check: CheckBox


func _init() -> void:
    name = "ToolOptionsHeader"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var side := SaUI.px(SaUI.BASE_MARGIN)
    add_theme_constant_override("margin_left", side)
    add_theme_constant_override("margin_right", side)
    add_theme_constant_override("margin_top", SaUI.px(2))
    add_theme_constant_override("margin_bottom", 0)

    var row := SaMake.row(self, "HeaderRow")
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    # Right-aligned, so the check sits clear of the rows' labels, which all
    # start at the left edge, and reads as a setting of the docker rather than
    # as a row of the tool.
    var spacer := Control.new()
    spacer.name = "Spacer"
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spacer)

    # Pressed before `toggled` is connected, so the handler does not hear it.
    check = SaMake.check_box(row, CHECK_NAME, tr("Advanced"), SaSettings.advanced_options)
    check.tooltip_text = tr(
        "Show the tool options a tool marks as advanced. The same switch as Advanced options in Preferences > Interface."
    )
    check.set_meta(SaUI.FONT_SCALE_META, ToolOptionsDocker.ROW_FONT_SCALE)
    check.toggled.connect(_on_toggled)

    # Connected at construction rather than on entering the tree, so a header
    # follows the setting from the moment it exists. The docker is built long
    # before it is shown, and the suite builds it without a tree at all, where
    # a connection made in `_ready` would never be made.
    EventBus.advanced_options_changed.connect(_on_advanced_options_changed)


func _ready() -> void:
    # The setting may have moved between construction and entering the tree,
    # which is when a profile is loaded, so the check is read again here.
    check.set_pressed_no_signal(SaSettings.advanced_options)


func _notification(what: int) -> void:
    # Freed, so the bus holds no callable into a header that is gone.
    if what == NOTIFICATION_PREDELETE and EventBus.advanced_options_changed.is_connected(_on_advanced_options_changed):
        EventBus.advanced_options_changed.disconnect(_on_advanced_options_changed)


## The painter clicked the check. Written only when it differs, because the
## setting's own change is what brings the event back here, and a write of the
## value that is already there would emit it for nothing.
func _on_toggled(pressed: bool) -> void:
    if SaSettings.advanced_options != pressed:
        SaSettings.advanced_options = pressed


## Some other writer moved the setting, Preferences most likely, so the check
## follows without writing it back.
func _on_advanced_options_changed(enabled: bool) -> void:
    if check != null and check.button_pressed != enabled:
        check.set_pressed_no_signal(enabled)
