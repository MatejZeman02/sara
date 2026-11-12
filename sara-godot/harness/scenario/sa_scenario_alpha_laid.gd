## The largest alpha a door stroke laid on its layer, read off the step the
## stroke wrote into the history, for the end of the stroke's line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why.** A painter who dabs nine presets at opacity 1.0 to close holes in
## a crown can find most laying two thirds of that or less, Sparse Specks
## nothing at all, while every answer reads healthy, and only a probe over each
## dab would tell. The answer now says how much
## alpha the stroke left where it changed the layer, and says it laid nothing
## when the layer is as it was.
##
## **Colour counts too.** A stroke over a layer already opaque under it would
## read "laid nothing" by alpha alone while the export shows it painted: a texel at alpha 1 takes a new colour
## and keeps its alpha. So a texel whose colour moved while its alpha did not
## is counted as recoloured, and only a stroke that moved no texel at all laid
## nothing. A texel left at alpha 0 has no colour a painter
## sees, so its colour moving is not counted.
##
## **Read off the history, not the stroke.** A brush's commit records the part
## of each chunk the stroke touched as it stood before, which is exactly the
## region and the old texels a reading needs. So the step is compared with the
## same region of the layer now, texel by texel, and nothing is read back while
## the stroke is painting (hard rule 1): the stroke has been committed when its
## step stands in the history.
##
## A stroke on a mask records the mask's step, and a layer whose colour is
## derived keeps no albedo in its snapshot, so neither gets a clause rather
## than one read off the wrong field.
##
## Reached by path from the stroke rather than by class name, so no editor
## rescan stands between a fresh checkout and a step.
class_name SaScenarioAlphaLaid
extends RefCounted

## How far a texel's alpha or a channel of its colour has to move to count as
## changed, under the eighth bit, so the rounding of a half float store is not
## read as paint.
const CHANGED := 0.001

## How many frames a stroke's report waits for its commit, as the brush walks
## what is left of a long fast stroke over the frames after the lift. A
## stroke that changed nothing records no step, and is read as that after them.
const WAIT_FRAMES := 120


## What the stroke about to be pressed on *document* is read against: the
## history's position, the layer it paints and whether a mask is its target,
## as numbers, because a verdict is spliced as a step.
static func before(document: SaDocument) -> Dictionary:
    if document == null or document.history == null or document.active_layer == null:
        return {}
    return {
        "serial": document.history.position(),
        "layer": document.active_layer.get_instance_id(),
        "mask": document.mask_target != null,
    }


## Whether the stroke *held* was taken against is still being laid on
## *document*: no step of its own yet, and a stroke buffer or a snapshot still
## open, so its report waits a frame.
static func pending(document: SaDocument, held: Dictionary) -> bool:
    if document == null or held.is_empty() or document.history == null:
        return false
    if document.history.position() != int(held["serial"]):
        return false
    var buffered := document.stroke_layer != null and not document.stroke_layer.chunks.is_empty()
    var open := document.stroke_transaction != null and not document.stroke_transaction.before_chunks.is_empty()
    return buffered or open


## The clause for what the stroke taken against *held* left on its layer of
## *document*, or nothing when there is nothing to read it against.
static func after(document: SaDocument, held: Dictionary) -> String:
    if document == null or held.is_empty() or bool(held["mask"]) or document.history == null:
        return ""
    var layer := instance_from_id(int(held["layer"])) as SaLayer
    if layer == null:
        return ""
    if document.history.position() == int(held["serial"]):
        return clause(0.0, 0, 0, 0)
    var states: Array = document.history.holdings().back() if document.history.step_count() > 0 else []
    var largest := 0.0
    var raised := 0
    var lowered := 0
    var recoloured := 0
    for state: Variant in states:
        if not state is Dictionary:
            continue
        for grid_pos: Variant in state.keys().filter(func(key: Variant) -> bool: return key is Vector2i):
            var read := _changed_in(layer, grid_pos as Vector2i, state[grid_pos])
            if read.is_empty():
                return ""
            largest = maxf(largest, float(read[0]))
            raised += int(read[1])
            lowered += int(read[2])
            recoloured += int(read[3])
    return clause(largest, raised, lowered, recoloured)


## The words for a stroke whose texels rose to *largest* at most over
## *raised* of them, fell over *lowered* and kept their alpha under a new
## colour over *recoloured*.
static func clause(largest: float, raised: int, lowered: int, recoloured: int = 0) -> String:
    if raised == 0 and lowered == 0 and recoloured == 0:
        return ", laid nothing on the layer"
    var said := ""
    if raised > 0:
        said = ", largest alpha laid %.2f over %d texel%s" % [largest, raised, "" if raised == 1 else "s"]
    if lowered > 0:
        said += ", lowered the alpha of %d texel%s" % [lowered, "" if lowered == 1 else "s"]
    if recoloured > 0:
        said += ", recoloured %d texel%s" % [recoloured, "" if recoloured == 1 else "s"]
    return said


## The largest alpha of the texels that rose in *layer*'s chunk at *grid_pos*
## against *stored*, the step's snapshot of it, with how many rose, how many
## fell and how many kept their alpha under a new colour, or empty when the chunk cannot be read as albedo. A brush keeps the
## part of the chunk it touched as a delta, and a fill the whole chunk.
static func _changed_in(layer: SaLayer, grid_pos: Vector2i, stored: Variant) -> Array:
    var chunk: SaChunk = layer.chunks.get(grid_pos, null)
    var was: SaTexture = null
    var rect := Rect2i()
    if stored is SaChunkDelta:
        var delta: SaChunkDelta = stored
        was = delta.fields.get(SaFieldSpec.ALBEDO, null)
        rect = delta.rect
        if was == null:
            return []
    elif stored is SaChunk:
        was = (stored as SaChunk).field(SaFieldSpec.ALBEDO)
        if was == null:
            return []
    elif stored != null:
        return []
    if chunk == null:
        return [0.0, 0, 0, 0]
    if rect.size == Vector2i.ZERO:
        rect = Rect2i(Vector2i.ZERO, Vector2i(chunk.pixel_size(), chunk.pixel_size()))
    var now := SaChunkDelta.capture(chunk, rect)
    var is_now: SaTexture = now.fields.get(SaFieldSpec.ALBEDO, null) if now != null else null
    if is_now == null:
        return []
    var after_texels := _channels(is_now)
    var before_texels := _channels(was) if was != null else PackedFloat32Array()
    if after_texels.is_empty() or (was != null and before_texels.size() != after_texels.size()):
        return []
    var largest := 0.0
    var raised := 0
    var lowered := 0
    var recoloured := 0
    for index in after_texels.size() >> 2:
        var at := index * 4
        var then_alpha := before_texels[at + 3] if was != null else 0.0
        var now_alpha := after_texels[at + 3]
        if now_alpha > then_alpha + CHANGED:
            raised += 1
            largest = maxf(largest, now_alpha)
        elif now_alpha < then_alpha - CHANGED:
            lowered += 1
        elif was != null and now_alpha > CHANGED and _colour_moved(before_texels, after_texels, at):
            recoloured += 1
    return [largest, raised, lowered, recoloured]


## Whether any of the three colour channels of the texel starting at *at*
## moved past `CHANGED` between *then* and *now*.
static func _colour_moved(then: PackedFloat32Array, now: PackedFloat32Array, at: int) -> bool:
    for channel in 3:
        if absf(now[at + channel] - then[at + channel]) > CHANGED:
            return true
    return false


## The four channels of every texel of *texture* in a row, read back once, or
## nothing for a format that is not four channels of float.
static func _channels(texture: SaTexture) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    var width: int = SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 0)
    var four := (
        texture.format == RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
        or texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    )
    if not four or not texture.rid.is_valid():
        return out
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    var count := floori(bytes.size() / float(width)) * 4
    out.resize(count)
    var half := texture.format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    var step := width >> 2
    for index in count:
        var at := index * step
        out[index] = bytes.decode_half(at) if half else bytes.decode_float(at)
    return out
