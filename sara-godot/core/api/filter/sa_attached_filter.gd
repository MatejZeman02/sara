## One filter attached under a node of the layer tree, kept for as long as the
## document lives.
##
## A filter is attached rather than made a layer of its own, and a global
## filter is one on the document's root. So a record hangs in
## `SaLayer.filters`, a group being a layer, or in `SaDocument.root_filters`,
## and its place in that array is its order. There is no order number on the
## record, because two records with the same number are a state an array cannot
## reach.
##
## For a painter who wants a filter as a layer, the adjustment layer,
## `SaBackdropLayer`, stands beside the attached filter. It
## is a layer that stores nothing, and its records hang in its own
## `SaLayer.filters` and run over the backdrop below it. Attaching stays the
## default, and the layer is a painter's choice.
##
## It names no layer, as `SaPointPass` names none: whoever
## evaluates it hands over the texture and the rectangle, so a layer, a group's
## cache and the root run the same record.
##
## It keeps values and never a filter instance. The registry holds one instance
## per key and a document may attach the same filter twice, so the instance is
## asked for by `key` when the record is evaluated, handed `parameters` through
## `SaFilter.set_parameters`, and keeps nothing of the record afterwards.
##
## Not persisted by itself. `SaSadFile.write_filters` and
## `SaSadFile.read_filters` are the two doors to disk.
class_name SaAttachedFilter
extends RefCounted

## The registry key the filter was attached under, `<module id>.<filter id>`,
## what `SaFilterRegistry.get_filter` answers to. A key no installed module
## registers is kept and written back, the way a missing module's layer is.
var key: StringName = &""

## What the filter's widgets held, as `SaFilter.parameters` answered it. Written
## through `replace_parameters`, so the revision moves with it.
var parameters: Dictionary[String, Variant] = {}

## What the filter leaves alone, or null for a filter over the whole node. The
## member is called mask on purpose: `SaMaskOps` takes an owner and reads
## `owner.mask`, so a record is an owner its operations already serve. The own
## form of `SaMask`, because a record stores no paint to carry a field.
var mask: SaMask = null

## Off, the node composites as if the record were not there, and everything
## else of it is kept for when it comes back on.
var enabled: bool = true

## Moves whenever what the record evaluates to moved. The evaluation compares
## it with the one its cached result was built at.
var revision: int = 0

## The pass the evaluation built from `parameters`, kept so a chunk that
## redraws does not run the filter's `run` again. Dropped by `touch`. Untyped
## beyond `RefCounted`, because a point pass and a neighbourhood pass are two
## classes and the record does not care which.
var cached_pass: RefCounted = null


## A record under *registry_key* holding *values*, or under the key of the
## filter that now reads such records and in its terms, by
## [method SaFilterRegistry.record_for], so a document saved before a filter
## took another's place loads as the filter that took it.
func _init(registry_key: StringName = &"", values: Dictionary = {}) -> void:
    var made := SaFilterRegistry.record_for(registry_key, values)
    key = made[0]
    parameters = SaTyped.strings(made[1]).duplicate(true)


## New values for the filter, as one change: the copy, the revision and the
## stale pass together, so no caller can do one and forget the other two.
func replace_parameters(values: Dictionary) -> void:
    parameters = SaTyped.strings(values).duplicate(true)
    touch()


## Says the record evaluates to something else now. For whoever changed the
## mask or the enabled flag, which are plain members.
func touch() -> void:
    revision += 1
    cached_pass = null


## What a painter reads for *record*: *title*, its filter's own, and from the
## second record of one key in *among* on, its number after it, so two
## Gaussian Blurs on one layer read "Gaussian Blur" and "Gaussian Blur 2".
## Counted from the front of the array, the order the records run in, so the
## newer of two, which the Layers docker lists above, is the "2". Worked out
## whenever it is asked and never kept: the format is unchanged, a removal renumbers.
## A record *among* does not hold reads the title alone.
static func numbered(title: String, among: Array[SaAttachedFilter], record: SaAttachedFilter) -> String:
    var place := 0
    for other: SaAttachedFilter in among.slice(0, among.find(record) + 1):
        if other.key == record.key:
            place += 1
    return "%s %d" % [title, place] if place > 1 else title


## [method numbered] for *record* wherever it hangs in *document*, for the
## windows that hold a record and not the list it stands in.
static func numbered_in(document: SaDocument, record: SaAttachedFilter, title: String) -> String:
    var holder := holder_in(document, record)
    if holder == null:
        return title
    return numbered(title, document.root_filters if holder == document else (holder as SaLayer).filters, record)


## The node *record* hangs under in *document*: the document itself for a record
## on the root, the layer or group whose `filters` hold it, or null when it hangs
## nowhere in *document*. The one walk a window that holds a record makes to say
## where it is.
##
## Every depth is walked, the way `SaStaleSpread` walks for the halo, although a
## group's members are its siblings in the document's flat order and a layer
## inside a group is a child of the document like any other.
static func holder_in(document: SaDocument, record: SaAttachedFilter) -> Node:
    if document == null or record == null:
        return null
    if document.root_filters.has(record):
        return document
    var pending: Array[Node] = [document]
    while not pending.is_empty():
        var parent: Node = pending.pop_back()
        for child: Node in parent.get_children():
            var layer := child as SaLayer
            if layer == null:
                continue
            if layer.filters.has(record):
                return layer
            pending.append(layer)
    return null


## A second record of the same filter, with a mask of its own holding a VRAM
## copy of this one's coverage. The cached pass is not copied, because it is
## rebuilt from the parameters the first time the copy is evaluated.
func duplicate_record() -> SaAttachedFilter:
    var copy := SaAttachedFilter.new(key, parameters)
    copy.enabled = enabled
    if mask != null:
        copy.mask = SaMask.own()
        copy.mask.enabled = mask.enabled
        copy.mask.rest = mask.rest
        for grid_pos: Vector2i in mask.grid_positions():
            copy.mask.set_chunk(grid_pos, mask.duplicate_chunk(grid_pos))
    return copy


## VRAM the record holds, which is its mask's chunks and nothing else. What a
## history step is charged with while the record is out of the document.
func byte_size() -> int:
    if mask == null:
        return 0
    var total := 0
    for grid_pos: Vector2i in mask.grid_positions():
        var chunk: SaChunk = mask.chunks.get(grid_pos, null)
        if chunk != null:
            total += chunk.byte_size()
    return total
