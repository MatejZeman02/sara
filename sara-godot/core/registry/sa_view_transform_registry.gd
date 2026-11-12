## The sixth registry: what the canvas can show that the document does not
## store, and which of it is showing.
##
## Holds the descriptors, the one active mode and each toggle's state, and
## hands the lot to a canvas material in `apply_to()`. It knows no shader
## code: the canvas owns the shader and a module's mode brings its own.
## `changed` fires on every registration and every state change, which is what
## the View menu and the canvas rebuild from.
class_name SaViewTransformRegistry
extends RefCounted

signal changed

## The ordinary view, which is no mode at all.
const NORMAL := &""

## What the ordinary view does, in the shape every descriptor's `tooltip` is in.
##
## It lives here rather than on a page because the ordinary view has no
## descriptor to carry it: it is the absence of a mode, so nothing registers it.
## Every surface that lists the modes lists this one beside them, and two
## surfaces each writing the sentence is a second copy.
const NORMAL_TOOLTIP := "The picture as the screen wants it: the document decoded, put into the display gamut and encoded again."

## What the ordinary view is called, for the same reason and in the same place
## as the sentence above it.
##
## The sentence moved here and the name did not, so the View menu wrote `Normal
## View` and the Display page's dropdown wrote `Display` for one row that is the
## absence of a mode. Two surfaces each writing the name is the same second copy
## the tooltip's own comment is about, and it drifted the moment somebody typed
## a different word.
const NORMAL_NAME := "Normal View"

var _transforms: Dictionary[StringName, SaViewTransformDescriptor] = {}
var _order: Array[StringName] = []
var _enabled: Dictionary[StringName, bool] = {}  # For toggles that keep their own state here
var mode: StringName = NORMAL


func register(descriptor: SaViewTransformDescriptor, module_id: StringName = &"") -> bool:
    if descriptor == null or String(descriptor.id).is_empty():
        push_error("SaViewTransformRegistry: a view transform needs an id.")
        return false
    if _transforms.has(descriptor.id):
        push_error("SaViewTransformRegistry: '%s' is already registered." % descriptor.id)
        return false
    descriptor.owner_module = module_id
    _transforms[descriptor.id] = descriptor
    _order.append(descriptor.id)
    changed.emit()
    return true


## Removes one transform, whoever registered it, so a module can take a
## built-in away.
func unregister(transform_id: StringName) -> void:
    if not _transforms.has(transform_id):
        return
    _drop(transform_id)
    changed.emit()


func unregister_module(module_id: StringName) -> void:
    var doomed: Array[StringName] = []
    for transform_id: StringName in _order:
        if _transforms[transform_id].owner_module == module_id:
            doomed.append(transform_id)
    if doomed.is_empty():
        return
    for transform_id in doomed:
        _drop(transform_id)
    changed.emit()


func _drop(transform_id: StringName) -> void:
    _transforms.erase(transform_id)
    _order.erase(transform_id)
    _enabled.erase(transform_id)
    # A mode whose module has gone cannot stay active: the canvas would be
    # holding a shader nobody owns.
    if mode == transform_id:
        mode = NORMAL


func has(transform_id: StringName) -> bool:
    return _transforms.has(transform_id)


func get_descriptor(transform_id: StringName) -> SaViewTransformDescriptor:
    return _transforms.get(transform_id)


## What *transform_id* does, for a surface that wants to say so.
##
## Answers [constant NORMAL_TOOLTIP] for [constant NORMAL] and the descriptor's
## own otherwise, so a caller listing the ordinary view beside the modes needs
## no special case, and "" for an id nobody registered.
func tooltip_for(transform_id: StringName) -> String:
    if transform_id == NORMAL:
        return NORMAL_TOOLTIP
    var descriptor := get_descriptor(transform_id)
    return descriptor.tooltip if descriptor != null else ""


## Every id, toggles and modes together, in menu order.
func list_ids() -> Array[StringName]:
    var ids := _order.duplicate()
    ids.sort_custom(_by_sort_order)
    return ids


func list_toggles() -> Array[SaViewTransformDescriptor]:
    return _of_kind(SaViewTransformDescriptor.Kind.TOGGLE)


func list_modes() -> Array[SaViewTransformDescriptor]:
    return _of_kind(SaViewTransformDescriptor.Kind.MODE)


func _of_kind(kind: SaViewTransformDescriptor.Kind) -> Array[SaViewTransformDescriptor]:
    var out: Array[SaViewTransformDescriptor] = []
    for transform_id: StringName in list_ids():
        var descriptor: SaViewTransformDescriptor = _transforms[transform_id]
        if descriptor.kind == kind:
            out.append(descriptor)
    return out


func _by_sort_order(a: StringName, b: StringName) -> bool:
    var da: SaViewTransformDescriptor = _transforms[a]
    var db: SaViewTransformDescriptor = _transforms[b]
    if da.sort_order != db.sort_order:
        return da.sort_order < db.sort_order
    return _order.find(a) < _order.find(b)


# --- Toggles ------------------------------------------------------------------


func set_enabled(transform_id: StringName, enabled: bool) -> bool:
    var descriptor := get_descriptor(transform_id)
    if descriptor == null or descriptor.kind != SaViewTransformDescriptor.Kind.TOGGLE:
        return false
    if descriptor.on_toggle.is_valid():
        descriptor.on_toggle.call(enabled)
    else:
        _enabled[transform_id] = enabled
    changed.emit()
    return true


func is_enabled(transform_id: StringName) -> bool:
    var descriptor := get_descriptor(transform_id)
    if descriptor == null or descriptor.kind != SaViewTransformDescriptor.Kind.TOGGLE:
        return false
    if descriptor.read_enabled.is_valid():
        var enabled: bool = descriptor.read_enabled.call()
        return enabled
    var stored: bool = _enabled.get(transform_id, false)
    return stored


# --- The one active mode ------------------------------------------------------


## Makes *transform_id* the active mode, or NORMAL for none. A toggle's id is
## refused, and so is one nobody registered.
func set_mode(transform_id: StringName) -> bool:
    if transform_id != NORMAL:
        var descriptor := get_descriptor(transform_id)
        if descriptor == null or descriptor.kind != SaViewTransformDescriptor.Kind.MODE:
            return false
    if mode == transform_id:
        return true
    mode = transform_id
    changed.emit()
    return true


## The active mode's own shader, or null when the built-in canvas shader
## implements the mode or there is none.
func mode_shader() -> Shader:
    var descriptor := get_descriptor(mode)
    return descriptor.shader if descriptor != null else null


## What the canvas shader's `view_mode` uniform should say: the active
## built-in mode's value, or 0 for the ordinary view and for a module's mode,
## which is running its own shader.
func mode_index() -> int:
    var descriptor := get_descriptor(mode)
    if descriptor == null or descriptor.shader != null:
        return 0
    return descriptor.view_mode


# --- The material -------------------------------------------------------------


## Writes the whole state onto a canvas material: the mode, then every
## toggle's uniforms through its own `apply`.
func apply_to(material: ShaderMaterial) -> void:
    if material == null:
        return
    material.set_shader_parameter("view_mode", mode_index())
    for descriptor in list_toggles():
        if descriptor.apply.is_valid():
            descriptor.apply.call(material, is_enabled(descriptor.id))
