## The drawn layer: a layer whose chunks are a cache of an `SaDrawnRecipe`,
## drawn here over what an edit touched and nowhere else.
##
## A vector layer and a text layer are both of this shape, and so is a
## module's own: the descriptor names a recipe script, `SaLayerTypeRegistry`
## gives the layer an instance of it through [method attach], and from then on
## the recipe's [signal SaDrawnRecipe.changed] is what draws. The chunks are
## ordinary `SaChunk`s at the document's depth, so every reader of
## `SaLayer.chunks` reads them as paint and nothing here asks a reader to
## change.
##
## **An edit redraws its own rectangles.** Each one is cut to the chunks it
## crosses and grown there to whole 16 pixel tiles, the workgroup of the
## kernels a recipe draws with, and each chunk's part is cleared and drawn once
## however many rectangles reach it, since a second draw over the first would
## lay its edges twice (hard rule 2). A chunk the recipe's bounds fall short of
## is let go (hard rule 3).
##
## **History keeps the recipe**, its JSON before and after an edit, through
## [method edit], and never a chunk, so a step costs what the recipe's text does.
##
## **Residency lets a chunk go unread.** [method let_go] gives a chunk's
## textures up with a [Redraw] in place of the compressed copy paint keeps,
## and the chunk's own gate draws it again the first time a reader meets it,
## so nothing is read back (hard rule 1).
@tool
class_name SaDrawnLayer
extends RefCounted

## The side of a tile a region is grown to, in document pixels.
const TILE := 16
## The meta a layer keeps its recipe's JSON under while no registered type
## can draw it, a file opened on a build without the module, so the next save
## writes the recipe back as it came.
const KEPT := &"drawn_recipe"

## The kernel a region is cleared by before it is drawn again, shared, since
## every drawn layer clears with it.
static var _clearer: SaCompute = null


## Gives *layer* a fresh recipe of *script*, read from *saved* when given and
## otherwise from what a file left on the layer, and draws it, at once over
## the chunks it holds or as each is read when it holds none. Answers the
## recipe, or null when *script* makes none.
static func attach(layer: SaLayer, script: Script, saved: Dictionary = {}) -> SaDrawnRecipe:
    if layer == null or script == null:
        return null
    var recipe := _made(script)
    if recipe == null:
        push_warning("SaDrawnLayer: the recipe of '%s' is not an SaDrawnRecipe, so the layer stays empty." % layer.name)
        return null
    var kept: Variant = layer.get_meta(KEPT, {})
    var source: Dictionary = saved if not saved.is_empty() else (kept if kept is Dictionary else {})
    if not source.is_empty():
        recipe.from_json(source)
    layer.remove_meta(KEPT)
    _bind(layer, recipe)
    if layer.chunks.is_empty():
        _owe(layer)
    else:
        redraw(layer, _everywhere(layer))
    return recipe


## Gives *layer*, which holds no chunk yet, a chunk under each square its
## recipe reaches, each a [Redraw] that draws itself the first time a reader
## asks for its textures. So a file opened or a layer made draws nothing at
## once, and the frames the open spreads its work across, or the view's first
## fold, draw the chunks as they reach them.
static func _owe(layer: SaLayer) -> void:
    var owed: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in regions_of([layer.recipe.bounds()]):
        var chunk := SaChunk.new()
        chunk.resolution_scale = layer.resolution_scale
        chunk.store(Redraw.new(layer, grid_pos, chunk))
        layer.set_chunk(grid_pos, chunk)
        owed[grid_pos] = SaDocument.WHOLE_CHUNK
    var document := layer.get_parent() as SaDocument
    if document != null and not owed.is_empty():
        document.invalidate_chunk_regions(owed, layer)


## Takes *layer*'s recipe away, for a type whose module has gone. The layer
## keeps its chunks as they are and the recipe's JSON, the way a scene layer
## of an uninstalled module keeps its path.
static func detach(layer: SaLayer) -> void:
    if layer == null or layer.recipe == null:
        return
    layer.set_meta(KEPT, layer.recipe.to_json())
    layer.recipe = null


## Gives *copy*, a duplicate of *source* holding copies of its chunks, a
## recipe of its own that says what the source's says.
static func copy_recipe(source: SaLayer, copy: SaLayer) -> void:
    if source == null or copy == null:
        return
    if source.has_meta(KEPT):
        var kept: Variant = source.get_meta(KEPT)
        if kept is Dictionary:
            var saved: Dictionary = kept
            copy.set_meta(KEPT, saved.duplicate(true))
    if source.recipe == null:
        return
    var held: Variant = source.recipe.get_script()
    var script: Script = held if held is Script else null
    var recipe := _made(script)
    if recipe == null:
        return
    recipe.from_json(source.recipe.to_json())
    _bind(copy, recipe)


## A new instance of *script* when it makes a recipe, and null otherwise.
static func _made(script: Script) -> SaDrawnRecipe:
    if script == null or not script.can_instantiate():
        return null
    var made: Variant = script.call(&"new")
    return made if made is SaDrawnRecipe else null


static func _bind(layer: SaLayer, recipe: SaDrawnRecipe) -> void:
    layer.recipe = recipe
    recipe.changed.connect(_on_changed.bind(layer))


static func _on_changed(rects: Array[Rect2i], layer: SaLayer) -> void:
    if is_instance_valid(layer) and layer.recipe != null:
        redraw(layer, rects)


## The recipe's bounds and the square of every chunk the layer holds, which
## a recipe drawn afresh has to reach: where it draws, and where a chunk
## stands that it may fail to cover now.
static func _everywhere(layer: SaLayer) -> Array[Rect2i]:
    var rects: Array[Rect2i] = [layer.recipe.bounds()]
    for grid_pos: Vector2i in layer.chunks:
        rects.append(Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE)))
    return rects


## Draws *layer*'s recipe again over *rects*, in document pixels, and hands
## the document what changed. Answers the regions drawn, grid position to
## chunk-local rectangle, a chunk let go among them as its whole square.
static func redraw(layer: SaLayer, rects: Array[Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var changed: Dictionary[Vector2i, Rect2i] = {}
    var recipe := layer.recipe if layer != null else null
    if recipe == null or GlobalShaderCompiler.get_rd() == null:
        return changed
    var bounds := recipe.bounds()
    var regions := regions_of(rects)
    for grid_pos: Vector2i in regions:
        var corner := grid_pos * SaChunk.SIZE
        var square := Rect2i(corner, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        var region := regions[grid_pos]
        if not square.intersects(bounds):
            if layer.chunks.has(grid_pos):
                layer.set_chunk(grid_pos, null)
                changed[grid_pos] = SaDocument.WHOLE_CHUNK
            continue
        if not region.intersects(bounds) and not layer.chunks.has(grid_pos):
            continue
        var chunk := layer.get_or_create_chunk(grid_pos)
        _clear(chunk, Rect2i(region.position - corner, region.size))
        if region.intersects(bounds):
            recipe.draw(region, chunk)
        layer.mark_unresolved(grid_pos)
        changed[grid_pos] = Rect2i(region.position - corner, region.size)
    var document := layer.get_parent() as SaDocument
    if document != null and not changed.is_empty():
        document.invalidate_chunk_regions(changed, layer)
    return changed


## *rects* cut to the chunks they cross, each part grown to whole tiles inside
## its chunk, and the parts in one chunk joined into one, in document pixels.
static func regions_of(rects: Array[Rect2i]) -> Dictionary[Vector2i, Rect2i]:
    var regions: Dictionary[Vector2i, Rect2i] = {}
    for rect in rects:
        if not rect.has_area():
            continue
        var first := Vector2i(floori(rect.position.x / float(SaChunk.SIZE)), floori(rect.position.y / float(SaChunk.SIZE)))
        var last := Vector2i(floori((rect.end.x - 1) / float(SaChunk.SIZE)), floori((rect.end.y - 1) / float(SaChunk.SIZE)))
        for grid_y in range(first.y, last.y + 1):
            for grid_x in range(first.x, last.x + 1):
                var grid_pos := Vector2i(grid_x, grid_y)
                var part := _tiled(rect.intersection(Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))))
                regions[grid_pos] = regions[grid_pos].merge(part) if regions.has(grid_pos) else part
    return regions


## *rect* grown to the tile lines round it. A chunk's side is a whole number
## of tiles, so a part inside one chunk stays inside it.
static func _tiled(rect: Rect2i) -> Rect2i:
    var start := Vector2i(floori(rect.position.x / float(TILE)), floori(rect.position.y / float(TILE))) * TILE
    var end := Vector2i(ceili(rect.end.x / float(TILE)), ceili(rect.end.y / float(TILE))) * TILE
    return Rect2i(start, end - start)


## Clears *local*, chunk-local document pixels, of *chunk*'s colour to
## transparent, at the chunk's own density. Its other fields, a mask above
## all, are the painter's and stay.
static func _clear(chunk: SaChunk, local: Rect2i) -> void:
    var albedo := chunk.albedo()
    if albedo == null:
        return
    var scale := chunk.pixel_size() / float(SaChunk.SIZE)
    var texels := Rect2i(Vector2i(Vector2(local.position) * scale), Vector2i(Vector2(local.size) * scale))
    if _clearer == null:
        _clearer = SaCompute.new("clear")
    _clearer.use_storage_format(albedo.format)
    _clearer.set_texture(0, albedo.rid)
    _clearer.set_push_constant_float_array(
        PackedFloat32Array([0.0, 0.0, texels.position.x, texels.position.y, texels.size.x, texels.size.y, 0.0, 0.0])
    )
    _clearer.dispatch_kernel("clear_chunk", SaCompute.groups_for(texels.size.x), SaCompute.groups_for(texels.size.y), 1)


## Runs *change* on *layer*'s recipe, which redraws what it touches as it
## says so, and records the step under *action_name* as the recipe's JSON
## before and after. Answers whether the recipe changed, and records nothing
## when it did not.
static func edit(layer: SaLayer, action_name: String, change: Callable) -> bool:
    if layer == null or layer.recipe == null:
        return false
    var before := layer.recipe.to_json()
    change.call(layer.recipe)
    var after := layer.recipe.to_json()
    if before == after:
        return false
    var document := layer.get_parent() as SaDocument
    if document != null and document.history != null:
        var step := Step.new(layer, before, after)
        document.history.commit_pair(action_name, step.redo, step.undo, step.bytes())
        document.modified = true
    return true


## *layer*'s recipe read back from *saved* and drawn again over its bounds
## before and after, which is an undo or a redo of an edit.
static func restore(layer: SaLayer, saved: Dictionary) -> void:
    if layer == null or layer.recipe == null:
        return
    var before := layer.recipe.bounds()
    layer.recipe.from_json(saved)
    redraw(layer, [before, layer.recipe.bounds()])


## Gives *chunk*'s textures up, a chunk of *layer* at *grid_pos*, with a
## [Redraw] to draw it again, and answers whether it did. False for a layer
## that is not drawn, and for a chunk holding a field the recipe does not
## draw, a mask, which `SaResidency` reads back as paint's.
static func let_go(layer: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> bool:
    if layer == null or not layer.is_drawn() or chunk == null or chunk.is_stored() or chunk.byte_size() == 0:
        return false
    if chunk.field_ids() != [SaFieldSpec.ALBEDO]:
        return false
    chunk.store(Redraw.new(layer, grid_pos, chunk))
    return true


## What an `SaChunk` holds in place of its textures while its layer is drawn
## and the card is full: nothing but where it stands, since the recipe can
## draw it again. Compressed bytes it keeps none of, so it counts nought in RAM.
class Redraw:
    extends SaChunk.Stored

    var _layer: WeakRef
    var _grid_pos: Vector2i
    var _scale: float

    func _init(layer: SaLayer, grid_pos: Vector2i, chunk: SaChunk) -> void:
        super(Vector2i(chunk.pixel_size(), chunk.pixel_size()), 0)
        _layer = weakref(layer)
        _grid_pos = grid_pos
        _scale = chunk.resolution_scale

    ## The chunk's square drawn afresh into new textures, transparent where
    ## the recipe draws nothing, and a layer gone or not drawn leaves it
    ## so throughout.
    func upload() -> Dictionary[StringName, SaTexture]:
        var held: Variant = _layer.get_ref()
        var layer: SaLayer = held if held is SaLayer else null
        var schema: Array[SaFieldSpec] = layer.schema if layer != null else SaFieldSpec.default_schema()
        var fresh := SaChunk.create(schema, _scale)
        fresh.clear(SaFieldSpec.NO_PAINT)
        var square := Rect2i(_grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
        if layer != null and layer.recipe != null and square.intersects(layer.recipe.bounds()):
            layer.recipe.draw(square, fresh)
        return fresh.fields


## One edit in the history: the recipe's JSON either side of it.
class Step:
    extends RefCounted

    var _layer: SaLayer
    var _before: Dictionary
    var _after: Dictionary

    func _init(layer: SaLayer, before: Dictionary, after: Dictionary) -> void:
        _layer = layer
        _before = before
        _after = after

    func undo() -> void:
        SaDrawnLayer.restore(_layer, _before)

    func redo() -> void:
        SaDrawnLayer.restore(_layer, _after)

    ## What the step holds, its two texts.
    func bytes() -> int:
        return JSON.stringify(_before).length() + JSON.stringify(_after).length()


## A change of the whole document's geometry, a crop, a Canvas Size, an Image
## Size, a flip or a quarter turn, handed to every drawn layer's recipe rather
## than to its chunks, and kept for the step's undo and redo.
##
## **Asked before the chunk walk.** The command makes one of these over its
## layers before it re-tiles any of them, so a recipe that takes the map is left
## out of the walk, [method moves_chunks] false, and is drawn again sharp at its
## new geometry instead of having its cache shifted or resampled. Its JSON on
## either side is what the step swaps, because the `.sad` keeps the recipe and
## not the chunks, and a cache moved under a recipe that stayed put is lettering
## an open draws back where it was.
##
## **A recipe that refuses becomes paint.** A map it cannot take, a quarter turn
## of text or a scale that is not uniform, leaves the layer's chunks to the walk
## as any paint layer's, and the layer gives up its recipe and its type in the
## same step, with a line in the corner saying so. So the picture shows what was
## asked and no later open draws the recipe somewhere else.
##
## Each swap is an exchange: what the layer is now goes into the held state and
## what was held goes on, so the one call undoes and redoes.
class Remap:
    extends RefCounted

    ## What the corner says of a drawn layer that became paint, by its name.
    const RASTERIZED := "'%s' could not follow this change of the picture as it is, so it is paint now."

    ## Layer to the recipe's JSON the next swap puts on, for those that took the map.
    var _held: Dictionary[Variant, Dictionary] = {}
    ## Layer to `[recipe, layer_type]` the next swap puts on, for those that refused.
    var _types: Dictionary[Variant, Array] = {}
    var _action: String
    var _first := true

    ## *map* sends a document pixel of the canvas as it stands to the one it
    ## lands on. *inside*, when it has an area, is the new canvas in those
    ## landed pixels and a recipe whose bounds reach past it refuses, for Delete
    ## Outside, which asks that nothing past the edge survive.
    func _init(layers: Array[SaLayer], map: Transform2D, action: String, inside: Rect2i = Rect2i()) -> void:
        _action = action
        for layer: SaLayer in layers:
            if layer == null or layer.recipe == null:
                continue
            var held: Variant = layer.recipe.get_script()
            var script: Script = held if held is Script else null
            var trial := SaDrawnLayer._made(script)
            var taken := false
            if trial != null:
                trial.from_json(layer.recipe.to_json())
                taken = trial.take_map(map)
                if taken and inside.has_area() and not inside.encloses(trial.bounds()):
                    taken = false
            if taken:
                _held[layer] = trial.to_json()
            else:
                _types[layer] = [null, &""]

    ## Whether the command's walk re-tiles *layer*'s chunks, false for one whose
    ## recipe took the map and is drawn again.
    func moves_chunks(layer: SaLayer) -> bool:
        return not _held.has(layer)

    ## Puts the held state on every layer, after the command has put the chunks
    ## the step holds for it, and keeps what was on for the next swap. A layer
    ## that took the map and holds no chunk yet, the first time, is owed one under
    ## each square its recipe reaches.
    func swap() -> void:
        for layer: Variant in _held:
            if not is_instance_valid(layer):
                continue
            var drawn: SaLayer = layer
            if drawn.recipe == null:
                continue
            var now := drawn.recipe.to_json()
            drawn.recipe.from_json(_held[layer])
            _held[layer] = now
            if drawn.chunks.is_empty():
                SaDrawnLayer._owe(drawn)
        for layer: Variant in _types:
            if not is_instance_valid(layer):
                continue
            var changing: SaLayer = layer
            var was: Array = [changing.recipe, changing.layer_type]
            var recipe: SaDrawnRecipe = _types[layer][0]
            if changing.recipe != null:
                # By the method, since the connection holds a bound callable.
                for connection: Dictionary in changing.recipe.changed.get_connections():
                    var callable: Callable = connection["callable"]
                    if callable.get_method() == &"_on_changed":
                        changing.recipe.changed.disconnect(callable)
                changing.recipe = null
            changing.layer_type = _types[layer][1]
            if recipe != null:
                SaDrawnLayer._bind(changing, recipe)
            _types[layer] = was
            if _first:
                SaProblems.refuse(_action, TranslationServer.translate(RASTERIZED) % changing.name)
        _first = false
