## Chunk-based texture management for an individual canvas layer.
##
## Uses a sparse dictionary of 256x256 SaChunk tiles to represent large drawing
## areas efficiently in VRAM. Handles per-layer opacity and blending.
##
## A chunk holds one texture per entry in this layer's `schema`, and everything
## here is a loop over the schema rather than a reach for `albedo`, so a layer
## type that adds a field needs no change here.
@tool
extends Node

class_name SaLayer

const CHUNK_SIZE: int = SaChunk.SIZE

## Chunk grid coordinate -> the tile stored there.
var chunks: Dictionary[Vector2i, SaChunk] = {}

## Arbitrary per-module state for this layer, as { module_id -> Dictionary }.
##
## Kubelka-Munk is a per-layer type rather than a document mode, so what its
## concentration channels mean belongs here rather than on the document. Written
## and read through `SaContext.layer_data()`, which hands a module its own slice
## and nobody else's.
##
## Data belonging to a module that is not installed is carried here untouched and
## written back out on the next save, because losing a collaborator's data for
## want of their module would be worse than refusing the file.
var module_data: Dictionary[String, Variant] = {}

## Which registered layer type this is, or empty.
##
## **Empty means a plain colour layer**, which is what a document's own
## Background and Layer 1 are. It is deliberately not written as `plain`: a default document is built by
## `SaDocument` with no registry in reach, and a core file inventing a registered
## id for itself is the coupling the registry exists to remove. Nothing branches
## on the difference, because a plain layer and an untyped one have the same
## schema, no resolve hook and the same blend mode.
##
## The id alone, never the descriptor: a `.sad` records this string and a
## document must open on a build where the module that owns the type is not
## installed. Such a layer keeps its fields and its id, and simply does not
## resolve. `SaLayerTypeRegistry.rebind()` re-attaches the hook when the module
## is there.
var layer_type: StringName = &""

## The kernel this layer evaluates instead of storing pixels, from its type,
## and the parameters it evaluates with. Empty for a layer that stores,
## which is every layer that is not a background. The parameters are the
## layer's own and travel with the `.sad`, and the kernel name comes back from
## the descriptor on load, the way the resolve hook does.
var generator: String = ""
var generator_params: Dictionary[String, Variant] = {}

## What this layer reads instead of storing pixels, from its type the way the
## kernel name is: `SaLayerTypeDescriptor.INPUT_BELOW` for an adjustment
## layer, whose attached filters run over the backdrop at its place in the
## walk. `SaLayerTypeDescriptor.INPUT_NAMED` for an effect layer, which reads
## the node [member source] names. Empty for every other layer.
var input: StringName = &""

## The node an effect layer reads, a layer or a group, by reference the way
## [member group] refers, so a rename does not lose it. Null for every other
## layer and for an effect layer that reads nothing yet. Set through
## `SaEffectLayer.read`, which refuses a node the layer would read itself
## through.
var source: SaLayer = null

## The scene this layer shows, from its type, and the properties set on the
## scene's root. Empty for every layer that is not a scene layer. Both are
## the layer's own and travel with the `.sad` in place of its pixels, and the
## viewport that renders it is the `SaSceneLayer` child a registry attaches.
var scene: String = ""
var scene_params: Dictionary[String, Variant] = {}

## What this layer's chunks are drawn from, an instance of its type's recipe,
## and null for every layer that is not drawn. The chunks are its cache,
## written by `SaDrawnLayer` over what an edit touched, and the `.sad` keeps
## the recipe in their place.
var recipe: SaDrawnRecipe = null

## The fields every chunk of this layer carries, in order.
##
## Defaults to a single authoritative RGBA32F `albedo`. An impasto layer declares
## `[albedo, height]`, a mixing layer `[concentrations, thickness, albedo*]`
## with the albedo derived, and nothing in this file changes for either.
var schema: Array[SaFieldSpec] = SaFieldSpec.default_schema():
    set(value):
        schema = value
        has_derived = false
        for spec in schema:
            if spec != null and spec.is_derived():
                has_derived = true
                break
        _follow_schema()
        mark_all_unresolved()

## What this layer hides, or null for a layer with no mask.
##
## A layer that stores paint keeps its mask as the `SaFieldSpec.MASK` field of
## its own chunks, through `add_mask` and `drop_mask`, and this member is the
## door onto that field. A group stores no paint, so it gets `SaMask.own()`
## here instead. Read it freely, and ask it nothing about which of the two it
## is.
var mask: SaMask = null

## Recomputes this layer's derived fields for one chunk.
##
## Called as `resolve_hook.call(self, grid_pos, chunk)` before the chunk is
## composited, and only for chunks whose authoritative fields have changed since
## the last time. Impasto resolves height into normals here, a Kubelka-Munk layer
## resolves concentrations and thickness into the RGBA the compositor consumes.
##
## The compositor reads `albedo` and never learns which of the two happened.
var resolve_hook: Callable = Callable()

## Chunks whose authoritative fields moved since the hook last ran on them.
var _unresolved: Dictionary[Vector2i, bool] = {}

## Cached from the schema, because resolve_pending() is called per composite and
## the answer is "no" for a plain layer.
## Whether anything in this layer's schema is computed rather than painted.
var has_derived: bool = false

@warning_ignore("unused_signal")
signal lock_changed(is_locked: bool)
@warning_ignore("unused_signal")
signal alpha_lock_changed(alpha_locked: bool)

## Whether the layer is visible
@export var visible: bool = true

## The opacity of the layer
@export_range(0.0, 1.0) var opacity: float = 1.0

## A note the painter, or the companion painting through the door, attaches to
## this layer.
##
## Free text and never read by anything that paints: the Layers docker draws a
## mark on the row when it is not empty and puts the text in the row's tooltip,
## and the rename field carries it while a name is being typed. Its own member
## rather than a slice of `module_data`, because it belongs to no module and a
## build with no modules at all still has to keep it across a save.
@export_multiline var comment: String = ""

## The name as the painter typed it, full stops, colons and per cent signs
## included, which the engine turns to underscores in a node's name. The node
## keeps the name the engine accepts, because that name is how a group, a
## `.sad` and a door step find the layer. Written by [method take_name] alone,
## and read through [method shown_name], which falls back on the node's name
## once anything renamed the node by hand.
var _typed_name: String = ""

## The colour the painter gave the row, Photoshop's way of telling layers apart
## at a glance: one of `SaLayerColorTag.IDS`, and `&""` for No Colour. Nothing
## that paints reads it, the Layers docker tints the row behind its eye.
@export var color_tag: StringName = &""

## The density every chunk made on this layer is stored at, 1.0 unless the
## layer was made otherwise. At 2.0 a chunk holds 512 texels across over the
## same 256 document pixels. One scale per layer, so no dab and no kernel
## meets two scales inside one layer, a rule held by construction.
@export var resolution_scale: float = 1.0

## A group: a layer that holds no paint and stands for the layers whose
## `group` it is. Pass-through by default, where its members composite as if
## ungrouped with its opacity multiplied in, or isolated, where they composite
## into an intermediate first and the group's own mode and opacity apply to
## that.
@export var is_group: bool = false
@export var isolated: bool = false

## An adjustment layer's Affect all: its step runs over the whole picture after
## the top level's last layer, wherever it sits, so a group can hold it and
## hiding the group turns it off. Off for every other kind, where nothing reads
## it. `SaBackdropLayer` says what it means to the walk and toggles it as one
## undo step.
@export var affects_all: bool = false

## Whether a group's row is folded shut in the layer lists. A way of looking at
## the stack and nothing the composite reads, but kept here so it is saved with
## the document and opened shut again, as Krita keeps it. No undo step records
## it. The Layers docker's keeper is its one writer.
@export var folded: bool = false

## The group this layer belongs to, or null at the top level. A reference
## rather than a name, because names are what the file uses and a rename must
## not orphan a layer. Members follow their group in the flat order, and the
## stack builder derives membership from this field, never from adjacency.
var group: SaLayer = null

## The filters attached under this layer, a group included, bottom first: the
## array's order is the order they are evaluated in over what the layer
## composites to. Edited through `SaFilterOps`, which makes each change a
## history step, and freed with the layer.
var filters: Array[SaAttachedFilter] = []

## The simulation stepping this layer's paint, an `SaSimulationRecord` of
## `core/layers/simulation`, or null for a layer no rule steps. Typed as its
## base because this folder is the door and the record lives behind it, and
## written by `SaSimulation` alone, which puts it on and takes it off.
var simulation: RefCounted = null

## The projective map this layer's paint is drawn through, an `SaLiveTransform`
## of `core/layers/transform`, or null for a layer drawn where it was painted.
## Typed as its base because this folder is the door and the transform lives
## behind it, and written by `SaLiveTransform` alone. The layer tells it where
## its paint changed, so its cache follows.
var live_transform: RefCounted = null

## Paint was written into this layer at *grid_positions* as one history step,
## a stroke, a fill, a filter or a paste. `SaDocument.record_pixel_step` emits
## it, and a simulation's seed follows it, since the seed is what was last
## painted. Undo and redo do not emit it, nor does a simulation's own step.
@warning_ignore("unused_signal")
signal paint_recorded(grid_positions: Array)

## The chunks at *grid_positions* were exchanged with the ones a history step
## held, by `SaDocument.swap_pixels`, which an undo and a redo of a pixel step
## run. A simulation's seed follows it as it follows [signal paint_recorded],
## so a Reset after an undo never puts back the stroke the undo took off.
@warning_ignore("unused_signal")
signal paint_swapped(grid_positions: Array)

## A stroke was pressed on this layer, before its first dab. `SaDocument.begin_stroke`
## emits it, and a running simulation pauses at it, so no step lands between a
## read of the layer and a write.
@warning_ignore("unused_signal")
signal stroke_pressed

## When a stroke was last pressed on this layer, in microseconds since Sara
## started, 0 for a layer never drawn on in this session. `SaResidency` evicts
## the least recently drawn layers first.
var drawn_at: int = 0


## Records that a stroke is pressed on this layer now.
func note_drawn() -> void:
    drawn_at = Time.get_ticks_usec()


## Whether painting/editing on this layer is locked (ignored). A group reports
## locked whatever was set, because there is nothing in it to paint on.
@export var is_locked: bool = false:
    set(value):
        if _locked != value:
            _locked = value
            lock_changed.emit(_locked)
    get:
        return _locked or is_group
## The lock as set on this layer itself. [member is_locked] answers true for
## every group, so a merge, which takes a group as its members drawn, and a
## stroke on a group's mask read this to find a lock somebody set.
var _locked: bool = false

## Whether this layer shows only where the layer below it has paint. The
## nearest layer below that is not itself clipped is the base, its alpha masks
## this layer's, and a hidden base hides this layer with it.
@export var clip_to_below: bool = false

## Whether alpha channel is locked during painting/filling
@export var alpha_locked: bool = false:
    set(value):
        if alpha_locked != value:
            alpha_locked = value
            alpha_lock_changed.emit(alpha_locked)

## The blend-mode ids code names by hand, as strings rather than shader-kernel
## ordinals so a module or a saved document cannot change behaviour when the
## kernels move. Not the list of modes: every built-in is a row of the
## skeleton's `BLEND_MODES` table and a module's is registered beside them, and
## `SaRegistries.blend_modes` lists them all. An id is here only while a script
## names it, so a new mode needs no line here.
const BLEND_MODE := {
    NORMAL = &"normal",
    MULTIPLY = &"multiply",
    SCREEN = &"screen",
    OVERLAY = &"overlay",
    ADD = &"add",
    ERASE = &"erase",
    SOFT_LIGHT = &"soft_light",
    # Not a mode a layer carries or a menu offers. It is what the stroke buffer
    # composites as when the active layer is alpha locked and the painting mode
    # is wash, so it lives with the other ids rather than as a loose string in
    # the brush and the commit.
    ALPHA_LOCK = &"alpha_lock",
}

## Ordinals persisted by documents written before blend modes became stable IDs.
## Only the six modes that existed then belong here. Appending to this list would
## invent a meaning for ordinals that were never written to disk.
const LEGACY_BLEND_MODES := [
    BLEND_MODE.NORMAL,
    BLEND_MODE.MULTIPLY,
    BLEND_MODE.SCREEN,
    BLEND_MODE.OVERLAY,
    BLEND_MODE.ADD,
    BLEND_MODE.ERASE,
]

## The blend mode for the layer or brush. This is serialised as its stable ID.
@export var blend_mode: StringName = BLEND_MODE.NORMAL


## Names this layer *value* as the painter typed it. The node takes the name
## with each character the engine refuses made an underscore, and a digit when a
## sibling holds that name already, and the typed name takes the same digits, so
## the node's name is always the typed one made acceptable and two siblings
## never show one name. The engine swaps one character for one underscore, so
## the typed text is kept up to where the landed name parts from it.
func take_name(value: String) -> void:
    var accepted := value.validate_node_name()
    name = accepted
    var landed := str(name)
    var kept := 0
    while kept < mini(accepted.length(), landed.length()) and accepted[kept] == landed[kept]:
        kept += 1
    _typed_name = value.left(kept) + landed.substr(kept)


## The name the layer shows the painter: the typed one while the node still
## holds it made acceptable, and the node's own once anything set `name` by
## hand, a duplicate's " copy" or an older file's name among them.
func shown_name() -> String:
    var node_name := str(name)
    if not _typed_name.is_empty() and _typed_name.validate_node_name() == node_name:
        return _typed_name
    return node_name


func get_blend_mode_name() -> StringName:
    return blend_mode


static func blend_mode_from_legacy(value: Variant) -> StringName:
    if value is StringName:
        return value
    if value is String:
        return StringName(str(value))
    if value is int and value >= 0 and value < LEGACY_BLEND_MODES.size():
        return LEGACY_BLEND_MODES[value]
    return BLEND_MODE.NORMAL


var _cached_fill_compute: SaCompute


func _get_fill_compute() -> SaCompute:
    if _cached_fill_compute == null:
        _cached_fill_compute = SaCompute.new("fill")
    return _cached_fill_compute


## Whether this layer evaluates a kernel rather than reading its chunks.
func is_generated() -> bool:
    return not generator.is_empty()


## Whether this layer adjusts the backdrop below it rather than reading chunks.
func is_adjustment() -> bool:
    return input == SaLayerTypeDescriptor.INPUT_BELOW


## Whether this layer's chunks are its named input run through its filters, a
## cache refreshed by `SaEffectLayer` and never painted.
func is_effect() -> bool:
    return input == SaLayerTypeDescriptor.INPUT_NAMED


## Whether this layer's pixels are its scene's rather than paint.
func is_scene() -> bool:
    return not scene.is_empty()


## Whether this layer's pixels are drawn from a recipe rather than paint.
func is_drawn() -> bool:
    return recipe != null


## Whether a tool that writes pixels turns this layer away.
##
## True for a locked layer, for a generated one, which stores no pixels and is
## drawn by its generator, so a pass writing its chunks would change nothing
## the compositor reads and leave an undo step that undoes nothing, and for an
## adjustment layer, which stores none either and shows its backdrop run
## through its filters, for an effect layer, whose chunks are a cache of its
## input that the next refresh would write over, and for a scene layer, whose
## chunks the scene writes again on its next dirty frame, so a stroke belongs
## on a layer above, and for a drawn one, whose chunks its recipe draws again
## on its next edit. One drawn through a live transform refuses it too, since a
## pass lands where aimed and the paint shows elsewhere, unless *mapped*, a
## stroke painted through a map that takes it. `is_locked` stays the lock
## alone, as the layers docker draws its padlock from it. Every layer of a
## file still opening refuses it until the last chunk is in, since a
## pass there would write over a chunk the open is about to replace.
func refuses_paint(mapped: bool = false) -> bool:
    var moved: bool = live_transform != null and not live_transform.call(&"takes_paint", self, mapped)
    var opening := SaSadFile.filling(get_parent() as SaDocument)
    return is_locked or is_generated() or is_adjustment() or is_effect() or is_scene() or is_drawn() or moved or opening


## The grid positions that cover a canvas of *canvas_size*.
static func grid_positions(canvas_size: Vector2i) -> Array[Vector2i]:
    var positions: Array[Vector2i] = []
    var chunks_x := ceili(canvas_size.x / float(CHUNK_SIZE))
    var chunks_y := ceili(canvas_size.y / float(CHUNK_SIZE))
    for x in range(chunks_x):
        for y in range(chunks_y):
            positions.append(Vector2i(x, y))
    return positions


## The grid positions a fill of a layer of *document* can paint: the whole
## canvas, or under an active selection only the positions the selection holds
## a chunk at. A position the selection holds no chunk at is unselected
## throughout, so a chunk allocated there would stay transparent on the layer
## for the rest of the session, against hard rule 3.
##
## With *layer*'s alpha locked it is none, because a chunk that does not exist
## holds no alpha for the fill to keep. Asked here, so the document's fill and
## the layer's own cannot disagree on it.
static func fill_reach(document: SaDocument, layer: SaLayer) -> Array[Vector2i]:
    if layer.alpha_locked:
        return []
    var grid := grid_positions(document.canvas_size)
    var selection := document.selection
    if selection == null or not selection.active:
        return grid
    var reached: Array[Vector2i] = []
    for grid_pos in grid:
        if selection.covers(grid_pos):
            reached.append(grid_pos)
    return reached


## Allocates a chunk at every grid position that covers the canvas.
##
## Only for a layer about to be filled edge to edge, because that is the one
## case where paint lands everywhere. Called for every new layer, it would start
## a blank document at the full canvas in VRAM twice over and allocate the whole
## canvas for every layer a painter adds before it holds a pixel, against hard
## rule 3.
func allocate_grid(canvas_size: Vector2i) -> void:
    assert(canvas_size.x > 0 and canvas_size.y > 0, "Canvas size must be positive")
    for grid_pos in grid_positions(canvas_size):
        get_or_create_chunk(grid_pos)


## Returns an existing chunk or allocates one on the fly, with a texture for
## every field in the schema, at the layer's `resolution_scale`. A *scale*
## above zero overrides it, which only the `.sad` reader asks for, to make a
## chunk at the scale the file stored it at.
func get_or_create_chunk(grid_pos: Vector2i, scale: float = 0.0) -> SaChunk:
    if chunks.has(grid_pos) and chunks[grid_pos] != null:
        return chunks[grid_pos]

    var new_chunk := SaChunk.create(schema, scale if scale > 0.0 else resolution_scale)
    assert(new_chunk.has_field(SaFieldSpec.ALBEDO), "Every layer schema must carry an albedo field")
    mark_unresolved(grid_pos)

    # Allocation leaves the textures undefined, so this is the only clear a new
    # chunk gets rather than the second one. Each field takes its own spec's
    # blank, so a chunk allocated under the brush on a masked layer opens fully
    # shown: a mask cleared to zero with the paint would hide the first dab.
    new_chunk.clear(SaFieldSpec.NO_PAINT)
    # A mask made from a selection or inverted rests at zero, and a chunk it
    # did not hold reads that rest, so the new chunk's field opens there and
    # hides what the mask hid while the position was empty.
    if mask != null and not mask.is_own() and mask.rest != 1.0 and new_chunk.has_field(SaFieldSpec.MASK):
        new_chunk.field(SaFieldSpec.MASK).clear(Color(mask.rest, mask.rest, mask.rest, mask.rest))

    chunks[grid_pos] = new_chunk
    return new_chunk


## The texture backing one field of one chunk, allocating the chunk if needed.
##
## The shorthand for the common case: a tool that paints colour wants the albedo
## and has no interest in the tile it lives in.
##
## The one door a lazy field comes in by, height above all: a chunk that holds
## none of it yet gains a texture of it here, at zero, so a field is allocated
## in exactly the chunks something has written it into. Null for a field the
## schema does not list.
func get_or_create_field(grid_pos: Vector2i, field_id: StringName = SaFieldSpec.ALBEDO) -> SaTexture:
    var chunk := get_or_create_chunk(grid_pos)
    if not chunk.has_field(field_id):
        var spec := SaFieldSpec.find(schema, field_id)
        if spec != null and spec.lazy:
            chunk.add_sparse_field(spec)
    return chunk.field(field_id)


## The texture backing one field of an existing chunk, or null.
func get_field(grid_pos: Vector2i, field_id: StringName = SaFieldSpec.ALBEDO) -> SaTexture:
    var chunk: SaChunk = chunks.get(grid_pos, null)
    return chunk.field(field_id) if chunk != null else null


## Whether a field in this layer's schema holds colour, and so obeys alpha lock
## and takes part in colour-space conversion. An unknown field is assumed to.
func is_color_field(field_id: StringName) -> bool:
    var spec := SaFieldSpec.find(schema, field_id)
    return spec == null or spec.is_color


## Fills every allocated chunk with a solid colour.
##
## Where a mask or an alpha lock has to be honoured this is a kernel over
## [SaChunkWalk], which is what decides how narrowly it dispatches: the size
## comes from the chunk rather than from CHUNK_SIZE, so a chunk stored at
## reduced resolution already dispatches the right thread count. Where neither
## has to be honoured there is no kernel and every field is cleared outright.
func fill(color: Color) -> void:
    # A fill lands everywhere, so a layer that belongs to a document takes the
    # grid first. Everything else, a stroke buffer, a cache, a layer built by
    # hand, fills what it has. Transparent is no paint, so it allocates nothing,
    # and neither does a fill under an alpha lock, by `fill_reach`.
    var document := get_parent() as SaDocument
    if document != null and color.a > 0.0:
        for grid_pos in fill_reach(document, self):
            get_or_create_chunk(grid_pos)
    # A selection turns a fill into a kernel too: a clear cannot leave the
    # unselected pixels alone, and the kernel reads the mask per pixel.
    var selection: SaSelection = document.selection if document != null else null
    var masked: bool = selection != null and selection.active
    var fill_compute: SaCompute = _get_fill_compute() if (alpha_locked or masked) else null

    mark_all_unresolved()
    if fill_compute == null:
        # Nothing to honour, so every field takes the colour outright and no
        # kernel is involved.
        for grid_pos: Vector2i in chunks:
            _clear_fields(chunks[grid_pos], color, false)
        return

    var alpha_lock_flag := 1.0 if alpha_locked else 0.0
    var params := PackedFloat32Array([color.r, color.g, color.b, color.a, alpha_lock_flag, 0.0, 0.0, 0.0])
    # The kernel binds a mask whatever the selection says, so a layer with no
    # document, a cache or one built by hand, fills through a stand-in of its own.
    var bindings: Dictionary[int, Variant] = {}
    # Held in a local rather than passed straight in, because the walk binds its
    # RID and a texture dropped before the dispatch would take that RID with it.
    var everything: SaTexture = null
    if selection == null:
        everything = SaTexture.new(Vector2i(1, 1), SaSelection.FORMAT)
        everything.clear(Color(1.0, 1.0, 1.0, 1.0))
        bindings[SaSelection.BINDING] = everything
    # A fill lands where the layer already holds a chunk, and those chunks are
    # not a canvas for a stroke buffer or a cache, so the walk is given the
    # rectangle they cover rather than the document's.
    var walk := SaChunkWalk.new(fill_compute, selection, self)
    var here := func(grid_pos: Vector2i) -> SaChunk: return chunks.get(grid_pos, null)
    var same := func(_grid_pos: Vector2i, _local: Rect2i, _start: Vector2i) -> PackedFloat32Array: return params
    var filled := walk.run("fill", SaChunkWalk.reach_of(chunks.keys()), here, same, bindings)
    # The fields the kernel does not write, and only in the chunks it stopped
    # at: a chunk the selection leaves out is left alone whole, colour and
    # everything else, which is what the walk decided by skipping it.
    for grid_pos: Vector2i in filled:
        _clear_fields(chunks[grid_pos], color, true)


## Writes *color* into every field of *chunk* outright. *painted_fields_done*
## leaves out the ones a fill kernel has already written, which are the colour
## fields the schema does not derive.
##
## Alpha lock is a property of colour: the kernel that preserves the existing
## alpha only means anything for an RGBA field, so a height or a concentration
## field is filled outright either way.
func _clear_fields(chunk: SaChunk, color: Color, painted_fields_done: bool) -> void:
    for field_id: StringName in chunk.fields:
        var texture: SaTexture = chunk.fields[field_id]
        assert(texture != null and texture.rid.is_valid(), "Invalid field RID during fill")
        # Filling a layer with colour is not a change to what the layer hides,
        # nor to how thick its paint stands, which a lazy field holds.
        if field_id == SaFieldSpec.MASK or chunk.blanks.has(field_id):
            continue
        if painted_fields_done and is_color_field(field_id):
            var spec := SaFieldSpec.find(schema, field_id)
            if spec == null or not spec.is_derived():
                continue
        texture.clear(color)


## Gives this layer a mask holding *value* everywhere, 1.0 for one that hides
## nothing yet and 0.0 for one that hides the whole layer. Answers the mask, and
## the one the layer already has when it has one.
##
## The schema is replaced rather than appended to, because a duplicated layer
## shares its source's array and would otherwise gain a field it has no
## textures for.
func add_mask(value: float = 1.0) -> SaMask:
    if mask != null:
        return mask
    if is_group or is_adjustment() or is_effect():
        # A group stores no paint, and neither does an adjustment layer or an
        # effect layer, whose chunks are a cache, so its
        # mask holds chunks of its own rather than dragging an albedo into a
        # schema field. Coverage it does not hold reads as one, so a mask that
        # hides everything is painted, not allocated over the canvas here.
        mask = SaMask.own()
        return mask
    var spec := SaFieldSpec.mask()
    for grid_pos: Vector2i in chunks:
        chunks[grid_pos].add_field(spec, Color(value, value, value, value))
    var with_mask: Array[SaFieldSpec] = schema.duplicate()
    with_mask.append(spec)
    schema = with_mask
    return mask


## Takes the mask away, the field and every texture of it, so the layer shows
## whole again. Applying a mask into the paint first is `SaMaskOps`'s.
func drop_mask() -> void:
    if mask == null:
        return
    if mask.is_own():
        mask = null
        return
    drop_field(SaFieldSpec.MASK)


## Whether this layer carries a height, which it gains on the first
## height-writing dab and which the Layers docker marks.
func carries_height() -> bool:
    return SaFieldSpec.find(schema, SaFieldSpec.HEIGHT) != null


## Puts *spec* into the schema and nothing into any chunk: a lazy field arrives
## in a chunk on its first write. Replaced rather than appended to, for the
## reason `add_mask` gives. False when the schema already lists the field.
func add_field(spec: SaFieldSpec) -> bool:
    if spec == null or SaFieldSpec.find(schema, spec.id) != null:
        return false
    var with_field: Array[SaFieldSpec] = schema.duplicate()
    with_field.append(spec)
    schema = with_field
    return true


## Takes a field out of the schema and its texture out of every chunk.
func drop_field(field_id: StringName) -> void:
    for grid_pos: Vector2i in chunks:
        chunks[grid_pos].drop_field(field_id)
    var without: Array[SaFieldSpec] = []
    for spec in schema:
        if spec != null and spec.id != field_id:
            without.append(spec)
    schema = without


## Keeps `mask` and the schema from disagreeing, from the schema's setter: a
## schema that carries the field has a mask to read it through, which is how a
## loaded or a duplicated layer comes by one, and a schema that lost the field
## has none. A mask with chunks of its own is a group's and is left alone.
func _follow_schema() -> void:
    var carries := SaFieldSpec.find(schema, SaFieldSpec.MASK) != null
    if carries and (mask == null or mask.is_own()):
        mask = SaMask.of_layer(self)
    elif not carries and mask != null and not mask.is_own():
        mask = null


## Automatic cleanup (Destructor)
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Let go of the chunks first, never clear them: a shared source's users hold one.
        chunks = {}
        _unresolved.clear()
        resolve_hook = Callable()
        live_transform = null
        # Drop the fill compute after chunks so its uniform set doesn't reference freed textures.
        _cached_fill_compute = null


## Drops every chunk this layer holds.
##
## The tiles are RefCounted and free their own textures, so releasing the
## dictionary is the whole operation. Needed when a layer's storage format
## changes: the old tiles are the wrong depth and a mismatched storage-image bind
## is undefined across the whole image, not merely wrong at one texel.
func release_chunks() -> void:
    chunks.clear()
    _unresolved.clear()
    if live_transform != null:
        live_transform.call(&"moved_all")


## A VRAM copy of one chunk, every field included, for undo history.
## Null when the chunk does not exist yet, which means the undo state is empty.
func duplicate_chunk(grid_pos: Vector2i) -> SaChunk:
    var chunk: SaChunk = chunks.get(grid_pos, null)
    return chunk.duplicate_chunk() if chunk != null else null


## Replaces one chunk, or removes it when `new_chunk` is null. This is how undo
## and redo put a captured tile back.
func set_chunk(grid_pos: Vector2i, new_chunk: SaChunk) -> void:
    if new_chunk == null:
        chunks.erase(grid_pos)
        _unresolved.erase(grid_pos)
        if live_transform != null:
            live_transform.call(&"moved", grid_pos)
    else:
        chunks[grid_pos] = new_chunk
        mark_unresolved(grid_pos)


## Notes that a chunk's authoritative fields changed, so its derived ones are
## stale. Cheap enough to call unconditionally: it is a dictionary insert, and
## resolve_pending() is what checks whether a hook exists at all.
func mark_unresolved(grid_pos: Vector2i) -> void:
    _unresolved[grid_pos] = true
    if live_transform != null:
        live_transform.call(&"moved", grid_pos)


func mark_all_unresolved() -> void:
    for grid_pos: Vector2i in chunks:
        _unresolved[grid_pos] = true
    if live_transform != null:
        live_transform.call(&"moved_all")


## Runs the resolve hook over every chunk that needs it, then clears the set.
##
## Called by whoever is about to read `albedo`, so the compositor never sees a
## stale derived field. A layer with no derived fields, which is all of them
## today, returns on the first line.
func resolve_pending() -> void:
    if not has_derived or not resolve_hook.is_valid():
        _unresolved.clear()
        return
    for grid_pos: Vector2i in _unresolved:
        var chunk: SaChunk = chunks.get(grid_pos, null)
        if chunk != null:
            resolve_hook.call(self, grid_pos, chunk)
    _unresolved.clear()
