## The rule a favourites list is held to: names in the order they were starred,
## each at most once, toggled, dropped and renamed without disturbing the rest.
##
## Its own class because two lists share it, the blend modes pinned to the top
## of the blend menu and the presets the painter starred, and the rule is not a
## preference of either. The lists stayed in `SaSettingsValues` as stored
## values, the way the brush slots did beside [SaSettingsBrushSlots], and the
## blend list's factory value came here as the slots' factory list sits there.
##
## Every call answers a new list and never edits the one it was given, so a
## caller writes the answer back through the preference's setter, which is what
## saves it and says so.
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsFavorites
extends RefCounted

## Normal and Multiply: the mode a painter is in, and the one they reach for
## first. A fresh profile shows the blend menu's section rather than an empty
## heading.
const BLEND_FACTORY: Array = ["normal", "multiply"]


## *favorites* with *name* added at the end when it was not there, or taken out
## when it was.
static func toggled(favorites: Array, name: String) -> Array:
    var out := favorites.duplicate()
    if out.has(name):
        out.erase(name)
    else:
        out.append(name)
    return out


## *favorites* without *name*, which is what a deleted preset leaves.
static func dropped(favorites: Array, name: String) -> Array:
    var out := favorites.duplicate()
    out.erase(name)
    return out


## *favorites* with *from* replaced by *to* in the place *from* held, so a
## renamed preset keeps its star and its place in the order starred. A list
## without *from* comes back as it was, and one that already holds *to* keeps
## it once.
static func renamed(favorites: Array, from: String, to: String) -> Array:
    var at := favorites.find(from)
    if at < 0 or from == to:
        return favorites.duplicate()
    var out := dropped(favorites, to)
    out[out.find(from)] = to
    return out
