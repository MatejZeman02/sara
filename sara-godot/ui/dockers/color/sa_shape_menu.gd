## The list of the picker's seven shapes, opened by a right press on the shape.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A list on a right press rather than a row on the docker.** The shape's
## setting lives on the Colour Picker page, and the Default layout shows the
## shape and the pair alone, so without this the page would be the only way to
## switch. A list adds no row and shows only while it is asked for. It holds
## no setting: a pick is `chosen` with the shape's key, and
## [SaColorPicker] writes `SaSettings.color_picker_shape` through the one door
## the Preferences row uses, so the two always read the same.
##
## Opened at the pointer rather than under an anchor, because the anchor is the
## whole shape and a list under it would open at the docker's foot.
##
## `@tool` because [SaChoicePopup] carries it, and the editor's language server
## warns MISSING_TOOL on a subclass that drops it.
@tool
class_name SaShapeMenu
extends SaChoicePopup

const SaPickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")


## `super()`, so the base builds its panel and its column before the first row.
func _init() -> void:
    super()
    name = "ShapeMenu"


## Fills the list with the seven shapes, *current_key* marked, without opening
## it, which is the half a suite runs on a picker outside the tree.
func fill(current_key: String) -> void:
    clear()
    for i in SaPickerShapeScript.KIND_KEYS.size():
        add_row(StringName(SaPickerShapeScript.KIND_KEYS[i]), tr(SaPickerShapeScript.KIND_LABELS[i]))
    set_current(StringName(current_key))


## Fills the list and opens it with its top left corner where *part*, a piece
## of the shape, was pressed at *local*, in its own coordinates. The corner is
## measured where an embedded popup's position is, the way
## `SaPopupRect.of_anchor` measures an anchor, and the scale is taken on open
## with the extra factor of the press's window, as `open_under` takes it (hard
## rule 7). Filled but not opened while the shape is out of a tree.
func open_at(part: Control, local: Vector2, current_key: String) -> void:
    fill(current_key)
    if not is_inside_tree() or not part.is_inside_tree():
        return
    set_meta(SaUI.EXTRA_SCALE_META, SaUI.extra_scale(part.get_window()))
    SaUI.apply_to_window(self)
    var wanted := Vector2(wanted_size(0.0)) * content_scale_factor
    var at := Vector2(SaPopupRect.at_point(part, local))
    popup(SaPopupRect.under(Rect2(at, Vector2.ZERO), Vector2i(wanted.round()), SaPopupRect.room_for(self)))
