## The engines the skeleton constructs, asked for by role name rather than
## by class.
##
## A module should be able to change, add or remove almost anything by
## subclassing a core class and re-implementing what it wants, and a
## construction site that names the class, `SaCrop.new(document)`, would never
## build its version. So the Canvas Size dialog, the crop-to-selection command
## and the crop tool look up the role `crop` here, and a module that registers
## a subclass under the same role is what the next lookup answers.
##
## A role holds a `Script`, never an instance, because an engine is built
## per document or per call and the constructor arguments are the caller's.
## What the caller does with the script is its own affair: `new(document)`
## for the crop, the transform, the resample, the flood and the gradient,
## and a static call for the selection filters, which are functions over a
## selection and have no instance to build.
##
## Unlike the other registries, a second registration under a role is not
## refused, it is the point: the skeleton registers its own engines first
## and a module registers over them. The registrations of a role are kept as
## a stack, the newest on top, so unloading the module on top uncovers the
## one it replaced rather than leaving the role empty. The console names
## both modules when a registration lands on a held role, so a painter who
## asks why the crop behaves differently has the answer in the log, and a
## module that registers a role twice by accident is told so too.
class_name SaRoleRegistry
extends RefCounted

## Emitted when a role is registered, replaced or removed.
signal changed

## Emitted when a registration lands on a role that already had one, with
## both owners, so a host can put the line where it wants it. The line is
## also printed, so the console carries it too.
signal replaced(role: StringName, previous_module: StringName, module: StringName)

## Each role's claims, `{"script": Script, "module": StringName}` apiece and
## oldest first. The last entry is the one a lookup answers.
var _claims: Dictionary[StringName, Array] = {}
## First-registration order of the roles.
var _order: Array[StringName] = []


## Registers *script* under *role* for *module_id*, on top of whatever the
## role already held, and says so on the console with both module ids.
## Refused only for an empty role or no script.
func register(role: StringName, script: Script, module_id: StringName = &"") -> bool:
    if String(role).is_empty() or script == null:
        push_error("SaRoleRegistry: a role needs a name and a script.")
        return false
    if _claims.has(role):
        var previous: StringName = _claims[role].back()["module"]
        print(claim_line(role, previous, module_id))
        replaced.emit(role, previous, module_id)
    else:
        _claims[role] = []
        _order.append(role)
    var claim: Dictionary[String, Variant] = {"script": script, "module": module_id}
    _claims[role].append(claim)
    changed.emit()
    return true


## The console line for a role claimed twice. A function rather than a
## literal in `register`, so a test reads the same words it asserts.
static func claim_line(role: StringName, previous_module: StringName, module_id: StringName) -> String:
    return (
        "[Sara] role '%s' was registered by '%s' and is now registered by '%s', which the lookups answer from here on."
        % [role, previous_module, module_id]
    )


## Removes the registration on top of *role*, uncovering the one under it.
## A role with one registration is gone after this and the next lookup
## answers null.
func unregister(role: StringName) -> void:
    if not _claims.has(role):
        return
    _claims[role].pop_back()
    _drop_if_empty(role)
    changed.emit()


## Removes every registration *module_id* made, wherever it sits in a
## role's stack, so a module that replaced the crop and is then unloaded
## leaves the skeleton's crop where it was.
func unregister_module(module_id: StringName) -> void:
    var touched := false
    for role: StringName in _order.duplicate():
        var kept: Array = _claims[role].filter(
            func(claim: Dictionary[String, Variant]) -> bool: return claim["module"] != module_id
        )
        if kept.size() == _claims[role].size():
            continue
        _claims[role] = kept
        _drop_if_empty(role)
        touched = true
    if touched:
        changed.emit()


func _drop_if_empty(role: StringName) -> void:
    if _claims[role].is_empty():
        _claims.erase(role)
        _order.erase(role)


func has(role: StringName) -> bool:
    return _claims.has(role)


## The script on top of *role*, or null when nothing is registered.
func script_for(role: StringName) -> Script:
    if not _claims.has(role):
        return null
    return _claims[role].back()["script"]


## The module whose registration is on top of *role*, or an empty name when
## nothing is registered.
func owner_of(role: StringName) -> StringName:
    if not _claims.has(role):
        return &""
    return _claims[role].back()["module"]


## Every module holding *role*, oldest first. Two names here is what "two
## modules claim the same thing" looks like after the console line scrolled.
func claimants_of(role: StringName) -> Array[StringName]:
    var out: Array[StringName] = []
    for claim: Dictionary[String, Variant] in _claims.get(role, []):
        out.append(claim["module"])
    return out


## Every role, in first-registration order.
func list_roles() -> Array[StringName]:
    return _order.duplicate()
