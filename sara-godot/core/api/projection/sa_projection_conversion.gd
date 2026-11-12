## Image > Projection's Convert: every layer of a document redrawn from its
## projection into another, so the picture stays where it was in the view and
## the pixels that make it move, as one history step. Between flat and polar it
## is what other programs sell as a Polar Coordinates filter, and a change of
## orientation alone is a convert too. Reached through `SaProjection.reproject`,
## the folder's facade, and named nowhere else.
##
## **No kind is named here.** A target texel goes through the target kind's
## `to_view`, across a bridge between the two kinds of view, and back through
## the source kind's `from_view`, so a kind a module registers converts as the
## built-ins do. The bridges are by view, never by kind:
##
## - a canvas and a disc meet as the disc inscribed in the canvas,
## - a canvas and a sphere as the sphere seen through a pinhole a quarter turn
##   wide, looking straight ahead with the canvas's middle on the horizon,
## - a disc and a sphere as the map that keeps the distance from the zenith,
##   the disc's rim the nadir, so equirectangular and polar in one orientation
##   lay their pixels out alike.
##
## **The canvas size is the pair's**, chosen so the picture keeps its pixels
## where it is densest, which [method size_for] says pair by pair.
##
## **The map runs on the CPU and the pixels on the GPU.** A kind is GDScript, so
## the map is evaluated at a lattice over each target chunk, as coarse as an
## eighth of a texel allows and down to every texel round a pole, and
## `reproject.gmacs` reads between its points. Each target chunk gathers from
## the source chunks its reads land in, its footprint, and one whose footprint
## covers no chunk the layer holds is never made. Only the lattice crosses to
## the GPU, and no pixel leaves it.
##
## **What keeps its record.** A generated layer evaluates its kernel over
## whatever the canvas is, a filter layer reads the backdrop, and an effect or
## a scene layer's chunks are a cache, so none of them holds pixels to move and
## each keeps its record as it was, which [method note] says. Their masks are
## pixels, and move with the picture at their rest, as a group's and an
## attached filter's do.
class_name SaProjectionConversion
extends RefCounted

## What the undo menu calls this.
const ACTION_NAME := "Convert Projection"
const SHADER := "reproject"
## The ceiling File > New and Image Size use.
const MAX_DIMENSION := 16384
## How far, in source texels, a read blended out of the lattice may stray from
## the map's own answer.
const TOLERANCE := 0.125
## The widest a lattice is drawn, in texels between its points.
const COARSEST := 16
## Lattice cells to a side of the block one footprint box is taken over.
const BLOCK := 8
## How far past an edge that joins nothing a read may lie and still reach the
## picture with a tap, in texels.
const REACH := 1.5
## The largest coordinate a read keeps, past which a float on the GPU no
## longer holds a texel apart from the next.
const FAR := 1.0e6

var _document: SaDocument
var _source: SaProjection
var _target: SaProjection
var _source_size: Vector2i
var _target_size: Vector2i
## The size of the document a canvas view is the pixels of, the flat side's.
var _canvas: Vector2
var _wraps_x: bool
var _wraps_y: bool
## Whether the source kind folds a read past its top or bottom edge over to
## the far side, and how many pixels across it lands.
var _folds_top := false
var _shift_top := 0.0
var _folds_bottom := false
var _shift_bottom := 0.0
var _compute: SaCompute = null
## Every density's lattices by target chunk, made on first use and read by
## every layer at that density.
var _lattices: Dictionary[float, Dictionary] = {}
## How many chunks `run` has worked out for layers, as `SaCrop.chunks_made`
## counts them. Read by a suite.
var chunks_made := 0


## *target* null leaves the document as it is, and so does a *document* null.
func _init(document: SaDocument, target: SaProjection) -> void:
    _document = document
    _source = document.projection if document != null else SaProjection.new()
    _target = target if target != null else _source
    _source_size = document.canvas_size if document != null else Vector2i.ONE
    _target_size = size_for(_source, _target, _source_size)
    var flat_side := _target_size if _target.kind.view == SaProjection.View.CANVAS else _source_size
    _canvas = Vector2(flat_side)
    _wraps_x = _source.wrapping != SaProjection.Wrap.NONE
    _wraps_y = _source.wrapping == SaProjection.Wrap.XY
    # Asked of the kind rather than known of it: a read half a pixel past each
    # edge, and where the kind's fold brings it back inside.
    var size := Vector2(_source_size)
    var top := _source.fold(Vector2(0.5, -0.5), size)
    _folds_top = not _wraps_y and top.y >= 0.0
    _shift_top = fposmod(top.x - 0.5, size.x)
    var bottom := _source.fold(Vector2(0.5, size.y + 0.5), size)
    _folds_bottom = not _wraps_y and bottom.y <= size.y
    _shift_bottom = fposmod(bottom.x - 0.5, size.x)


## The canvas a document of *size* in projection *from* takes in *to*, by the
## two kinds of view and never by kind.
##
## - The same view keeps the size, so a change of orientation, or between
##   equirectangular and polar, keeps every pixel's place on the canvas.
## - A canvas to a disc is TAU r by r for the inscribed radius r, a pixel
##   across the rim and down a radius each the canvas's own, and a disc to a
##   canvas is the square twice the disc's height, which is its inverse.
## - A canvas to a sphere is pi times its width across and half that down, so
##   the canvas's middle keeps its density, and a sphere to a canvas is the
##   square a pi-th of the width across, its inverse.
static func size_for(from: SaProjection, to: SaProjection, size: Vector2i) -> Vector2i:
    var out := size
    var a := from.kind.view
    var b := to.kind.view
    if a == SaProjection.View.CANVAS and b == SaProjection.View.DISC:
        var radius := mini(size.x, size.y) * 0.5
        out = Vector2i(roundi(TAU * radius), roundi(radius))
    elif a == SaProjection.View.DISC and b == SaProjection.View.CANVAS:
        out = Vector2i(2 * size.y, 2 * size.y)
    elif a == SaProjection.View.CANVAS and b == SaProjection.View.SPHERE:
        var half := roundi(PI * size.x * 0.5)
        out = Vector2i(2 * half, half)
    elif a == SaProjection.View.SPHERE and b == SaProjection.View.CANVAS:
        var side := roundi(size.x / PI)
        out = Vector2i(side, side)
    return out.clamp(Vector2i.ONE, Vector2i(MAX_DIMENSION, MAX_DIMENSION))


## The sentence the dialog says a convert of *document* to *target* in: the
## size the canvas takes, and the layers that hold no pixels and keep their
## record.
static func note(document: SaDocument, target: SaProjection) -> String:
    if document == null or target == null:
        return ""
    if target.matches(document.projection):
        return String(TranslationServer.translate("The pixels are that projection already, so Convert has nothing to move."))
    var size := size_for(document.projection, target, document.canvas_size)
    var words := String(TranslationServer.translate("Convert redraws every layer's pixels at %s by %s.")) % [size.x, size.y]
    var moving: Array[SaLayer] = []
    var kept: Array[SaLayer] = []
    _sort(document, document, moving, kept)
    if kept.is_empty():
        return words
    var said := TranslationServer.translate_plural(
        "%d filter, generated or scene layer holds no pixels and keeps its record.",
        "%d filter, generated or scene layers hold no pixels and keep their record.",
        kept.size()
    )
    return "%s %s" % [words, String(said) % kept.size()]


## *point* of a view of kind *from* carried to a view of kind *to*. *canvas* is
## the size of the document a canvas view is the pixels of. NAN in x where the
## bridge has no point, which is behind a canvas looking at a sphere.
static func bridge(point: Vector3, from: SaProjection.View, to: SaProjection.View, canvas: Vector2) -> Vector3:
    if from == to:
        return point
    var radius := minf(canvas.x, canvas.y) * 0.5
    var middle := canvas * 0.5
    var half := canvas.x * 0.5
    if from == SaProjection.View.CANVAS and to == SaProjection.View.DISC:
        return Vector3((point.x - middle.x) / radius, (middle.y - point.y) / radius, 0.0)
    if from == SaProjection.View.DISC and to == SaProjection.View.CANVAS:
        return Vector3(middle.x + radius * point.x, middle.y - radius * point.y, 0.0)
    if from == SaProjection.View.CANVAS:
        return Vector3((point.x - middle.x) / half, (middle.y - point.y) / half, -1.0).normalized()
    if to == SaProjection.View.CANVAS:
        var seen := point.normalized()
        if seen.z > -0.000001:
            return Vector3(NAN, NAN, NAN)
        return Vector3(middle.x + half * seen.x / -seen.z, middle.y - half * seen.y / -seen.z, 0.0)
    var across := Vector2(point.x, point.y)
    if from == SaProjection.View.DISC:
        var out := across.length()
        var turned := out * PI
        var way := across / out if out > 0.0 else Vector2(0.0, 1.0)
        return Vector3(sin(turned) * way.x, cos(turned), -sin(turned) * way.y)
    var ray := point.normalized()
    var from_zenith := acos(clampf(ray.y, -1.0, 1.0)) / PI
    var level := Vector2(ray.x, -ray.z)
    var heading := level / level.length() if level.length() > 0.0 else Vector2(0.0, 1.0)
    return Vector3(heading.x * from_zenith, heading.y * from_zenith, 0.0)


## Redraws every layer and mask into the target projection, puts the size and
## the projection on the document and records the step. False when there is
## nothing to convert or no GPU to draw with.
func run() -> bool:
    if _document == null or _target.matches(_source) or GlobalShaderCompiler.get_rd() == null:
        return false
    var moving: Array[SaLayer] = []
    var kept: Array[SaLayer] = []
    _sort(_document, _document, moving, kept)
    # Keyed by Variant, because a typed key refuses a layer that was freed.
    var before: Dictionary[Variant, Dictionary] = {}
    var after: Dictionary[Variant, Dictionary] = {}
    for layer: SaLayer in moving:
        before[layer] = layer.chunks.duplicate()
        var twin := SaCrop.done_user(layer, after)
        if twin != null:
            after[layer] = after[twin]
            continue
        after[layer] = _redrawn(layer.chunks, layer.schema, layer.resolution_scale, {})
        chunks_made += after[layer].size()
    var masks_before: Dictionary[Variant, Dictionary] = {}
    var masks_after: Dictionary[Variant, Dictionary] = {}
    for mask: SaMask in SaCrop.own_masks(_document):
        masks_before[mask] = mask.chunks.duplicate()
        masks_after[mask] = _redrawn(mask.chunks, SaMask.schema(), 1.0, SaCrop.at_rest(mask))
    _lattices.clear()
    _compute = null
    var exchange := SaCanvasExchange.new(_document, _source_size, before, masks_before, _put_back, Rect2i(), false, _source)
    _apply(_target_size, after, masks_after, _target)
    exchange.commit(ACTION_NAME)
    return true


## Every layer under *from* into *moving* when its chunks are its pixels and
## into *kept* when it holds none and keeps its record. A group holds none of
## its own and is neither, and the stroke buffer is transient.
static func _sort(document: SaDocument, from: Node, moving: Array[SaLayer], kept: Array[SaLayer]) -> void:
    for child: Node in from.get_children():
        var layer := child as SaLayer
        if layer == null or layer == document.stroke_layer:
            continue
        if layer.is_generated() or layer.is_adjustment() or layer.is_effect() or layer.is_scene():
            kept.append(layer)
        elif not layer.is_group:
            moving.append(layer)
        _sort(document, layer, moving, kept)


## The chunks a store of *chunks* holds once redrawn into the target, a layer's
## with its *schema* at its *density* or an own mask's, whose *blanks* is its
## rest. A target chunk is made only where its footprint covers one it holds.
func _redrawn(
    chunks: Dictionary[Vector2i, SaChunk], schema: Array[SaFieldSpec], density: float, blanks: Dictionary[StringName, Color]
) -> Dictionary[Vector2i, SaChunk]:
    var fresh: Dictionary[Vector2i, SaChunk] = {}
    if not chunks.values().any(func(chunk: SaChunk) -> bool: return chunk != null):
        return fresh
    for grid_pos: Vector2i in SaLayer.grid_positions(_target_size):
        var lattice := _lattice(grid_pos, density)
        var sources: Array[Vector2i] = []
        for held: Vector2i in lattice.reads:
            if chunks.get(held, null) != null:
                sources.append(held)
        if sources.is_empty():
            continue
        var chunk := SaChunk.create(schema, density)
        for field_id: StringName in blanks:
            chunk.blanks[field_id] = blanks[field_id]
        # A lazy field, height, comes along where a chunk it reads holds one.
        for held: Vector2i in sources:
            for field_id: StringName in chunks[held].fields:
                var spec := SaFieldSpec.find(schema, field_id)
                if spec != null and spec.lazy and not chunk.has_field(field_id):
                    chunk.add_sparse_field(spec)
        for field_id: StringName in chunk.fields:
            _draw(chunk, field_id, schema, chunks, sources, lattice, density)
        fresh[grid_pos] = chunk
    return fresh


## One field of a fresh *chunk*: cleared, every source chunk at *sources* added
## over the part of the chunk that reads it, and a colour field divided
## through by its alpha.
func _draw(
    chunk: SaChunk,
    field_id: StringName,
    schema: Array[SaFieldSpec],
    chunks: Dictionary[Vector2i, SaChunk],
    sources: Array[Vector2i],
    lattice: Lattice,
    density: float
) -> void:
    var into: SaTexture = chunk.fields[field_id]
    var spec := SaFieldSpec.find(schema, field_id)
    var colour := spec == null or spec.is_color
    var rest: Color = chunk.blanks.get(field_id, SaFieldSpec.NO_PAINT)
    var edge := chunk.pixel_size()
    var whole := Rect2i(0, 0, edge, edge)
    var compute := _kernel(into.format)
    var reading := Reading.new(lattice, density, colour, rest)
    _run(compute, "reproject_clear", into, into, whole, Vector2i.ZERO, reading)
    for held: Vector2i in sources:
        var source: SaChunk = chunks[held]
        var from := source.field(field_id)
        if from == null:
            continue
        _run(compute, "reproject_gather", into, from, lattice.reads[held], held * source.pixel_size(), reading)
    if colour:
        _run(compute, "reproject_settle", into, into, whole, Vector2i.ZERO, reading)


## One dispatch of *kernel* over *region* of *into* reading *from*, whose chunk
## starts at the layer's texel *origin*.
func _run(
    compute: SaCompute, kernel: String, into: SaTexture, from: SaTexture, region: Rect2i, origin: Vector2i, reading: Reading
) -> void:
    if not region.has_area():
        return
    var texels := SaCrop.texels(_source_size, reading.density)
    var rest := reading.rest
    compute.set_texture(0, into.rid)
    compute.set_texture(1, from.rid)
    compute.set_texture(2, reading.lattice.texture.rid)
    (
        compute
        . set_push_constant_float_array(
            PackedFloat32Array(
                [
                    region.position.x,
                    region.position.y,
                    region.size.x,
                    region.size.y,
                    origin.x,
                    origin.y,
                    reading.lattice.step,
                    1.0 if _wraps_y else 0.0,
                    texels.x,
                    texels.y,
                    1.0 if _wraps_x else 0.0,
                    1.0 if reading.colour else 0.0,
                    1.0 if _folds_top else 0.0,
                    roundi(_shift_top * reading.density),
                    1.0 if _folds_bottom else 0.0,
                    roundi(_shift_bottom * reading.density),
                    rest.r,
                    rest.g,
                    rest.b,
                    rest.a,
                ]
            )
        )
    )
    compute.dispatch_kernel(kernel, SaCompute.groups_for(region.size.x), SaCompute.groups_for(region.size.y), 1)


func _kernel(format: int) -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    _compute.use_storage_format(format)
    return _compute


## The lattice of the target chunk at *grid_pos* at *density*, measured once.
func _lattice(grid_pos: Vector2i, density: float) -> Lattice:
    if not _lattices.has(density):
        _lattices[density] = {}
    var held: Dictionary = _lattices[density]
    if not held.has(grid_pos):
        held[grid_pos] = _measure(grid_pos, density)
    return held[grid_pos]


## The coarsest lattice over the chunk at *grid_pos* whose blend stays within
## TOLERANCE of the map. Each step is tried against the points of the one
## half as wide, which are the points the next try is made of, so no point is
## worked out twice for the test. Only the part of the chunk inside the target
## canvas is measured, because nothing past it is drawn.
func _measure(grid_pos: Vector2i, density: float) -> Lattice:
    var edge := _edge(density)
    var inside := (SaCrop.texels(_target_size, density) - grid_pos * edge).clamp(Vector2i.ZERO, Vector2i(edge, edge))
    var texels := Vector2(SaCrop.texels(_source_size, density))
    var step := COARSEST
    while step > 1 and edge % step != 0:
        step /= 2
    var fine := _points(grid_pos, density, edge, maxi(1, step >> 1), inside)
    while step > 1:
        var side := _side(fine)
        if _fits(fine, side, step >> 1, inside, texels):
            var coarse := _every_other(fine, side)
            return Lattice.new(coarse, step, _footprint(coarse, step, density, inside))
        step /= 2
        if step > 1:
            fine = _points(grid_pos, density, edge, step >> 1, inside)
    return Lattice.new(fine, 1, _footprint(fine, 1, density, inside))


## The points to a side of a square lattice of *points*.
static func _side(points: PackedVector3Array) -> int:
    return roundi(sqrt(float(points.size())))


## The texels to a side of a chunk at *density*, which the chunk says.
static func _edge(density: float) -> int:
    var none: Array[SaFieldSpec] = []
    return SaChunk.create(none, density).pixel_size()


## The map at every *step*-th texel of the chunk at *grid_pos*, a row at a
## time, each the source texel it reads and one in z where the map gives one.
## A point further past *inside*, the texels of the chunk the target canvas
## covers, than the coarsest step is never blended and stays empty. A wrapping
## axis is unwrapped against the point before, so a blend between two
## neighbours never crosses the canvas the long way round.
func _points(grid_pos: Vector2i, density: float, edge: int, step: int, inside: Vector2i) -> PackedVector3Array:
    var side := roundi(float(edge) / step) + 1
    var texels := Vector2(SaCrop.texels(_source_size, density))
    var origin := Vector2(grid_pos * edge) + Vector2(0.5, 0.5)
    var out := PackedVector3Array()
    out.resize(side * side)
    for row in side:
        for column in side:
            if row * step >= inside.y + COARSEST or column * step >= inside.x + COARSEST:
                out[row * side + column] = Vector3.ZERO
                continue
            var at := _map((origin + Vector2(column * step, row * step)) / density) * density - Vector2(0.5, 0.5)
            if not _usable(at):
                out[row * side + column] = Vector3.ZERO
                continue
            var near := Vector3.ZERO
            if column > 0:
                near = out[row * side + column - 1]
            if near.z == 0.0 and row > 0:
                near = out[(row - 1) * side + column]
            if near.z > 0.0 and _wraps_x:
                at.x += roundf((near.x - at.x) / texels.x) * texels.x
            if near.z > 0.0 and _wraps_y:
                at.y += roundf((near.y - at.y) / texels.y) * texels.y
            out[row * side + column] = Vector3(at.x, at.y, 1.0)
    return out


## The source pixel the target pixel *pixel* shows, NAN where it shows none.
func _map(pixel: Vector2) -> Vector2:
    var view := _target.to_view(pixel, Vector2(_target_size))
    var carried := bridge(view, _target.kind.view, _source.kind.view, _canvas)
    if is_nan(carried.x):
        return Vector2(NAN, NAN)
    return _source.from_view(carried, Vector2(_source_size))


## Whether the map gave a point at all, a number and not one so far off that a
## blend of it would lose the texels near it.
static func _usable(at: Vector2) -> bool:
    return not (is_nan(at.x) or is_nan(at.y) or absf(at.x) > FAR or absf(at.y) > FAR)


## Whether a read at *point*, in source texels of a canvas *texels* across,
## lands no tap on the picture: no point, or past an edge the kind neither
## wraps nor folds by more than a tap reaches.
func _reads_nothing(point: Vector3, texels: Vector2) -> bool:
    if point.z == 0.0:
        return true
    if not _wraps_x and (point.x < -REACH or point.x > texels.x - 1.0 + REACH):
        return true
    if not _wraps_y and not _folds_top and point.y < -REACH:
        return true
    return not _wraps_y and not _folds_bottom and point.y > texels.y - 1.0 + REACH


## Whether the lattice of every other point of *fine*, *side* to a side and
## *half* texels apart, reads within TOLERANCE of the map at the points
## between that lie inside the target canvas, the first *inside* texels. Where
## the map, its corners and their blend all read nothing, as past the rim of a
## disc or round the far side of a gnomonic view, any blend fits, and a point
## between that reads where a corner gives no point does not.
func _fits(fine: PackedVector3Array, side: int, half: int, inside: Vector2i, texels: Vector2) -> bool:
    for row in side:
        if row * half >= inside.y:
            break
        for column in side:
            if column * half >= inside.x:
                break
            if row % 2 == 0 and column % 2 == 0:
                continue
            var left := column - column % 2
            var right := column + column % 2
            var up := row - row % 2
            var down := row + row % 2
            var corners := PackedVector3Array(
                [fine[up * side + left], fine[up * side + right], fine[down * side + left], fine[down * side + right]]
            )
            var actual := fine[row * side + column]
            var whole := true
            var nothing := _reads_nothing(actual, texels)
            var sum := Vector2.ZERO
            for corner: Vector3 in corners:
                whole = whole and corner.z > 0.0
                nothing = nothing and _reads_nothing(corner, texels)
                sum += Vector2(corner.x, corner.y)
            var blend := sum / 4.0
            if nothing and _reads_nothing(Vector3(blend.x, blend.y, 1.0 if whole else 0.0), texels):
                continue
            if not whole or actual.z == 0.0:
                return false
            if absf(blend.x - actual.x) > TOLERANCE or absf(blend.y - actual.y) > TOLERANCE:
                return false
    return true


static func _every_other(fine: PackedVector3Array, side: int) -> PackedVector3Array:
    var coarse_side := ((side - 1) >> 1) + 1
    var out := PackedVector3Array()
    out.resize(coarse_side * coarse_side)
    for row in coarse_side:
        for column in coarse_side:
            out[row * coarse_side + column] = fine[2 * row * side + 2 * column]
    return out


## Which source chunks the lattice *points*, *step* texels apart, reads, each
## with the part of the target chunk that reads it, in chunk-local texels. A
## block of lattice cells at a time, and only the cells inside the target
## canvas, the first *inside* texels of the chunk: the box round the points
## that bound them, grown by the taps a bilinear read takes and the float a
## blend can drift by.
func _footprint(points: PackedVector3Array, step: int, density: float, inside: Vector2i) -> Dictionary[Vector2i, Rect2i]:
    var side := _side(points)
    var cells := side - 1
    var edge := _edge(density)
    var drawn := Rect2i(Vector2i.ZERO, inside)
    var reads: Dictionary[Vector2i, Rect2i] = {}
    for top in range(0, cells, BLOCK):
        for left in range(0, cells, BLOCK):
            var region := Rect2i(Vector2i(left, top) * step, Vector2i(BLOCK, BLOCK) * step).intersection(drawn)
            if not region.has_area():
                continue
            var last := Vector2i((Vector2(region.end - Vector2i.ONE) / step).floor()) + Vector2i.ONE
            last = last.min(Vector2i(cells, cells))
            var low := Vector2(INF, INF)
            var high := Vector2(-INF, -INF)
            for row in range(top, last.y + 1):
                for column in range(left, last.x + 1):
                    var point := points[row * side + column]
                    if point.z > 0.0:
                        low = low.min(Vector2(point.x, point.y))
                        high = high.max(Vector2(point.x, point.y))
            if low.x > high.x:
                continue
            var from := Vector2i(floori(low.x) - 1, floori(low.y) - 1)
            var box := Rect2i(from, Vector2i(floori(high.x) + 3, floori(high.y) + 3) - from)
            for held: Vector2i in _under(box, density, edge):
                reads[held] = reads[held].merge(region) if reads.has(held) else region
    return reads


## The source chunks *box*, in the layer's texels, lies over once the kind's
## edges have brought every part of it back inside: across a wrap, and over a
## fold to the far side.
func _under(box: Rect2i, density: float, edge: int) -> Array[Vector2i]:
    var texels := SaCrop.texels(_source_size, density)
    var last := box.end - Vector2i.ONE
    # Each part is its rows and the texels its columns shift by.
    var parts: Array[Vector3i] = [Vector3i(box.position.y, last.y, 0)]
    if _folds_top and box.position.y < 0:
        parts.append(Vector3i(0, -1 - box.position.y, roundi(_shift_top * density)))
    if _folds_bottom and last.y >= texels.y:
        parts.append(Vector3i(2 * texels.y - 1 - last.y, texels.y - 1, roundi(_shift_bottom * density)))
    var found: Array[Vector2i] = []
    for part: Vector3i in parts:
        for rows: Vector2i in _spans(part.x, part.y, texels.y, _wraps_y):
            for columns: Vector2i in _spans(box.position.x + part.z, last.x + part.z, texels.x, _wraps_x):
                for grid_y in range(floori(rows.x / float(edge)), floori(rows.y / float(edge)) + 1):
                    for grid_x in range(floori(columns.x / float(edge)), floori(columns.y / float(edge)) + 1):
                        if not found.has(Vector2i(grid_x, grid_y)):
                            found.append(Vector2i(grid_x, grid_y))
    return found


## The inclusive run *low* to *high* inside a canvas *limit* texels long, as
## the runs it is once a wrap has brought it round, or clipped where it does
## not wrap.
static func _spans(low: int, high: int, limit: int, wraps: bool) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if high < low:
        return out
    if wraps:
        if high - low + 1 >= limit:
            out.append(Vector2i(0, limit - 1))
            return out
        var first := posmod(low, limit)
        var past := first + high - low
        out.append(Vector2i(first, mini(past, limit - 1)))
        if past >= limit:
            out.append(Vector2i(0, past - limit))
        return out
    var start := maxi(low, 0)
    var end := mini(high, limit - 1)
    if start <= end:
        out.append(Vector2i(start, end))
    return out


## Puts *size*, every store's *chunks* and *masks* and *projection* on the
## document, and tells everything that draws it. The selection is dropped, for
## the reason `SaResample` gives: its chunks are in the old pixels. A size kept
## keeps the view where it was, and a new one has the view fit it afresh.
func _apply(
    size: Vector2i, chunks: Dictionary[Variant, Dictionary], masks: Dictionary[Variant, Dictionary], projection: SaProjection
) -> void:
    var source := Rect2i(Vector2i.ZERO, size) if size == _document.canvas_size else Rect2i()
    # The picture is drawn again at the new size, so the side a brush is read
    # against is scaled the way `SaResample._apply` scales it, and an undo
    # brings back the side an earlier crop kept.
    var side := _document.brush_side * minf(size.x, size.y) / minf(_document.canvas_size.x, _document.canvas_size.y)
    _document.canvas_size = size
    _document.brush_side = side
    for layer: SaLayer in chunks:
        # Emptied and refilled by key, because the layer's dictionary is typed
        # and refuses a plain one, the silent no-op `SaCrop` records.
        var wanted := SaTyped.chunks(chunks[layer])
        layer.chunks.clear()
        for grid_pos: Vector2i in wanted:
            layer.chunks[grid_pos] = wanted[grid_pos]
        layer.mark_all_unresolved()
    SaCrop.put_masks(_document, masks)
    _document.projection = projection
    _document.selection.deselect_and_forget()
    _document.modified = true
    _document.update_caches()
    _document.invalidate_all_allocated_chunks()
    _document.resize_source = source
    EventBus.document_resized.emit(_document, size)
    _document.resize_source = Rect2i()
    _document.document_changed.emit()


## What `SaCanvasExchange` puts back at an undo or a redo.
func _put_back(
    size: Vector2i,
    chunks: Dictionary[Variant, Dictionary],
    masks: Dictionary[Variant, Dictionary],
    _from: Rect2i,
    projection: SaProjection
) -> void:
    _apply(size, chunks, masks, projection)


## One target chunk's lattice: its points on the GPU, *step* texels apart, and
## the source chunks they read with the part of the chunk that reads each.
class Lattice:
    extends RefCounted

    var step: int
    var texture: SaTexture
    var reads: Dictionary[Vector2i, Rect2i]

    func _init(points: PackedVector3Array, lattice_step: int, footprint: Dictionary[Vector2i, Rect2i]) -> void:
        step = lattice_step
        reads = footprint
        var side := int(sqrt(float(points.size())) + 0.5)
        var floats := PackedFloat32Array()
        floats.resize(points.size() * 4)
        for index in points.size():
            var point := points[index]
            floats[index * 4] = point.x
            floats[index * 4 + 1] = point.y
            floats[index * 4 + 2] = point.z
        texture = SaTexture.new(Vector2i(side, side), RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
        GlobalShaderCompiler.get_rd().texture_update(texture.rid, 0, floats.to_byte_array())


## What one field's dispatches share: the lattice, the layer's density, and
## whether the field is colour or reads *rest* where nothing is held.
class Reading:
    extends RefCounted

    var lattice: Lattice
    var density: float
    var colour: bool
    var rest: Color

    func _init(of: Lattice, at_density: float, is_colour: bool, at_rest: Color) -> void:
        lattice = of
        density = at_density
        colour = is_colour
        rest = at_rest
