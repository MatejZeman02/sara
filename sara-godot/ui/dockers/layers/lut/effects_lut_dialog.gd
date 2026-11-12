## The window of Export Effects as LUT: the node it exports, the table's size,
## what the file leaves out, and Save.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What is left out is listed when the window opens, before anything is written,
## so the painter knows what the file does not carry. The measurement runs on
## Save alone, so opening the window costs nothing on the GPU. Once written,
## the line at the foot names the file and its rows, and says so when the
## effects change with the place in the picture, which a table cannot hold.
@tool
extends SaDialogWindow

## The words over the list of what is left out, and in its place when nothing is.
const LEFT_OUT_HEAD := "Left out, because a LUT carries only a colour change made pixel by pixel:"
const NOTHING_LEFT_OUT := "Nothing is left out. The file carries every effect here."
const NOTHING_CARRIED := "Nothing here changes a colour, so the file would leave every colour as it is."

var _export: SaEffectsLut = null
var _what: Label = null
var _size: SaChoiceButton = null
var _head: Label = null
var _left_out: Label = null
var _written: Label = null
var _save: Button = null


func _init() -> void:
    _init_dialog(SaEffectsLut.DIALOG_NAME, tr("Export Effects as LUT"), Vector2i(460, 320), Vector2i(360, 240))
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    _what = SaMake.label(column, "WhatLabel")
    _what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var size_row := SaMake.row(column, "SizeRow", SaTheme.GAP)
    SaMake.label(size_row, "SizeLabel", tr("Points a side"))
    var sizes: Array = []
    for side in SaEffectsLut.SIZES:
        sizes.append({"id": side, "label": str(side)})
    _size = SaMake.choice(size_row, "SizeChoice", sizes)
    _size.select_value(SaEffectsLut.DEFAULT_SIZE)
    _head = SaMake.label(column, "LeftOutHead")
    _head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _left_out = SaMake.label(column, "LeftOut")
    _left_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_left_out, "text_muted")
    _written = SaMake.label(column, "WrittenLine")
    _written.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var buttons := pinned_buttons(column)
    var cancel := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel.pressed.connect(hide)
    _save = SaMake.button(buttons, "LutSaveButton", tr("Save..."), tr("Pick where the .cube file goes, and write it."))
    _save.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    _save.pressed.connect(_ask)
    default_button = _save


## Shows *export* and opens.
func open_for(export: SaEffectsLut) -> void:
    fill(export)
    popup_centered()
    fit_opening_size()


## The window's lines for *export*, without showing it.
func fill(export: SaEffectsLut) -> void:
    _export = export
    _what.text = (
        tr("The effects of '%s' as a .cube table, which DaVinci Resolve, Premiere, Photoshop, Krita, Nuke and OBS read.")
        % export.node.name
    )
    var lines := export.left_out()
    _head.text = tr(LEFT_OUT_HEAD) if not lines.is_empty() else tr(NOTHING_LEFT_OUT)
    if not export.carries_anything():
        _head.text = tr(NOTHING_CARRIED) + " " + _head.text
    _left_out.text = "\n".join(lines)
    _left_out.visible = not lines.is_empty()
    _written.text = ""
    _written.visible = false


## The side picked.
func chosen_size() -> int:
    var picked: Variant = _size.selected_value()
    return int(picked) if picked != null else SaEffectsLut.DEFAULT_SIZE


## The picker over Save, on the format's one extension.
func _ask() -> void:
    if _export == null:
        return
    var filters := PackedStringArray(["*.cube ; Colour lookup table"])
    SaFilePicker.open(_save, SaFilePicker.Mode.SAVE_FILE, filters, save_to, tr("Export Effects as LUT"))


## Writes the table to *path*, `.cube` added when it has no extension, and says
## what was written on the line at the foot.
func save_to(path: String) -> void:
    if _export == null or path.is_empty():
        return
    var target := path if not path.get_extension().is_empty() else path + ".cube"
    var rows := _export.write(target, chosen_size())
    _written.visible = true
    if rows == 0:
        _written.text = tr("Could not write %s.") % target
        SaProblems.refuse("SaEffectsLut", tr("Could not write %s.") % target)
        return
    _written.text = tr_n("Wrote %d row to %s.", "Wrote %d rows to %s.", rows) % [rows, target]
    if _export.moved:
        _written.text += (
            " "
            + tr(
                (
                    "The effects change with the place in the picture, a grain or a noise, which a table cannot hold,"
                    + " so the file has what they do at one place."
                )
            )
        )
    SaMessage.notice(tr("Wrote the effects of '%s' to %s") % [_export.node.name, target.get_file()])
