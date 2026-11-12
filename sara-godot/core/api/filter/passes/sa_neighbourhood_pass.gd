## A filter's pass that reads its neighbours, recorded rather than run: a
## blur, a sharpen, anything whose output texel reads the input within
## [member radius] of it.
##
## A point kernel rewrites binding 0 in place. A neighbourhood kernel cannot,
## because a texel it writes is one another thread is still reading, so it
## reads one texture and writes another:
##
## - Binding 0 is the source, the chunk padded by [method halo] on every side,
##   gathered from the chunk and its eight neighbours. A position inside the
##   document that no chunk holds reads as transparent, never as a mirror of
##   the edge. A position past the document's edge reads the nearest texel
##   inside it, once the runner knows the document.
## - Binding 1 is the mask at `SaSelection.BINDING`, `r32f`, read per pixel as a
##   point kernel reads it (a 1 by 1 mask reads as 1.0 through a clamped read).
## - Binding 2 is the target, chunk-sized, written at the chunk-local pixel. It
##   is not binding 1 because the mask holds 1 in every point kernel.
## - Buffers sit from binding 3 upwards, or from binding 4 in a file that
##   declares [const PREVIOUS_BINDING].
##
## The runner writes four named params when the block declares them: `origin`,
## where the dispatched region starts in the chunk, `halo`, how far the padding
## reaches, `chunk`, where the chunk starts in document pixels, and `source`,
## the document pixel the source's first texel stands for. A kernel reads its
## source at `pixel + ivec2(origin) + ivec2(halo)`.
##
## A dispatch goes out in pieces of at most `SaFilterContext.SUBMIT_TEXELS`
## threads, each handed its own corner as `origin`. A step recorded with a
## [member Step.coarser] of *n* says its threads count on a level of a pyramid,
## 2^n texels of the frame apart, at `((ivec2(origin) + ivec2(halo)) >> n) +
## pixel`, and return past the level's last texel. Its pieces are cut in that
## space, so no texel of a level is written twice. It is a declaration and not
## a param's name, since the wavelet denoise's `level` is a spacing of taps at
## full resolution.
##
## A pass is a list of steps, each a kernel of the same file and its params,
## run in order, because a separable blur is two dispatches and a scratch
## between them. [method then] adds a step. In a pass of more than one:
##
## - Binding 0 is still the gathered source for every step.
## - Binding [const PREVIOUS_BINDING] is what the step before wrote, a scratch
##   the size of the padded source and in its frame. The first step reads the
##   source there too.
## - A step before the last writes that scratch at `pixel + ivec2(origin) +
##   ivec2(halo)`, over the dispatched region grown by the halo on every side,
##   so `origin` is negative on those steps. Its reads near the scratch's outer
##   edge fall outside the padding and must be clamped by the kernel.
## - The last step writes the target, and the halo the gather pads by is the
##   pass's [member radius], the reach of every step together.
##
## [Runner] gathers and dispatches it, for the compositor's chain and for Apply
## alike, so the attached form and the one-shot cannot disagree about a radius.
## A reach of [const WHOLE_NODE] is a filter whose texel reads anywhere on the
## node, and the `WRITES_` constants say where such a pass writes.
class_name SaNeighbourhoodPass
extends SaPointPass

## Where the target is bound, the next slot after the mask.
const TARGET_BINDING: int = 2
## Where a step reads what the step before it wrote, in a file that declares an
## image here. Bound on every dispatch of such a file, the source standing in
## for a first step or a pass of one, so a file can hold a one-step kernel
## beside a list without a binding left empty.
const PREVIOUS_BINDING: int = 3
## The reach of a filter that reads the whole node rather than a radius round
## each texel, a kaleidoscope folding a wedge from the far side of the canvas. A
## named value and not a large number, because a radius is clamped to one chunk
## and this is read everywhere the node holds a chunk. Its source is the node's
## allocated chunks gathered once into one texture, a [Whole], read through
## `chunk` and `source` alone since `halo` is zero. The texture spans the node's
## bounds (268 MB at 4096 square), so it is taken for a filter that declares the
## whole node and for nothing else.
const WHOLE_NODE: int = -1
## A whole-node pass that writes the chunks its node holds and nothing else,
## which is the default. The one-shot allocates what [method lands_on] answers
## and the chain composites the node over it, so the two forms agree.
const WRITES_NODE: int = 0
## A whole-node pass that may write anywhere on the canvas, and says no more.
const WRITES_CANVAS: int = 1
## A whole-node pass whose paint moves by [member displacement], modulo the
## canvas, so it writes the held chunks and where each of them lands. A wrap
## moves paint to where the node holds nothing, and [method lands_on] answers the
## held chunks moved round the canvas by it.
const WRITES_DISPLACED: int = 2

## How far a neighbour is read, in document pixels, as the filter asked.
var radius: int = 0
## The first kernel's params by name, as the filter wrote them. `origin` and
## `halo` are written per dispatch by [Runner] and win over anything here.
var params: Dictionary[String, Variant] = {}
## Where a pass that reads the whole node writes, one of the `WRITES_` values,
## given to the constructor by [method SaFilterContext.neighbourhood_pass], or
## declared on the record afterwards by a filter that also sets a
## [member displacement]. Read by nothing for a pass with a radius, which
## writes its chunks and the ring its halo reaches.
var writes: int = WRITES_NODE
## How far a texel's paint moves, in document pixels, modulo the canvas, for a
## pass that declares [const WRITES_DISPLACED]: a texel read at `p` is written
## at `p + displacement`.
var displacement: Vector2i = Vector2i.ZERO
## Where a whole-node pass that moves paint unlike a displacement carries a
## change, a kaleidoscope's fold: called with the changed rectangle in document
## pixels and the canvas size, the rectangles reading it. Empty reads as all.
var carries: Callable = Callable()
## Every kernel of the pass in the order it runs, the first being
## [member SaPointPass.kernel] with [member params].
var steps: Array[Step] = []


func _init(
    shader_key: String,
    kernel_name: String,
    values: Dictionary[String, Variant],
    reach: int,
    bound: Dictionary[int, SaCompute.Buffer] = {},
    lands: int = WRITES_NODE
) -> void:
    super(shader_key, kernel_name, PackedFloat32Array(), bound, 0)
    params = values
    radius = reach
    writes = lands
    steps.append(Step.new(kernel_name, values))


## Adds *kernel_name* of the same file with its *values* as the next step, and
## answers the pass, so a filter can chain the steps it records. Refused with a
## problem on a pass that reads the whole node, whose source is not padded and
## has no frame a scratch could share.
## *coarser* is [member Step.coarser], 0 for a step whose threads count
## texel for texel.
func then(kernel_name: String, values: Dictionary[String, Variant], coarser: int = 0) -> SaNeighbourhoodPass:
    if whole():
        SaProblems.report(
            "SaNeighbourhoodPass",
            (
                TranslationServer.translate("%s reads the whole node and runs one kernel, so %s was not added.")
                % [kernel, kernel_name]
            )
        )
        return self
    steps.append(Step.new(kernel_name, values, coarser))
    return self


## Whether this pass reads the whole node, [const WHOLE_NODE].
func whole() -> bool:
    return radius == WHOLE_NODE


## The padding actually gathered, [member radius] clamped to one chunk. A
## gather reaches the eight neighbours and no further, and a filter that asks
## for more is softer than it asked rather than missing, because a blur that is
## a little too soft is legible and a filter that draws nothing is not. Zero
## for a pass that reads the whole node, whose source is gathered once and
## never padded.
func halo() -> int:
    return halo_at(SaChunk.SIZE)


## [method halo] on a chunk *side* texels across, the radius taken from
## document pixels into those texels and clamped to one chunk of them: twice
## the texels on a layer at twice the document's resolution, so a blur reaches
## as far on the canvas.
func halo_at(side: int) -> int:
    if whole():
        return 0
    return clampi(SaFilterDensity.length(radius, side), 0, side)


## The named params for a dispatch over the region starting at *origin*, with
## the padding *reach*, in the chunk that starts at the document pixel *chunk*,
## reading a source whose first texel is the document pixel *source*, for the
## fields *layout* declares, over *values*, the step's own params, or the first
## step's when it is null.
##
## *density* is the chunk's texels per document pixel on a side. Past 1.0 the
## places above are in those texels, a param named `radius`, the one length
## the blurs in the tree declare, is multiplied by it, and a kernel that
## declares `scale` is told it, for a length of another name. That is the pass
## scaling a length and not each module.
func params_for(
    layout: Array,
    origin: Vector2i,
    reach: int,
    chunk: Vector2i = Vector2i.ZERO,
    source: Vector2i = Vector2i.ZERO,
    values: Variant = null,
    density: float = 1.0
) -> Dictionary[String, Variant]:
    var out: Dictionary[String, Variant] = params.duplicate() if values == null else SaTyped.strings(values)
    if density != 1.0 and out.has("radius"):
        out["radius"] = out["radius"] * density
    for raw_field: Variant in layout:
        var field := SaTyped.strings(raw_field)
        match SaTyped.text_at(field, "name", ""):
            "scale":
                out["scale"] = density
            "origin":
                out["origin"] = Vector2(origin)
            "halo":
                out["halo"] = reach
            "chunk":
                out["chunk"] = Vector2(chunk)
            "source":
                out["source"] = Vector2(source)
    return out


## The grid positions this pass writes over a node that holds chunks at *held*,
## on a canvas of *canvas* document pixels, as a set. The held positions
## always, since the pass rewrites them, and past them what [member writes]
## declares, kept to the canvas. A pass with a radius answers the held
## positions alone, its ring being the caller's to add.
func lands_on(held: Array, canvas: Vector2i) -> Dictionary[Vector2i, bool]:
    var found: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in held:
        found[grid_pos] = true
    if not whole() or writes == WRITES_NODE or canvas.x <= 0 or canvas.y <= 0:
        return found
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    var bounds := Rect2i(Vector2i.ZERO, canvas)
    if writes == WRITES_CANVAS:
        _reach_over(bounds, found)
        return found
    for grid_pos: Vector2i in held:
        var from := Rect2i(grid_pos * side, side).intersection(bounds)
        if from.size.x <= 0 or from.size.y <= 0:
            continue
        var start := Vector2i(
            posmod(from.position.x + displacement.x, canvas.x), posmod(from.position.y + displacement.y, canvas.y)
        )
        # The moved rectangle is no wider than the canvas, so it crosses each
        # far edge at most once, and the part past an edge wraps to the start.
        for part in _wrapped(Rect2i(start, from.size), canvas):
            _reach_over(part, found)
    return found


## Every position *records* write over a node holding chunks at *held*, a set
## keyed by grid position, from the passes they were last evaluated to. *held*
## itself when no enabled record writes past its node, and otherwise a set of
## its own. A layer's chunk table comes in through `SaTyped.positions`, since
## its values are chunks and not `true`.
static func landing(
    records: Array[SaAttachedFilter], held: Dictionary[Vector2i, bool], canvas: Vector2i
) -> Dictionary[Vector2i, bool]:
    var out := held
    for record in records:
        if record == null or not record.enabled or not (record.cached_pass is SaNeighbourhoodPass):
            continue
        var recorded := record.cached_pass as SaNeighbourhoodPass
        if recorded.whole() and recorded.writes != WRITES_NODE:
            var found := recorded.lands_on(held.keys(), canvas)
            for grid_pos: Vector2i in out:
                found[grid_pos] = true
            out = found
    return out


## Every position a paint over *regions*, grid position -> chunk-local Rect2i,
## makes stale past the regions on a node at *held* whose *records* read it whole.
##
## A node whose one whole-node pass says where a change lands makes stale
## there alone: a wrap, [const WRITES_DISPLACED], *regions* moved round the
## canvas of *canvas* pixels by the displacement, and a pass with
## [member carries], what that answers. The root too, because its gather is not
## taken over the dirty set. Every other node makes
## every position it holds or lands on stale, [method landing] over them.
static func stale_under(
    records: Array[SaAttachedFilter], held: Dictionary[Vector2i, bool], regions: Dictionary[Vector2i, Rect2i], canvas: Vector2i
) -> Dictionary[Vector2i, bool]:
    var carried := _carried_by(records)
    if not carried.is_valid() or canvas.x <= 0 or canvas.y <= 0:
        return landing(records, held.merged(SaTyped.positions(regions)), canvas)
    var found: Dictionary[Vector2i, bool] = {}
    var bounds := Rect2i(Vector2i.ZERO, canvas)
    for grid_pos: Vector2i in regions:
        var region: Rect2i = regions[grid_pos]
        var from := Rect2i(grid_pos * SaChunk.SIZE + region.position, region.size).intersection(bounds)
        if from.size.x <= 0 or from.size.y <= 0:
            continue
        for part: Rect2i in carried.call(from, canvas):
            _reach_over(part.intersection(bounds), found)
    return found


## Whether [method stale_under] answers *records* from the regions alone, the
## one enabled whole-node pass saying where a change lands, so a caller need
## not gather what the node holds for it.
static func carries_change(records: Array[SaAttachedFilter], canvas: Vector2i) -> bool:
    return canvas.x > 0 and canvas.y > 0 and _carried_by(records).is_valid()


## Where the one enabled whole-node pass of *records* carries a change, empty for none or two.
static func _carried_by(records: Array[SaAttachedFilter]) -> Callable:
    var carried := Callable()
    var count := 0
    for record in records:
        if record == null or not record.enabled or not (record.cached_pass is SaNeighbourhoodPass):
            continue
        var recorded := record.cached_pass as SaNeighbourhoodPass
        if not recorded.whole():
            continue
        count += 1
        carried = recorded.carries
        if recorded.writes == WRITES_DISPLACED:
            carried = _displaced.bind(recorded.displacement)
    return carried if count == 1 else Callable()


## *from* moved by *shift* round the canvas, cut at each edge it crosses.
static func _displaced(from: Rect2i, canvas: Vector2i, shift: Vector2i) -> Array[Rect2i]:
    var start := Vector2i(posmod(from.position.x + shift.x, canvas.x), posmod(from.position.y + shift.y, canvas.y))
    return _wrapped(Rect2i(start, from.size), canvas)


## Adds every grid position *area*, in document pixels, reaches to *found*.
static func _reach_over(area: Rect2i, found: Dictionary[Vector2i, bool]) -> void:
    if area.size.x <= 0 or area.size.y <= 0:
        return
    var side := float(SaChunk.SIZE)
    var first := Vector2i((Vector2(area.position) / side).floor())
    var last := Vector2i((Vector2(area.end - Vector2i.ONE) / side).floor())
    for y in range(first.y, last.y + 1):
        for x in range(first.x, last.x + 1):
            found[Vector2i(x, y)] = true


## *area*, which starts on the canvas of *canvas* pixels and may run past its
## right or bottom edge, cut at each edge it crosses with the part past it
## moved back to the start.
static func _wrapped(area: Rect2i, canvas: Vector2i) -> Array[Rect2i]:
    var across: Array[Rect2i] = [area]
    if area.end.x > canvas.x:
        across = [
            Rect2i(area.position, Vector2i(canvas.x - area.position.x, area.size.y)),
            Rect2i(Vector2i(0, area.position.y), Vector2i(area.end.x - canvas.x, area.size.y)),
        ]
    var out: Array[Rect2i] = []
    for part in across:
        if part.end.y > canvas.y:
            out.append(Rect2i(part.position, Vector2i(part.size.x, canvas.y - part.position.y)))
            out.append(Rect2i(Vector2i(part.position.x, 0), Vector2i(part.size.x, part.end.y - canvas.y)))
        else:
            out.append(part)
    return out


## Whether any enabled record of *records* was last evaluated to a pass that
## reads the whole node, so a paint under the node makes every chunk it holds
## stale.
static func reads_whole(records: Array[SaAttachedFilter]) -> bool:
    for record in records:
        if record != null and record.enabled and record.cached_pass is SaNeighbourhoodPass:
            if (record.cached_pass as SaNeighbourhoodPass).whole():
                return true
    return false


## The largest halo the enabled records of *records* read, in document pixels,
## from the pass each was last evaluated to: what a paint under the node makes
## stale around itself. Zero before the first composite has built a pass,
## which is a composite of the whole document anyway, since every
## `SaFilterOps` operation redraws everything.
static func halo_of(records: Array[SaAttachedFilter]) -> int:
    var widest := 0
    for record in records:
        if record != null and record.enabled and record.cached_pass is SaNeighbourhoodPass:
            widest = maxi(widest, (record.cached_pass as SaNeighbourhoodPass).halo())
    return widest


## *regions*, grid position -> Rect2i in chunk-local pixels, each grown by
## *reach* on every side and cut back into the chunks it reaches, merged. Hard
## rule 2 for a neighbourhood filter: the rectangle is wider than the paint that
## dirtied it, and it is still a rectangle.
static func grown(regions: Dictionary[Vector2i, Rect2i], reach: int) -> Dictionary[Vector2i, Rect2i]:
    if reach <= 0:
        return regions
    var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
    var out: Dictionary[Vector2i, Rect2i] = {}
    for grid_pos: Vector2i in regions:
        var region: Rect2i = regions[grid_pos]
        if region.size.x <= 0 or region.size.y <= 0:
            continue
        var wide := Rect2i(region.position - Vector2i(reach, reach), region.size + Vector2i(reach, reach) * 2)
        for dy: int in [-1, 0, 1]:
            for dx: int in [-1, 0, 1]:
                var step := Vector2i(dx, dy)
                var part := wide.intersection(Rect2i(step * side, side))
                if part.size.x <= 0 or part.size.y <= 0:
                    continue
                var local := Rect2i(part.position - step * side, part.size)
                var at: Vector2i = grid_pos + step
                out[at] = (out[at] as Rect2i).merge(local) if out.has(at) else local
    return out


## Gathers a chunk and its neighbours into one padded texture and dispatches a
## neighbourhood pass over part of it.
##
## Held by whoever runs passes, so the padded texture and the two helper
## kernels are made once and reused rather than per chunk.
class Runner:
    extends RefCounted

    # The chunk and the paint around it, which every step reads.
    var _padding := SaChunkPadding.new()
    var _copy: SaCompute = null
    var _clear: SaCompute = null
    # The document's size in pixels, zero while no document was named, which
    # clamps nothing.
    var _canvas: Vector2i = Vector2i.ZERO
    # What the document's projection joins, the seam a halo reads across.
    var _wrapping: SaProjection.Wrap = SaProjection.Wrap.NONE
    var _reported: bool = false
    var _unchained: bool = false
    # What each step before the last writes, two taken in turn.
    var _scratches: Array[SaTexture] = [null, null]
    # The side of the pieces a dispatch is cut into.
    var _side: int = SaFilterContext.SUBMIT_SIDE

    ## A runner whose dispatches go out in pieces *side* on a side, the filter
    ## context's bound unless a suite asks for one dispatch to hold it against.
    func _init(side: int = SaFilterContext.SUBMIT_SIDE) -> void:
        _side = side

    ## *recorded* over *work*, a rectangle in the chunk at *grid_pos* in
    ## chunk-local pixels, into *target* through *compute*, masked by *mask*.
    ##
    ## *center* is what stands for the chunk itself and is read over *work*
    ## alone. *neighbour* answers the texture of the chunk at a grid position, or
    ## null where there is none, and is read over the part of *work* grown by the
    ## halo that falls on it. Everything else of the padding reads as
    ## transparent. [SaChunkPadding] writes all of it before the kernel runs, so
    ## *center* and *target* may be one texture.
    ##
    ## The padding and the dispatch cover *work* grown by the halo and nothing
    ## more.
    ##
    ## Past the document's edge the padding reads the nearest texel inside it,
    ## once [method reads_canvas_of] has named the document, rather than
    ## transparent, which would make an opaque layer's edge an edge against
    ## nothing, a bright rim under a sharpen and a dark one under a blur.
    func run(
        recorded: SaNeighbourhoodPass,
        compute: SaCompute,
        target: SaTexture,
        center: SaTexture,
        neighbour: Callable,
        grid_pos: Vector2i,
        work: Rect2i,
        mask: SaTexture
    ) -> void:
        # The chunk's own side, 512 on a layer at twice the document's
        # resolution, and the halo and the places in its texels.
        var side := target.size.x
        var density := float(side) / SaChunk.SIZE
        var reach := recorded.halo_at(side)
        if reach < SaFilterDensity.length(recorded.radius, side) and not _reported:
            _reported = true
            SaProblems.report(
                "SaNeighbourhoodPass",
                (
                    TranslationServer.translate("%s was limited to a radius of %s px (asked for %s).")
                    % [recorded.kernel, reach, recorded.radius]
                )
            )
        var margin := Vector2i(reach, reach)
        var grown := Rect2i(work.position - margin, work.size + margin * 2)
        var canvas := SaFilterDensity.in_texels(_canvas, side)
        var padded := _padding.build(center, neighbour, grid_pos, work, reach, target.format, canvas, side, _wrapping)
        var layout := GlobalShaderCompiler.push_constant_layout(recorded.shader)
        var chunk := grid_pos * side
        var chained := GlobalShaderCompiler.binding_kind(recorded.shader, PREVIOUS_BINDING) == "image"
        var last := recorded.steps.size() - 1
        if last > 0 and not chained:
            _report_unchained(recorded)
            last = 0
        var previous := padded
        for index in range(last + 1):
            var step: Step = recorded.steps[index]
            var into := target
            var region := work
            if index < last:
                # Two scratches taken in turn, since a step reads only the one
                # before it: a list of any length costs at most two.
                into = _scratch(index % 2, padded)
                region = grown
            compute.use_storage_format(target.format)
            compute.set_texture(0, padded.rid)
            compute.set_texture(SaSelection.BINDING, mask.rid)
            compute.set_texture(TARGET_BINDING, into.rid)
            if chained:
                compute.set_texture(PREVIOUS_BINDING, previous.rid)
            recorded.bind(compute)
            # A step whose threads count on a coarser level, 2^level texels
            # apart, is cut in its threads' own space, and a piece's corner
            # handed on as the origin those threads count from. A thread past
            # the level's last texel returns, so none past it is dispatched.
            var shift := step.coarser
            var threads := region.size
            if shift > 0:
                threads = threads.min(Vector2i(((padded.size.x - 1) >> shift) + 1, ((padded.size.y - 1) >> shift) + 1))
            for piece: Rect2i in SaFilterContext.submits(Rect2i(Vector2i.ZERO, threads), _side):
                var at := region.position + piece.position * (1 << shift)
                compute.set_params(recorded.params_for(layout, at, reach, chunk, chunk - margin, step.params, density))
                compute.dispatch_kernel(step.kernel, SaCompute.groups_for(piece.size.x), SaCompute.groups_for(piece.size.y), 1)
                SaFilterContext.note_submit(piece)
            previous = into

    ## *recorded*, a pass that reads the whole node, over *work* of the chunk at
    ## *grid_pos* into *target*, reading *whole* as its source, masked by
    ## *mask*. Nothing is gathered here: [method gather] built *whole* once for
    ## every chunk of the evaluation, and *target* may be the chunk's own
    ## texture, since the kernel never reads it.
    ##
    ## With *listed* the dispatch joins the list open on *compute*, opened
    ## when none is, and the caller ends it after its last chunk. That is the
    ## root's canvas written straight, passed as the chunk at
    ## the origin with *work* in document pixels.
    ##
    ## *halvings* above 0 draws it coarser, for a canvas preview while a
    ## control drags, when the kernel declares a param named `block`: it is
    ## handed 2^halvings, the side of the square of texels the kernel is to
    ## read once and spread. The dispatch stays a thread a texel, so the kernel
    ## keeps the card's width and shares the read among the square's threads. A
    ## kernel that declares no `block` runs exact whatever this says.
    func run_whole(
        recorded: SaNeighbourhoodPass,
        compute: SaCompute,
        target: SaTexture,
        whole: Whole,
        grid_pos: Vector2i,
        work: Rect2i,
        mask: SaTexture,
        listed: bool = false,
        halvings: int = 0
    ) -> void:
        if whole == null or whole.texture == null:
            return
        compute.use_storage_format(target.format)
        compute.set_texture(0, whole.texture.rid)
        compute.set_texture(SaSelection.BINDING, mask.rid)
        compute.set_texture(TARGET_BINDING, target.rid)
        recorded.bind(compute)
        var layout := GlobalShaderCompiler.push_constant_layout(recorded.shader)
        var block := 1 << halvings if halvings > 0 and _declares(layout, "block") else 1
        # In the filter context's bounded pieces, each handed its own corner.
        for piece: Rect2i in SaFilterContext.submits(work, _side):
            var values := recorded.params_for(layout, piece.position, 0, grid_pos * SaChunk.SIZE, whole.origin)
            if block > 1:
                values["block"] = block
            compute.set_params(values)
            var x := SaCompute.groups_for(piece.size.x)
            var y := SaCompute.groups_for(piece.size.y)
            if listed:
                compute.list_dispatch_kernel(recorded.kernel, target.format, x, y, 1)
            else:
                compute.dispatch_kernel(recorded.kernel, x, y, 1)
            SaFilterContext.note_submit(piece)

    ## Whether *layout*, a kernel's push constant fields, holds one *named*.
    static func _declares(layout: Array, named: String) -> bool:
        for raw_field: Variant in layout:
            if SaTyped.text_at(SaTyped.strings(raw_field), "name", "") == named:
                return true
        return false

    ## The chunks at *positions*, each answered by *field*, gathered into one
    ## texture at *format* over the rectangle they span, into *into* when it is
    ## given so its texture is reused. A position inside the rectangle that holds
    ## no chunk reads as transparent, and a chunk stored below full resolution
    ## is left out, as the neighbour gather leaves one out.
    ##
    ## A pass over the node and not over the canvas: the clears and the copies
    ## cover the rectangle of what the node allocated and nothing past it.
    ##
    ## **A kept node copies only what it owes**. *owing*
    ## answers, for the chunks held and whether the node starts anew, the
    ## positions to copy, and every one without it. A node over another
    ## rectangle or at another format starts anew.
    ##
    ## **Only the positions it holds no chunk at are cleared**, rather than one
    ## clear over the whole span, which is a dispatch over the canvas for a node
    ## of two chunks in opposite corners and writes every chunk the node holds a
    ## second time under its own copy. A position it holds is wholly overwritten,
    ## so nothing is owed to it, and the zeros belong where nothing was
    ## gathered.
    func gather(positions: Array, field: Callable, format: int, into: Whole = null, owing := Callable()) -> Whole:
        var whole := into if into != null else Whole.new()
        if positions.is_empty():
            whole.texture = null
            return whole
        var first: Vector2i = positions[0]
        var last: Vector2i = positions[0]
        for grid_pos: Vector2i in positions:
            first = first.min(grid_pos)
            last = last.max(grid_pos)
        var size := (last - first + Vector2i.ONE) * SaChunk.SIZE
        var anew := into == null or whole.origin != first * SaChunk.SIZE
        whole.origin = first * SaChunk.SIZE
        if whole.texture == null or whole.texture.format != format or whole.texture.size != size:
            whole.texture = SaTexture.new(size, format)
            anew = true
        var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
        # Read every chunk before writing any, so a texture that is both the
        # source and the target of this gather cannot be read after it was
        # cleared.
        var held: Dictionary[Vector2i, SaTexture] = {}
        for grid_pos: Vector2i in positions:
            var found: Variant = field.call(grid_pos)
            var texture: SaTexture = found if found is SaTexture else null
            if texture == null or texture.size != side:
                continue
            held[grid_pos] = texture
        var owed: Array = owing.call(held, anew) if owing.is_valid() else held.keys()
        # A cell the node no longer holds may still hold what it held.
        if owed.size() == held.size():
            _clear_unheld(whole.texture, Rect2i(first, last - first + Vector2i.ONE), held)
        for grid_pos: Vector2i in owed:
            _copy_onto(whole.texture, held[grid_pos], Vector2i.ZERO, grid_pos * SaChunk.SIZE - whole.origin, side)
        return whole

    ## Names the document *node* belongs to, a layer, a group or the document
    ## itself, so [method run] clamps the padding to its edge, and reads across
    ## the seam where its projection wraps. A node in no
    ## document clamps nothing, which is what a stroke buffer or a suite's bare
    ## layer wants.
    func reads_canvas_of(node: Node) -> void:
        var up := node
        while up != null and not up is SaDocument:
            up = up.get_parent()
        _canvas = (up as SaDocument).canvas_size if up != null else Vector2i.ZERO
        _wrapping = (up as SaDocument).projection.wrapping if up != null else SaProjection.Wrap.NONE

    ## The scratch *slot* of a pass of several steps, the size and format of
    ## *like*, made once and kept.
    func _scratch(slot: int, like: SaTexture) -> SaTexture:
        var kept: SaTexture = _scratches[slot]
        if kept == null or kept.format != like.format or kept.size != like.size:
            kept = SaTexture.new(like.size, like.format)
            _scratches[slot] = kept
        return kept

    ## Says once that *recorded* lists more kernels than its file can chain,
    ## because the file declares no image at [const PREVIOUS_BINDING], and that
    ## only its first runs.
    func _report_unchained(recorded: SaNeighbourhoodPass) -> void:
        if _unchained:
            return
        _unchained = true
        SaProblems.report(
            "SaNeighbourhoodPass",
            (
                TranslationServer.translate_plural(
                    "%s lists %d kernel and its file declares no image at binding %d, so only the first ran.",
                    "%s lists %d kernels and its file declares no image at binding %d, so only the first ran.",
                    recorded.steps.size()
                )
                % [recorded.kernel, recorded.steps.size(), PREVIOUS_BINDING]
            )
        )

    ## Clears every chunk-sized cell of *cells*, a rectangle of grid positions,
    ## that *held* has no entry for, one dispatch each, in the pixels of *target*
    ## whose first texel stands for the first cell of *cells*.
    ##
    ## A position the node holds is wholly overwritten by its own copy, so a
    ## clear over it would be a second write of the same texels and a dispatch
    ## over a rectangle nobody painted. A node of two chunks at opposite corners
    ## of a four by four span therefore clears fourteen cells and copies two,
    ## where one clear over the span covered the whole canvas.
    func _clear_unheld(target: SaTexture, cells: Rect2i, held: Dictionary[Vector2i, SaTexture]) -> void:
        var side := Vector2i(SaChunk.SIZE, SaChunk.SIZE)
        for y in range(cells.position.y, cells.end.y):
            for x in range(cells.position.x, cells.end.x):
                var grid_pos := Vector2i(x, y)
                if held.has(grid_pos):
                    continue
                _clear_on(target, Rect2i((grid_pos - cells.position) * SaChunk.SIZE, side))

    ## Clears *area* of *target*, in its own pixels. A dispatch and not
    ## `texture_clear`, because the copies and the kernel after it are compute,
    ## and a clear is a transfer the driver does not order against them.
    func _clear_on(target: SaTexture, area: Rect2i) -> void:
        if _clear == null:
            _clear = SaCompute.new("clear")
        _clear.use_storage_format(target.format)
        _clear.set_texture(0, target.rid)
        _clear.set_push_constant_float_array(
            PackedFloat32Array([0.0, 0.0, area.position.x, area.position.y, area.size.x, area.size.y, 0.0, 0.0])
        )
        _clear.dispatch_kernel("clear_chunk", SaCompute.groups_for(area.size.x), SaCompute.groups_for(area.size.y), 1)

    ## Copies *size* texels of *source* from *from* onto *target* at *to*.
    func _copy_onto(target: SaTexture, source: SaTexture, from: Vector2i, to: Vector2i, size: Vector2i) -> void:
        if source == null or size.x <= 0 or size.y <= 0:
            return
        if _copy == null:
            _copy = SaCompute.new("copy_region")
        _copy.use_storage_format(source.format)
        _copy.set_texture(0, target.rid)
        _copy.set_texture(1, source.rid)
        _copy.set_push_constant_float_array(PackedFloat32Array([from.x, from.y, to.x, to.y, size.x, size.y, 0.0, 0.0]))
        _copy.dispatch_kernel("copy_region", SaCompute.groups_for(size.x), SaCompute.groups_for(size.y), 1)

    func _notification(what: int) -> void:
        if what == NOTIFICATION_PREDELETE:
            # The texture first, while the device is still there, then the
            # computes, whose own PREDELETE frees their pipelines.
            _padding = null
            _scratches.clear()
            _copy = null
            _clear = null


## A node's allocated chunks gathered into one texture, the source a pass that
## reads the whole node reads. Built by [method Runner.gather] once per
## evaluation and read by every chunk of it, and kept from one evaluation to
## the next by the chain, which says what changed in between.
class Whole:
    extends RefCounted

    ## The gathered texture, null over a node that holds no chunk.
    var texture: SaTexture = null
    ## The document pixel the first texel of [member texture] stands for.
    var origin: Vector2i = Vector2i.ZERO


## One kernel of a pass and its params by name.
class Step:
    extends RefCounted

    ## The entry point in the pass's file.
    var kernel: String = ""
    ## Its params by name, as the filter wrote them.
    var params: Dictionary[String, Variant] = {}
    ## How many times the frame is halved on the level its threads count on, 0
    ## for a step whose threads count texel for texel. What the runner cuts a
    ## dispatch of the step by, written on [SaNeighbourhoodPass].
    var coarser: int = 0

    func _init(kernel_name: String, values: Dictionary[String, Variant], halved: int = 0) -> void:
        kernel = kernel_name
        params = values
        coarser = maxi(0, halved)
