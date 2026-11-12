## The question a preset save asks before it writes over another preset, which
## the tool bar's Save As and the brush editor's Rename both put.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A name typed into either field that another preset already holds, with case
## folded as `SaPresetNames` folds it, writes nothing until the painter says
## so, and Cancel is the default, the way a file's Save As asks before it
## replaces a file. The New Preset dialog refuses a taken name outright, and
## these two fields ask instead, because writing over a preset on purpose is
## how a painter updates one from another brush.
##
## The preset in hand is no other preset: its own name, in any case, is a
## plain Save and asks nothing.
##
## Its own file because `tool_options_presets.gd` stands at its line limit, and
## both bars call [method ask] in one line.
class_name SaPresetReplace
extends RefCounted

const REPLACE := 0
const CANCEL := 1


## Writes through *proceed* under the stored name *wanted* lands on, at once
## when that is no other preset's and after the painter's Replace when it is.
## *loaded* is the preset in hand, empty for none. *proceed* is called with one
## argument, the name to write under: the existing preset's own stored name
## when *wanted* differs from it only in case, so a confirmed save never makes
## a second file differing in case, and *wanted* otherwise.
##
## Answers the question's window when one was put up, and null when the write
## went ahead without one, so a suite and the state dump can read it.
static func ask(host: Node, store: SaPresetStore, wanted: String, loaded: String, proceed: Callable) -> SaMessage:
    var taken := store.taken_as(wanted) if store != null else ""
    if taken.is_empty() or taken.to_lower() == loaded.to_lower():
        proceed.call(wanted if taken.is_empty() else taken)
        return null
    SaTrail.stage("asked whether to replace the preset %s" % taken)
    return SaMessage.confirm(
        host,
        TranslationServer.translate("Replace preset"),
        TranslationServer.translate("A preset named '%s' already exists. Replace it with this brush?") % taken,
        PackedStringArray([TranslationServer.translate("Replace"), TranslationServer.translate("Cancel")]),
        _answered.bind(taken, proceed),
        CANCEL,
        CANCEL
    )


static func _answered(index: int, taken: String, proceed: Callable) -> void:
    SaTrail.stage("answered %s" % ("Replace" if index == REPLACE else "Cancel"))
    if index == REPLACE:
        proceed.call(taken)
