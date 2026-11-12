## Carrying the selection with the pixels a transform commits.
##
## In the transform's `selection` folder beside Select > Transform Selection,
## which runs the same carry with no pixels under it, because both are the
## selection's half of a transform and the folder above is at the 2500 lines a
## package is read whole by. The module's own files reach each other by
## `class_name`.
##
## A sibling of [SaTransform] rather than more of it, because what is here
## is only the mask half: the pixel half, the lift, the preview and the history
## step, all stay there and none of it is duplicated. The two share the kernels
## by name, `crop`'s `shift` and `transform`'s `resample`, not by object. The
## mask's three are an object of their own, [Kernels], which the pass keeps for
## its life beside its picture kernels, because they run at the mask's `r32f`
## and the picture's at the document's depth: one object switched between the
## two would rebuild its pipelines on every switch.
##
## **Why the selection moves at all.** A commit that moved the pixels and left
## the marching ants where they were would send a painter who committed and
## dragged again to pick up empty canvas. Photoshop and Krita both carry the selection,
## and Sara carries it, because the box the transform tool draws *is* the
## selection's bounds while a selection is active, and a box that stops
## describing what it is a box around is the worse of the two failures.
##
## **The mask is resampled, not moved.** Reading the bounds and offsetting it
## would be right for a plain translate and a lie for everything else: a rotated
## rectangle's bounds is a larger rectangle, and a feathered edge that moved as a
## block would harden at one corner. This runs the same `resample` kernel over
## the same inverse map the pixels went through, so a feathered, rotated or
## sheared selection lands as the same shape the picture did.
##
## **The carry is undoable.** It leaves a [SaSelection.Swap] on the same history step as the
## pixels, one step for both, because an undo that put the pixels back and left the mask where
## the commit moved it would leave the box the tool draws describing nothing it is a box
## around, and a painter who undid and dragged again would lift empty canvas. Every other
## selection change a painter makes is a step of its own through `SaSelection.change`, the
## tools and the Select menu wrapping the edit, so the carry is no exception.
class_name SaTransformSelection

## Grid edge, in document pixels. Read from the layer rather than assumed, the
## way hard rule 3 (sparse chunks) asks.
const EDGE := SaChunk.SIZE


## The carry, plus what the history step needs to undo it: a [SaSelection.Swap]
## holding the mask the carry replaced, or null when nothing moved.
##
## The old chunks are read here rather than in [SaTransform] because the mask is
## this file's half of the commit, and because that file is at the 700 lines the
## brief's rule names. Nothing is copied: the carry builds a new dictionary, so
## the one held here is the one that would otherwise be let go of.
##
## *kernels* is the pass's own [Kernels], so a commit builds no compute.
static func carry_and_hold(
    selection: SaSelection,
    homography: PackedFloat32Array,
    matrix: Transform2D,
    bounds: Rect2i,
    landed: Rect2i,
    filter: int,
    kernels: Kernels = null
) -> SaSelection.Swap:
    if selection == null or not selection.active:
        return null
    var was_chunks: Dictionary = selection.chunks
    var was_bounds: Rect2i = selection.bounds
    if not carry(selection, homography, matrix, bounds, landed, filter, kernels):
        return null
    return SaSelection.Swap.new(selection, was_chunks, was_bounds)


## Moves the outline of *selection* by *by* whole pixels and leaves the picture
## where it is, the marquee's drag inside a selection. True when it moved.
##
## Through [method carry] with a translate, so the mask is carried by the
## kernels and never read back, and only the chunks the moved bounds reach are
## written. A whole-pixel offset puts every texel exactly on another rather than
## between two, and the nearest filter makes that certain, so a feathered edge
## arrives as it left. Nothing is recorded here, unlike [method carry_and_hold]:
## the caller wraps this in `SaSelection.change`, whose step holds the chunks
## the carry replaced, because the carry lands on fresh chunks and never writes
## into the old ones.
static func translate(selection: SaSelection, by: Vector2i, kernels: Kernels = null) -> bool:
    if selection == null or not selection.active or by == Vector2i.ZERO:
        return false
    var bounds := selection.bounds
    var landed := Rect2i(bounds.position + by, bounds.size)
    var matrix := Transform2D(0.0, Vector2(by))
    return carry(selection, PackedFloat32Array(), matrix, bounds, landed, SaResampleKernel.Filter.NEAREST, kernels)


## Puts *selection* through the map, reading it over *bounds* and landing it on
## *landed*. True when the selection moved.
##
## *homography* is the perspective map when a gesture has one and empty
## otherwise, and *matrix* is the affine map every other gesture drives, which
## is the pair `SaHomography.kernel_rows` takes and the pair the picture's own
## resample is handed. The two are passed rather than one, because a homography
## is what a `Transform2D` cannot hold and its affine part is a reading rather
## than the truth.
##
## *filter* is [SaResampleKernel.Filter], so the mask reads between texels exactly
## the way the picture did and a pixel-art transform leaves a hard-edged selection.
##
## *kernels* are the three computes the carry runs. A caller that holds none, a
## suite asking one question, gets three made for this call alone.
static func carry(
    selection: SaSelection,
    homography: PackedFloat32Array,
    matrix: Transform2D,
    bounds: Rect2i,
    landed: Rect2i,
    filter: int,
    kernels: Kernels = null
) -> bool:
    if selection == null or not selection.active:
        return false
    if bounds.size.x <= 0 or bounds.size.y <= 0 or landed.size.x <= 0 or landed.size.y <= 0:
        return false
    # The identity short circuit is the affine one only. A perspective map whose
    # affine part reads as identity still moves the picture, which is the whole
    # reason the affine part is not the map.
    if homography.size() != 9 and matrix.is_equal_approx(Transform2D.IDENTITY):
        return false
    var held := kernels if kernels != null else Kernels.new()
    if not held.prepare():
        return false
    var stitched := stitch(selection.chunks, bounds, 0.0, held)
    if stitched == null:
        return false
    # The landed walk is not an [SaChunkWalk] for the reason `SaResample` gives
    # about its own: every stop dispatches through `SaResampleKernel`, which
    # owns that kernel's extent along with its twenty floats. The grid maths is
    # the walk's.
    var landed_chunks: Dictionary = {}
    for grid_pos: Vector2i in SaChunkWalk.positions_in(landed):
        var local := SaChunkWalk.local_rect(grid_pos, landed, EDGE)
        if local.size.x <= 0 or local.size.y <= 0:
            continue
        var chunk := selection.make_chunk(0.0)
        _resample_into(
            held.resample, chunk.field(SaSelection.FIELD), stitched, homography, matrix, bounds, grid_pos, local, filter
        )
        landed_chunks[grid_pos] = chunk

    if landed_chunks.is_empty():
        return false
    selection.chunks = landed_chunks
    selection.bounds = landed
    selection.changed.emit()
    return true


## One texture the size of *bounds*, holding over it the coverage *chunks*, a
## grid position to [SaChunk] store of the one mask field, carries. A position
## the store holds nothing at reads *rest*, which the texture opens at.
##
## The same walk `SaTransform._stitch` does for the picture, over one field
## rather than every colour field, because a mask has exactly one. Public and
## handed a store rather than a selection because a group's mask is carried
## through it too: the two coverages are the same single channel at the
## same format, and one stitch keeps them reading the same way.
static func stitch(chunks: Dictionary, bounds: Rect2i, rest: float, kernels: Kernels) -> SaTexture:
    var shift := kernels.shift
    var into := SaTexture.new(bounds.size, SaSelection.FORMAT)
    # Through the kernel rather than a transfer clear, for the reason
    # SaTransform gives about its own stitch: this is fresh memory and a
    # transfer clear is not ordered against the shifts that follow it.
    _blank(kernels.blank, into, Rect2i(Vector2i.ZERO, bounds.size), rest)
    var wrote := false
    for grid_pos: Vector2i in chunks:
        var origin: Vector2i = grid_pos * EDGE
        var taken := Rect2i(origin, Vector2i(EDGE, EDGE)).intersection(bounds)
        if taken.size.x <= 0 or taken.size.y <= 0:
            continue
        var chunk: SaChunk = chunks[grid_pos]
        if chunk == null:
            continue
        var from := chunk.field(SaFieldSpec.MASK)
        if from == null or not from.rid.is_valid():
            continue
        shift.use_storage_format(into.format)
        shift.set_texture(0, from.rid)
        shift.set_texture(1, into.rid)
        var to := taken.position - bounds.position
        var at := taken.position - origin
        shift.set_push_constant_float_array(PackedFloat32Array([to.x, to.y, at.x, at.y, taken.size.x, taken.size.y, 0.0, 0.0]))
        shift.dispatch_kernel("shift", SaCompute.groups_for(taken.size.x), SaCompute.groups_for(taken.size.y), 1)
        wrote = true
    return into if wrote else null


## One resample dispatch, through the one writer of the `resample` kernel's push
## constant. The mask goes through the same door the picture did, so the two
## cannot disagree about the map.
##
## **The map handed over is whichever one the gesture is driving**. It was affine
## and only ever affine until the perspective mode arrived, and the mask then
## stayed on the box the lift covered while the picture landed on a quad, which
## is the same bug in the one mode the carry had not known about. `kernel_rows`
## answers a third row of (0, 0, 1) for an affine map, so nothing about the
## affine path changed.
static func _resample_into(
    compute: SaCompute,
    target: SaTexture,
    source: SaTexture,
    homography: PackedFloat32Array,
    matrix: Transform2D,
    bounds: Rect2i,
    grid_pos: Vector2i,
    local: Rect2i,
    filter: int
) -> void:
    SaResampleKernel.dispatch(
        compute,
        target,
        source,
        SaHomography.kernel_rows(homography, matrix, Vector2(bounds.position)),
        Vector2(grid_pos * EDGE),
        local,
        filter == SaResampleKernel.Filter.NEAREST
    )


## *local* of *target* set to *value* everywhere, the `blank` kernel rather
## than `clear`'s, which writes zero and nothing else: a mask whose rest is one
## opens its stitch at one.
static func _blank(compute: SaCompute, target: SaTexture, local: Rect2i, value: float) -> void:
    if target == null or not target.rid.is_valid() or local.size.x <= 0 or local.size.y <= 0:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, target.rid)
    compute.set_push_constant_float_array(
        PackedFloat32Array([value, value, value, value, local.position.x, local.position.y, local.size.x, local.size.y])
    )
    compute.dispatch_kernel("blank_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## The three kernels a carry runs, made once at the mask's format and kept.
##
## Kept rather than made at the commit, because a kernel built at the document's
## depth is rebuilt at once at the mask's `r32f`, so a commit that made all
## three afresh would ask the device for six sets of pipelines and the first of
## a session would wait on the first load of the `r32f` variants, in the frame
## the painter is watching. [SaTransform] holds one of these for its life and
## asks for it at the lift, while a painter is only picking the piece up, so
## the commit finds all three ready.
##
## An inner class because it owns one thing, the three objects, and has no
## reader but this file and the pass that holds it.
class Kernels:
    extends RefCounted

    ## `crop`'s `shift`, which stitches the mask's chunks into one texture.
    var shift: SaCompute = null

    ## `transform`'s `resample`, which lands the mask through the map.
    var resample: SaCompute = null

    ## `blank`'s `blank_region`, which opens the stitch at the rest before it
    ## is written.
    var blank: SaCompute = null

    ## Makes the three at the mask's format, the first time. True when they are
    ## ready, false in a run with no device behind it.
    func prepare() -> bool:
        if shift != null:
            return true
        if GlobalShaderCompiler.get_rd() == null:
            return false
        shift = _at_mask_format("crop")
        resample = _at_mask_format("transform")
        blank = _at_mask_format("blank")
        return true

    static func _at_mask_format(shader_name: String) -> SaCompute:
        var compute := SaCompute.new(shader_name)
        compute.use_storage_format(SaSelection.FORMAT)
        return compute
