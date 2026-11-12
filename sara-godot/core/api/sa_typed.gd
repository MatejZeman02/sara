## A Dictionary typed where it enters.
##
## `JSON.parse_string`, a `ConfigFile` value, a `.sad` header and a module's
## return all hand back a plain `Dictionary`, and a typed one refuses a plain
## one at runtime: the assignment or the call stops the function with a script
## error rather than converting. Every place such a value enters a typed
## annotation goes through one of these, so the conversion is one call and not
## a pair of lines repeated at each door, and a value that was typed already
## comes through as it was.
##
## A `class_name` rather than a preload, for the reason `SaReportShapes` gives:
## a module reads its own files through this too.
extends RefCounted

class_name SaTyped


## *raw* keyed by String, the shape of a JSON object, a module's parameters and
## a report, or an empty one when it is not a Dictionary at all, which is what
## every reader here did with a missing or malformed key. A StringName key
## becomes its String.
static func strings(raw: Variant) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = {}
    if raw is Dictionary:
        var plain: Dictionary = raw
        out.assign(plain)
    return out


## *raw* as regions, grid position to a Rect2i in chunk-local pixels, the shape
## a module hands `SaDocument.invalidate_chunk_regions`, or empty when it is
## not a Dictionary.
static func regions(raw: Variant) -> Dictionary[Vector2i, Rect2i]:
    var out: Dictionary[Vector2i, Rect2i] = {}
    if raw is Dictionary:
        var plain: Dictionary = raw
        out.assign(plain)
    return out


## The keys of *raw* as a set of grid positions, whatever its values were: a
## layer's chunk table, a set, or regions.
static func positions(raw: Variant) -> Dictionary[Vector2i, bool]:
    var out: Dictionary[Vector2i, bool] = {}
    if raw is Dictionary:
        for grid_pos: Vector2i in raw:
            out[grid_pos] = true
    return out


## *raw* as a chunk table, grid position to chunk, the shape of
## `SaSelection.chunks`, which a module assigns a table of its own to, or
## empty when it is not a Dictionary.
static func chunks(raw: Variant) -> Dictionary[Vector2i, SaChunk]:
    var out: Dictionary[Vector2i, SaChunk] = {}
    if raw is Dictionary:
        var plain: Dictionary = raw
        out.assign(plain)
    return out


## *raw* when it is an Array, or an empty one when it is anything else, the
## shape of a list read back from a `ConfigFile` or a JSON document.
static func list(raw: Variant) -> Array:
    var out: Array = raw if raw is Array else []
    return out


## *value* as an int when it is a number or a bool, truncated as `int()` would,
## text that spells a number parsed as `int()` parses it, or *fallback* when it
## is anything else, text that spells no number among it.
## JSON hands every number back as a float, so a `.sad` header's `3` arrives as
## `3.0`, and an XML attribute is always text, so an ORA offset arrives as
## `"12"`. The typed local is where the Variant becomes an int, which is what
## makes the read safe rather than a constructor handed a Variant.
static func whole(value: Variant, fallback: int = 0) -> int:
    if value is String or value is StringName:
        var said: String = value
        return said.to_int() if said.is_valid_float() else fallback
    if not _is_number(value):
        return fallback
    var out: int = value
    return out


## *value* as a float when it is a number or a bool, text that spells a number
## parsed as `float()` parses it, or *fallback*, as `whole`.
static func real(value: Variant, fallback: float = 0.0) -> float:
    if value is String or value is StringName:
        var said: String = value
        return said.to_float() if said.is_valid_float() else fallback
    if not _is_number(value):
        return fallback
    var out: float = value
    return out


## *value* as a flag when it is a bool or a number, which reads as `bool()`
## reads it, nought false and anything else true, or *fallback*.
static func flag(value: Variant, fallback: bool = false) -> bool:
    if not _is_number(value):
        return fallback
    var out: bool = value
    return out


## *value* as a String when it is text, a StringName coming back as its String,
## or *fallback* when it is anything else.
static func text(value: Variant, fallback: String = "") -> String:
    if not (value is String or value is StringName):
        return fallback
    var out: String = value
    return out


## The number *raw* holds at *key* as an int, or *fallback* when the key is
## absent or holds anything but a number, as `whole`.
static func int_at(raw: Dictionary, key: Variant, fallback: int) -> int:
    return whole(raw.get(key, fallback), fallback)


## The number *raw* holds at *key* as a float, or *fallback*, as `real`.
static func float_at(raw: Dictionary, key: Variant, fallback: float) -> float:
    return real(raw.get(key, fallback), fallback)


## The flag *raw* holds at *key*, or *fallback*, as `flag`.
static func bool_at(raw: Dictionary, key: Variant, fallback: bool) -> bool:
    return flag(raw.get(key, fallback), fallback)


## The text *raw* holds at *key* as a String, or *fallback*, as `text`.
static func text_at(raw: Dictionary, key: Variant, fallback: String) -> String:
    return text(raw.get(key, fallback), fallback)


## The text *raw* holds at *key* as a StringName, or *fallback*, as `text`.
static func name_at(raw: Dictionary, key: Variant, fallback: StringName) -> StringName:
    return StringName(text(raw.get(key, fallback), fallback))


static func _is_number(value: Variant) -> bool:
    return value is int or value is float or value is bool
