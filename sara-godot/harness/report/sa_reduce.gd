## The sum, the mean, the minimum and the maximum of a layer's channels over a
## rectangle, reduced on the graphics card.
##
## The notebook's `sara_array.py` needs these four as reductions, and a notebook
## asks them cheaply here without reading a layer back. Every channel is the
## stored value in the document's own space, in float, so a value below zero
## or above one reduces as it is (hard rule 5).
##
## **Passes on the card, a record read back.** `shaders/compute/reduce.gmacs`
## folds each workgroup of sixty-four texels into one record of sixteen floats
## in shared memory, one dispatch per chunk the rectangle covers, through
## [SaChunkWalk] like every pass that honours hard rules 2 and 3. Then it
## folds sixty-four records into one, pass after pass, between two buffers
## taken in turn, until one record is left, and only those sixty-four bytes
## cross the bus. A chunk of 256 is 1024 records, so one chunk takes two folds
## and a canvas of forty chunks takes three. The fold is a tree, so the float
## sum loses what a pairwise sum loses and not what a running total does.
##
## **An unallocated chunk is zero.** A layer holds nothing where it has no
## chunk, and a reader of the layer as an array reads zeros there. So the
## texels of the rectangle no chunk holds are counted on the processor as
## zeros: they add nothing to the sum, they count in the mean, and they bring
## zero into the minimum and the maximum. No dispatch touches them, which is
## what makes the dispatch count follow the chunks and not the canvas.
##
## Nothing here runs during a stroke. The readback is the allowance hard rule 1
## gives the `texel` step, widened to a reduction whose answer is a handful of
## numbers, the same shape [SaMeasure] reads.
class_name SaReduce
extends RefCounted

## The kernel file, by the name `SaCompute` resolves under `shaders/compute/`.
const SHADER := "reduce"

## Where `reduce.gmacs` reads and writes its records. Binding 0 is the chunk's
## own field, which the walk binds.
const BINDING_SOURCE: int = 1
const BINDING_TARGET: int = 2

## Floats in a record, the kernel's RECORD, and the texels or records one
## workgroup folds, its LANES.
const RECORD: int = 16
const LANES: int = 64

## The four operations the step answers, in the order a line prints them.
const OPERATIONS: Array[String] = ["sum", "mean", "min", "max"]

## The layer reduced. A constructor argument because that is how a thing
## outside this class sets what it owns.
var _layer: SaLayer = null

## Built on first use, so a reduction over nothing allocates no pipelines.
var _compute: SaCompute = null

## The records pass one has handed out so far, which is where the next chunk
## starts writing. Reset at the start of every reduction.
var _written: int = 0


## *compute* is one a caller reducing many layers in a row hands every one of
## them, so the layers step builds the kernel's pipelines once and not once a
## layer, and null builds this reduction its own on first use.
func _init(layer: SaLayer, compute: SaCompute = null) -> void:
    _layer = layer
    _compute = compute


## The reduction of the layer over *rect*, in document pixels.
##
## `texels` is the area of *rect* and `allocated` how many of those a chunk
## holds, both in document pixels on a layer at any scale. `sum`, `mean`, `min` and `max` are four floats each, red, green, blue
## and alpha. An empty rectangle answers a zero sum and null for the other
## three, because there is no texel to take a mean, a least or a most of, and
## a zero there would read as a value.
func reduce(rect: Rect2i) -> Dictionary:
    var area := maxi(rect.size.x, 0) * maxi(rect.size.y, 0)
    if area <= 0 or _layer == null:
        return _answer(area, 0, Vector4.ZERO, null, null)

    var allocated := 0
    var sum := Vector4.ZERO
    var least: Variant = null
    var most: Variant = null
    for side: int in _sides_in(rect):
        # A chunk at 2.0 holds four texels over one document pixel, so each
        # texel weighs the document area it covers and the answer is the
        # document's whatever scale the layer was painted at.
        var weight := float(SaChunk.SIZE * SaChunk.SIZE) / float(side * side)
        var record := _reduce_chunks(rect, side)
        var held := int(record[0])
        if held <= 0:
            continue
        allocated += int(round(held * weight))
        sum += Vector4(record[4], record[5], record[6], record[7]) * weight
        var low := Vector4(record[8], record[9], record[10], record[11])
        var high := Vector4(record[12], record[13], record[14], record[15])
        least = low if least == null else (least as Vector4).min(low)
        most = high if most == null else (most as Vector4).max(high)
    if allocated < area:
        # The zeros of the texels no chunk holds.
        least = Vector4.ZERO if least == null else (least as Vector4).min(Vector4.ZERO)
        most = Vector4.ZERO if most == null else (most as Vector4).max(Vector4.ZERO)
    return _answer(area, allocated, sum, least, most)


## The edges in texels of the chunks *rect* reaches, each once, so every
## scale the layer's chunks are stored at reduces on its own and is weighed.
func _sides_in(rect: Rect2i) -> Array[int]:
    var out: Array[int] = []
    for grid_pos in SaChunkWalk.positions_in(rect):
        var chunk: SaChunk = _layer.chunks.get(grid_pos, null)
        if chunk != null and chunk.has_field(SaFieldSpec.ALBEDO) and not out.has(chunk.pixel_size()):
            out.append(chunk.pixel_size())
    return out


## Pass one over every allocated chunk in *rect* stored *side* texels across,
## then the folds, and the one record they end in, counted in texels. Sixteen
## zeros when no such chunk held a texel of *rect*.
func _reduce_chunks(rect: Rect2i, side: int) -> PackedFloat32Array:
    var nothing := PackedFloat32Array()
    nothing.resize(RECORD)
    nothing.fill(0.0)

    # Room for every workgroup a chunk's whole texture could take, because the
    # walk decides each chunk's share only as it reaches it. A chunk of 256 is
    # 64 KiB of records, and only the records written are folded.
    var room := 0
    for grid_pos in SaChunkWalk.positions_in(rect):
        var chunk: SaChunk = _layer.chunks.get(grid_pos, null)
        if chunk != null and chunk.has_field(SaFieldSpec.ALBEDO) and chunk.pixel_size() == side:
            var groups := SaCompute.groups_for(side)
            room += groups * groups
    if room <= 0:
        return nothing

    var empty := PackedFloat32Array()
    empty.resize(room * RECORD)
    empty.fill(0.0)
    var first := SaCompute.Buffer.new(empty.to_byte_array())
    var second := SaCompute.Buffer.new(empty.to_byte_array())
    var compute := _get_compute()
    _written = 0
    var walk := SaChunkWalk.new(compute, null, null, SaFieldSpec.ALBEDO)
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        var chunk: SaChunk = _layer.chunks.get(grid_pos, null)
        return chunk if chunk != null and chunk.pixel_size() == side else null
    walk.run("reduce_chunk", rect, chunk_at, _push_chunk, {BINDING_SOURCE: second, BINDING_TARGET: first})
    if _written <= 0:
        return nothing

    # Each fold reads what the last wrote. Binding 0 still holds the last
    # chunk the walk bound, which the fold never reads, so the uniform set is
    # whole without a stand-in.
    var from := first
    var into := second
    var count := _written
    while count > 1:
        var groups := ceili(float(count) / LANES)
        compute.set_buffer(BINDING_SOURCE, from.rid)
        compute.set_buffer(BINDING_TARGET, into.rid)
        compute.set_push_constant_float_array(_fold_params(count))
        compute.dispatch_kernel("reduce_fold", groups, 1, 1)
        var swap := from
        from = into
        into = swap
        count = groups
    return from.read(0, RECORD * 4).to_float32_array()


## The push constant for one stop of the walk, in the order `reduce.gmacs`
## declares its block, and the records that stop writes handed out.
func _push_chunk(_grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
    var groups := Vector2i(SaCompute.groups_for(local.end.x - start.x), SaCompute.groups_for(local.end.y - start.y))
    var base := _written
    _written += groups.x * groups.y
    return PackedFloat32Array(
        [
            float(start.x),
            float(start.y),
            float(local.position.x),
            float(local.position.y),
            float(local.end.x),
            float(local.end.y),
            float(base),
            float(groups.x),
            0.0,
            0.0,
            0.0,
            0.0,
        ]
    )


## The push constant for a fold over *count* records. The chunk's fields are
## left at zero, since the fold reads none of them.
static func _fold_params(count: int) -> PackedFloat32Array:
    var params := PackedFloat32Array()
    params.resize(12)
    params.fill(0.0)
    params[8] = float(count)
    return params


func _get_compute() -> SaCompute:
    if _compute == null:
        _compute = SaCompute.new(SHADER)
    return _compute


## One reduction as the step and the suite both read it.
static func _answer(area: int, allocated: int, sum: Vector4, least: Variant, most: Variant) -> Dictionary:
    var mean: Variant = null
    if area > 0:
        mean = sum / float(area)
    return {
        "texels": area,
        "allocated": allocated,
        "sum": _channels(sum),
        "mean": _channels(mean),
        "min": _channels(least),
        "max": _channels(most),
    }


## Four floats for a Vector4, and null for the null that says undefined.
static func _channels(value: Variant) -> Variant:
    if not (value is Vector4):
        return null
    var channels := value as Vector4
    return [channels.x, channels.y, channels.z, channels.w]


# --- The `reduce` step --------------------------------------------------------


## Reduces a layer's rectangle: to its sum, mean, minimum and maximum, from a
## scenario or through the door, `{"reduce": {...}}`.
##
## `layer` is a name or an index from the bottom of the stack, 0 the lowest,
## and the active layer when it is left out. `rect` is `[x, y, w, h]` in
## document pixels, clipped to the canvas, and the whole canvas when it is left
## out. `ops` is any of `sum`, `mean`, `min` and `max`, all four when left out.
##
## The answer is one line, `SaCapture: reduce <json>`: the layer's name and
## index, the rectangle as reduced, `texels` and `allocated`, and each operation
## asked for as four floats, or null with `undefined` naming it when the
## rectangle is empty.
static func capture(document: SaDocument, spec: Variant) -> String:
    var ask: Dictionary = spec if spec is Dictionary else {}
    if document == null:
        return "SaCapture: reduce refused, no document"
    var stack := SaLayerOps.new(document).layers()
    var layer := _layer_named(document, stack, ask.get("layer", null))
    if layer == null:
        return "SaCapture: reduce refused, no layer %s" % JSON.stringify(ask.get("layer", null))
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    var rect := canvas
    if ask.has("rect"):
        rect = _rect(ask["rect"]).intersection(canvas)
    var wanted: Array = ask.get("ops", OPERATIONS) if ask.get("ops", null) is Array else OPERATIONS
    for op: Variant in wanted:
        if not OPERATIONS.has(String(op)):
            return "SaCapture: reduce refused, no operation %s, the four are %s" % [op, ", ".join(OPERATIONS)]

    var result := SaReduce.new(layer).reduce(rect)
    var answer := {
        "layer": String(layer.name),
        "index": stack.find(layer),
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "texels": result["texels"],
        "allocated": result["allocated"],
    }
    var undefined: Array[String] = []
    for op: String in OPERATIONS:
        if not wanted.has(op):
            continue
        answer[op] = result[op]
        if result[op] == null:
            undefined.append(op)
    if not undefined.is_empty():
        answer["undefined"] = undefined
    return "SaCapture: reduce %s" % JSON.stringify(answer)


## The layer *named* names: a name, an index from the bottom, or null for the
## active layer. A float index is what a JSON number arrives as.
static func _layer_named(document: SaDocument, stack: Array[SaLayer], named: Variant) -> SaLayer:
    if named == null:
        return document.active_layer
    if named is int or named is float:
        var index := int(named)
        return stack[index] if index >= 0 and index < stack.size() else null
    for layer in stack:
        if String(layer.name) == String(named):
            return layer
    return null


## `[x, y, w, h]` as a rectangle, and the empty one for anything shorter, which
## reads as a reduction over nothing rather than over everything.
static func _rect(raw: Variant) -> Rect2i:
    var numbers: Array = raw if raw is Array else []
    if numbers.size() < 4:
        return Rect2i()
    return Rect2i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3]))
