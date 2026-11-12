## The fourteenth registry: the picture formats Sara opens and exports. A module
## registers an [SaImageFormat] through [method SaContext.register_image_format],
## and the skeleton registers its four the same way (hard rule 6).
##
## **The order is the order registered**, which is the order the Export dialog
## lists and the open dialog's Image line names. The skeleton registers PNG,
## JPEG, WebP and EXR, and the image formats module of the base modules adds
## TIFF, Radiance and OpenRaster after them, so the dialog reads PNG, JPG, EXR,
## TIFF, OpenRaster as it always did.
##
## **Asked without an app.** [SaImageImport] and the dialogs ask through
## [method shared], since a picture is read by a static call from a suite, a
## tool script or a dropped file alike. `SaRegistries` installs the app's own
## once the skeleton has registered into it, and it is held weakly, so a suite
## that built registries of its own and let them go leaves nothing behind. With
## none installed, the skeleton registers its formats into one of this class's
## own the first time one is asked for, through the same call it makes in the
## app, so a process with no app still reads and writes the pictures it always
## did.
class_name SaImageFormatRegistry
extends RefCounted

## Registration and removal, which the Export dialog refills its list on.
signal changed

const SkeletonImageFormats = preload("res://core/loader/image_formats/skeleton_image_formats.gd")

## How many first bytes a claim is shown. PNG's signature is eight, WebP's name
## sits at twelve, and a Radiance file's first line is eleven with its end.
const HEAD_BYTES: int = 16

## The registry the app installed, weakly, or null.
static var _installed: WeakRef = null
## The registry built for a process with no app, the first time one was asked.
static var _own: SaImageFormatRegistry = null

## `{"format": SaImageFormat, "module": StringName}` apiece, in registration order.
var _entries: Array[Dictionary] = []


## The registry the app installed, or one with the skeleton's formats in it.
static func shared() -> SaImageFormatRegistry:
    if _installed != null:
        var held: SaImageFormatRegistry = _installed.get_ref()
        if held != null:
            return held
    if _own == null:
        _own = SaImageFormatRegistry.new()
        var context := SaContext.new(Callable(), Callable(), SkeletonImageFormats.MODULE_ID)
        context.image_formats = _own
        SkeletonImageFormats.register(context)
    return _own


## Makes *registry* the one [method shared] answers while something holds it.
static func install(registry: SaImageFormatRegistry) -> void:
    _installed = weakref(registry) if registry != null else null


## Registers *format* for *module_id*. Refused for no format, no id, no
## extension, or an id another module holds. The same module registering an id
## again replaces its entry where it stands.
func register(format: SaImageFormat, module_id: StringName = &"") -> bool:
    if format == null or format.id.is_empty() or format.extensions.is_empty():
        push_error("SaImageFormatRegistry: a format needs an id and an extension.")
        return false
    for at in _entries.size():
        var held: SaImageFormat = _entries[at]["format"]
        if held.id != format.id:
            continue
        if _entries[at]["module"] != module_id:
            push_error("SaImageFormatRegistry: '%s' is %s's already." % [format.id, _entries[at]["module"]])
            return false
        _entries[at] = {"format": format, "module": module_id}
        changed.emit()
        return true
    _entries.append({"format": format, "module": module_id})
    changed.emit()
    return true


## Removes every format *module_id* registered.
func unregister_module(module_id: StringName) -> void:
    var kept: Array[Dictionary] = []
    for held: Dictionary in _entries:
        if held["module"] != module_id:
            kept.append(held)
    if kept.size() == _entries.size():
        return
    _entries = kept
    changed.emit()


## Every format, in registration order.
func all() -> Array[SaImageFormat]:
    var formats: Array[SaImageFormat] = []
    for held: Dictionary in _entries:
        formats.append(held["format"])
    return formats


## The format called *format_id*, or null.
func find(format_id: StringName) -> SaImageFormat:
    for format in all():
        if format.id == format_id:
            return format
    return null


## The formats that open as one picture, in order.
func flat() -> Array[SaImageFormat]:
    return all().filter(func(format: SaImageFormat) -> bool: return format.reads())


## The formats that open as a document with its layers, in order.
func layered() -> Array[SaImageFormat]:
    return all().filter(func(format: SaImageFormat) -> bool: return format.opens_layers())


## The formats Export writes, in the order its list shows them.
func exported() -> Array[SaImageFormat]:
    return all().filter(func(format: SaImageFormat) -> bool: return format.writes())


## The first of *formats* whose extensions *path* ends in, or null.
static func named_in(formats: Array[SaImageFormat], path: String) -> SaImageFormat:
    for format in formats:
        if format.names(path):
            return format
    return null


## The flat format *path*'s name claims, or null.
func flat_named(path: String) -> SaImageFormat:
    return named_in(flat(), path)


## The layered format *path*'s name claims, or null.
func layered_named(path: String) -> SaImageFormat:
    return named_in(layered(), path)


## The format Export writes for *path*'s name, or null.
func exported_named(path: String) -> SaImageFormat:
    return named_in(exported(), path)


## The flat format whose own claim *head* answers, or null.
func claiming(head: PackedByteArray) -> SaImageFormat:
    for format in flat():
        if format.claims.is_valid() and format.claims.call(head) == true:
            return format
    return null


## The extensions of *formats*, in order.
static func extensions_of(formats: Array[SaImageFormat]) -> PackedStringArray:
    var extensions := PackedStringArray()
    for format in formats:
        extensions.append_array(format.extensions)
    return extensions


## Every extension a file opens by, the flat formats' first.
func open_extensions() -> PackedStringArray:
    var extensions := extensions_of(flat())
    extensions.append_array(extensions_of(layered()))
    return extensions


## The open dialog's line for every flat format, under *word* in the painter's
## language. The word alone is translated, since the patterns read the same in
## every language and a catalogue could never hold the whole line.
func image_filter(word: String) -> String:
    var patterns := Array(extensions_of(flat())).map(func(extension: String) -> String: return "*." + extension)
    return "%s ; %s" % [", ".join(patterns), TranslationServer.translate(word)]


## The open dialog's lines for the layered formats, in order, each in the
## painter's language.
func layered_filters() -> PackedStringArray:
    var lines := PackedStringArray()
    for format in layered():
        lines.append(TranslationServer.translate(format.open_filter))
    return lines
