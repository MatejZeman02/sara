## An ICC profile file the painter chose as a colour space, read into one
## under the profile's own description, or refused with the reason.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The facade of `ui/color_space/profile_file`. The colour space picker lists
## the last profile read as an entry of its own and opens the file dialog
## through [method ask], so Image > Colour Space and File > New take a profile
## file alike. The reading is `SaIccProfile`'s, which the display profile uses
## as well: a matrix profile of version 2 or 4, and a lookup table or CMYK one
## refused with the reason rather than read approximately.
class_name SaProfileFile
extends RefCounted

## The filter the file dialog offers, both extensions a profile is found under.
const FILTER := "*.icc, *.icm ; ICC profiles"

## The profile's description, or the file's name when it carries none.
var name: String = ""

## The space the profile describes, carrying [member name] as its
## `profile_name`, or null when the file was refused.
var space: SaColorSpace = null

## Why [member space] is null, in a sentence for the painter, or empty.
var problem: String = ""


func _init(profile_name: String, profile_space: SaColorSpace, refusal: String = "") -> void:
    name = profile_name
    problem = refusal
    if profile_space != null:
        space = profile_space.with_depth(profile_space.depth)
        space.profile_name = profile_name


## The profile at *path*, read or refused.
static func read(path: String) -> SaProfileFile:
    var profile := SaIccProfile.read(path)
    if profile.space == null:
        var reason := profile.problem
        if reason.is_empty():
            reason = "The profile could not be read."
        return SaProfileFile.new(profile.name, null, reason)
    return SaProfileFile.new(profile.name, profile.space)


## Opens the file dialog over *host* and hands the path chosen to
## *on_chosen*, `func(path: String)`. A cancel calls nothing, so the picker's
## choice stays where it was. Answers the file picker, which a scenario's
## `file_picker` step answers in the platform's place.
static func ask(host: Node, on_chosen: Callable) -> SaFilePicker:
    var filters := PackedStringArray([SaPage.translated(FILTER)])
    return SaFilePicker.open(
        host,
        SaFilePicker.Mode.OPEN_FILE,
        filters,
        func(path: Variant) -> void: on_chosen.call(String(path)),
        SaPage.translated("Choose a Colour Profile")
    )
