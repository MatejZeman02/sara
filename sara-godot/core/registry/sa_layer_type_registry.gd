## Every kind of layer the application knows about, described rather than
## hardcoded. The fifth registry.
##
## The registry holds descriptors, not layers. A layer is built by
## [method apply_to], which is the only supported way to put a type's schema and
## resolve hook onto an `SaLayer`: a module that constructs an `SaLayer` and pokes
## its `schema` is doing what this exists to replace.
##
## `SaLayer.schema` and `resolve_hook` stay public and writable. The descriptor is
## the supported route, not a lock.
class_name SaLayerTypeRegistry
extends RefCounted

## Emitted when a type is added or removed, so UI built before modules load still
## updates. This is what lets the loader run before the layers docker exists.
signal changed

var _descriptors: Dictionary[StringName, SaLayerTypeDescriptor] = {}
var _order: Array[StringName] = []

## What a layer composites, the one answer the compositor and the fold ask
## instead of a flag each. Paint reads its chunks, a group its members, a
## generated layer its kernel, an adjustment the backdrop below it, and an
## effect its named input through its filters.
enum Composites { PAINT, GROUP, GENERATED, ADJUSTMENT, EFFECT }

## (type_id, registry) -> void, what picking a kind's row in the search does:
## the Layer menu's own row for the kind, which only the app holds. Bound where
## the app wires the search, and while it is not the rows are listed dimmed.
## The registry is handed in at the call, so what is bound never holds it.
var search_pick: Callable = Callable()


func register(descriptor: SaLayerTypeDescriptor, module_id: StringName = &"") -> bool:
    if descriptor == null or not descriptor.is_valid():
        push_error("SaLayerTypeRegistry: refusing a layer type with no id or an empty schema.")
        return false
    if _descriptors.has(descriptor.id):
        push_error("SaLayerTypeRegistry: layer type '%s' is already registered." % descriptor.id)
        return false
    descriptor.owner_module = module_id
    _descriptors[descriptor.id] = descriptor
    _order.append(descriptor.id)
    changed.emit()
    return true


## Removes one type. Used by SaModule.unregister so a module can be unloaded.
func unregister(type_id: StringName) -> void:
    if not _descriptors.has(type_id):
        return
    _descriptors.erase(type_id)
    _order.erase(type_id)
    changed.emit()


## Removes everything a module registered, so unloading is not the module's
## bookkeeping problem.
##
## *layers* are the open documents' layers, handed in by whoever knows them,
## because a registry reaches for no document. Each one of an erased type is
## put in the state a layer of an uninstalled module is in after a load, the
## one [method rebind] documents: its hook and its generator go, because both
## point into the module that just went, and its fields, its schema, its
## parameters and its type id stay. Only a reload hands any in: at shutdown
## nothing is drawn again, so there is nothing to put right.
func unregister_module(module_id: StringName, layers: Array = []) -> void:
    var doomed: Array[StringName] = []
    for type_id: StringName in _order:
        if _descriptors[type_id].owner_module == module_id:
            doomed.append(type_id)
    for type_id in doomed:
        _descriptors.erase(type_id)
        _order.erase(type_id)
    for layer: SaLayer in layers:
        if layer != null and doomed.has(layer.layer_type):
            layer.resolve_hook = Callable()
            layer.generator = ""
            layer.input = &""
            SaSceneLayer.detach(layer)
            SaDrawnLayer.detach(layer)
    if not doomed.is_empty():
        changed.emit()


func has(type_id: StringName) -> bool:
    return _descriptors.has(type_id)


func get_descriptor(type_id: StringName) -> SaLayerTypeDescriptor:
    return _descriptors.get(type_id, null)


## Registration order, which is the order the add-layer list offers them in.
func list_ids() -> Array[StringName]:
    return _order.duplicate()


func list_descriptors() -> Array:
    var out: Array = []
    for type_id in _order:
        out.append(_descriptors[type_id])
    return out


## A row of the search for every kind the Layer menu adds, in its order, titled
## as a painter asks for it: "New Paper Layer". The background is not added by
## a painter and the plain layer is the command New Layer, so neither is a row.
func search_rows() -> Array[SaSearchRegistry.Row]:
    var out: Array[SaSearchRegistry.Row] = []
    var place := tr("Layer")
    for type_id: StringName in _order:
        if type_id == &"background" or type_id == SaLayerTypeDescriptor.PLAIN:
            continue
        var descriptor := _descriptors[type_id]
        if not descriptor.offered():
            continue
        var words := descriptor.display_name if not descriptor.display_name.is_empty() else String(type_id)
        var named := words if words.to_lower().ends_with("layer") else "%s Layer" % words
        var title := tr("New %s") % tr(named)
        # A shipped kind's row is a whole sentence, so a language with cases can
        # decline its name. A module's own kind reads the generic one.
        if SaWholeSentences.LAYER_NEW.has(named):
            title = tr(SaWholeSentences.LAYER_NEW[named])
        var said := "%s %s" % [words, descriptor.hint]
        var act := _search_picked.bind(type_id)
        out.append(SaSearchRegistry.Row.new(SaSearchRegistry.LAYER, title, place, act, &"", said, search_pick.is_valid()))
    return out


func _search_picked(type_id: StringName) -> void:
    if search_pick.is_valid():
        search_pick.call(type_id, self)


## Puts a type onto a layer: its schema at the document's depth, its resolve hook,
## its default blend mode, and the type id the layer reports afterwards.
##
## Returns false for an unknown type, leaving the layer exactly as it was. A
## caller that cannot make a layer the type it asked for should say so rather
## than hand back something that looks right and composites as a plain layer.
func apply_to(layer: SaLayer, type_id: StringName, space: SaColorSpace) -> bool:
    var descriptor: SaLayerTypeDescriptor = _descriptors.get(type_id, null)
    if layer == null or descriptor == null:
        return false
    layer.layer_type = descriptor.id
    layer.schema = descriptor.schema_for(space)
    layer.resolve_hook = descriptor.resolve
    layer.blend_mode = descriptor.default_blend_mode
    layer.generator = descriptor.generator
    layer.input = descriptor.input
    layer.generator_params = SaGeneratedLayer.defaults_for(descriptor, space)
    layer.scene = descriptor.scene
    layer.scene_params = descriptor.scene_defaults.duplicate(true)
    SaSceneLayer.detach(layer)
    SaSceneLayer.attach(layer)
    SaDrawnLayer.detach(layer)
    layer.remove_meta(SaDrawnLayer.KEPT)
    SaDrawnLayer.attach(layer, descriptor.recipe)
    return true


## What *layer* composites, its descriptor's answer as the layer carries it.
##
## [method apply_to] copies the descriptor's kernel and input onto the layer
## and [method rebind] copies them again after a load, so the layer holds the
## descriptor's answer, and reading it there rather than looking the type up
## keeps two cases right. A layer whose module is not installed keeps its type
## id with no kernel, and composites inert as paint. A layer a suite or a
## conversion gave a kernel by hand composites by that kernel. A group has no
## type of its own and is a group by what it holds.
static func composites(layer: SaLayer) -> Composites:
    if layer.is_group:
        return Composites.GROUP
    if layer.is_generated():
        return Composites.GENERATED
    if layer.is_adjustment():
        return Composites.ADJUSTMENT
    if layer.is_effect():
        return Composites.EFFECT
    return Composites.PAINT


## The answers of one composite, each layer's [method composites] read the
## first time it is asked and kept until the composite is built again, so a
## walk that meets a layer in several places asks once.
class Reading:
    extends RefCounted

    var _answers: Dictionary[int, Composites] = {}

    func of(layer: SaLayer) -> Composites:
        var id := layer.get_instance_id()
        if not _answers.has(id):
            _answers[id] = SaLayerTypeRegistry.composites(layer)
        return _answers[id]

    ## Whether *layer* holds members, a group, which composites them.
    func nests(layer: SaLayer) -> bool:
        return of(layer) == Composites.GROUP

    ## Whether *layer* reads the backdrop below it, an adjustment.
    func reads_below(layer: SaLayer) -> bool:
        return of(layer) == Composites.ADJUSTMENT

    ## Whether *layer* stores nothing a painter laid, a kernel or an effect's
    ## cache, so a fold over transparent cannot stand in for it.
    func stores_nothing(layer: SaLayer) -> bool:
        return of(layer) == Composites.GENERATED or of(layer) == Composites.EFFECT

    ## Whether *layer* reads nothing but what it holds, paint its chunks and a
    ## group its members, so its step folds over transparent as it lies.
    func reads_own(layer: SaLayer) -> bool:
        return of(layer) == Composites.PAINT or of(layer) == Composites.GROUP


## Re-attaches resolve hooks to layers that already carry a type id.
##
## A `.sad` records which type a layer is, not the Callable that resolves it, so
## a loaded document has the fields but nothing to recompute the derived ones
## with. Called after a load.
##
## The schema is deliberately left as the file recorded it. Rewriting it from the
## descriptor would silently reformat a document to whatever this build's version
## of the type happens to store, and the stored chunks are already allocated to
## the recorded one.
##
## A layer whose type is not registered, because the module owning it is not
## installed, keeps its fields and its type id and simply does not resolve. That
## is the same thing that happens to it in memory, and losing the layer would be
## worse than opening it inert.
func rebind(layers: Array) -> void:
    for layer: SaLayer in layers:
        if layer == null or String(layer.layer_type).is_empty():
            continue
        var descriptor: SaLayerTypeDescriptor = _descriptors.get(layer.layer_type, null)
        if descriptor == null:
            continue
        layer.resolve_hook = descriptor.resolve
        # The kernel name is the type's, the parameters are the layer's and
        # came from the file.
        layer.generator = descriptor.generator
        layer.input = descriptor.input
        # The path is the type's too, and the viewport starts only where the
        # module that ships the scene is installed.
        if descriptor.is_scene():
            layer.scene = descriptor.scene
            SaSceneLayer.attach(layer)
        # The recipe the file kept, drawn again by the type's own script.
        if descriptor.is_drawn() and layer.recipe == null:
            SaDrawnLayer.attach(layer, descriptor.recipe)


## One line for every layer whose recorded schema no longer names the fields
## its registered type declares, by id and in order. [method rebind] keeps the
## schema the chunks were allocated to, so a module reloaded with a changed
## schema resolves over the old fields, and the painter who changed it has to
## restart for the new ones. The reload prints these so that is said rather
## than found.
func schema_drift(layers: Array) -> Array[String]:
    var lines: Array[String] = []
    for layer: SaLayer in layers:
        if layer == null:
            continue
        var descriptor: SaLayerTypeDescriptor = _descriptors.get(layer.layer_type, null)
        if descriptor == null:
            continue
        if _field_ids(layer.schema) != _field_ids(descriptor.schema):
            lines.append(
                (
                    "Layer '%s' keeps the fields %s it was made with, and type '%s' now declares %s. Restart Sara to use them."
                    % [layer.name, _field_ids(layer.schema), layer.layer_type, _field_ids(descriptor.schema)]
                )
            )
    return lines


static func _field_ids(schema: Array[SaFieldSpec]) -> Array[StringName]:
    var ids: Array[StringName] = []
    for spec in schema:
        ids.append(spec.id if spec != null else &"")
    return ids


## Every registered type's schema is one the chunk allocator can actually serve.
## Called by the contract test: a type naming a format nothing can allocate is
## refused at startup rather than at the first dab.
func validate() -> Array[String]:
    var problems: Array[String] = []
    for type_id in _order:
        var descriptor: SaLayerTypeDescriptor = _descriptors[type_id]
        for spec in descriptor.schema:
            if spec == null:
                problems.append("layer type '%s' has a null field in its schema" % type_id)
            elif spec.bytes_per_texel() == 0:
                problems.append("layer type '%s' field '%s' names a format nothing can allocate" % [type_id, spec.id])
    return problems
