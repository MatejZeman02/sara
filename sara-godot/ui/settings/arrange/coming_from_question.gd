## The question a press on "I'm coming from" asks before it writes anything:
## which program, the five preferences with each one's value now and after,
## and what stays.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Every press asks, the one that releases the lit button included**, since
## a release writes over the same five. Without the question a painter who
## arranged their dockers loses the arrangement to one stray click, because a
## moved docker forks the layout to "Default (Custom)" and the press loads the
## program's over it.
##
## **A press that would change nothing asks nothing**, so [method changes] is
## read before the question is built, and an empty answer writes at once.
##
## **The question is `SaMessage.confirm`'s**, the one Reset all preferences and
## a palette's Delete put up, so its look, its keys and its logical sizing are
## theirs. Cancel is the first answer, Enter's and Escape's, and Overwrite the
## second.
class_name SaComingFromQuestion
extends RefCounted

## The two answers, in the order the buttons are built. Cancel first, so the
## safe one is both the default and the cancel index.
const ANSWER_CANCEL: int = 0
const ANSWER_OVERWRITE: int = 1

## The question's size, tall enough for the five lines and the paragraph under
## them at the default font, so nothing is read by scrolling.
const SIZE := Vector2i(600, 400)

## The order the lines are listed in, which is the order a press writes them.
const KEYS: Array[String] = ["shortcuts", "palette", "layout", "picker", "zoom"]


## Every preference *answer* sets, as `{key, what, now, after, changes}`, the
## values in the words a painter reads on the page that sets each one. A null
## *store* leaves the layout out, as [method SaComingFromRow.apply] does.
static func lines(answer: String, store: DockerLayoutStore) -> Array[Dictionary]:
    var wanted := SaComingFromRow.values_of(answer)
    var out: Array[Dictionary] = []
    if wanted.is_empty():
        return out
    for key: String in KEYS:
        if key == "layout" and store == null:
            continue
        var now := _now(key, store)
        var after := String(wanted[key])
        var same := SaComingFromRow._shortcuts_match(now, after) if key == "shortcuts" else now == after
        (
            out
            . append(
                {
                    "key": key,
                    "what": _what(key),
                    "now": _title(key, now, store),
                    "after": _title(key, after, store),
                    "changes": not same,
                }
            )
        )
    return out


## The lines of [method lines] whose value a press would change, none when the
## settings are already *answer*'s.
static func changes(answer: String, store: DockerLayoutStore) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for line: Dictionary in lines(answer, store):
        if bool(line["changes"]):
            out.append(line)
    return out


## The question's title: the program a press sets, or Sara's own for a release.
static func title(answer: String) -> String:
    if answer == SaComingFromRow.OWN:
        return TranslationServer.translate("Go back to Sara's own settings?")
    var program := String(SaComingFromRow.values_of(answer).get("title", answer))
    return TranslationServer.translate("Set Sara up as %s?") % program


## The question's text: what the press writes over, each preference with its
## value now and after, then what stays.
static func text(answer: String, store: DockerLayoutStore) -> String:
    var parts := PackedStringArray()
    if answer == SaComingFromRow.OWN:
        parts.append(TranslationServer.translate("Sara's own values will overwrite these settings:"))
    else:
        var program := String(SaComingFromRow.values_of(answer).get("title", answer))
        parts.append(TranslationServer.translate("A press on %s will overwrite these settings:") % program)
    for line: Dictionary in lines(answer, store):
        if bool(line["changes"]):
            parts.append(TranslationServer.translate("%s: '%s' becomes '%s'") % [line["what"], line["now"], line["after"]])
        else:
            parts.append(TranslationServer.translate("%s: '%s' stays") % [line["what"], line["now"]])
    return (
        "\n".join(parts)
        + "\n\n"
        + TranslationServer.translate("The UI scale stays as it is.")
        + " "
        + TranslationServer.translate("Your own shortcut profiles, palettes and layouts stay on disk and can be picked again.")
    )


## Puts the question up over *host* and calls *on_overwrite* only on Overwrite.
## Cancel, Escape, the close button and every other way out write nothing.
static func ask(host: Node, answer: String, store: DockerLayoutStore, on_overwrite: Callable) -> SaMessage:
    var question := SaMessage.confirm(
        host,
        title(answer),
        text(answer, store),
        PackedStringArray([TranslationServer.translate("Cancel"), TranslationServer.translate("Overwrite")]),
        func(index: int) -> void:
            if index == ANSWER_OVERWRITE:
                on_overwrite.call(),
        ANSWER_CANCEL,
        ANSWER_CANCEL
    )
    question.name = "ComingFromQuestion"
    # The fit `SaDialogWindow` runs on the frame after a window is shown grows
    # it to this and keeps it centred.
    question.logical_size = SIZE
    return question


## The value in force for *key*, in the name the settings store it under.
static func _now(key: String, store: DockerLayoutStore) -> String:
    match key:
        "shortcuts":
            return SaSettings.shortcuts_profile
        "palette":
            return SaSettings.theme_name
        "layout":
            return store.current_preset()
        "picker":
            return SaSettings.color_picker_shape
        "zoom":
            return SaSettings.reset_zoom
    return ""


## What each preference is called in the question.
static func _what(key: String) -> String:
    match key:
        "shortcuts":
            return TranslationServer.translate("Shortcut profile")
        "palette":
            return TranslationServer.translate("Colour theme")
        "layout":
            return TranslationServer.translate("Docker layout")
        "picker":
            return TranslationServer.translate("Colour picker")
        "zoom":
            return TranslationServer.translate("Ctrl+0 shows")
    return key


## *value* of *key* in the words of the page that sets it: the shortcut
## profile as the Keyboard Shortcuts page lists it, the palette and the layout
## by their titles, the picker's shape as its dropdown reads and Ctrl+0 as the
## Display page's "Reset zoom to" row does.
static func _title(key: String, value: String, store: DockerLayoutStore) -> String:
    match key:
        "shortcuts":
            return SaShortcutStore.DEFAULT_PROFILE if SaComingFromRow.SARA_SHORTCUTS.has(value) else value
        "palette":
            for palette: Dictionary in SaTheme.available():
                if String(palette["id"]) == value:
                    return TranslationServer.translate(String(palette["name"]))
            return value
        "layout":
            if store == null:
                return value
            return store.presets().title(value)
        "picker":
            var kind := SaPickerShape.KIND_KEYS.find(value)
            if kind < 0:
                return value
            return TranslationServer.translate(SaPickerShape.KIND_LABELS[kind])
        "zoom":
            if value == SaView.RESET_PIXELS:
                return TranslationServer.translate("Actual pixels")
            return TranslationServer.translate("The whole picture")
    return value
