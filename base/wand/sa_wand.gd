## The magic wand's flood: the contiguous region of colour around a seed,
## as a selection, computed on the GPU one chunk at a time.
##
## `wand.gmacs`, under the module's `shaders/`, tests a
## chunk's texels against the start once when the chunk joins, packing what is
## passable into a buffer of bits, and a sweep settles the chunk from those
## bits in one workgroup, running its rows and columns until nothing moves and
## reading the neighbour's bits across each seam. When the flood has settled
## the bits are unpacked into the masks. The CPU's part is
## the schedule: which chunks are in play. It starts with the seed's, and
## after each batch of sweeps reads a small buffer that says which chunks
## changed and which chunk edges the flood reached, so only the chunks the
## region touches are ever dispatched, only those where it can still move are
## swept again, and the mask stays as sparse as the region.
## That read is one buffer per batch, never a texture, and a click is not a
## stroke. A batch runs ahead of what the last read showed, into rings of
## chunks the flood may reach next, and a chunk of them it did not reach
## leaves the region at the read.
##
## The flood lands in chunks of its own and joins the selection in the mode
## the tool asked for through `SaSelection.merge_region`: replacing it, united
## with it, taken out of it, or met with it.
##
## **On a document whose kind wraps, the flood crosses the seam.** [Grid] finds
## the chunk past the canvas's edge at the far end of the row, and the kernels
## read that chunk's bits where the canvas ends, so a fill or a wand selection
## that reaches one edge carries on from the other.
##
## In the base module's `wand/` with the wand tool, because the flood serves that
## tool, the bucket fill and one capture step, and nothing in the skeleton.
## The capture step asks for it under the `flood` role, so the class name is
## the module's own affair now.
##
## **A chunk stored smaller than the mask is read at its own scale**. A
## selection chunk is always `SaChunk.SIZE` across and the colour chunk under
## it may not be, a `.sad` file restoring one at a `resolution_scale` under
## one, so every push carries the ratio and the kernel reads the colour texel
## under a mask texel rather than the one at its own coordinates. Asked of the
## texture rather than assumed, which is the first half of hard rule 3, sparse chunks.
class_name SaWand
extends RefCounted

## A region that needs more rounds than this is a maze, and the wand gives up
## on it rather than stalling the frame. A batch may run past it by its rings.
const MAX_SWEEPS: int = 256

## Rings of chunks a batch makes ahead of the flood's front before its one
## read, each swept in a round of its own after the round of what is due. A
## ring the flood does not reach costs its sweeps and nothing else, since its
## chunks leave the region again at the read, and a whole canvas reached from
## one click sweeps nearly all of them anyway. Measured on `wand-2` of
## `perf-repeat.json`, one ring took the reads from 12 to 8, two to 5 over the
## same 148 chunk sweeps, and three and four read 6 and 5 over more sweeps.
const RINGS_AHEAD: int = 2

## The side of a mask chunk the sweep kernels are compiled for, their `SIDE`:
## their workgroup memory holds one chunk as bits and their workgroup is one
## thread a row, so both are fixed when the kernel compiles. The two change
## together, and [method flood] refuses a chunk of another size.
const SWEEP_SIDE: int = 256

const BINDING_MASK: int = 0
const BINDING_COLOUR: int = 1
const BINDING_FLOOD: int = 2
const BINDING_BITS: int = 3
const BINDING_GAPS: int = 4

## Words a chunk's slot has in the bits buffer, its `CHUNK_WORDS`: a bit a
## texel for what is passable and as many for what is selected.
const CHUNK_WORDS: int = 4096
## Words a chunk's slot has in the gaps buffer, its `GAP_WORDS`: a bit a texel
## for the walls, as many for the other regions and as many for what the fill
## takes, which only a fill that closes gaps writes.
const GAP_WORDS: int = 6144

## The bits of the push's `neighbours`, which of the four has a slot.
const HAS_NEIGHBOUR: Array[int] = [1, 2, 4, 8]
## Where the seed, `neighbours` and `radius` sit in the push constant.
const PUSH_SEED: int = 6
const PUSH_NEIGHBOURS: int = 9
const PUSH_RADIUS: int = 11

## The four words before the seed and the four of the seed, in the buffer. The
## per-chunk flags start after both.
const FLAGS_OFFSET: int = 8

## Words a chunk has in the buffer: the four edges the flood reached, left,
## right, up and down, and whether any texel of the chunk changed this sweep.
const FLAGS_PER_CHUNK: int = 5
const FLAG_CHANGED: int = 4
const NEIGHBOURS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
## The eight chunks around one, in the order of the bits the gap passes read
## from `neighbours`: the four sides as above, then the four corners.
const AROUND: Array[Vector2i] = [
    Vector2i(-1, 0),
    Vector2i(1, 0),
    Vector2i(0, -1),
    Vector2i(0, 1),
    Vector2i(-1, -1),
    Vector2i(1, -1),
    Vector2i(-1, 1),
    Vector2i(1, 1),
]

## The widest gap a fill may ask to close, in texels. `spread` in `wand.gmacs`
## reaches less than a word either way, and half of this is its reach.
const MAX_GAP: int = 40

var _compute: SaCompute = null
## How many buffer reads the last [method flood] waited on, one a batch of
## rounds. What the wand's suite holds under a bound.
var reads: int = 0
## A 1 by 1 transparent texel at each colour format met, for a layer chunk
## the layer does not hold.
var _blank: Dictionary = {}
## The bits buffer of the last flood, kept for the next one on a canvas of
## as many chunks, since `classify` writes a chunk's slot whole before anything
## reads it. 16 KB a chunk of the canvas, 640 KB at 1920 by 1080, and it only
## grows.
var _bits: SaCompute.Buffer = null
var _bits_chunks: int = 0
## The gaps buffer, made by the first fill that closes gaps and kept the same
## way. 24 KB a chunk, 960 KB at 1920 by 1080. Until then every pass binds a
## buffer of one slot, which no kernel writes while the radius is 0, and a fill
## that closes gaps sizes it before its first pass, so [method _bind] binds the
## one it needs.
var _gaps: SaCompute.Buffer = null
var _gaps_chunks: int = 0


## Selects the contiguous region around *seed* whose colours are within
## *tolerance* of the seed's, read from *colour* (the merged output at
## document coordinates) when it is given, else from *layer*'s own chunks.
## Returns the number of chunks the region reached, 0 when the seed is off
## the canvas.
##
## A colour is measured premultiplied and with its alpha, so an empty texel is
## as far from the seed as the seed's own alpha and nothing behind the layer is
## asked for. `wand.gmacs` says why above `held`.
##
## **A *gap* above 1 closes gaps in the walls up to that many texels wide**,
## the bucket fill's Close gaps, and the wand leaves it at 0. Each chunk joining
## the flood is narrowed by `close` before its first sweep, and that reads the
## walls of all eight chunks around it, so those are classified with it, a ring
## of reads round the region and never a dispatch over the canvas. Once the
## flood settles, three passes take it back to the walls in place of `unpack`,
## over the region and that ring, since a flood that stops short of a seam can
## still reach past it, and keep it from the other regions round a gap it
## closed. One more buffer read then says which of them hold a texel, and only
## those join the selection.
func flood(
    document: SaDocument,
    start: Vector2i,
    tolerance: float,
    mode: int,
    colour: SaTexture = null,
    layer: SaLayer = null,
    gap: int = 0
) -> int:
    var format := _format_for(document, start, colour, layer)
    if format < 0:
        return 0
    var canvas_size := document.canvas_size
    var selection := document.selection
    var side := SaChunk.SIZE
    var grid_w := int(ceil(float(canvas_size.x) / side))
    var grid_h := int(ceil(float(canvas_size.y) / side))
    var grid := Grid.new(canvas_size, document.projection.wrapping, start)
    if colour == null and layer.chunks.is_empty():
        # A layer with no chunks reads the same transparent texel everywhere,
        # so every texel is within any tolerance of the seed and the flood
        # would reach the whole canvas. The sweeps would get there too, a
        # ring of chunks a sweep, and the fill measured that at 813 dispatches
        # and a quarter of a second on a 1920 by 1080 canvas.
        selection.merge_region(_whole_canvas(selection, canvas_size), mode)
        return grid_w * grid_h

    if side != SWEEP_SIDE:
        push_error("SaWand: the sweep kernels hold a %d chunk, and a mask chunk is %d." % [SWEEP_SIDE, side])
        return 0
    var buffer := _seeded(document, start, tolerance, format, colour, layer)
    var bits := _bits_for(grid_w * grid_h)
    var radius := floori(clampi(gap, 0, MAX_GAP) / 2.0)
    if radius > 0:
        _gaps_for(grid_w * grid_h)
    var seed_grid := Vector2i(floori(float(start.x) / side), floori(float(start.y) / side))
    var seed_local := start - seed_grid * side
    var zero_flags := PackedInt32Array()
    zero_flags.resize(grid_w * grid_h * FLAGS_PER_CHUNK)
    var zero_bytes := zero_flags.to_byte_array()

    # The region's own chunks, starting from the seed's, whose one selected
    # texel `classify` sets in its bits.
    var region: Dictionary = {}
    region[seed_grid] = selection.make_chunk()
    # The chunks the next sweep runs over. A chunk is swept again only when
    # something can have moved in it since its last sweep: it is new, a texel
    # of it changed, or a neighbour's did, which changes the carry across the
    # seam. The rest are where the flood already stopped, and sweeping every
    # chunk the region holds on every sweep would be more than half the fill's
    # dispatches.
    var due: Dictionary[Vector2i, bool] = {seed_grid: true}
    # The chunks made since the last read, the flood's front, and the seed's is
    # the first. The rings ahead of a read are counted out from these.
    var fresh: Array[Vector2i] = [seed_grid]
    # Chunks made ahead of the front that the flood did not reach, so still
    # empty, kept for the read that does reach one rather than made twice.
    var spare: Dictionary[Vector2i, SaChunk] = {}

    # **Not an [SaChunkWalk], and the one loop under core/ that is not.** The
    # walk exists so a pass names a rectangle and gets one dispatch per chunk
    # over that chunk's share of it. Three things here are none of that. The
    # chunks are not a rectangle's, they are a set the readback below grows one
    # neighbour at a time, and the rectangle they will end up covering is not
    # known until the flood has finished. The dispatch is one workgroup a chunk,
    # because a sweep holds the whole chunk in workgroup memory and runs its
    # rows and columns there until nothing moves, and a second workgroup on the
    # chunk would see none of it. And the storage format is the colour image's
    # rather than the mask's, set once outside the loop, because changing it
    # reloads every pipeline. Bending the walk to take all three would make it a
    # wrapper round a `dispatch_kernel` rather than a door.
    #
    # What a chunk's sweep is handed besides its bits, the same along the rows
    # and down the columns and in every round but for which neighbours have a
    # slot, so built once a chunk. Building it for every dispatch, with every
    # binding set again beside it, is most of what recording a round costs the
    # CPU.
    var pushes: Dictionary[Vector2i, PackedFloat32Array] = {}
    var colours: Dictionary[Vector2i, SaTexture] = {}
    # The region's chunks `close` has narrowed, which a chunk leaving the region
    # as a spare and coming back stays.
    var closed: Dictionary[Vector2i, bool] = {}
    var classify_push := func(grid_pos: Vector2i) -> void:
        var chunk_colour := _colour_for(grid_pos, colour, layer, format)
        colours[grid_pos] = chunk_colour
        pushes[grid_pos] = _push_floats(
            grid_pos,
            canvas_size,
            tolerance,
            grid_pos.x + grid_pos.y * grid_w,
            _colour_offset(grid_pos, colour),
            seed_local if grid_pos == seed_grid else Vector2i(-1, -1),
            _colour_scale(chunk_colour, colour),
            0,
            grid_w,
            radius,
            grid
        )
    reads = 0
    var rounds := 0
    while rounds < MAX_SWEEPS:
        # One read, several rounds. The first sweeps what is due, and each after
        # it sweeps a ring of chunks made ahead of the front together with the
        # ring before it, so the flood crosses into chunks no read has shown it
        # reaching yet. Waiting on the card once a round is most of a click's
        # time, most of that a fixed cost a read carries whatever it waits on,
        # so a round saved is worth the sweeps a blind ring spends.
        var batch: Array[Array] = [due.keys()]
        var ahead: Array[Vector2i] = []
        var ring: Array[Vector2i] = fresh
        for _ring in RINGS_AHEAD:
            var next_ring: Array[Vector2i] = []
            for grid_pos: Vector2i in ring:
                for step: Vector2i in NEIGHBOURS:
                    var next := grid.step(grid_pos, step)
                    if next == Grid.OFF or region.has(next):
                        continue
                    region[next] = spare[next] if spare.has(next) else selection.make_chunk()
                    spare.erase(next)
                    next_ring.append(next)
            if next_ring.is_empty():
                break
            ahead.append_array(next_ring)
            var both: Array[Vector2i] = ring.duplicate()
            both.append_array(next_ring)
            batch.append(both)
            ring = next_ring

        buffer.update(PackedInt32Array([0, 0, 0, 0]).to_byte_array(), 0)
        # Every chunk made since the last batch is classified before anything
        # sweeps it or reads its seam, and a spare one coming back keeps its
        # bits, which nothing turned on.
        var joining: Array[Vector2i] = []
        for grid_pos: Vector2i in region:
            if pushes.has(grid_pos):
                continue
            classify_push.call(grid_pos)
            joining.append(grid_pos)
        # A chunk `close` narrows reads the walls of the eight around it, so
        # they are classified in the same list, whether or not the flood ever
        # gets there.
        var closing: Array[Vector2i] = []
        if radius > 0:
            for grid_pos: Vector2i in region:
                if closed.has(grid_pos):
                    continue
                closing.append(grid_pos)
                closed[grid_pos] = true
                for step: Vector2i in AROUND:
                    var next := grid.step(grid_pos, step)
                    if next != Grid.OFF and not pushes.has(next):
                        classify_push.call(next)
                        joining.append(next)
        _classify(joining, selection.nothing(), buffer, bits, colours, pushes)
        _gap_pass("close", closing, pushes, {}, selection.nothing(), buffer, bits, colours, pushes, grid)
        var touched: Dictionary[Vector2i, bool] = {}
        for swept: Array in batch:
            for grid_pos: Vector2i in swept:
                touched[grid_pos] = true
            _round(swept, region, buffer, bits, colours, pushes, grid)
            rounds += 1
        var read := buffer.read().to_int32_array()
        reads += 1
        if read.is_empty():
            break

        # A chunk made ahead that the flood did not reach holds nothing, so it
        # leaves the region before anything below counts it as a neighbour.
        for grid_pos: Vector2i in ahead:
            if read[FLAGS_OFFSET + (grid_pos.x + grid_pos.y * grid_w) * FLAGS_PER_CHUNK + FLAG_CHANGED] == 0:
                spare[grid_pos] = region[grid_pos]
                region.erase(grid_pos)
        due = {}
        fresh = []
        for grid_pos: Vector2i in touched:
            if not region.has(grid_pos):
                continue
            var flags := FLAGS_OFFSET + (grid_pos.x + grid_pos.y * grid_w) * FLAGS_PER_CHUNK
            if read[flags + FLAG_CHANGED] != 0:
                due[grid_pos] = true
                for direction in 4:
                    var beside := grid.step(grid_pos, NEIGHBOURS[direction])
                    if region.has(beside):
                        due[beside] = true
            for direction in 4:
                if read[flags + direction] == 0:
                    continue
                var next := grid.step(grid_pos, NEIGHBOURS[direction])
                if next == Grid.OFF or region.has(next):
                    continue
                region[next] = spare[next] if spare.has(next) else selection.make_chunk()
                spare.erase(next)
                due[next] = true
                fresh.append(next)
        buffer.update(zero_bytes, FLAGS_OFFSET * 4)
        if due.is_empty():
            break

    if radius > 0:
        region = _contested(region, spare, selection, buffer, bits, colours, pushes, grid)
    else:
        _unpack(region, buffer, bits, colours, pushes)
    selection.merge_region(region, mode)
    return region.size()


## *region* after the three passes that take the settled flood back to its
## walls, `rival`, `contest` and `grow`, over the region and every chunk around
## it, all classified. `grow` writes the masks. The flags were cleared after
## the loop's last read, so one more read says which chunks it wrote a texel
## into, and the rest are left out: a neighbour the fill did not reach after
## all, and a chunk the flood joined at a seam without lighting anything in it.
func _contested(
    region: Dictionary,
    spare: Dictionary[Vector2i, SaChunk],
    selection: SaSelection,
    buffer: SaCompute.Buffer,
    bits: SaCompute.Buffer,
    colours: Dictionary[Vector2i, SaTexture],
    pushes: Dictionary[Vector2i, PackedFloat32Array],
    grid: Grid
) -> Dictionary:
    var reached: Dictionary = region.duplicate()
    for grid_pos: Vector2i in region:
        for step: Vector2i in AROUND:
            var next := grid.step(grid_pos, step)
            if next == Grid.OFF or reached.has(next) or not pushes.has(next):
                continue
            reached[next] = spare[next] if spare.has(next) else selection.make_chunk()
    var order: Array[Vector2i] = []
    order.assign(reached.keys())
    var nothing := selection.nothing()
    for kernel: String in ["rival", "contest"]:
        _gap_pass(kernel, order, reached, {}, nothing, buffer, bits, colours, pushes, grid)
    _gap_pass("grow", order, reached, reached, nothing, buffer, bits, colours, pushes, grid)
    var read := buffer.read().to_int32_array()
    reads += 1
    if read.is_empty():
        return reached
    var kept: Dictionary = {}
    for grid_pos: Vector2i in order:
        if read[FLAGS_OFFSET + (grid_pos.x + grid_pos.y * grid.size.x) * FLAGS_PER_CHUNK + FLAG_CHANGED] != 0:
            kept[grid_pos] = reached[grid_pos]
    return kept


## Records one list of *kernel*, one of the passes a fill that closes gaps adds,
## over *chunks*. Each gets its own push with which of the eight around it are
## in *present*, which holds only chunks of the grid and finds them across the
## seam of *grid* where the canvas wraps, the seed *grid* holds in the chunk's
## own texels wherever it lies, its copy a canvas away when that is nearer, and the
## radius. `close` reads the walls of every classified chunk and the passes
## after the flood read only the chunks they run over, since a slot outside
## those holds what an earlier pass left. `grow` writes the mask chunk *masks*
## holds for it, and the rest write no mask, so *mask* stands in for theirs.
func _gap_pass(
    kernel: String,
    chunks: Array[Vector2i],
    present: Dictionary,
    masks: Dictionary,
    mask: SaTexture,
    buffer: SaCompute.Buffer,
    bits: SaCompute.Buffer,
    colours: Dictionary[Vector2i, SaTexture],
    pushes: Dictionary[Vector2i, PackedFloat32Array],
    grid: Grid
) -> void:
    if chunks.is_empty():
        return
    _bind(buffer, mask, colours[chunks[0]])
    _compute.set_buffer(BINDING_BITS, bits.rid)
    _compute.list_begin(_compute.index_of_kernel(kernel))
    for grid_pos: Vector2i in chunks:
        if masks.has(grid_pos):
            _compute.set_texture(BINDING_MASK, (masks[grid_pos] as SaChunk).field(SaSelection.FIELD).rid)
        var push := pushes[grid_pos].duplicate()
        var neighbours := 0
        for direction in AROUND.size():
            var next := grid.step(grid_pos, AROUND[direction])
            if next != Grid.OFF and present.has(next):
                neighbours |= 1 << direction
        var local_seed := grid.seed_near(grid_pos) - grid_pos * SaChunk.SIZE
        push[PUSH_SEED] = local_seed.x
        push[PUSH_SEED + 1] = local_seed.y
        push[PUSH_NEIGHBOURS] = float(neighbours)
        _compute.set_push_constant_float_array(push)
        _compute.list_dispatch(1, SaCompute.groups_for(SWEEP_SIDE), 1)
    _compute.list_end()


## Selects every texel whose colour is within *tolerance* of the seed's, joined
## to it or not, and joins that to the selection in *mode*. The same reading and
## the same distance as [method flood], which is what the bucket fill's
## Contiguous off asks for, Krita's reading of it. Returns the number of chunks
## that hold a selected texel, 0 when the seed is off the canvas.
##
## **One dispatch a chunk and one readback, and no sweeps.** Nothing has to
## travel, so every chunk is marked on its own through `select_matching`, and
## the one buffer read after says which chunks hold a texel, so a chunk with
## none never joins the selection or gets painted. A chunk the layer does not
## hold reads the same transparent texel everywhere, so one of them is
## dispatched as the probe for all of them, and they all join whole when it
## matched. Over the merged picture every chunk of the canvas is read, because a
## global selection has to look at every texel of it, and that is the one pass
## over the canvas this makes, a click rather than a stroke.
func select_matching(
    document: SaDocument, start: Vector2i, tolerance: float, mode: int, colour: SaTexture = null, layer: SaLayer = null
) -> int:
    var format := _format_for(document, start, colour, layer)
    if format < 0:
        return 0
    var selection := document.selection
    var canvas_size := document.canvas_size
    var side := SaChunk.SIZE
    var grid_w := int(ceil(float(canvas_size.x) / side))
    var grid_h := int(ceil(float(canvas_size.y) / side))
    if colour == null and layer.chunks.is_empty():
        # Every texel reads transparent, the seed as well, so all of it matches.
        selection.merge_region(_whole_canvas(selection, canvas_size), mode)
        return grid_w * grid_h

    var buffer := _seeded(document, start, tolerance, format, colour, layer)
    var tested: Array[Vector2i] = []
    var probe := Vector2i(-1, -1)
    for grid_y in grid_h:
        for grid_x in grid_w:
            var grid_pos := Vector2i(grid_x, grid_y)
            if colour != null or layer.chunks.has(grid_pos):
                tested.append(grid_pos)
            elif probe.x < 0:
                probe = grid_pos
                tested.append(grid_pos)

    var region: Dictionary = {}
    _compute.set_buffer(BINDING_FLOOD, buffer.rid)
    _compute.set_buffer(BINDING_BITS, _bits_for(1).rid)
    _compute.set_buffer(BINDING_GAPS, _gaps_for(1).rid)
    _compute.list_begin(_compute.index_of_kernel("select_matching"))
    for grid_pos: Vector2i in tested:
        var chunk := selection.make_chunk()
        region[grid_pos] = chunk
        var chunk_colour := _colour_for(grid_pos, colour, layer, format)
        _compute.set_texture(BINDING_MASK, chunk.field(SaSelection.FIELD).rid)
        _compute.set_texture(BINDING_COLOUR, chunk_colour.rid)
        _compute.set_push_constant_float_array(
            _push_floats(
                grid_pos,
                canvas_size,
                tolerance,
                grid_pos.x + grid_pos.y * grid_w,
                _colour_offset(grid_pos, colour),
                Vector2i.ZERO,
                _colour_scale(chunk_colour, colour)
            )
        )
        _compute.list_dispatch(SaCompute.groups_for(side), SaCompute.groups_for(side), 1)
    _compute.list_end()

    var read := buffer.read().to_int32_array()
    var hit := func(grid_pos: Vector2i) -> bool:
        var flag := FLAGS_OFFSET + (grid_pos.x + grid_pos.y * grid_w) * FLAGS_PER_CHUNK + FLAG_CHANGED
        return not read.is_empty() and read[flag] != 0
    var matched: Dictionary = {}
    for grid_pos: Vector2i in tested:
        if grid_pos != probe and hit.call(grid_pos):
            matched[grid_pos] = region[grid_pos]
    if probe.x >= 0 and hit.call(probe):
        var whole := _whole_canvas(selection, canvas_size)
        for grid_pos: Vector2i in whole:
            if not layer.chunks.has(grid_pos):
                matched[grid_pos] = whole[grid_pos]
    selection.merge_region(matched, mode)
    return matched.size()


## The format of the colours a flood would read, or -1 when there is nothing to
## read or the seed is off the canvas.
static func _format_for(document: SaDocument, start: Vector2i, colour: SaTexture, layer: SaLayer) -> int:
    if document == null or (colour == null and layer == null):
        return -1
    var canvas_size := document.canvas_size
    if start.x < 0 or start.y < 0 or start.x >= canvas_size.x or start.y >= canvas_size.y:
        return -1
    if colour != null:
        return colour.format
    return layer.schema[0].format if not layer.schema.is_empty() else -1


## The buffer both readings share, with the seed's colour already written into
## it on the GPU, and the storage format set for *format*.
func _seeded(
    document: SaDocument, start: Vector2i, tolerance: float, format: int, colour: SaTexture, layer: SaLayer
) -> SaCompute.Buffer:
    var selection := document.selection
    var canvas_size := document.canvas_size
    var side := SaChunk.SIZE
    var grid_w := int(ceil(float(canvas_size.x) / side))
    var grid_h := int(ceil(float(canvas_size.y) / side))
    if _compute == null:
        _compute = SaCompute.new("wand")
    _compute.use_storage_format(format)
    var words := PackedInt32Array()
    words.resize(FLAGS_OFFSET + grid_w * grid_h * FLAGS_PER_CHUNK)
    var buffer := SaCompute.Buffer.new(words.to_byte_array())

    # The seed's colour into the buffer, from wherever the colours come.
    var seed_grid := Vector2i(floori(float(start.x) / side), floori(float(start.y) / side))
    var seed_local := start - seed_grid * side
    var seed_colour := _colour_for(seed_grid, colour, layer, format)
    _bind(buffer, selection.nothing(), seed_colour)
    _push(
        seed_grid,
        canvas_size,
        tolerance,
        0,
        _colour_offset(seed_grid, colour),
        seed_local if colour == null else start,
        _colour_scale(seed_colour, colour)
    )
    _compute.dispatch_kernel("seed", 1, 1, 1)
    return buffer


## Every chunk of a canvas *canvas_size* across, selected wherever it lies
## on the canvas, as a flood that reached all of it would leave them.
static func _whole_canvas(selection: SaSelection, canvas_size: Vector2i) -> Dictionary:
    var side := SaChunk.SIZE
    var region: Dictionary = {}
    for grid_y in int(ceil(float(canvas_size.y) / side)):
        for grid_x in int(ceil(float(canvas_size.x) / side)):
            var grid_pos := Vector2i(grid_x, grid_y)
            var valid := (canvas_size - grid_pos * side).min(Vector2i(side, side))
            if valid == Vector2i(side, side):
                region[grid_pos] = selection.make_chunk(1.0)
                continue
            var chunk := selection.make_chunk()
            selection.dispatch(
                "select_rect",
                chunk.field(SaSelection.FIELD),
                Rect2i(Vector2i.ZERO, valid),
                PackedFloat32Array([0.0, 0.0, valid.x, valid.y, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
            )
            region[grid_pos] = chunk
    return region


func _bind(buffer: SaCompute.Buffer, mask: SaTexture, colour: SaTexture) -> void:
    _compute.set_texture(BINDING_MASK, mask.rid)
    _compute.set_texture(BINDING_COLOUR, colour.rid)
    _compute.set_buffer(BINDING_FLOOD, buffer.rid)
    _compute.set_buffer(BINDING_BITS, _bits_for(1).rid)
    _compute.set_buffer(BINDING_GAPS, _gaps_for(1).rid)


## Sets the push constant [method _push_floats] builds.
func _push(
    grid_pos: Vector2i,
    canvas_size: Vector2i,
    tolerance: float,
    index: int,
    colour_offset: Vector2i,
    start: Vector2i,
    colour_scale: float
) -> void:
    _compute.set_push_constant_float_array(
        _push_floats(grid_pos, canvas_size, tolerance, index, colour_offset, start, colour_scale)
    )


## The push constant of one dispatch, which the sweeps keep a chunk.
##
## *valid* is measured in mask texels, which are the document's pixels, so the
## chunk's own edge length is `SaChunk.SIZE` here on purpose: the mask chunk
## is always that size, and the colour chunk's size goes in *colour_scale*.
## *grid* says where the canvas's seams are for a pass that reads a neighbour,
## and nothing reads them in the dispatches that leave it out.
static func _push_floats(
    grid_pos: Vector2i,
    canvas_size: Vector2i,
    tolerance: float,
    index: int,
    colour_offset: Vector2i,
    start: Vector2i,
    colour_scale: float,
    neighbours: int = 0,
    grid_width: int = 0,
    radius: int = 0,
    grid: Grid = null
) -> PackedFloat32Array:
    var side := SaChunk.SIZE
    var valid := Vector2i(mini(side, canvas_size.x - grid_pos.x * side), mini(side, canvas_size.y - grid_pos.y * side))
    var seam := grid.seam() if grid != null else Vector2i.ZERO
    return PackedFloat32Array(
        [
            colour_offset.x,
            colour_offset.y,
            valid.x,
            valid.y,
            tolerance,
            float(index),
            start.x,
            start.y,
            colour_scale,
            float(neighbours),
            float(grid_width),
            float(radius),
            float(seam.x),
            float(seam.y),
            float(grid.size.y if grid != null else 0),
        ]
    )


## Colour texels per mask texel for *texture*: one for the merged picture,
## which is at document resolution, and the chunk's own edge over the mask's
## for a layer chunk, which is its `resolution_scale`. A blank stand-in texel
## is one across and reads the same wherever it is asked.
func _colour_scale(texture: SaTexture, colour: SaTexture) -> float:
    if colour != null or texture == null or texture.size.x <= 1:
        return 1.0
    return float(texture.size.x) / float(SaChunk.SIZE)


## Records one round over *swept*, one list along the rows and one down the
## columns.
##
## Every chunk of the round in one list a direction. A list ends in a barrier
## and the chunks of one direction need none between them: a chunk writes its
## own bits alone and reads a neighbour's only at the seam, where a texel only
## ever turns on, so a read that misses one turning on this sweep sees it on the
## next, and that neighbour changed, which puts this chunk in the next round
## anyway. The round that ends the flood changes nothing, so what it reads is
## settled. One list per chunk was a barrier per dispatch, about half the
## click's wait on the card.
##
## A sweep reads no colour and writes no mask, only the two buffers, so the
## images are bound once a list for the set to be whole.
func _round(
    swept: Array,
    region: Dictionary,
    buffer: SaCompute.Buffer,
    bits: SaCompute.Buffer,
    colours: Dictionary[Vector2i, SaTexture],
    pushes: Dictionary[Vector2i, PackedFloat32Array],
    grid: Grid
) -> void:
    if swept.is_empty():
        return
    var first: Vector2i = swept[0]
    for horizontal: bool in [true, false]:
        _bind(buffer, (region[first] as SaChunk).field(SaSelection.FIELD), colours[first])
        _compute.set_buffer(BINDING_BITS, bits.rid)
        _compute.list_begin(_compute.index_of_kernel("sweep_rows" if horizontal else "sweep_columns"))
        for grid_pos: Vector2i in swept:
            var push := pushes[grid_pos]
            var neighbours := 0
            for direction in 4:
                if region.has(grid.step(grid_pos, NEIGHBOURS[direction])):
                    neighbours |= HAS_NEIGHBOUR[direction]
            push[PUSH_NEIGHBOURS] = float(neighbours)
            _compute.set_push_constant_float_array(push)
            _compute.list_dispatch(1, 1, 1)
        _compute.list_end()


## Records one list of `classify` over the chunks joining the flood, which reads
## their colours once and writes their slots whole. It writes no mask, and a
## chunk classified for `close` to read is in no region, so *mask* is bound for
## the set to be whole.
func _classify(
    joining: Array[Vector2i],
    mask: SaTexture,
    buffer: SaCompute.Buffer,
    bits: SaCompute.Buffer,
    colours: Dictionary[Vector2i, SaTexture],
    pushes: Dictionary[Vector2i, PackedFloat32Array]
) -> void:
    if joining.is_empty():
        return
    _bind(buffer, mask, colours[joining[0]])
    _compute.set_buffer(BINDING_BITS, bits.rid)
    var bound: SaTexture = colours[joining[0]]
    _compute.list_begin(_compute.index_of_kernel("classify"))
    for grid_pos: Vector2i in joining:
        if colours[grid_pos] != bound:
            bound = colours[grid_pos]
            _compute.set_texture(BINDING_COLOUR, bound.rid)
        _compute.set_push_constant_float_array(pushes[grid_pos])
        _compute.list_dispatch(1, SaCompute.groups_for(SWEEP_SIDE), 1)
    _compute.list_end()


## Records one list of `unpack` over the region, each chunk's selected bits into
## its mask, once the flood has settled.
func _unpack(
    region: Dictionary,
    buffer: SaCompute.Buffer,
    bits: SaCompute.Buffer,
    colours: Dictionary[Vector2i, SaTexture],
    pushes: Dictionary[Vector2i, PackedFloat32Array]
) -> void:
    if region.is_empty():
        return
    var first: Vector2i = region.keys()[0]
    _bind(buffer, (region[first] as SaChunk).field(SaSelection.FIELD), colours[first])
    _compute.set_buffer(BINDING_BITS, bits.rid)
    _compute.list_begin(_compute.index_of_kernel("unpack"))
    for grid_pos: Vector2i in region:
        _compute.set_texture(BINDING_MASK, (region[grid_pos] as SaChunk).field(SaSelection.FIELD).rid)
        _compute.set_push_constant_float_array(pushes[grid_pos])
        _compute.list_dispatch(SaCompute.groups_for(SWEEP_SIDE), SaCompute.groups_for(SWEEP_SIDE), 1)
    _compute.list_end()


## A bits buffer of at least *chunks* slots, the one the last flood used when it
## is large enough.
func _bits_for(chunks: int) -> SaCompute.Buffer:
    if _bits == null or _bits_chunks < chunks:
        var bytes := PackedByteArray()
        bytes.resize(chunks * CHUNK_WORDS * 4)
        _bits = SaCompute.Buffer.new(bytes)
        _bits_chunks = chunks
    return _bits


## A gaps buffer of at least *chunks* slots, kept as [method _bits_for] keeps
## its own.
func _gaps_for(chunks: int) -> SaCompute.Buffer:
    if _gaps == null or _gaps_chunks < chunks:
        var bytes := PackedByteArray()
        bytes.resize(chunks * GAP_WORDS * 4)
        _gaps = SaCompute.Buffer.new(bytes)
        _gaps_chunks = chunks
    return _gaps


## Where the chunk's texel (0, 0) sits in the colour image: its origin in
## the merged output, nothing in its own chunk.
static func _colour_offset(grid_pos: Vector2i, colour: SaTexture) -> Vector2i:
    return grid_pos * SaChunk.SIZE if colour != null else Vector2i.ZERO


## The colours the sweep of *grid_pos* tests: the merged output, the
## layer's chunk, or a transparent texel where the layer has none.
func _colour_for(grid_pos: Vector2i, colour: SaTexture, layer: SaLayer, format: int) -> SaTexture:
    if colour != null:
        return colour
    var own := layer.get_field(grid_pos)
    if own != null:
        return own
    var blank: SaTexture = _blank.get(format, null)
    if blank == null:
        blank = SaTexture.new(Vector2i(1, 1), format)
        blank.clear(Color(0.0, 0.0, 0.0, 0.0))
        _blank[format] = blank
    return blank


## The canvas's grid of chunks and where its edges meet, for a flood stepping
## from one chunk to the next. On a document whose kind wraps in x, the chunk
## past the last column is the first and the other way round, and down the
## columns too for a kind that wraps both ways, so a flood or a wand selection
## that reaches the seam carries on from the other edge. A flat canvas's edge
## is the end of the grid, as it always was.
class Grid:
    extends RefCounted

    ## What [method step] answers past an edge that does not wrap.
    const OFF := Vector2i(-1, -1)

    ## Chunks across and down.
    var size: Vector2i
    ## Where the flood was seeded, in canvas texels.
    var start: Vector2i
    var _canvas: Vector2i
    var _wraps: Vector2i

    func _init(canvas_size: Vector2i, wrapping: SaProjection.Wrap, seed_at: Vector2i) -> void:
        var side := float(SaChunk.SIZE)
        _canvas = canvas_size
        start = seed_at
        size = Vector2i(ceili(canvas_size.x / side), ceili(canvas_size.y / side))
        _wraps = Vector2i(1 if wrapping != SaProjection.Wrap.NONE else 0, 1 if wrapping == SaProjection.Wrap.XY else 0)

    ## The chunk *by* away from *grid_pos*, across the seam where the canvas
    ## wraps, and [constant OFF] past an edge that does not.
    func step(grid_pos: Vector2i, by: Vector2i) -> Vector2i:
        var next := grid_pos + by
        if _wraps.x != 0:
            next.x = posmod(next.x, size.x)
        if _wraps.y != 0:
            next.y = posmod(next.y, size.y)
        if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
            return OFF
        return next

    ## The kernels' `seam_width` and `seam_height`: how far the last column and
    ## the last row run before the canvas meets its first, nought along an axis
    ## that does not wrap.
    func seam() -> Vector2i:
        var last := (size - Vector2i.ONE) * SaChunk.SIZE
        return (_canvas - last) * _wraps

    ## [member start], or its copy a canvas away along an axis that wraps,
    ## whichever lies nearest the chunk at *grid_pos*, which is where that
    ## chunk's own texels see the seed when it sits just across the seam.
    func seed_near(grid_pos: Vector2i) -> Vector2i:
        var near := start
        for axis in 2:
            if _wraps[axis] == 0:
                continue
            var low := grid_pos[axis] * SaChunk.SIZE
            var high := low + SaChunk.SIZE - 1
            var best := absi(start[axis] - clampi(start[axis], low, high))
            for turn: int in [-1, 1]:
                var copy := start[axis] + turn * _canvas[axis]
                var away := absi(copy - clampi(copy, low, high))
                if away < best:
                    best = away
                    near[axis] = copy
        return near
