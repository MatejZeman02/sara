## The sixteenth registry: the codecs a save can code a chunk's field with, asked
## for by name, so the save never names the library behind one. A module
## registers one with `context.codecs.register(name, encode, decode)`, the
## door's call, the way it announces a search source, and the JPEG XL
## module of `modules/sara-jxl` is the first (hard rule 6).
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Asked without an app.** A save and a load run as static calls from a
## worker, a suite or a tool script alike, so they ask through [method shared].
## `SaRegistries` installs the app's own, held weakly, so a suite that built
## registries of its own and let them go leaves nothing behind. With none
## installed, [method shared] answers an empty registry of this class's own,
## since the skeleton itself brings no codec, and [method named] answers null
## for every name there.
##
## **A view per module.** [method for_module] hands a module a view that files
## what it registers under the module and shares one list with the app's own,
## so a module that unloads takes its codecs with it.
class_name SaCodecRegistry
extends RefCounted

## The registry the app installed, weakly, or null.
static var _installed: WeakRef = null
## The registry answered while no app installed one, empty unless a suite
## registered into it.
static var _own: SaCodecRegistry = null

## `{"codec": Codec, "module": StringName}` apiece, in registration order, one
## array shared by every module's view of the registry.
var _entries: Array = []
## The module a view files what it registers under, empty for the app's own.
var _module_id: StringName = &""


## One codec, its name and the two calls that code a field of a chunk. Both
## take the texture's own bytes as Sara reads them back and say what they are:
## `encode(texels, width, height, channels, bytes_per_channel)` answers the
## coded stream, and `decode(stream, width, height, channels,
## bytes_per_channel)` answers the texels. Either answers an empty array when it
## refuses. Written by its constructor alone.
class Codec:
    extends RefCounted
    ## What a save asks for it by, `&"jxl"` for the JPEG XL module's.
    var name: StringName
    var _encoder: Callable
    var _decoder: Callable

    func _init(named: StringName, encoder: Callable, decoder: Callable) -> void:
        name = named
        _encoder = encoder
        _decoder = decoder

    ## *texels* coded to a stream, or an empty array when the codec refused.
    func encode(texels: PackedByteArray, width: int, height: int, channels: int, bytes_per_channel: int) -> PackedByteArray:
        return _encoder.call(texels, width, height, channels, bytes_per_channel)

    ## *stream* back as texels, or an empty array when it is not that picture.
    func decode(stream: PackedByteArray, width: int, height: int, channels: int, bytes_per_channel: int) -> PackedByteArray:
        return _decoder.call(stream, width, height, channels, bytes_per_channel)


## *held* is the list of another view, so a module's view and the app's hold
## one list. A new registry starts its own.
func _init(module_id: StringName = &"", held: Variant = null) -> void:
    _module_id = module_id
    _entries = held if held is Array else []


## The registry the app installed, or an empty one of this class's own.
static func shared() -> SaCodecRegistry:
    if _installed != null:
        var held: SaCodecRegistry = _installed.get_ref()
        if held != null:
            return held
    if _own == null:
        _own = SaCodecRegistry.new()
    return _own


## Makes *registry* the one [method shared] answers while something holds it.
static func install(registry: SaCodecRegistry) -> void:
    _installed = weakref(registry) if registry != null else null


## A view of this registry that files what it registers under *module_id*,
## which `SaContext.for_module` hands a module.
func for_module(module_id: StringName) -> SaCodecRegistry:
    return SaCodecRegistry.new(module_id, _entries)


## Registers the codec *codec_name*, coding with *encoder* and *decoder* as
## [SaCodecRegistry.Codec] says they are called, filed under *module_id* or
## else the view's module. A module names neither this class nor the codec's,
## only the door's `codecs`. Refused for no name, a callable that is not valid,
## or a name another module holds. The same module registering a name again
## replaces its entry where it stands.
func register(codec_name: StringName, encoder: Callable, decoder: Callable, module_id: StringName = &"") -> bool:
    if module_id.is_empty():
        module_id = _module_id
    if codec_name.is_empty():
        push_error("SaCodecRegistry: a codec needs a name.")
        return false
    if not encoder.is_valid() or not decoder.is_valid():
        push_error("SaCodecRegistry: codec '%s' needs an encode and a decode." % codec_name)
        return false
    var codec := Codec.new(codec_name, encoder, decoder)
    for at in _entries.size():
        var held: Codec = _entries[at]["codec"]
        if held.name != codec_name:
            continue
        if _entries[at]["module"] != module_id:
            push_error("SaCodecRegistry: '%s' is %s's already." % [codec_name, _entries[at]["module"]])
            return false
        _entries[at] = {"codec": codec, "module": module_id}
        return true
    _entries.append({"codec": codec, "module": module_id})
    return true


## Removes every codec *module_id* registered.
func unregister_module(module_id: StringName) -> void:
    for at in range(_entries.size() - 1, -1, -1):
        if _entries[at]["module"] == module_id:
            _entries.remove_at(at)


## The codec called *codec_name*, or null when no module registered one by it.
func named(codec_name: StringName) -> Codec:
    for held: Dictionary in _entries:
        var codec: Codec = held["codec"]
        if codec.name == codec_name:
            return codec
    return null


## The names registered, in registration order.
func names() -> Array[StringName]:
    var listed: Array[StringName] = []
    for held: Dictionary in _entries:
        var codec: Codec = held["codec"]
        listed.append(codec.name)
    return listed
