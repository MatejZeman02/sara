## Whether a `.sad` keeps the Reference docker's pictures inside it, the
## Preferences > Files switch "Keep reference pictures inside the file".
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A board that keeps paths only opens on another machine with an empty frame
## where each picture was, so a painting sent on can carry its pictures. The
## switch starts off. What the switch makes a save do is
## `SaSadReferencePictures`'s, beside the writer.
##
## A file of its own because `SaSettingsValues` stands at its thousand lines,
## the way `SaSettingsNewDocument` left it.
##
## **A link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsSearchRecents` extends this extends
## `SaSettingsNewDocument`, so
## `SaSettings.sad_keeps_reference_pictures` is the property below and not a
## forward to it. It adds no signal, the chain shares
## [signal SaSettingsImporting.changed].
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsReferencePictures
extends SaSettingsNewDocument

## On, a save stores each reference picture's own file bytes in the `.sad`
## beside its path. Off, paths only, as every save did before the switch.
## Additive, an older profile has no key and reads it off.
var sad_keeps_reference_pictures: bool = false:
    set(val):
        sad_keeps_reference_pictures = val
        changed.emit(&"sad_keeps_reference_pictures")
