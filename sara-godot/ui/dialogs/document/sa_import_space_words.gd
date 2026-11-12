## What the import fit dialog's space row says about the colour space a picture
## arrived in: whether the file named it, in a `cICP` chunk or a profile, or the
## format's convention supplied it, and why a profile it carries was set aside.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The row's sentence, its tooltip and the name each listed space goes by all
## follow from the same two facts about the file, so they are answered here from
## those two, and the dialog asks rather than holding the cases itself. The list
## of every sentence the row may carry comes from here as well, which is what
## `SaLineReserve` sizes the row's label by.
class_name SaImportSpaceWords
extends RefCounted

## The row's sentence for a file that names no gamut, and for one that does,
## in which `%s` is the gamut's name. The tooltip beside each says it again in
## the words of what the painter could do about it, and names the gamut too.
const UNNAMED_LINE := "The file names no colour space, so Sara assumes sRGB for 8-bit files and linear light for float files."
const NAMED_LINE: String = "The file names its colour space, %s, so this starts there."
const UNNAMED_TIP: String = "The file names no colour space, so this is a guess. Change it if the colours look wrong."
const NAMED_TIP: String = "The file says it is in %s. Change this only if you know the file is wrong."
## The sentence for a file that carries an ICC colour profile Sara read, `%s`
## the profile's name, and for one Sara could not use, the name and the reason.
const PROFILE_LINE: String = "The file carries the colour profile %s, so this starts there."
const REFUSED_LINE: String = (
    "The file carries the colour profile %s, which Sara cannot use: %s "
    + "So Sara assumes sRGB for 8-bit files and linear light for float files."
)

## Whether the file named the space the row opened on, rather than its format's
## convention supplying it.
var named: bool = false
## The name of the ICC profile the file carries, empty when it carries none or
## names its gamut otherwise, as `SaImageImport.profile_for` answers.
var _profile: String = ""
## Why Sara could not use that profile, empty when it could.
var _problem: String = ""


func _init(file_named: bool = false, carried: SaIccProfile = null) -> void:
    named = file_named
    if carried != null:
        _profile = carried.name
        _problem = carried.problem if carried.space == null else ""


## The name the row lists the space *id* by: the profile's own for a custom
## space read off one, since "Custom" says nothing of Adobe RGB, and the
## preset's otherwise.
func name_of(id: StringName) -> String:
    if id == SaColorSpace.ID_CUSTOM and not _profile.is_empty() and _problem.is_empty():
        return _profile
    return tr(SaColorSpace.display_name(id))


## The row's sentence when it stands on the space *id*.
func line(id: StringName) -> String:
    if not _problem.is_empty():
        return tr(REFUSED_LINE) % [_profile, tr(_problem)]
    if not named:
        return tr(UNNAMED_LINE)
    return tr(PROFILE_LINE) % _profile if not _profile.is_empty() else tr(NAMED_LINE) % name_of(id)


## The row's tooltip when it stands on the space *id*.
func tip(id: StringName) -> String:
    return tr(NAMED_TIP) % name_of(id) if named and _problem.is_empty() else tr(UNNAMED_TIP)


## Every sentence the row may carry over *choices*, the spaces it lists.
func sentences(choices: Array[SaColorSpace]) -> Array:
    var said: Array = [tr(UNNAMED_LINE)]
    for space: SaColorSpace in choices:
        said.append(tr(NAMED_LINE) % name_of(space.id))
    if not _profile.is_empty():
        said.append(tr(PROFILE_LINE) % _profile)
        said.append(tr(REFUSED_LINE) % [_profile, tr(_problem)])
    return said
