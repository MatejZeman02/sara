## The shape of the brush slot list: how many slots there are, what an empty
## list is, and how any stored list becomes exactly that many names.
##
## Its own class because the shape is a rule three readers agree on, the
## profile's setter, the Preferences page that builds a row a slot and the
## commands that answer the ten keys, and none of them is a preference. It is
## the one rule of `SaSettingsValues` that is not a stored value: the
## preference stayed there, and the shape it is held to came here.
##
## `@tool` because the autoload that reads it is.
@tool
class_name SaSettingsBrushSlots
extends RefCounted

## Ten, which is what the parity spec's entry is called and how many keys the
## top row of a keyboard has. Here rather than beside the commands, because the
## key that stores them is `core`'s and `core` does not read `ui`.
const COUNT: int = 10

## The ten slots a fresh profile starts with, one shipped preset in each, so
## Ctrl+Alt with a digit loads a brush on a first start rather than nothing.
##
## Names and not paths, because a slot holds a preset name and the store is
## what knows where one lives. They are names from the stamp brush's shipped
## recipe table, which `core` does not read, so the suite `test_a_fresh_profile_starts_on_a_shipped_preset` holds
## this list to that table. Every slot is a stamp preset, because `core` names
## no module's engine. A painter's own noise preset in a slot loads as well,
## onto the Brush through the noise engine.
##
## Slot 1 is also the brush a fresh session starts on, which is why it is Paint
## rather than a line tool: `ToolOptionsPresets.scan` picks the first slot that
## loads when nothing has been picked yet.
const FACTORY: Array[String] = [
    "Paint",
    "Sketch",
    "Pencil",
    "Inked Pen",
    "Flat Brush",
    "Airbrush",
    "Blender",
    "Charcoal",
    "Wash",
    "Eraser",
]


## Ten empty slots, the shape a list is padded to.
static func empty() -> Array:
    var out: Array = []
    out.resize(COUNT)
    out.fill("")
    return out


## The ten slots a fresh profile has, [constant FACTORY] as an untyped list.
static func factory() -> Array:
    return sized(FACTORY)


## *val* as exactly [constant COUNT] strings, padded with empty slots or cut.
static func sized(val: Array) -> Array:
    var out := empty()
    for slot in mini(val.size(), out.size()):
        out[slot] = str(val[slot])
    return out
