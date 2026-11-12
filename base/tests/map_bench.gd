## What the three map filter suites share: an easel of one painted chunk
## holding a height the suite chose, one of the two map filters registered and
## attached over it, and the chain's answer at a texel of it.
##
## The height is painted through `texture_update` from an `Image`, the way
## `test_box_blur` paints its line, and an answer is read through
## `tests/fixtures/attached_filter_bench.gd`, the bench the neighbourhood suite
## reads with. The chunk is the second one in, so every texel read below has a
## neighbour on all four sides and none of them is the canvas's own edge, where
## the gather finds no chunk and so reads a height of zero.
extends RefCounted

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const OWNER: StringName = &"sara-base-modules"
const SIZE := Vector2i(1024, 1024)
## The chunk every height is painted into and every answer read from.
const PAINTED := Vector2i(1, 1)

## The heights a suite can ask for, by name rather than by the numbers.
##
## Each carries the slope it means, because that is the number every expectation
## in the three suites is built out of:
##
## - [constant FLAT] and [constant ABOVE_ONE] are one grey everywhere, so both
##   slopes are exactly zero and the answer is the identity normal.
## - [constant RAMP_RIGHT] climbs one grey level a texel to the right, and
##   [constant RAMP_TOP] climbs one a texel upwards, which is one level down
##   `v`, since the canvas's own v runs down.
## - [constant RIDGE] is a tent peaking in the middle, so its left half rises to
##   the right and its right half falls, and the two texels the bump suite reads
##   stand at the same height and lean opposite ways.
const FLAT := 0
const ABOVE_ONE := 1
const RAMP_RIGHT := 2
const RAMP_TOP := 3
const RIDGE := 4

## The grey [constant ABOVE_ONE] holds, which is out of range on purpose: the
## shade may darken it and may not clamp it (hard rule 5).
const BRIGHT := 2.0
## How many grey levels [constant RAMP_RIGHT] and [constant RAMP_TOP] climb
## over, which is the chunk's own width less one: one texel is one 255th.
const LEVELS := float(SaChunk.SIZE - 1)
## The column [constant RIDGE] peaks at, and the heights it reaches either side.
## Halves rather than slashes, because an integer division is a warning
## `check_lsp.sh` fails the run over and the shift is the tree's own spelling.
const PEAK := SaChunk.SIZE >> 1
## The two texels of the ridge that lean, and the height both stand at. The
## first climbs to the right and so faces left, the second the other way.
const CLIMBING := PEAK >> 1
const FALLING := PEAK + (PEAK >> 1)
const LEANING_HEIGHT := 0.5

var easel: SaEasel = null
var document: SaDocument = null
var layer: SaLayer = null
var record: SaAttachedFilter = null
var filter: SaFilter = null
var key: StringName = &""
var height: int = FLAT


## An easel whose one painted chunk holds *kind*, with *its_filter* registered
## under this module's id.
func _init(kind: int, its_filter: SaFilter) -> void:
    filter = its_filter
    height = kind
    easel = Bench.easel(SIZE)
    var registry := SaFilterRegistry.new()
    registry.register(filter, OWNER)
    easel.compositor.filter_chain.registry = registry
    key = SaFilterRegistry.key_for(OWNER, filter)
    document = easel.document
    layer = document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    _paint()


func release() -> void:
    record = null
    filter = null
    layer = null
    document = null
    easel.free()
    easel = null


## Puts *kind* in the chunk, for a suite that reads two shapes out of one bench.
func repaint(kind: int) -> void:
    height = kind
    _paint()
    Bench.composite(easel)


## Attaches the filter with *params*, composites once, and answers what the
## record kept. A record already attached is taken off first, so a suite that
## repainted and attached again holds one record and not two.
func attach(params: Dictionary) -> Dictionary:
    if record != null:
        SaFilterOps.new(document).detach(layer, record)
        record = null
    filter.set_parameters(params)
    var kept := filter.parameters()
    record = SaFilterOps.new(document).attach(layer, key, kept)
    Bench.composite(easel)
    return kept


## The chain's answer at *at*, a pixel of the painted chunk.
func answer(at: Vector2i) -> Color:
    var filtered := easel.compositor.filter_chain.filtered(layer, layer.get_field(PAINTED), PAINTED, SaDocument.WHOLE_CHUNK)
    return Bench.texel(filtered, at)


## The same answer through the whole compositor, at *at* in document pixels.
func composite(at: Vector2i) -> Color:
    return Bench.texel(easel.output, PAINTED * SaChunk.SIZE + at)


## How many grey levels a texel of [constant RAMP_RIGHT] and [constant RAMP_TOP]
## climbs, which is the slope both filters read.
static func step() -> float:
    return 1.0 / LEVELS


## The height *kind* holds at a texel of the chunk, as the grey both filters
## read: the luminance of a grey is the grey.
static func height_at(kind: int, x: int, y: int) -> float:
    match kind:
        ABOVE_ONE:
            return BRIGHT
        RAMP_RIGHT:
            return float(x) / LEVELS
        RAMP_TOP:
            return float(SaChunk.SIZE - 1 - y) / LEVELS
        RIDGE:
            return 1.0 - float(abs(x - PEAK)) / float(PEAK)
    return 0.5


func _paint() -> void:
    var chunk := layer.get_or_create_chunk(PAINTED)
    if height == FLAT or height == ABOVE_ONE:
        # Cleared rather than uploaded, and that is the point of the second of
        # the two: a clear is a compute kernel and carries a value above one
        # into the chunk unchanged, where `Image.set_pixel` may not.
        var level := height_at(height, 0, 0)
        chunk.clear(Color(level, level, level, 1.0))
        return
    chunk.clear(Color(0.0, 0.0, 0.0, 1.0))
    var image := Image.create(SaChunk.SIZE, SaChunk.SIZE, false, Image.FORMAT_RGBAF)
    image.fill(Color(0.0, 0.0, 0.0, 1.0))
    for y in SaChunk.SIZE:
        for x in SaChunk.SIZE:
            var grey := height_at(height, x, y)
            image.set_pixel(x, y, Color(grey, grey, grey, 1.0))
    GlobalShaderCompiler.get_rd().texture_update(chunk.field(SaFieldSpec.ALBEDO).rid, 0, image.get_data())
