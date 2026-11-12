## What a group shows, held as the chunks of a layer outside the document, for
## a flood that finds its region on a group named as the fill's reference.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A group holds no paint of its own, so the wand, which reads a layer's chunks,
## found nothing in one and took the whole canvas. Here every position the
## group's members draw on, as `SaNodeInput`, the door for a node's input,
## counts them, and its filters' halo around them, is drawn by
## `SaTreeRender.render_node` with the compositor's own steps: the members over
## transparent, then the group's filters, its mask, its mode and its opacity.
## So what the flood reads is what the group shows and not what its members
## hold. `SaNodeInput` itself leaves the group's filters and mask out, which is
## why the drawing is the tree render's and only the positions are the door's.
##
## The picture is chunks rather than one texture the size of the canvas,
## because the wand reads a layer's chunks already and a chunk it does not hold
## reads transparent, so nothing is cleared or dispatched where the group draws
## nothing (hard rule 2), and a canvas texture would double the easel's memory
## at the click. Nothing is read back: every chunk is drawn and read in VRAM.
## Each chunk's albedo is blanked by the compositor's kernel and not by a
## transfer, which a compute pass is not ordered against.
##
## The layer is a node and never enters the tree, so the caller frees it once
## the flood has read it, and its chunks' textures go with it.
extends RefCounted


## A layer outside *document* holding what *group* shows, one chunk at each
## position it draws on, or one with no chunks when it draws nothing. A hidden
## group shows nothing, so it answers one with no chunks too.
static func shown(document: SaDocument, group: SaLayer) -> SaLayer:
    var picture := SaLayer.new()
    picture.schema = SaFieldSpec.schema_for_space(document.color_space)
    var compositor := document.compositor
    if compositor == null or not group.visible:
        return picture
    var render := SaTreeRender.new(document)
    var drawn: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in SaNodeInput.new(document, group).positions():
        drawn[grid_pos] = true
    for grid_pos: Vector2i in render.reach(group, drawn):
        var chunk := SaChunk.create(picture.schema)
        var albedo := chunk.albedo()
        compositor.clear_scratch_batch([[albedo, Rect2i(Vector2i.ZERO, albedo.size)]])
        render.render_node(albedo, group, grid_pos)
        picture.set_chunk(grid_pos, chunk)
    return picture
