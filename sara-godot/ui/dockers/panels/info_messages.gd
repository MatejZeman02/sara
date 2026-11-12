## The foot of the Info docker: the last three distinct pop-up messages, newest
## first, and a button that puts them on the clipboard.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A notice goes away by itself after a moment, and a painter who looked at the
## other monitor loses the sentence that said why nothing happened. `SaNoticeLog`
## keeps the last few, and this reads them on the docker's tick, so no signal
## needs wiring and a docker built late still shows what was said before it.
## Only the text that changed is written, so a tick with nothing new asks for no
## frame.
class_name SaInfoMessages
extends VBoxContainer

## The element's name in the Info docker's layout, the one Preferences lists.
const ELEMENT := "Messages"

## Test seam, as `SaLocalServerDialog.clipboard` is. A suite that replaces it
## puts `DisplayServer.clipboard_set` back.
static var clipboard: Callable = DisplayServer.clipboard_set

var lines: Array[Label] = []
var copy_button: Button

var _shown := PackedStringArray()


func _init() -> void:
    name = "Messages"
    set_meta(SaMake.KIND_META, SaMake.Kind.COLUMN)
    SaSettingsRows.embolden(SaMake.label(self, "Title", tr("Messages")))
    var list := SaMake.column(self, "Rows")
    list.set_meta(SaUI.FONT_SCALE_META, SaInfoSection.ROW_FONT_SCALE)
    for index in SaNoticeLog.KEEP:
        var line := SaMake.label(list, "Body")
        line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        line.custom_minimum_size.x = 1.0
        line.visible = false
        lines.append(line)
    copy_button = SaMake.button(self, "Copy", tr("Copy"))
    copy_button.disabled = true
    copy_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    copy_button.pressed.connect(copy)


## Shows what the log holds now, writing only a line that differs.
func refresh() -> void:
    var now := SaNoticeLog.recent
    if now == _shown:
        return
    _shown = now.duplicate()
    for index in lines.size():
        var has := index < now.size()
        lines[index].visible = has
        lines[index].text = now[index] if has else ""
    copy_button.disabled = now.is_empty()


## Puts the messages, newest first and one to a line, on the clipboard.
func copy() -> void:
    clipboard.call(SaNoticeLog.as_text())
