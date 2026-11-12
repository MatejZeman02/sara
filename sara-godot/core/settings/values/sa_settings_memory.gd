## How much of the graphics card Sara keeps its open documents to: the share of
## the card's memory `SaMemoryBudget` reads as its budget.
##
## The default is read from the card's reported memory, a fraction of it, with
## a Preferences row to lower it, so a painter sharing the card with Blender
## can. So the setting is a share, at most the default, and the Performance page's row only lowers it.
## A share rather than GiB, because one profile follows a painter from a
## laptop to a desktop card and a share means the same on both.
##
## **It is a link of the settings autoload's chain**: `SaSettings` extends
## `SaSettingsValues` extends `SaSettingsShapeCheck` extends
## `SaSettingsLocation` extends this extends `SaSettingsIdle`, so
## `SaSettings.card_memory_share` is the property below and not a forward to
## it. It adds no signal, because [signal SaSettingsImporting.changed] is the
## one the rest of the chain shares.
##
## `@tool` because the autoload that extends it is.
@tool
class_name SaSettingsMemory
extends SaSettingsIdle

## The share of the card a fresh profile keeps to, and the most a hand may set.
## Six tenths leaves four for what is not Sara's: `SaCardMemory`'s margin of a
## tenth, the desktop and another program on the card, and room for eviction to
## move layers to RAM before a document is refused at the card less the margin.
const MAX_CARD_MEMORY_SHARE: float = 0.6
## The least a hand may set. Below a tenth a single large layer would be past
## the budget on most cards and everything would live in RAM.
const MIN_CARD_MEMORY_SHARE: float = 0.1

## The share of the card's memory the open documents are kept to.
##
## Additive, without a SETTINGS_VERSION bump: an older profile has no key and
## reads the default a new one has.
var card_memory_share: float = MAX_CARD_MEMORY_SHARE:
    set(val):
        val = clampf(val, MIN_CARD_MEMORY_SHARE, MAX_CARD_MEMORY_SHARE)
        if is_equal_approx(card_memory_share, val):
            return
        card_memory_share = val
        changed.emit(&"card_memory_share")
