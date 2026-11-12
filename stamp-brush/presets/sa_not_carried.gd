## The tag a converted or imported preset wears for what did not come across,
## `not carried: pattern png`, as a painter reads it in their own language.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The tag is stored in English, because it is the tag's identity: a filter,
## a rename and the profile all name the stored word. This turns it into its
## line at the moment it is shown, as whole sentences with placeholders, so a
## translator can reorder the words. The Krita import's report builds its line
## from the same phrases, which is why they live in one class. The module
## registers [method label] with `SaTagLabels`, so the presets chooser, which
## may not name a module, reads a stored tag through the door.
class_name SaNotCarried
extends RefCounted

## What every such tag begins with, the stored spelling.
const PREFIX: String = "not carried: "


## Whether *tag* is one of these.
static func is_tag(tag: String) -> bool:
    return tag.begins_with(PREFIX)


## *tag* as the painter reads it: a not-carried tag in their language, any
## other tag as it is.
static func label(tag: String) -> String:
    if not is_tag(tag):
        return tag
    return TranslationServer.translate("not carried: %s") % reason(tag.trim_prefix(PREFIX))


## One phrase of what did not carry in the painter's language. The phrase
## itself stays English where it is stored, and a phrase this does not know
## is answered as it is.
static func reason(item: String) -> String:
    match item:
        "masking brush":
            return TranslationServer.translate("masking brush")
        "masking tip":
            return TranslationServer.translate("masking tip")
        "masking size in pixels":
            return TranslationServer.translate("masking size in pixels")
        "image tip":
            return TranslationServer.translate("image tip")
        "painting mode":
            return TranslationServer.translate("painting mode")
        "texturing mode":
            return TranslationServer.translate("texturing mode")
        "colour source":
            return TranslationServer.translate("colour source")
        "colour gradient":
            return TranslationServer.translate("colour gradient")
        "mask softness curve":
            return TranslationServer.translate("mask softness curve")
        "mask softness curve, it does not descend":
            return TranslationServer.translate("mask softness curve, it does not descend")
        "grain field":
            return TranslationServer.translate("grain field")
        "bristle field":
            return TranslationServer.translate("bristle field")
        "picture field":
            return TranslationServer.translate("picture field")
        "strength":
            return TranslationServer.translate("strength")
        "picture rotation":
            return TranslationServer.translate("picture rotation")
        "second channel":
            return TranslationServer.translate("second channel")
    var tail: Variant = _after(item, "masking dynamics: ")
    if tail != null:
        return TranslationServer.translate("masking dynamics: %s") % tail
    tail = _after(item, "masking composite op ")
    if tail != null:
        return TranslationServer.translate("masking composite op %s") % tail
    tail = _after(item, "pipe selection mode ")
    if tail != null:
        return TranslationServer.translate("pipe selection mode %s") % tail
    tail = _after(item, "pipe tip: ")
    if tail != null:
        return TranslationServer.translate("pipe tip: %s") % tail
    tail = _after(item, "tip: ")
    if tail != null:
        return TranslationServer.translate("tip: %s") % tail
    tail = _after(item, "blend mode ")
    if tail != null:
        return TranslationServer.translate("blend mode %s") % tail
    tail = _after(item, "pattern ")
    if tail != null:
        return TranslationServer.translate("pattern %s") % tail
    return item


## What *text* says after *prefix*, or null when it does not start with it.
static func _after(text: String, prefix: String) -> Variant:
    if text.begins_with(prefix):
        return text.substr(prefix.length())
    return null
