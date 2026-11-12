## A binding target for a setting that is a call and not a property.
##
## A declared row binds to an object and a property path, and reads and writes
## through `get_indexed` and `set_indexed`. Some settings have no property to
## name: a docker option is `SaSettings.get_docker_option(category, key)` and
## its setter, and the settings folder is `SaSettingsFile.set_pointer(path)`.
## This object stands in for them. Its `_get` hands the property name to a
## reader and its `_set` hands the name and the value to a writer, and both
## engine calls reach a script's `_get` and `_set`, so the row needs no change
## to bind to one:
##
##     var options:= SaPageBinding.new(
##         func(key: StringName) -> Variant: return SaSettings.get_docker_option("layers", key),
##         func(key: StringName, value: Variant) -> void: SaSettings.set_docker_option("layers", key, value))
##     rows.toggle(tr("Thumbnails"), options, ^"thumbnails")
##
## After a write it emits `changed`, which the page's watch listens to, so the
## page re-reads what the target made of the value: a folder the settings
## answer as "" shows the default folder rather than what was typed.
##
## **The two callables reach autoloads and statics only**, never the page that
## declares the row. The page holds its rows, a row holds this object, and a
## callable bound to the page closes that into a ring GDScript never collects.
## A lambda written inside a page's
## `build` captures nothing of the page as long as it names no member of it.
class_name SaPageBinding
extends RefCounted

## After every write, with no argument, which is the shape `SaPageWatch` calls.
signal changed

var _reader: Callable = Callable()
var _writer: Callable = Callable()


## *reader* is `func(property: StringName) -> Variant` and answers null for a
## name it does not know, which the engine then reads as unhandled. *writer* is
## `func(property: StringName, value: Variant) -> void`.
func _init(reader: Callable, writer: Callable) -> void:
    _reader = reader
    _writer = writer


func _get(property: StringName) -> Variant:
    if not _reader.is_valid():
        return null
    return _reader.call(property)


func _set(property: StringName, value: Variant) -> bool:
    if not _writer.is_valid():
        return false
    _writer.call(property, value)
    changed.emit()
    return true
