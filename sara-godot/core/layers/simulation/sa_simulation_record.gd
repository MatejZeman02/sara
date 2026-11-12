## A simulation rule on one paint layer: the rule's key, its parameters, the
## seed, the step count, and the second copy of the layer's state the step
## writes into. Held at `SaLayer.simulation` and built by [SaSimulation], whose
## page says what a rule is and why the step runs the way it does. The record
## keeps no reference to the layer that holds it, the facade hands the layer to
## every step and reset.
##
## **The second copy** is one texture per chunk the step has reached, the size
## and format of what the step reads, the chunk's `albedo`, or the field of the
## rule's own, [SaSimulationField], when it declares one. A step writes every
## one of them before it swaps any, so no chunk reads a neighbour already
## stepped. The record owns them, so they go when the record goes (hard rule 4).
##
## **The seed** is what Reset returns the layer to, the paint as last painted:
## a copy of every chunk's `albedo` when the record goes on, and again at every
## grid position a history step writes paint into ([signal SaLayer.paint_recorded])
## or an undo or a redo exchanges ([signal SaLayer.paint_swapped]), so the seed
## holds what the canvas holds after either. A step is not a history step, so it
## never moves the seed. Every copy is a dispatch rather than a texture copy,
## because a copy is a transfer and the step that follows it is compute, and the
## two are not ordered inside a frame. A `.sad` file keeps the seed beside the
## layer's paint, and a rule with a field of its own seeds the field from the
## seed every time the seed moves, and at Reset.
##
## **Painting while paused edits the current state, and that becomes the
## seed**. Before the first step only the painted chunks are copied, and once it
## has stepped every chunk is, since a stroke over a stepped state leaves that
## state for Reset to return to, and the count goes back to nought with it. Paint
## recorded pauses a running simulation, and so does the press of a stroke, which
## comes before any dab, through [signal SaLayer.stroke_pressed].
##
## **Playing is counted in steps.** [method steps_due] adds a frame's share of
## [member speed] to what earlier frames owed and answers the whole steps. A
## frame longer than [constant LONGEST_FRAME] counts as that long, so steps that
## made a frame slow never ask for more of themselves in the next.
##
## **The ring** is how the pattern grows into chunks the layer did not hold. A
## rule of reach r moves paint at most r texels a step, so paint in a chunk
## cannot leave the ring of chunks round it until a chunk's side over r steps
## have passed. Before the first step, and again every time that many steps have
## gone, the record allocates the ring of empty chunks round every chunk the
## layer holds, and paint that sets the seed counts from nought. A chunk the
## layer gained by a way that sets no seed, a transform baked into it, is ringed
## before the next step, since its paint may lie at its edge already. Nothing is
## read back to ask where the pattern went (hard rules 1 and 3). The ring keeps
## to the chunks [member domain] touches inside the canvas, a chunk once
## allocated stays for the run, and Reset drops every chunk the seed does not hold.
class_name SaSimulationRecord
extends RefCounted

## The longest a frame counts for when playing, in seconds: a thirtieth, twice
## a frame at 60 Hz, so the ordinary jitter of a frame is paid in full and a
## stall is not.
const LONGEST_FRAME := 1.0 / 30.0

## The key of the rule the record runs, as the registry holds it.
var rule: StringName = &""

## The id of the module that registered [member rule], kept so a file can say
## which module a document needs, and empty for a rule nobody said the owner of.
var module: StringName = &""

## The rule's parameters as this layer sets them, over the rule's defaults.
var params: Dictionary[String, Variant] = {}

## How many steps the layer has taken since the seed.
var steps: int = 0

## The rectangle, in document pixels, the pattern may grow inside, which the
## painter sets in the panel, and no area for the whole canvas. A ring takes the
## chunks it touches, and never one past the canvas whatever it says.
var domain: Rect2i = Rect2i()

## Whether the layer steps on its own, frame by frame, at [member speed].
## Written by [method play] and [method pause].
var playing: bool = false

## How many steps a second playing runs, between [constant SaSimulation.SLOWEST]
## and [constant SaSimulation.FASTEST]. A count of steps and never a span of
## clock time.
var speed: float = SaSimulation.DEFAULT_SPEED

## What the layer's signals call, the paint recorded and the press, bound to
## the layer so the record holds no reference of its own to the layer that
## holds it.
var _heard: Callable = Callable()
var _pressed: Callable = Callable()
## The part of a step the frames played so far owe and have not run.
var _owed: float = 0.0
## Grid position -> the `albedo` as last painted.
var seed_chunks: Dictionary[Vector2i, SaTexture] = {}
## Grid position -> the second copy of that chunk's state.
var _second: Dictionary[Vector2i, SaTexture] = {}
## The field the rule steps in place of the paint, or null for a rule that
## steps the paint itself.
var _field: SaSimulationField = null
## The grid positions the layer held after the last ring, so a chunk it gained
## since is known by its absence.
var _ringed: Dictionary[Vector2i, bool] = {}
## Shader key -> the compute that runs a rule's kernel, made once.
var _computes: Dictionary[String, SaCompute] = {}
var _copier: SaCompute = null
## The padding and the dispatch, the same runner a filter's neighbourhood pass
## goes through, so a rule's halo is gathered exactly as a blur's is.
var _runner := SaNeighbourhoodPass.Runner.new()


## The rule called *rule_key*, which the module *module_id* registered, on
## *layer* with *values* over its defaults. The seed is taken from the layer as
## it stands, or is *kept* when a file hands one back with the grid positions
## its last ring left *ringed*, so a reopened layer steps on as it would have.
## A rule whose *state* is a field of its own has the field seeded from it.
func _init(
    layer: SaLayer,
    rule_key: StringName,
    values: Dictionary[String, Variant],
    module_id: StringName = &"",
    kept: Dictionary[Vector2i, SaTexture] = {},
    ringed: Array[Vector2i] = [],
    state: SaSimulation.State = null
) -> void:
    rule = rule_key
    module = module_id
    params = values.duplicate(true)
    if kept.is_empty():
        keep_seed(layer.chunks.keys(), layer)
    else:
        seed_chunks = kept.duplicate()
    for grid_pos in ringed:
        _ringed[grid_pos] = true
    if state != null:
        _field = SaSimulationField.new(layer, state)
        _field.seed(layer, seed_chunks, seed_chunks.keys())
    _heard = _painted.bind(layer)
    layer.paint_recorded.connect(_heard)
    layer.paint_swapped.connect(_heard)
    _pressed = pause
    layer.stroke_pressed.connect(_pressed)


## Lets go of *layer*'s signals, which the facade calls as it takes the record
## off, so a record nobody holds hears nothing more, and takes a field of the
## rule's own off the layer.
func release(layer: SaLayer) -> void:
    if _field != null and layer != null:
        _field.release(layer)
        _field = null
    if layer != null and layer.paint_recorded.is_connected(_heard):
        layer.paint_recorded.disconnect(_heard)
    if layer != null and layer.paint_swapped.is_connected(_heard):
        layer.paint_swapped.disconnect(_heard)
    if layer != null and layer.stroke_pressed.is_connected(_pressed):
        layer.stroke_pressed.disconnect(_pressed)


## Starts the layer stepping on its own.
func play() -> void:
    playing = true


## Stops it, and forgets the part of a step the frames owed.
func pause() -> void:
    playing = false
    _owed = 0.0


## The whole steps *delta* seconds of a frame owe at [member speed], with what
## is left of a step carried to the next frame. None while paused.
func steps_due(delta: float) -> int:
    if not playing:
        return 0
    _owed += speed * clampf(delta, 0.0, LONGEST_FRAME)
    # A hair over, so ten frames of a tenth of a step each make the step their
    # float sum falls short of by a last bit.
    var due := floori(_owed + 1.0e-6)
    _owed = maxf(_owed - due, 0.0)
    return due


## Paint recorded on *layer* at *grid_positions*, or exchanged there by an undo
## or a redo: it pauses the run and is the seed from here, the whole layer once
## it has stepped, as the page says.
func _painted(grid_positions: Array, layer: SaLayer) -> void:
    pause()
    if steps == 0:
        keep_seed(grid_positions, layer)
        _seed_field(grid_positions, layer)
        return
    # A position the seed holds and the layer no longer does is let go too.
    var every: Array = layer.chunks.keys()
    every.append_array(seed_chunks.keys().filter(func(grid_pos: Vector2i) -> bool: return not layer.chunks.has(grid_pos)))
    keep_seed(every, layer)
    _seed_field(every, layer)
    steps = 0


## Whether the `albedo` of *layer* is worked out from this record's field,
## which is the one derived colour a rule put on in its place may take off.
func colours(layer: SaLayer) -> bool:
    return _field != null and SaFieldSpec.find(layer.schema, _field.spec.id) == _field.spec


## A field of the rule's own seeded again at *grid_positions* from the seed.
func _seed_field(grid_positions: Array, layer: SaLayer) -> void:
    if _field != null:
        _field.seed(layer, seed_chunks, grid_positions)


## What the step reads and writes, the rule's own field or the paint.
func _stepped() -> StringName:
    return _field.spec.id if _field != null else SaFieldSpec.ALBEDO


## Holds *kept* as the seed in place of the one held, which Image > Depth hands
## over written again at the document's new depth, and its undo hands back.
func reseed(kept: Dictionary[Vector2i, SaTexture]) -> void:
    seed_chunks = kept.duplicate()


## Copies *layer*'s `albedo` at *grid_positions* into the seed, and forgets a
## position the layer holds no chunk at any more.
func keep_seed(grid_positions: Array, layer: SaLayer) -> void:
    for grid_pos: Vector2i in grid_positions:
        var painted := layer.get_field(grid_pos)
        if painted == null:
            seed_chunks.erase(grid_pos)
            continue
        var held: SaTexture = seed_chunks.get(grid_pos, null)
        if held == null or held.size != painted.size or held.format != painted.format:
            held = SaTexture.new(painted.size, painted.format)
            seed_chunks[grid_pos] = held
        _copy(held, painted)


## One step of *found*, the rule this record names, over every chunk of
## *layer*, the layer the record is on, that *window* reaches, in document
## pixels, once the ring the step is due has grown on a canvas of *canvas*
## pixels. Answers the grid positions it wrote, empty when the window reaches
## none, and counts the step either way. *mask* is what binding 1 reads, one
## everywhere.
func step(layer: SaLayer, found: SaSimulation.Rule, window: Rect2, mask: SaTexture, canvas: Vector2i) -> Array[Vector2i]:
    if _field == null and found.state != null:
        _take_up(layer, found.state)
    _grow(layer, found.reach, canvas)
    var reached := _reached(layer, window)
    var compute := _compute_for(found.shader)
    var recorded := SaNeighbourhoodPass.new(found.shader, found.kernel, _values(found), found.reach)
    _runner.reads_canvas_of(layer)
    var stepped := _stepped()
    var neighbour := layer.get_field.bind(stepped)
    var answers: Dictionary[Vector2i, SaTexture] = {}
    for grid_pos: Vector2i in reached:
        var state := layer.get_field(grid_pos, stepped)
        if state == null:
            continue
        var next := _second_for(grid_pos, state)
        _runner.run(recorded, compute, next, state, neighbour, grid_pos, Rect2i(Vector2i.ZERO, state.size), mask)
        answers[grid_pos] = next
    # Only now the swap: every chunk above read its neighbours as they were.
    for grid_pos: Vector2i in answers:
        var chunk: SaChunk = layer.chunks[grid_pos]
        _second[grid_pos] = chunk.fields[stepped]
        chunk.fields[stepped] = answers[grid_pos]
        layer.mark_unresolved(grid_pos)
    _forget_gone(layer)
    steps += 1
    var wrote: Array[Vector2i] = []
    wrote.assign(answers.keys())
    return wrote


## The field *state* names put on *layer* by the first step of a record a file
## reopened, which knew no rule. A chunk's texture of the field the file held
## is the state at the step it counts and is kept, and a chunk with none is
## seeded, as is every chunk when nothing has stepped since the seed.
func _take_up(layer: SaLayer, state: SaSimulation.State) -> void:
    var unheld: Array = []
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        var held := chunk.field(state.field.id)
        var edge := chunk.pixel_size()
        if steps == 0 or held == null or held.size != Vector2i(edge, edge) or held.format != state.field.format:
            unheld.append(grid_pos)
    _field = SaSimulationField.new(layer, state)
    _field.seed(layer, seed_chunks, unheld)


## The seed copied back into every chunk *layer*, the layer the record is on,
## still holds, every chunk a ring grew into dropped, and the count back to
## nought. Answers the grid positions it wrote or dropped.
func reset(layer: SaLayer) -> Array[Vector2i]:
    var wrote: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks.keys():
        if not seed_chunks.has(grid_pos):
            layer.set_chunk(grid_pos, null)
            wrote.append(grid_pos)
    _forget_gone(layer)
    _ringed.clear()
    for grid_pos: Vector2i in seed_chunks:
        var live := layer.get_field(grid_pos)
        var kept: SaTexture = seed_chunks[grid_pos]
        if live == null or live.size != kept.size or live.format != kept.format:
            continue
        _copy(live, kept)
        layer.mark_unresolved(grid_pos)
        wrote.append(grid_pos)
    _seed_field(seed_chunks.keys(), layer)
    steps = 0
    return wrote


## The rule's defaults with this layer's parameters over them, and `step`, the
## number of the step being taken, kept to the names *found*'s kernel declares,
## since a push constant refuses a name its block does not have.
func _values(found: SaSimulation.Rule) -> Dictionary[String, Variant]:
    var given: Dictionary[String, Variant] = found.defaults.duplicate(true)
    given.merge(params, true)
    given["step"] = steps
    var out: Dictionary[String, Variant] = {}
    for raw: Variant in GlobalShaderCompiler.push_constant_layout(found.shader):
        var named := SaTyped.text_at(SaTyped.strings(raw), "name", "")
        if given.has(named):
            out[named] = given[named]
    return out


## The chunks *layer* has allocated whose cells *window* reaches.
func _reached(layer: SaLayer, window: Rect2) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var side := Vector2(SaChunk.SIZE, SaChunk.SIZE)
    for grid_pos: Vector2i in layer.chunks:
        if window.intersects(Rect2(Vector2(grid_pos) * side, side)):
            out.append(grid_pos)
    return out


## The ring step number [member steps] is due on a rule of *reach*, allocated in
## *layer*: round every chunk it holds when the step's number is a multiple of
## the steps paint takes to cross a chunk, and otherwise round the chunks the
## layer gained since the last ring alone. A reach of nought never moves paint
## and grows nothing. A reach wider than a chunk grows as many rings as it
## crosses chunks in a step.
func _grow(layer: SaLayer, reach: int, canvas: Vector2i) -> void:
    if reach <= 0 or layer.chunks.is_empty():
        return
    var side := _narrowest(layer)
    var crossing := maxi(1, floori(float(side) / reach))
    var round_of: Array[Vector2i] = []
    for grid_pos: Vector2i in layer.chunks:
        if steps % crossing == 0 or not _ringed.has(grid_pos):
            round_of.append(grid_pos)
    var cells := _cells_of(canvas)
    for _ring in ceili(float(reach * crossing) / side):
        var ring: Dictionary[Vector2i, bool] = {}
        for grid_pos: Vector2i in round_of:
            for dy: int in [-1, 0, 1]:
                for dx: int in [-1, 0, 1]:
                    var beside := grid_pos + Vector2i(dx, dy)
                    if cells.has_point(beside):
                        layer.get_or_create_chunk(beside)
                        ring[beside] = true
        round_of.assign(ring.keys())
    _ringed.clear()
    for grid_pos: Vector2i in layer.chunks:
        _ringed[grid_pos] = true


## The texels across the narrowest chunk *layer* holds, a chunk's side in
## texels at its own resolution, which is what a rule's reach is counted in.
static func _narrowest(layer: SaLayer) -> int:
    var side := 0
    for grid_pos: Vector2i in layer.chunks:
        var chunk: SaChunk = layer.chunks[grid_pos]
        if chunk != null and (side == 0 or chunk.pixel_size() < side):
            side = chunk.pixel_size()
    return maxi(side, 1)


## The grid positions a ring may take on a canvas of *canvas* pixels, those of
## the chunks [member domain] touches inside the canvas, as a rectangle of grid
## cells.
func _cells_of(canvas: Vector2i) -> Rect2i:
    var inside := Rect2i(Vector2i.ZERO, canvas)
    if domain.has_area():
        inside = inside.intersection(domain)
    if not inside.has_area():
        return Rect2i()
    var first := Vector2i(floori(inside.position.x / float(SaChunk.SIZE)), floori(inside.position.y / float(SaChunk.SIZE)))
    var past := Vector2i(ceili(inside.end.x / float(SaChunk.SIZE)), ceili(inside.end.y / float(SaChunk.SIZE)))
    return Rect2i(first, past - first)


## The second copy at *grid_pos*, made like *state* the first time and again
## when the layer's chunks changed size or format under it.
func _second_for(grid_pos: Vector2i, state: SaTexture) -> SaTexture:
    var held: SaTexture = _second.get(grid_pos, null)
    if held == null or held.size != state.size or held.format != state.format:
        held = SaTexture.new(state.size, state.format)
        _second[grid_pos] = held
    return held


## Drops the second copy of a position *layer* holds no chunk at any more, one
## an undo or a reset took away, so the record holds no state the layer lost.
func _forget_gone(layer: SaLayer) -> void:
    for grid_pos: Vector2i in _second.keys():
        if not layer.chunks.has(grid_pos):
            _second.erase(grid_pos)


func _compute_for(shader: String) -> SaCompute:
    if not _computes.has(shader):
        _computes[shader] = SaCompute.new(shader)
    return _computes[shader]


## *from* written over *into*, both one chunk, by `copy_region`.
func _copy(into: SaTexture, from: SaTexture) -> void:
    if _copier == null:
        _copier = SaCompute.new("copy_region")
    _copier.use_storage_format(from.format)
    _copier.set_texture(0, into.rid)
    _copier.set_texture(1, from.rid)
    _copier.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, from.size.x, from.size.y, 0.0, 0.0]))
    _copier.dispatch_kernel("copy_region", SaCompute.groups_for(from.size.x), SaCompute.groups_for(from.size.y), 1)
