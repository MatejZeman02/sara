## Filter > Equalize, the door a painter finds Equalize by: a row of its own
## under Tone in the Filter menu and in the filter browser, which opens Levels
## with the map taken.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Equalize is a button inside Levels, and a painter who looks for the word in
## the menu or the search would find nothing there, because both read "Levels".
## So this is an entry over Levels and no
## filter of its own, the shape Desaturate is over Hue/Saturation. Its page is
## Levels' page under Levels' title, and its panel presses Equalize as it
## opens, so the layer shows equalized with the button pressed and Reset
## beside it, and the handles take it further. An Attach, or a layer the
## browser adds, is filed as Levels' own record, see [method filed_as], so a
## double click on either opens Levels on the map.
##
## Reached through [method SaLevelsFilter.equalize_entry], since the module
## names the folder's facade alone.
class_name SaEqualizeFilter
extends SaLevelsFilter


func _init() -> void:
    super(true)


func title() -> String:
    return "Equalize"


## Under Tone, beside Levels, whose page it opens.
func family() -> StringName:
    return &"tone"


func sentence() -> String:
    return (
        "Spread the layer's lightness evenly from black to white, and leave its chroma and hue alone. "
        + "Opens in Levels, where the handles take it further."
    )


## Its own registry key, since Levels' is `SaPointAdjust.LEVELS`.
func id() -> StringName:
    return &"equalize"


## Its own command, so the palette and the Keyboard Shortcuts page find it by
## the same word, with no chord: Ctrl+L is Levels'.
func action_name() -> StringName:
    return &"filter_equalize"


func chord() -> Array[InputEvent]:
    return []


## Levels' rows and panel, under Levels' title, since the page is Levels.
func build(ui: SaDialog) -> void:
    super.build(ui)
    ui.title(super.title())


## Levels' key under the module this registered in, and the values the panel
## holds, the map with them, so the record is a Levels record. The two ids
## share the module half of *own_key*, which a fixture registered with no
## module leaves empty.
func filed_as(own_key: StringName) -> SaAttachedFilter:
    var module := String(own_key).trim_suffix(String(id()))
    return SaAttachedFilter.new(StringName(module + String(SaPointAdjust.LEVELS)), parameters())
