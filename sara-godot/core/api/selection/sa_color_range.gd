## Colour range: pick a colour, set a fuzziness, and every texel of the
## picture within it is chosen, as coverage from zero to one.
##
## One engine and two destinations. `select` merges the coverage into the
## document's selection in a mode, which is the Select menu's command, and
## `SaMaskOps.from_color_range` writes it into an attached filter's mask, which
## is how "sharpen the reds only" is done. Beside `SaSelectionFilters` in the
## skeleton rather than in the base module, because the skeleton's own Select
## menu is one of the two callers and `core` never names a module.
##
## **Not the magic wand.** The wand floods the contiguous region around a seed,
## sweeping chunk by chunk and reading a buffer back per sweep. A colour range
## has no seed and no contiguity, so it is one dispatch per chunk over the
## canvas and nothing crosses the bus. The two measure differently as well: the
## wand takes the largest channel distance over the document's stored numbers,
## and this takes the Euclidean distance in Oklab, because a range covers the
## whole canvas and the stored numbers mean different things in an sRGB and an
## Oklab document. So a tolerance of forty and a fuzziness of forty are not the
## same spread, and are not meant to be.
##
## `color_range.gmacs` holds the maths. Coverage is `1 - d / t`, clamped to a
## mask's zero and one, where *d* is the Oklab distance and the threshold *t*
## is [method threshold] of the fuzziness. At a hundred there is no threshold
## and every texel is chosen whole, since in a float document a colour can stand
## further from the pick than black does from white.
class_name SaColorRange
extends RefCounted

## What a transparent texel is measured over, the wand's neutral mid grey, so
## the two tools agree about what lies behind nothing. Written here rather than
## read from the wand, which is a module's class. A display colour, carried
## into the document's numbers before it reaches the kernel.
const NEUTRAL_BACKDROP := Color(0.5, 0.5, 0.5, 1.0)

## The fuzziness a new dialog opens on, out of a hundred.
const DEFAULT_FUZZINESS: float = 40.0
const MAX_FUZZINESS: float = 100.0
## The power [method threshold] raises the fuzziness to, which narrows the low
## end of the slider and leaves its top where it was.
const CURVE: float = 2.5
## What [method threshold] answers at [constant MAX_FUZZINESS], a distance no
## texel reaches. `color_range.gmacs` reads it, at this value or above, as "no
## threshold" and covers the texel at full strength without measuring it, so a
## texel of any distance, an infinite or a NaN one in a float document too, is
## chosen. Finite because a push constant is not trusted with an infinity.
const UNBOUNDED: float = 1.0e30

const BINDING_MASK: int = 0
const BINDING_COLOR: int = 1
const BINDING_COLORS: int = 2

var _document: SaDocument
var _compute: SaCompute = null
## A 1 by 1 transparent texel per colour format, for a chunk the layer does
## not hold.
var _blank: Dictionary[int, SaTexture] = {}


func _init(document: SaDocument) -> void:
    _document = document


## The Oklab distance at which coverage reaches zero, for a fuzziness out of a
## hundred: the fuzziness over a hundred to the power [constant CURVE], and
## [constant UNBOUNDED] at a hundred, where there is no such distance.
##
## A curve rather than a straight line, because the colours a painter tells
## apart sit close together in Oklab. A mid blue such as `#3c78c8` is 0.14 from
## a mid grey, and the curve gives 0.10 at forty, which leaves that grey at
## zero, 0.28 at sixty, and 0.975 at ninety-nine. The top of the slider is the
## whole picture, whatever its distance, because a float colour can stand
## further from the pick than black does from white.
static func threshold(fuzziness: float) -> float:
    if fuzziness >= MAX_FUZZINESS:
        return UNBOUNDED
    return pow(maxf(fuzziness, 0.0) / MAX_FUZZINESS, CURVE)


## Coverage of *color* at *fuzziness* over the canvas, as a fresh mask chunk
## per canvas chunk, keyed by grid position.
##
## *color* is a display colour, the kind the swatch and the eyedropper hand
## over. The picture is *merged*, the easel's output at document resolution,
## when it is given, else *layer*'s own chunks, and a chunk the layer does not
## hold reads as transparent and so as the backdrop.
##
## *only*, when it has an area, keeps the dispatch to the chunks it reaches, in
## document pixels. The dialog's live preview passes what the view shows, so a
## move of the slider costs the chunks on screen and not the canvas, and Apply
## passes nothing and covers it all.
func coverage(
    color: Color, fuzziness: float, merged: SaTexture = null, layer: SaLayer = null, only: Rect2i = Rect2i()
) -> Dictionary[Vector2i, SaChunk]:
    var out: Dictionary[Vector2i, SaChunk] = {}
    if _document == null or (merged == null and layer == null):
        return out
    var format: int = merged.format if merged != null else _layer_format(layer)
    if format < 0:
        return out
    var space := _document.color_space
    var pick := space.from_display(Color(color.r, color.g, color.b, 1.0))
    var behind := space.from_display(NEUTRAL_BACKDROP)
    var colors := SaCompute.Buffer.new(
        PackedFloat32Array([pick.r, pick.g, pick.b, 1.0, behind.r, behind.g, behind.b, 1.0]).to_byte_array()
    )
    if _compute == null:
        _compute = SaCompute.new("color_range")
    # The colour image's depth rather than the mask's, which the kernel names
    # as r32f itself, the wand's arrangement and for the wand's reason.
    _compute.use_storage_format(format)
    var tail := space.to_push_constant()
    var t := threshold(fuzziness)
    var canvas := Rect2i(Vector2i.ZERO, _document.canvas_size)
    var side := SaChunk.SIZE
    for grid_pos: Vector2i in SaLayer.grid_positions(_document.canvas_size):
        if only.has_area() and not SaSelection.chunk_rect(grid_pos).intersects(only):
            continue
        var chunk := _document.selection.make_chunk()
        var target := chunk.field(SaSelection.FIELD)
        var local := SaChunkWalk.local_rect(grid_pos, canvas, side)
        if target == null or local.size.x <= 0 or local.size.y <= 0:
            continue
        var source := merged if merged != null else _layer_texture(layer, grid_pos, format)
        var offset := grid_pos * side if merged != null else Vector2i.ZERO
        var scale := 1.0
        if merged == null and source.size.x > 1:
            scale = float(source.size.x) / float(side)
        var params := PackedFloat32Array(
            [0.0, 0.0, float(local.end.x), float(local.end.y), float(offset.x), float(offset.y), scale, t]
        )
        params.append_array(tail)
        _compute.set_texture(BINDING_MASK, target.rid)
        _compute.set_texture(BINDING_COLOR, source.rid)
        _compute.set_buffer(BINDING_COLORS, colors.rid)
        _compute.set_push_constant_float_array(params)
        _compute.dispatch_kernel("color_range", SaCompute.groups_for(local.end.x), SaCompute.groups_for(local.end.y), 1)
        out[grid_pos] = chunk
    return out


## Chooses every texel within *fuzziness* of *color* and merges it into the
## selection in *mode*, a `SaSelection.Mode`: replacing it, united with it,
## taken out of it or met with it, through `SaSelection.merge_region`. One undo
## step, through `SaSelection.change`.
func select(color: Color, fuzziness: float, mode: int, merged: SaTexture = null, layer: SaLayer = null) -> void:
    var selection := _document.selection if _document != null else null
    if selection != null:
        selection.change(SaSelection.COLOR_RANGE_TITLE, _select.bind(selection, color, fuzziness, mode, merged, layer))


func _select(selection: SaSelection, color: Color, fuzziness: float, mode: int, merged: SaTexture, layer: SaLayer) -> void:
    if mode == SaSelection.Mode.SUBTRACT and not selection.active:
        # Everything is selected and nothing holds it, so there is nothing to
        # take the range out of, and the coverage is not worth computing.
        return
    var region := coverage(color, fuzziness, merged, layer)
    if not region.is_empty():
        selection.merge_region(region, mode)


static func _layer_format(layer: SaLayer) -> int:
    if layer == null or layer.schema.is_empty():
        return -1
    return layer.schema[0].format


## *layer*'s colour at *grid_pos*, or a transparent texel where it holds none.
func _layer_texture(layer: SaLayer, grid_pos: Vector2i, format: int) -> SaTexture:
    var own := layer.get_field(grid_pos)
    if own != null and own.format == format:
        return own
    var blank: SaTexture = _blank.get(format, null)
    if blank == null:
        blank = SaTexture.new(Vector2i(1, 1), format)
        blank.clear(Color(0.0, 0.0, 0.0, 0.0))
        _blank[format] = blank
    return blank
