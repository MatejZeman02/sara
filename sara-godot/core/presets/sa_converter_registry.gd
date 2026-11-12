## The preset converters modules offer, keyed by the pair of engine names a
## converter goes from and to.
##
## One module implements the conversion from one engine's preset to another's,
## and an engine can be asked whether it converts from a given engine, so a
## painter with a shelf of stamp presets is not starting from nothing. The
## converters are the engines' own to write, so the skeleton registers none and
## this registry is the whole of what it adds: a place to put one and the
## question the preset store asks of it.
##
## A converter is a `Callable` taking the preset as loaded, its settings with
## its tags and its engine in the metadata, and answering a new settings
## resource of the target engine, or null when it cannot. It never writes the
## preset it was handed and never saves anything: the store owns what lands
## on disk, so a converted preset is always a new preset beside the original
## and never a replacement, whoever wrote the converter.
##
## Here beside the store rather than in `core/registry`, because the store is
## the one thing that asks it, and built by every `SaContext` rather than
## handed to one, so a context a test builds bare still takes a module's
## converter and the stamp module's suites need no fixture of their own.
##
## One converter per pair, and a second registration of a pair is refused,
## unlike a role. Two modules each claiming stamp to noise is a clash for a
## painter to hear about, not a replacement to stack, because the menu offers
## the target engine once and would have to pick one of the two in silence.
class_name SaConverterRegistry
extends RefCounted

## Emitted when a converter is added or removed, so a menu built before the
## modules loaded still offers what they registered.
signal changed

## "from>to" -> {"from", "to", "converter": Callable, "module"}.
var _pairs: Dictionary[String, Dictionary] = {}
## Registration order of the keys above, which is the order the menu lists.
var _order: Array[String] = []


## Registers *converter* for presets of engine *from_engine* becoming presets of
## engine *to_engine*, owned by *module_id*. Refused for an empty engine, a pair of
## one engine, an invalid callable and a pair already held.
func register(from_engine: StringName, to_engine: StringName, converter: Callable, module_id: StringName = &"") -> bool:
    if String(from_engine).is_empty() or String(to_engine).is_empty() or from_engine == to_engine:
        push_error("SaConverterRegistry: a converter needs two different engines.")
        return false
    if not converter.is_valid():
        push_error("SaConverterRegistry: the converter from '%s' to '%s' is not callable." % [from_engine, to_engine])
        return false
    var key := _key(from_engine, to_engine)
    if _pairs.has(key):
        push_error(
            (
                "SaConverterRegistry: '%s' to '%s' is already converted by '%s', and '%s' was refused."
                % [from_engine, to_engine, _pairs[key]["module"], module_id]
            )
        )
        return false
    _pairs[key] = {"from": from_engine, "to": to_engine, "converter": converter, "module": module_id}
    _order.append(key)
    changed.emit()
    return true


## Removes the converter of one pair.
func unregister(from_engine: StringName, to_engine: StringName) -> void:
    var key := _key(from_engine, to_engine)
    if not _pairs.has(key):
        return
    _pairs.erase(key)
    _order.erase(key)
    changed.emit()


## Removes every converter *module_id* registered, so unloading is not the
## module's bookkeeping.
func unregister_module(module_id: StringName) -> void:
    var doomed: Array[String] = []
    for key: String in _order:
        if _pairs[key]["module"] == module_id:
            doomed.append(key)
    for key in doomed:
        _pairs.erase(key)
        _order.erase(key)
    if not doomed.is_empty():
        changed.emit()


## Whether an engine converts presets of *from_engine* into its own, *to_engine*.
func converts(from_engine: StringName, to_engine: StringName) -> bool:
    return _pairs.has(_key(from_engine, to_engine))


## The converter of one pair, or an empty callable when none is registered.
func converter_for(from_engine: StringName, to_engine: StringName) -> Callable:
    var key := _key(from_engine, to_engine)
    return _pairs[key]["converter"] if _pairs.has(key) else Callable()


## The module holding one pair, or an empty name when nothing does.
func owner_of(from_engine: StringName, to_engine: StringName) -> StringName:
    var key := _key(from_engine, to_engine)
    return _pairs[key]["module"] if _pairs.has(key) else &""


## Every engine a preset of *from_engine* can become, in registration order: the
## engines that answer yes, which is what the presets docker's Convert to
## rows list.
func targets_from(from_engine: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for key: String in _order:
        if _pairs[key]["from"] == from_engine:
            out.append(_pairs[key]["to"])
    return out


## Every pair, as `[from, to]`, in registration order.
func list_pairs() -> Array:
    var out: Array = []
    for key: String in _order:
        out.append([_pairs[key]["from"], _pairs[key]["to"]])
    return out


## One string per pair. `>` because no engine name carries one: an engine is
## a `PRESET_ENGINE` constant, `&"stamp"` or a module's own word.
static func _key(from_engine: StringName, to_engine: StringName) -> String:
    return "%s>%s" % [from_engine, to_engine]
