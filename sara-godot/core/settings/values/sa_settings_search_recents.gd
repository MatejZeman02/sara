## The rows last picked in the F3 search, which the list shows first under
## Recent when it opens with the field empty.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The search opened again is most often for what it found last time, so the
## last three picked stand at the top. Each row is kept by what it acts
## on, the key `SaSearchWindow` makes of it, so a row the search builds again on
## the next opening is the same row. What the keys mean and which of them are
## shown are the search's, and this keeps the list only.
##
## A file of its own because `SaSettingsValues` stands at its thousand lines,
## the way `SaSettingsReferencePictures` left it.
##
## **A link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends this extends `SaSettingsReferencePictures`, so
## `SaSettings.search_recents` is the property below and not a forward to it.
## It adds no signal, the chain shares [signal SaSettingsImporting.changed].
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsSearchRecents
extends SaSettingsReferencePictures

## How many picks the list keeps.
const SEARCH_RECENTS_KEPT := 3

## The keys of the rows last picked, newest first, at most
## [constant SEARCH_RECENTS_KEPT]. Additive, an older profile has no key and
## reads as none.
var search_recents: Array = []:
    set(val):
        search_recents = val.duplicate()
        changed.emit(&"search_recents")


## Puts *key* at the front of the recent picks, once, and drops the oldest past
## [constant SEARCH_RECENTS_KEPT].
func remember_search_pick(key: String) -> void:
    if key.is_empty():
        return
    var kept := search_recents.duplicate()
    kept.erase(key)
    kept.push_front(key)
    search_recents = kept.slice(0, SEARCH_RECENTS_KEPT)
