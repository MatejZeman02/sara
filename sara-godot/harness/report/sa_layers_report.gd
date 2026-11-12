## The `layers` step's answer: the stack in one verdict line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A notebook and a small model both need the stack's names and order, and until
## this the only place they were written was the state dump, whose Layers docker
## block sits among a hundred and fifty thousand characters. This reads the
## document rather than the docker, so the answer is the same with the docker
## closed, and prints the line the harness's contract names,
## `SaCapture: layers <json>`.
##
## One entry a layer, bottom first, the order `SaLayerOps.layers()` keeps and
## the index a client names a layer by: `i` its index from the bottom, 0 the
## lowest, `name`, `kind` (`group`, or the layer type's id, `plain` for an
## untyped layer because the two have the same schema and nothing branches on
## the difference), `visible`, `opacity`, `blend`, `active`, `group` (the name
## of the group it sits in, or null at the top level), `bounds`, the
## `[x, y, w, h]` the allocated chunks cover in document pixels, or null when
## none is allocated, `transformed`, whether a live transform draws it other
## than where it was painted, and `smart`, whether it is a smart layer, one
## that carries a live transform, which a reset leaves smart
## and not transformed, `open`, whether its contents are open untransformed,
## and `source`, the names of the layers sharing its source, itself among
## them, or none for a layer whose paint is its own, and `link`, the file a
## linked layer reads, whether a save writes it relative, its state and why it
## is broken, left out for a layer with no file behind it so a long stack's
## line stays short, and `alpha`, the largest alpha the layer stores, or null
## for a group and a layer with no paint.
##
## **The largest alpha is how a script finds paint above one.** Hard rule 5
## keeps alpha unclamped, so a layer can hold coverage above one that the screen
## shows as an ordinary dark silhouette, and paint laid over it lifts that
## black as it lifts any pixel. It is [SaReduce]'s maximum over the layer's
## chunks, reduced on the card with one record read back a layer, the
## allowance hard rule 1 gives the `reduce` step, and four places are enough to
## tell 1.0001 from one. One reduction a layer is felt in a stack of
## hundreds: a file of 729 layers lists in 0.6 s with it and 0.21 s
## without, so `{"layers": {"alpha": false}}` and the glance leave it out and
## the reductions share one [SaCompute], whose pipelines are built once.
##
## **Bounds are the chunk grid, never the painted texels**, for the reason
## `SaResample._painted_bounds` gives: a tight box is a readback of every chunk,
## which hard rule 1 forbids for a step a model may take between two strokes. A
## chunk's footprint in the document is `SaChunk.SIZE` whatever its texture's
## `pixel_size()`, because a chunk stored at another resolution still covers the
## same grid cell, so the edge is the grid's and not the texture's.
##
## Short keys, and opacity to three places, so a ten-layer document stays under
## twenty-two hundred characters, which the suite measures.
extends RefCounted


## The verdict line for *document*'s stack, or a refusal when there is none.
## *alpha* false leaves each layer's largest alpha out.
static func capture(document: SaDocument, alpha: bool = true) -> String:
    if document == null:
        return "SaCapture: layers refused, no document"
    return "SaCapture: layers %s" % JSON.stringify(stack(document, alpha))


## The stack as the line carries it, one dictionary a layer, bottom first.
static func stack(document: SaDocument, alpha: bool = true) -> Array:
    var out: Array = []
    var layers := SaLayerOps.new(document).layers()
    var compute := SaCompute.new(SaReduce.SHADER) if alpha else null
    for index in layers.size():
        out.append(_entry(document, layers[index], index, compute))
    return out


static func _entry(document: SaDocument, layer: SaLayer, index: int, compute: SaCompute) -> Dictionary:
    var entry := {
        "i": index,
        "name": layer.shown_name(),
        "kind": _kind(layer),
        "visible": layer.visible,
        "opacity": snappedf(layer.opacity, 0.001),
        "blend": String(layer.blend_mode),
        "active": layer == document.active_layer,
        "group": _group_name(layer),
        "bounds": _bounds(layer),
        "transformed": _transformed(layer),
        "smart": SaLiveTransform.of(layer) != null,
        "open": SaLocalView.untransformed(layer),
        "source": SaSharedSource.names_sharing(layer),
    }
    if compute != null:
        entry["alpha"] = _most_alpha(layer, compute)
    var link := SaLinkedFile.state_of(layer)
    if not link.is_empty():
        entry["link"] = link
    return entry


## Whether *layer* is drawn other than where it was painted: through a map
## other than the identity, or cropped.
static func _transformed(layer: SaLayer) -> bool:
    var live := SaLiveTransform.of(layer)
    return live != null and (not live.matrix.is_equal_approx(Basis.IDENTITY) or live.crop.any())


## The name of the group *layer* sits in, or null at the top level.
static func _group_name(layer: SaLayer) -> Variant:
    if layer.group == null:
        return null
    return layer.group.shown_name()


static func _kind(layer: SaLayer) -> String:
    if layer.is_group:
        return "group"
    return String(layer.layer_type) if layer.layer_type != &"" else "plain"


## The largest alpha *layer* stores, or null for a group or a layer that holds
## no paint, which has no alpha to report.
static func _most_alpha(layer: SaLayer, compute: SaCompute) -> Variant:
    if layer.is_group:
        return null
    var cells: Variant = _bounds(layer)
    if cells == null:
        return null
    var most: Variant = SaReduce.new(layer, compute).reduce(Rect2i(cells[0], cells[1], cells[2], cells[3]))["max"]
    if most == null:
        return null
    return snappedf(float(most[3]), 0.0001)


## The union of the grid cells the layer has a chunk in, as `[x, y, w, h]`.
static func _bounds(layer: SaLayer) -> Variant:
    var edge := SaChunk.SIZE
    var found := Rect2i()
    var first := true
    for grid_pos: Vector2i in layer.chunks:
        if layer.chunks[grid_pos] == null:
            continue
        var cell := Rect2i(grid_pos * edge, Vector2i(edge, edge))
        found = cell if first else found.merge(cell)
        first = false
    if first:
        return null
    return [found.position.x, found.position.y, found.size.x, found.size.y]
