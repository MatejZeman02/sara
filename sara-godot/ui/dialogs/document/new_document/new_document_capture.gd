## The `new_document_row` step and the `new_document` block of the dump, the
## New Document dialog's half of the capture door.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `new_document_dialog.gd`, which stood at the thousand lines the run
## fails at. Cut by responsibility: this file owns the door, what a step may
## ask of the rows and what the dump reads back, and the dialog owns the rows.
## It stays in the dialog's folder rather than in `harness/captures`, for the
## reason `brush_presets_capture.gd` gives: a dialog describes itself to the
## harness, and the dialog's `capture_row` and `capture_state` hand the step
## here so the step table names one class.
##
## It moves a row only through the dialog's own `select_row`, so a step that
## says it set a row went through what picking the entry does, and it reads the
## dictionary each part of the dialog hands it rather than the part's members.
@tool
extends RefCounted


## The `new_document_row` step, which `NewDocumentDialog.capture_row` describes:
## each row of `CAPTURE_ROWS` the spec names put on the entry it names, in that
## order, then a template saved or deleted and the dialog put away if asked.
static func row(tree: SceneTree, spec: Dictionary) -> String:
    var dialog := tree.root.find_child("NewDocumentDialog", true, false) as NewDocumentDialog
    if dialog == null or not dialog.visible:
        return "SaCapture: no New Document dialog open"
    var done := PackedStringArray()
    for row_name: String in NewDocumentDialog.CAPTURE_ROWS:
        if not spec.has(row_name):
            continue
        if not dialog.select_row(StringName(row_name), spec[row_name]):
            return "SaCapture: the %s row has no entry %s" % [row_name, JSON.stringify(spec[row_name])]
        var option := dialog.row_option(StringName(row_name))
        done.append("%s = %s" % [row_name, option.text])
    # `"close": true` puts the dialog away the way Cancel does, after any rows the
    # same step named. Escape reaches the main window rather than an embedded one,
    # so without it a scenario that opens this dialog leaves it open over the
    # canvas, and a stroke after it lands on the dialog.
    # `"save_template": "Name"` saves the rows as it, `"delete_template": true` deletes.
    if spec.has("save_template"):
        var saved := dialog.save_template(String(spec["save_template"]))
        done.append("saved %s" % saved if dialog.replace_question == null else "asked whether to replace the template")
    if bool(spec.get("delete_template", false)):
        done.append("deleted %s" % dialog.delete_template())
    # `"primaries": [[x, y], [x, y], [x, y]]` and `"white_xy": [x, y]` type into
    # the colour space's fields, and `"save_space": "Name"` keeps the space under
    # that name, so a scenario reaches a space no preset names.
    if spec.has("primaries"):
        var typed := PackedVector2Array()
        for pair: Array in spec["primaries"]:
            typed.append(Vector2(float(pair[0]), float(pair[1])))
        dialog.picker.set_primaries(typed)
        done.append("primaries = %s" % typed)
    if spec.has("white_xy"):
        var pair: Array = spec["white_xy"]
        dialog.picker.set_white(Vector2(float(pair[0]), float(pair[1])))
        done.append("white = %s" % dialog.picker.white)
    if spec.has("save_space"):
        done.append("saved the space as '%s'" % dialog.picker.save_as(String(spec["save_space"])))
    if bool(spec.get("close", false)):
        dialog.hide()
        done.append("closed")
    if done.is_empty():
        return "SaCapture: no row named, the dialog was left alone"
    return "SaCapture: new document %s" % ", ".join(done)


## Whether *entry* is one of the page's dropdowns.
static func _is_choice(entry: SaPageRow) -> bool:
    return entry.kind == SaPageRow.Kind.CHOICE


## Every row the dialog is showing, for a capture: what each dropdown reads,
## the white point and the space the colour rows hand, and the memory line's
## figure. The count of dropdowns is what says no fourth chooser appeared.
static func state(root: Window) -> Dictionary:
    var dialog := root.find_child("NewDocumentDialog", true, false) as NewDocumentDialog
    if dialog == null or not dialog.visible:
        return {}
    var out := dialog.picker.capture_state()
    out.merge(dialog.memory_line.capture_state(dialog.selected_size(), dialog.selected_space()))
    for row_name: String in NewDocumentDialog.CAPTURE_ROWS:
        out[row_name] = dialog.row_option(StringName(row_name)).text
    (
        out
        . merge(
            {
                "dropdowns": dialog.page.rows().filter(_is_choice).size(),
                "background_colour": "#%s" % dialog.background_color.to_html(false),
                "background_colour_shown": dialog.page.row(&"background_colour").line.visible,
                "details_open": dialog.details_open,
                "memory_warning": dialog.memory_warning.text,
                "memory_warning_shown": dialog.memory_warning.visible,
                "memory_warning_lines": dialog.memory_warning.get_line_count(),
                "memory_warning_width": dialog.memory_warning.size.x,
                "create_rect": dialog.create_button.get_global_rect(),
                "window_size": dialog.size,
            }
        )
    )
    return out
