## One saved look: the filter layers of a group in their order, each with its
## records, blend mode, opacity and visibility, and the group's own blending.
## The file the Filters docker's Looks part writes through [SaPresetStore] and
## reads back, and the layers it puts into a document again.
##
## **What a look is.** The workflow: "A group of filter layers is a
## look. Duplicate the group, switch one member off, compare. Save the group as
## a preset the way a brush is saved." So it is saved the way a brush preset
## is, one `.tres` by name through the store brush presets and gradients use,
## in a folder of its own beside theirs, so neither list offers the other's.
##
## **What it keeps.** A member's records are their keys, values and switches,
## the shape `SaSadFile.write_filters` gives a node's records on disk, and its
## name, kind, blend mode, opacity and visibility come with them. The group
## keeps its isolation, its mode, its opacity and any record of its own,
## because the members adjust the backdrop the group hands them, and the look's
## picture is that. Masks are painted per picture, so a look keeps none, a
## member's, a record's or the group's.
##
## **Only filter layers.** A look is refused for anything but a group whose
## every member is an adjustment layer, the filter layer, and
## [method refusal] says why in a sentence. A paint layer in the group would
## carry paint, which is the picture and not the look.
##
## A file of its own rather than an inner class of the part, because
## `ResourceSaver` takes the `script` line of a `.tres` from the script's
## `resource_path`, which is what `SaFilterPreset` found: a look nested in the
## part would save a file holding no field and come back as a bare `Resource`.
extends Resource

## Where the looks go, under the data root beside `filter_presets`, and apart
## from it because the store lists a whole folder.
const FOLDER := "filter_looks"

## The history row an add is, which the Undo History docker shows.
const ADD_STEP := "Add Look"

## Where [method store] points a store. A test points this somewhere disposable
## and puts it back, which is the only reason it is a variable rather than the
## folder above.
static var root: String = SaDataRoot.path(FOLDER)

## The members, bottom first, the order they composite in. Each is
## `{"name", "type", "blend_mode", "opacity", "visible", "records"}`, the
## records each `{"key", "params", "enabled"}`.
@export var members: Array[Dictionary] = []

## Whether the group composites as one, which is what its members read below
## them.
@export var isolated: bool = false

## The group's own mode and opacity, read only when it is isolated.
@export var blend_mode: StringName = SaLayer.BLEND_MODE.NORMAL
@export var opacity: float = 1.0

## Records attached to the group itself, in the members' shape.
@export var group_records: Array[Dictionary] = []


## A look of *group*, which [method refusal] has let through, or an empty one
## for the loader, which builds every resource with no argument.
func _init(group: SaLayer = null) -> void:
    if group == null:
        return
    isolated = group.isolated
    blend_mode = group.blend_mode
    opacity = group.opacity
    group_records = _records_of(group)
    for member in members_of(group):
        var kept := {
            "name": String(member.name),
            "type": String(member.layer_type),
            "blend_mode": String(member.blend_mode),
            "opacity": member.opacity,
            "visible": member.visible,
            "records": _records_of(member),
        }
        members.append(kept)


## The store every look is listed, saved, renamed and deleted through.
static func store() -> SaPresetStore:
    var made := SaPresetStore.new()
    made.dir = root
    return made


## Why *layer* cannot be saved as a look, or an empty string when it can.
static func refusal(layer: SaLayer) -> String:
    if layer == null:
        return TranslationServer.translate("No layer is active, so there is no group to save as a look.")
    if not layer.is_group:
        return (
            TranslationServer.translate("'%s' is not a group. A look is a group of filter layers, so save their group.")
            % layer.name
        )
    var held := members_of(layer)
    if held.is_empty():
        return TranslationServer.translate("'%s' holds no layer, so it has no look to save.") % layer.name
    for member in held:
        if not member.is_adjustment():
            return (
                TranslationServer.translate("'%s' in '%s' is not a filter layer, and a look keeps filter layers only.")
                % [member.name, layer.name]
            )
    return ""


## The layers directly inside *group*, bottom first.
static func members_of(group: SaLayer) -> Array[SaLayer]:
    var held: Array[SaLayer] = []
    var document := group.get_parent() if group != null else null
    if document == null:
        return held
    for child in document.get_children():
        var layer := child as SaLayer
        if layer != null and layer != group and SaLayerStack.parent_of(layer) == group:
            held.append(layer)
    return held


## Why the look cannot go into *document* with the kinds *types* registers, or
## an empty string when it can. A member's kind comes from a module, and a
## module not installed here leaves the member nothing to be.
func place_refusal(document: SaDocument, types: SaLayerTypeRegistry) -> String:
    if document == null:
        return TranslationServer.translate("There is no document to add the look to.")
    if members.is_empty():
        return TranslationServer.translate("The look holds no filter layer.")
    for member: Dictionary in members:
        var kind := StringName(String(member.get("type", "")))
        var known := types.get_descriptor(kind) if types != null and types.has(kind) else null
        if known == null or known.input != SaLayerTypeDescriptor.INPUT_BELOW:
            return (
                TranslationServer.translate("'%s' is a kind of layer no installed module registers, so the look cannot be added.")
                % String(member.get("name", ""))
            )
    return ""


## Puts the look into *document* above its active layer, in that layer's group,
## as a new group named after *title* holding a layer for each member, and
## answers them bottom first, the group last, the block
## `SaLayerOps.commit_added` records as one step. Empty when [method
## place_refusal] has a reason, and then nothing is put in.
func place(document: SaDocument, types: SaLayerTypeRegistry, title: String) -> Array[SaLayer]:
    var block: Array[SaLayer] = []
    if not place_refusal(document, types).is_empty():
        return block
    var active := document.active_layer
    var at := active.get_index() + 1 if active != null and active.get_parent() == document else document.get_child_count()
    var group := SaLayer.new()
    group.is_group = true
    group.schema = SaFieldSpec.schema_for_space(document.color_space)
    group.name = _free_name(document, title, [])
    group.group = SaLayerStack.parent_of(active)
    group.isolated = isolated
    group.blend_mode = blend_mode
    group.opacity = opacity
    group.filters = _built_records(group_records)
    for member: Dictionary in members:
        var layer := SaLayer.new()
        layer.schema = SaFieldSpec.schema_for_space(document.color_space)
        types.apply_to(layer, StringName(String(member.get("type", ""))), document.color_space)
        layer.name = _free_name(document, String(member.get("name", "")), block)
        layer.blend_mode = StringName(String(member.get("blend_mode", SaLayer.BLEND_MODE.NORMAL)))
        layer.opacity = float(member.get("opacity", 1.0))
        layer.visible = bool(member.get("visible", true))
        layer.filters = _built_records(member.get("records", []))
        layer.group = group
        block.append(layer)
    block.append(group)
    for layer in block:
        document.add_child(layer)
        document.move_child(layer, at)
        layer.mark_all_unresolved()
        at += 1
    document.set_active_layer(group)
    return block


## *node*'s records in the shape a look keeps, without their masks.
static func _records_of(node: SaLayer) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for record in node.filters:
        if record != null:
            out.append({"key": String(record.key), "params": record.parameters.duplicate(true), "enabled": record.enabled})
    return out


## Fresh records from *kept*, each a record of its own, so a look added twice
## gives two layers that never share a record.
static func _built_records(kept: Variant) -> Array[SaAttachedFilter]:
    var out: Array[SaAttachedFilter] = []
    if not kept is Array:
        return out
    for item: Variant in kept:
        var entry := SaTyped.strings(item)
        var key := String(entry.get("key", ""))
        if key.is_empty():
            continue
        var record := SaAttachedFilter.new(StringName(key), SaTyped.strings(entry.get("params", {})))
        record.enabled = bool(entry.get("enabled", true))
        out.append(record)
    return out


## *wanted* when no layer of *document* and none of *placing* has it, else
## the first of `wanted 2`, `wanted 3` and on that none has. Godot would name
## a second child "Curves2" itself, so the number is given here the way
## Duplicate Layer gives it. A look's name is a file's, and a mark a node's
## name cannot hold is a space, as `SaFilterConversion.layer_name_for` makes it.
static func _free_name(document: SaDocument, wanted: String, placing: Array[SaLayer]) -> String:
    var words := wanted
    for mark: String in [".", ":", "@", "/", '"', "%"]:
        words = words.replace(mark, " ")
    words = " ".join(words.split(" ", false))
    var base: String = words if not words.is_empty() else String(TranslationServer.translate("Look"))
    var candidate := base
    var number := 2
    while _taken(document, candidate, placing):
        candidate = "%s %d" % [base, number]
        number += 1
    return candidate


static func _taken(document: SaDocument, candidate: String, placing: Array[SaLayer]) -> bool:
    if document.has_node(NodePath(candidate)):
        return true
    for layer in placing:
        if String(layer.name) == candidate:
            return true
    return false
