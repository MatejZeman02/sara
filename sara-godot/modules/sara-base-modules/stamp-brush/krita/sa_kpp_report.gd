## What the Krita import says about each file it read, as sentences a painter
## reads in their own language.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The importer's results hold English data: a refusal's reason, the phrases of
## what did not carry, the notes. The presets store writes the phrases into a
## tag, so they stay as they are. This class turns a result into its line at the
## moment the line is shown, every sentence a whole message with placeholders so
## a translator can reorder the words. The pieces of a line are joined with a
## comma as a list is, and each piece is its own sentence.
##
## The line keeps the `SaKppImport:` log tag in front, which the presets page
## takes off and the console keeps.
class_name SaKppReport
extends RefCounted

const TAG: String = "SaKppImport: "


## The line for one *result* of [method SaKppImport.import_preset].
static func line(result: Dictionary) -> String:
    var source := String(result.get("source", "")).get_file()
    var error := String(result.get("error", ""))
    if not error.is_empty():
        return TAG + TranslationServer.translate("%s refused: %s") % [source, error]
    var tips := int(result.get("tips", 0))
    if tips > 0:
        return TAG + _tips(source, tips, result.get("tips_skipped", []))
    if result.has("kept"):
        return TAG + TranslationServer.translate("%s kept '%s', already in the presets") % [source, String(result["kept"])]
    var name := String(result.get("name", ""))
    var head := (
        TranslationServer.translate("%s replaced '%s'")
        if result.get("replaced", false)
        else TranslationServer.translate("%s imported as '%s'")
    )
    var parts := PackedStringArray([head % [source, name]])
    var not_carried: Array = result.get("not_carried", [])
    if not_carried.is_empty():
        parts.append(TranslationServer.translate("not carried: nothing"))
    else:
        var reasons := PackedStringArray()
        for item: String in not_carried:
            reasons.append(reason(item))
        parts.append(TranslationServer.translate("not carried: %s") % ", ".join(reasons))
    var unread: Array = result.get("unread", [])
    if not unread.is_empty():
        parts.append(TranslationServer.translate("read by no row: %s") % ", ".join(PackedStringArray(unread)))
    for note: String in result.get("notes", []):
        parts.append(_note(note))
    if result.has("pressure"):
        parts.append(TranslationServer.translate("under %s") % String(result["pressure"]))
    return TAG + ", ".join(parts)


## One phrase of a result's `not_carried` in the painter's language. The phrase
## itself stays English where it is stored, as the tag the preset wears, and
## the words are [SaNotCarried]'s, which the presets chooser shows the tag by, through `SaTagLabels`.
static func reason(item: String) -> String:
    return SaNotCarried.reason(item)


## A note, the sentences about what came from somewhere other than the file.
static func _note(note: String) -> String:
    if note == SaKppImport.GRADIENT_FROM_THE_PAINTER:
        return TranslationServer.translate("gradient from the painter's colour to the background colour, the file holding none")
    return note


## The line for a bundle that carried tips and no preset: how many arrived, and
## the ones that did not, named, because a painter who exported twenty-five
## brushes and finds nineteen needs the other six named.
static func _tips(source: String, written: int, skipped: Array) -> String:
    var parts := PackedStringArray(
        [
            (
                TranslationServer.translate_plural(
                    "%s holds no preset, %d brush tip into the tip list",
                    "%s holds no preset, %d brush tips into the tip list",
                    written
                )
                % [source, written]
            )
        ]
    )
    if not skipped.is_empty():
        parts.append(TranslationServer.translate("passed over: %s") % ", ".join(PackedStringArray(skipped)))
    return ", ".join(parts)
