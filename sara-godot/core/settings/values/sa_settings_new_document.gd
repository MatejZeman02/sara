## What the New Document dialog keeps between one opening and the next: the
## template it was last created from, whether its details switch is open, and
## the colour spaces the painter saved in the picker it shares with every
## other place that asks for a colour space.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A file of its own because `SaSettingsValues` reached its thousand lines
## when the details switch joined it, and the two are one subject, the dialog's
## memory of the painter, the way `SaSettingsShapeCheck` holds the Shape
## check's.
##
## **A link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsSearchRecents` extends
## `SaSettingsReferencePictures` extends this
## extends `SaSettingsShapeCheck`, so `SaSettings.last_template` is the property below and not a forward to it.
## It adds no signal, the chain shares [signal SaSettingsImporting.changed].
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsNewDocument
extends SaSettingsShapeCheck

## The New Document template last created from, which the dialog opens on.
## Empty is a profile that never created one and opens on the first template.
var last_template: String = "":
    set(val):
        last_template = val
        changed.emit(&"last_template")

## Whether the New Document dialog's details switch is open, the ground, the
## colour space, the depth and the memory line behind it. Shut by default, so
## a first document asks only its size and background. Additive, an
## older profile has no key and opens it shut.
var new_document_details: bool = false:
    set(val):
        if new_document_details == val:
            return
        new_document_details = val
        changed.emit(&"new_document_details")

## The colour spaces the painter saved in the colour space picker, in the order
## saved, each `{"name": String, "space": Dictionary}` with the space as the
## header a `.sad` writes for it. Additive, an older profile has no key and
## lists none. Kept as plain data, because `core` names no class of the picker
## that reads it.
var saved_color_spaces: Array = []:
    set(val):
        saved_color_spaces = val.duplicate(true)
        changed.emit(&"saved_color_spaces")
