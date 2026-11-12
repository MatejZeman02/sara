## The `.sad` reader's refusal of a layer below the document's resolution.
##
## **Why refused.** A file may record any `resolution_scale`, and the reader
## could take anything from 0.5 to 2.0, but nothing in Sara draws or paints a chunk
## coarser than the document. The paint context, the stamp's and the noise
## brush's dab kernels and the compositor's density all floor a chunk's scale
## at 1.0, so a layer at 0.5 would show its 128 texels as 128 document pixels,
## a quarter of its chunk, and a stroke on it would land at twice its place.
## Until all of them take a scale below one, the reader opens such a layer at
## 1.0 and says so.
##
## **Where the picture goes.** A chunk the file stored coarser is widened into
## a chunk at 1.0, each stored texel repeated over the document pixels it
## covered, so the picture stays where the file put it and nothing is lost.
class_name SaSadCoarseLayer
extends RefCounted

## The lowest scale the reader opens a layer or a chunk at.
const LOWEST_SCALE := 1.0

## The highest, the double resolution a layer may hold.
const HIGHEST_SCALE := 2.0


## The scale a layer the file names *layer_name* opens at when the file asks
## for *asked*, with a warning when that is not what it asked for below.
static func opened_scale(layer_name: String, asked: float) -> float:
    if asked < LOWEST_SCALE:
        push_warning(refusal(layer_name, asked))
    return clampf(asked, LOWEST_SCALE, HIGHEST_SCALE)


## What the reader says when it refuses *asked* on the layer *layer_name*.
static func refusal(layer_name: String, asked: float) -> String:
    var asks := "SaExport.load_sad: '%s' asks for a resolution scale of %s, below the document's," % [layer_name, str(asked)]
    return asks + " which nothing paints yet, so it opens at 1.0"


## The scale a chunk the file stored at *stored* is made at.
static func chunk_scale(stored: float) -> float:
    return maxf(stored, LOWEST_SCALE)


## *raw*, one field of a chunk stored at *stored*, as the bytes of the chunk
## `chunk_scale` makes: itself at 1.0 and above, and below that each texel
## repeated over the texels at 1.0 whose document pixels it covered. Bytes
## that are not a whole square of texels come back as they are, and the
## texture update refuses them as it would have.
static func widened(raw: PackedByteArray, stored: float) -> PackedByteArray:
    if stored >= LOWEST_SCALE:
        return raw
    var from_side := maxi(1, roundi(float(SaChunk.SIZE) * stored))
    var texel := floori(float(raw.size()) / (from_side * from_side))
    if texel <= 0 or texel * from_side * from_side != raw.size():
        return raw
    var to_side := SaChunk.SIZE
    var out := PackedByteArray()
    var row := PackedByteArray()
    row.resize(to_side * texel)
    var built_from := -1
    for y in to_side:
        var from_y := floori(float(y * from_side) / to_side)
        if from_y != built_from:
            built_from = from_y
            for x in to_side:
                var at := (from_y * from_side + floori(float(x * from_side) / to_side)) * texel
                for b in texel:
                    row[x * texel + b] = raw[at + b]
        out.append_array(row)
    return out
