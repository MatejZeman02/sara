## The wand's Tolerance means one distance, whether it reads the merged
## picture or the active layer alone: the largest difference over the
## premultiplied colour and the alpha.
##
## A drive measured three floods from one point on one picture and got two
## answers out of one number: 20 percent stopped at an orange stroke with Merged
## off and ran straight over it with Merged on. This is that picture, in a test,
## because an ant count in a screenshot cannot tell a flood that stopped at the
## stroke from one that took it: the ants alternate light and dark and the
## counted threshold catches one phase over grey and neither over orange.
##
## **The two readings do not give one answer at every tolerance.** Compositing
## the layer over what lies behind it before measuring would read the merged
## picture at the seed. That picture holds the seed's own layer, so under a
## near-opaque dark seed every empty texel would be seen as the seed and a fill
## would take the whole layer. No backdrop is guessed. The merged picture is orange on grey, 0.41 apart,
## and the layer alone is orange on nothing, a whole alpha apart, so the layer
## alone keeps the band out at any tolerance under 100 percent, as a painter
## reading one layer's line art wants. Below 0.41 both readings stop at the band
## and produce the same mask, which the last case holds.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

## The stroke the drive painted, `#e8b23c`, and its seed, both the drive's own
## numbers. The seed is chunk (1, 3) and the band is chunk row 2, so the flood
## meets it from below.
const ORANGE := Color(0.91, 0.70, 0.24, 1.0)
const SEED := Vector2i(500, 916)
## The band's own chunk, and a texel in the middle of it.
const IN_THE_BAND := Vector2i(3, 2)


## The drive's canvas, its Background the opaque mid grey a default document
## gets, and a paint layer holding a band of orange across the middle. A band of
## chunks rather than a brush stroke, because a stroke's soft edge is a second
## variable and the barrier is what this measures. Chunks 1 to 5 rather than all
## eight, so the flood can go round the ends exactly as it did round the drive's
## stroke.
func _picture() -> Array:
    var easel := SaEasel.create_default(Vector2i(1920, 1080))
    var document := easel.document
    var layer := document.active_layer
    for cx in range(1, 6):
        layer.get_or_create_chunk(Vector2i(cx, 2)).clear(ORANGE)
    easel.request_full_composite()
    easel.process_pending_composite()
    return [easel, document]


func _flood(document: SaDocument, easel: SaEasel, tolerance: float, merged: bool) -> int:
    document.selection.deselect()
    var wand := SaWand.new()
    var colour: SaTexture = easel.output if merged else null
    return wand.flood(document, SEED, tolerance, SaSelection.Mode.REPLACE, colour, document.active_layer)


## Whether the flood took the band itself. A texel rather than a chunk: the band does not span the
## canvas, so the flood reaches its chunks from above and below whatever the
## tolerance is, and a chunk in the region says nothing about the band in it.
func _crossed(document: SaDocument) -> bool:
    var chunk: SaChunk = document.selection.chunks.get(IN_THE_BAND, null)
    if chunk == null:
        return false
    return _texel(chunk.field(SaSelection.FIELD), 128, 128).r >= 0.5


func _texel(texture: SaTexture, x: int, y: int) -> Color:
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, y * texture.size.x + x)


## The merged picture is the drive's: orange on the grey Background, 0.41 apart
## in the largest channel. A tolerance under that stops at the band and one over
## it crosses.
func test_on_the_merged_picture_the_tolerance_decides_where_the_flood_stops() -> void:
    var built := _picture()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    for tolerance: float in [0.02, 0.2]:
        _flood(document, easel, tolerance, true)
        assert_false(_crossed(document), "At %d%% the merged flood stops at the band" % int(tolerance * 100.0))
    for tolerance: float in [0.5, 0.99]:
        _flood(document, easel, tolerance, true)
        assert_true(_crossed(document), "and at %d%% it crosses" % int(tolerance * 100.0))
    easel.free()


## The layer alone holds the band on nothing, so the band is a whole alpha from
## the seed and only 100 percent crosses it. Compositing it over the
## merged picture would cross at 50 percent, the merged reading's answer.
func test_on_the_layer_alone_the_band_is_a_whole_alpha_from_nothing() -> void:
    var built := _picture()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    for tolerance: float in [0.02, 0.2, 0.5, 0.99]:
        _flood(document, easel, tolerance, false)
        assert_false(_crossed(document), "At %d%% the layer's flood stops at the band" % int(tolerance * 100.0))
    _flood(document, easel, 1.0, false)
    assert_true(_crossed(document), "and at 100% it crosses")
    easel.free()


## Under both distances the two readings produce the same mask, texel for
## texel: the flood takes everything but the band either way.
func test_under_both_distances_the_two_readings_produce_the_same_mask() -> void:
    var built := _picture()
    var easel: SaEasel = built[0]
    var document: SaDocument = built[1]

    _flood(document, easel, 0.3, false)
    var alone := _mask_rows(document)
    _flood(document, easel, 0.3, true)
    var together := _mask_rows(document)

    assert_eq(alone.size(), together.size(), "The same chunks are in the region")
    assert_eq(alone, together, "and every one of them holds the same coverage")
    easel.free()


## A row of samples across every chunk the selection holds, keyed by chunk, so a
## mismatch names the chunk rather than a texel index.
func _mask_rows(document: SaDocument) -> Dictionary:
    var out: Dictionary = {}
    for grid_pos: Vector2i in document.selection.chunks:
        var field := (document.selection.chunks[grid_pos] as SaChunk).field(SaSelection.FIELD)
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(field.rid, 0)
        var row: Array[bool] = []
        for i in 16:
            var at := i * 16
            row.append(SaFieldSpec.decode_texel(bytes, field.format, at * field.size.x + at).r >= 0.5)
        out[grid_pos] = row
    return out
