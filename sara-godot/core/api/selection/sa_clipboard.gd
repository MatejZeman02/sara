## What Cut and Copy hold and Paste puts down: chunks copied on the GPU through
## the selection, together with the colour space they were painted in.
##
## Everything stays in VRAM. A copy is one masked kernel per colour field of
## each chunk the selection reaches, never a readback, which is hard rule 1. The
## clipboard carries the source document's colour space because a paste into a
## document that stores its colours differently has to convert, or the pixels
## land wearing the wrong meaning. Depth is not converted, the same way the
## conversion pass never changes it: a paste across depths is refused and says so.
##
## Held by `SaDocuments`, one for every open document, so Copy in one painting
## and Paste in another works and a copy outlives its document being closed.
## Not a static, because the owner is let go of while the rendering device is
## still alive, and a static holding textures would be freed at shutdown
## against a device already gone.
##
## **Copy puts no picture on the desktop clipboard.** A picture there would be
## the canvas read back at Copy, which rule 1 does not allow, so Copy says it
## holds the pixels inside Sara. A Paste that finds this clipboard empty reads
## the desktop's through `SaDesktopPicture`.
##
## **A copy leaves a mark on the desktop clipboard instead**, a line of text
## of its own, [method mark_desktop], which reads no pixel back. A Paste reads
## it again, [method desktop_changed], and a desktop clipboard that holds
## something else was given something newer than Sara's copy, a picture from a
## browser say, which is then what the painter means to paste. The mark is a
## text rather than a list of the types and a hash of what the desktop held at
## the copy, because reading those means starting a clipboard program and
## reading a whole picture at every Copy, where the text costs one call to the
## engine at Copy and one at Paste.
class_name SaClipboard
extends RefCounted

## The text a copy puts on the desktop clipboard, with the process and the
## number of the copy, so a copy in another Sara is a change here. It says what
## it is, since a painter who pastes into a text field sees it, and it opens
## on a small letter, so the template does not take it for a label Sara shows.
const MARK := "sara copy %d.%d, pixels copied in Sara, which paste in Sara only"

## The binding the copy kernel writes to. The source is 0 and the mask is
## SaSelection.BINDING, as in every kernel that honours the selection.
const DESTINATION_BINDING: int = 2

## Grid position -> SaChunk, a masked copy of what was there.
var chunks: Dictionary[Vector2i, SaChunk] = {}

## The schema the copied chunks were made with.
var schema: Array[SaFieldSpec] = []

## What the copied colours mean, so a paste elsewhere can convert them.
var space: SaColorSpace = null

## The rectangle the copy covers, in document pixels of the source.
var bounds: Rect2i = Rect2i()

## The canvas size of the document the copy was taken from. A paste into a
## canvas of that size shares the copy's coordinates and lands in place, and
## any other centres the copy, `offset_in`.
var _from_size: Vector2i = Vector2i.ZERO

## The rectangle Copy read, in document pixels of the source, which Cut clears.
## The selection's bounds when there is one, and otherwise the canvas together
## with every chunk of the layer, so paint past the canvas edge comes too.
## `bounds` stays the canvas then, because a paste places the copy by the frame
## it was taken in, and a paste into a canvas of that size lands in place.
var _taken: Rect2i = Rect2i()

## Whether the copy lands at its own coordinates whatever the canvas, which
## Layer via Copy and Layer via Cut ask for, since that copy never leaves its
## document. Given by `to_new_layer` to the clipboard it makes for the press,
## and kept through `clear`, since it belongs to the clipboard and not the copy.
var _in_place: bool = false

## What Copy holds when several layers are picked, every one a layer of its
## own, `SaClipboardLayers`. Empty while the chunks above hold a single copy,
## and the other way round, since the latest copy is the one a paste puts down.
var layers := SaClipboardLayers.new()

## What the desktop clipboard reads for this clipboard's marks, a
## `DesktopClipboard` in everything but a suite, which gives one of its own so
## no run takes what the person running it copied.
## Test seam. A suite that replaces it puts a `DesktopClipboard.new()` back.
static var desktop: DesktopClipboard = DesktopClipboard.new()

## How many marks this run has made, so each copy's text is its own.
static var _marks: int = 0

## The text the latest copy put on the desktop clipboard, or empty while there
## is none: nothing was marked, or the desktop clipboard could not be read back,
## a headless run or a platform with none, where Paste keeps Sara's copy first.
var _desktop_mark: String = ""

var _copy_compute: SaCompute = null
var _cut_compute: SaCompute = null
var _seamless_compute: SaCompute = null
var _height_compute: SaCompute = null
var _lift_compute: SaCompute = null
var _blank_compute: SaCompute = null


## *from_size* is the canvas the copy comes from, for a clipboard filled by
## hand rather than by `copy`, as a layer dropped on another tab's is.
## *in_place* keeps the copy at its own coordinates in any canvas.
func _init(from_size: Vector2i = Vector2i.ZERO, in_place: bool = false) -> void:
    _from_size = from_size
    _in_place = in_place


func is_empty() -> bool:
    return chunks.is_empty()


## Whether a Paste has anything of Sara's to put down, one copy or several
## layers.
func holds() -> bool:
    return not chunks.is_empty() or not layers.is_empty()


## Puts a text of this copy's own on the desktop clipboard, so a later Paste can
## tell whether the desktop was given something since. Cut, Copy and Copy
## Merged call it on the clipboard every document shares, and a clipboard made
## for one press, Layer via Copy's, never does, since nothing pastes from it.
## The mark stays unset when the desktop clipboard does not hand the text back.
func mark_desktop() -> void:
    _desktop_mark = ""
    if not holds() or not desktop.readable():
        return
    _marks += 1
    var mark := MARK % [OS.get_process_id(), _marks]
    desktop.write(mark)
    if desktop.text() == mark:
        _desktop_mark = mark


## Whether the desktop clipboard holds something other than the latest copy's
## mark, so the painter copied elsewhere after copying in Sara. False with no
## mark, which keeps Sara's copy first.
func desktop_changed() -> bool:
    return not _desktop_mark.is_empty() and desktop.text() != _desktop_mark


func clear() -> void:
    chunks.clear()
    layers.clear()
    schema = []
    space = null
    bounds = Rect2i()
    _taken = Rect2i()
    _from_size = Vector2i.ZERO
    _desktop_mark = ""


## Copies what the selection covers of *layer*, or the whole layer when there is
## no selection or Select All's stands, every chunk wherever it lies, and
## returns the number of chunks taken.
##
## *seamless* gives the colour the alpha Layer via Seamless Cut lifts,
## `seamless_copy_masked.gmacs`, which stacks over the hole a cut leaves back to
## the picture that stood there, rather than the selection's share of it.
func copy(document: SaDocument, layer: SaLayer, seamless: bool = false) -> int:
    clear()
    if document == null or layer == null:
        return 0
    var selection := document.selection
    space = document.color_space
    _from_size = document.canvas_size
    # The mask stays with the layer it hides. A pasted layer has no mask, so a
    # copied one would ride on every chunk unseen and unfreed.
    schema = []
    for spec: SaFieldSpec in layer.schema:
        if spec.id != SaFieldSpec.MASK:
            schema.append(spec)
    var masks := _masks(selection)
    bounds = selection.bounds if masks.active else Rect2i(Vector2i.ZERO, document.canvas_size)
    _taken = bounds
    if not masks.active and not layer.chunks.is_empty():
        _taken = bounds.merge(SaChunkWalk.reach_of(layer.chunks.keys()))

    for grid_pos: Vector2i in layer.chunks.keys():
        var mask := masks.texture_for(grid_pos)
        var local := SaChunkWalk.local_rect(grid_pos, _taken, (layer.chunks[grid_pos] as SaChunk).pixel_size())
        if mask == null or local.size.x <= 0 or local.size.y <= 0:
            continue
        var source: SaChunk = layer.chunks[grid_pos]
        var taken := SaChunk.create(schema, source.resolution_scale)
        taken.clear(Color(0.0, 0.0, 0.0, 0.0))
        for field_id: StringName in source.fields:
            if field_id == SaFieldSpec.MASK:
                continue
            var from: SaTexture = source.fields[field_id]
            var to: SaTexture = taken.field(field_id)
            if from != null and to == null and field_id == SaFieldSpec.HEIGHT:
                # A lazy field, which `create` leaves out, and a chunk that
                # holds it gives it to the copy.
                to = taken.add_sparse_field(SaFieldSpec.find(schema, field_id))
            if from == null or to == null:
                continue
            if layer.is_color_field(field_id) and seamless:
                _dispatch(_seamless(), "seamless_copy_masked", from, mask, local, to)
            elif layer.is_color_field(field_id):
                _dispatch(_copy(), "copy_masked", from, mask, local, to)
            elif field_id == SaFieldSpec.HEIGHT:
                # Masked on the thickness itself, `height_masked.gmacs`.
                _dispatch(_height(), "height_copy_masked", from, mask, local, to)
            else:
                # A concentration has no alpha to mask, so it comes whole. What
                # a partial copy of such a field should mean belongs to the
                # layer type that introduces it.
                var extent := Vector3(from.size.x, from.size.y, 1)
                GlobalShaderCompiler.get_rd().texture_copy(from.rid, to.rid, Vector3.ZERO, Vector3.ZERO, extent, 0, 0, 0, 0)
        chunks[grid_pos] = taken
    return chunks.size()


## Copies what the selection covers of the picture as the canvas shows it,
## every visible layer merged, or the whole picture when nothing is selected,
## and returns the number of chunks taken. Edit > Copy Merged.
##
## *merged* is the easel's output, one texture over the whole canvas at
## document resolution, and the caller composites what it holds first, the way
## Colour Range over the merged picture does. A clipboard holds chunks, so each
## chunk the selection reaches is lifted out of the output at its place by
## `copy_region` into a scratch, and the scratch goes through the selection by
## the masked kernel `copy` uses. Every step is a dispatch, so nothing is read
## back (rule 1), and the dispatch covers the selection's share of the chunk
## (rule 2). A copy holds the colour field alone: the output has no height and
## no mask to give it.
##
## The chunk is blanked by a kernel rather than a transfer clear, because the
## masked copy writes part of it next and a transfer is not ordered against
## compute.
func copy_merged(document: SaDocument, merged: SaTexture) -> int:
    clear()
    if document == null or merged == null:
        return 0
    var selection := document.selection
    space = document.color_space
    _from_size = document.canvas_size
    schema = SaFieldSpec.schema_for_space(space)
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    bounds = selection.bounds.intersection(canvas) if selection.active else canvas
    var scratch: SaTexture = null
    for grid_pos: Vector2i in SaLayer.grid_positions(document.canvas_size):
        var mask := selection.texture_for(grid_pos)
        if mask == null:
            continue
        var taken := SaChunk.create(schema)
        var side := taken.pixel_size()
        var local := SaChunkWalk.local_rect(grid_pos, bounds, side)
        var to := taken.field(SaFieldSpec.ALBEDO)
        if local.size.x <= 0 or local.size.y <= 0 or to == null:
            continue
        if scratch == null:
            scratch = SaTexture.new(Vector2i(side, side), merged.format)
        _blank(to, side)
        _lift(merged, grid_pos * side + local.position, scratch, local)
        _dispatch(_copy(), "copy_masked", scratch, mask, local, to)
        chunks[grid_pos] = taken
    return chunks.size()


## Copies *local* of the canvas-wide *merged*, starting at *origin* in it, to
## the same place in the chunk-sized *scratch*.
func _lift(merged: SaTexture, origin: Vector2i, scratch: SaTexture, local: Rect2i) -> void:
    if _lift_compute == null:
        _lift_compute = SaCompute.new("copy_region")
    _lift_compute.use_storage_format(merged.format)
    _lift_compute.set_texture(0, scratch.rid)
    _lift_compute.set_texture(1, merged.rid)
    _lift_compute.set_push_constant_float_array(
        PackedFloat32Array([origin.x, origin.y, local.position.x, local.position.y, local.size.x, local.size.y, 0.0, 0.0])
    )
    _lift_compute.dispatch_kernel("copy_region", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## Writes no paint over the whole of *target*, a chunk *side* texels across.
func _blank(target: SaTexture, side: int) -> void:
    if _blank_compute == null:
        _blank_compute = SaCompute.new("blank")
    _blank_compute.use_storage_format(target.format)
    _blank_compute.set_texture(0, target.rid)
    _blank_compute.set_push_constant_float_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, side, side]))
    _blank_compute.dispatch_kernel("blank_region", SaCompute.groups_for(side), SaCompute.groups_for(side), 1)


## Copies, then clears the selected pixels of *layer* as one history step, or
## all of its paint when nothing is selected or Select All's selection stands,
## past the canvas edge too. *seamless* is `copy`'s, and the hole is the same.
func cut(document: SaDocument, layer: SaLayer, seamless: bool = false) -> bool:
    if layer == null:
        return false
    if ("is_locked" in layer) and layer.is_locked:
        # Said rather than returned in silence, so a Ctrl+X on a locked layer
        # does not read as a key that never arrived.
        SaContext.refuse_paint(layer, tr("cut"))
        return false
    if copy(document, layer, seamless) == 0:
        return false

    var state: Dictionary[Vector2i, Variant] = {}
    var regions: Dictionary[Vector2i, Rect2i] = {}
    # The delta is captured as the walk asks for the chunk, which is the last
    # moment before the kernel clears what it records. A part of a tile, the way
    # a stroke is captured, so the step costs the rectangle rather than the
    # chunk.
    var chunk_at := func(grid_pos: Vector2i) -> SaChunk:
        if not chunks.has(grid_pos):
            return null
        var live: SaChunk = layer.chunks[grid_pos]
        var local := SaChunkWalk.local_rect(grid_pos, _taken, live.pixel_size())
        state[grid_pos] = SaChunkDelta.capture(live, local)
        regions[grid_pos] = local
        return live
    var push := func(_grid_pos: Vector2i, local: Rect2i, start: Vector2i) -> PackedFloat32Array:
        return PackedFloat32Array([start.x, start.y, local.end.x - start.x, local.end.y - start.y])
    var masks := _masks(document.selection)
    var walk := SaChunkWalk.new(_cut(), masks, layer)
    walk.run("cut_masked", _taken, chunk_at, push)
    # The walk cuts colour, and the height under the hole is thinned by the
    # same selection. Each chunk was captured above, height and all.
    for grid_pos: Vector2i in regions:
        var height := layer.get_field(grid_pos, SaFieldSpec.HEIGHT)
        if height != null:
            var mask := masks.texture_for(grid_pos)
            _dispatch(_height(), "height_cut_masked", height, mask, regions[grid_pos], null)

    document.record_pixel_step("Cut", layer, state)
    document.invalidate_chunk_regions(regions)
    document.modified = true
    document.document_changed.emit()
    return true


## Puts the clipboard down as a new layer above the active one, placed by
## *fit*, and returns it. Null when there is nothing to paste, or when the
## depths differ. *layer_name* is what the layer is called, numbered when a
## layer has it: Layer via Copy names it after its source and puts it down
## through here, so the two and Paste lay one layer one way.
##
## **Where it lands is Photoshop's rule.** `ACTUAL`, the default, keeps
## every texel of the copy at its own size: in place in a canvas the size of
## the one it was taken from, its own above all, and otherwise its bounds
## centred on the canvas, `offset_in`, with what hangs past the edges kept on the layer for the
## Move tool to bring into view, so a copy from a larger painting is never cut
## by the smaller canvas at its old coordinates. `INSIDE` and `STRETCH` scale
## the copy onto the canvas and `GROW` grows the canvas about its middle first,
## the choices `SaImportFitDialog` offers a picture larger than the canvas.
## `ORIGIN` reads as `ACTUAL`, since a copy's own place is its origin.
func paste(
    document: SaDocument, layer_name: String = "Pasted Layer", fit: SaImageImport.Fit = SaImageImport.Fit.ACTUAL
) -> SaLayer:
    if is_empty() or document == null:
        return null
    if space != null and space.depth != document.color_space.depth:
        SaProblems.refuse(
            "Clipboard",
            (
                tr("The clipboard has %s pixels and this document is %s, so they cannot be pasted here.")
                % [SaColorSpace.depth_name(space.depth), SaColorSpace.depth_name(document.color_space.depth)]
            )
        )
        return null
    if fit == SaImageImport.Fit.GROW:
        # The canvas grows and the copy lands in one step, so one Ctrl+Z takes
        # back what one Paste did.
        var put: Array[SaLayer] = []
        var work := func() -> void:
            SaImageImport.grow_to_hold(document, bounds.size)
            put.append(paste(document, layer_name, SaImageImport.Fit.ACTUAL))
        if document.history != null:
            document.history.as_one("Paste", work)
        else:
            work.call()
        return put[0] if not put.is_empty() else null
    var placed := _placed(document, fit)
    if placed.is_empty():
        return null

    # At the scale the copy was taken at, so a copy from a double resolution
    # layer pastes its own texels rather than a quarter of them.
    var layer := SaLayerOps.new(document).add(&"", null, scale(), "Paste")
    if layer == null:
        return null
    layer.name = _free_name(document, layer_name)
    # Height comes with the paint it was copied with. The new layer gains the
    # field inside the paste's own step, since undoing the paste takes the
    # whole layer away, rather than through `SaHeightOps.gain`, which would be
    # a second step. Nothing is allocated that the copy did not hold.
    var height := SaFieldSpec.find(schema, SaFieldSpec.HEIGHT)
    if height != null and _holds_height():
        layer.add_field(SaFieldSpec.sparse(height.id, height.format))
    for grid_pos: Vector2i in placed:
        layer.set_chunk(grid_pos, placed[grid_pos])

    # Painted in another space: convert the pasted pixels into this document's,
    # the same pass Image > Convert runs, over this one layer.
    if space != null and not space.matches(document.color_space):
        SaColorConversion.new(document).convert_layer(layer, space)

    layer.mark_all_unresolved()
    document.invalidate_chunks(placed.keys())
    document.update_caches()
    document.modified = true
    # The layers docker rebuilds its rows when a child enters the tree and when
    # the active layer changes, and both happened inside add() under the name
    # add() gave. A document change refreshes controls only, so the rename is
    # announced the way the active layer is, or the docker keeps saying Layer 2.
    document.active_layer_changed.emit(layer)
    document.document_changed.emit()
    return layer


## How far the copy's pixels move to land in *document*, in its pixels: not
## at all in a canvas the size of the one it was copied from, where its bounds
## mean the same place, and otherwise its bounds' middle onto the canvas's
## middle, the extra pixel of an odd difference to the right and down as
## Canvas Size centres.
##
## By size and not by document, because a region copied between two paintings
## of one size lands in place, and a copy outlives
## the document it came from. Photoshop centres there too, and Sara keeps the
## place, which is Paste in Place for two canvases that line up.
func offset_in(document: SaDocument) -> Vector2i:
    var canvas := Rect2i(Vector2i.ZERO, document.canvas_size)
    if _in_place or (canvas.size == _from_size and canvas.encloses(bounds)):
        return Vector2i.ZERO
    return SaCrop.offset_for(bounds.size, canvas.size, Vector2i(1, 1)) - bounds.position


## Whether the copy is wider or taller than *document*'s canvas, which is when
## a paste asks how it lands, as a picture of the wrong size does.
func overhangs(document: SaDocument) -> bool:
    return bounds.size.x > document.canvas_size.x or bounds.size.y > document.canvas_size.y


## The chunks a paste into *document* by *fit* puts down, fresh, so the
## clipboard keeps its own and a second paste is the same picture. A whole
## number of chunks' shift moves the grid, and any other is re-tiled on the
## GPU by `SaCrop.shifted`, never read back. A scale goes through
## `SaResample.mapped_chunks`, the Image Size walk, onto the canvas.
func _placed(document: SaDocument, fit: SaImageImport.Fit) -> Dictionary[Vector2i, SaChunk]:
    var canvas := document.canvas_size
    var scales := fit == SaImageImport.Fit.INSIDE or fit == SaImageImport.Fit.STRETCH
    if scales and bounds.size.x > 0 and bounds.size.y > 0:
        return SaResample.new(document).mapped_chunks(chunks, schema, scale(), fit_map(bounds, canvas, fit), canvas)
    var offset := offset_in(document)
    var edge := SaLayer.CHUNK_SIZE
    var fresh: Dictionary[Vector2i, SaChunk] = {}
    if offset.x % edge == 0 and offset.y % edge == 0:
        # Exact, since both sides of the shift are whole chunks.
        @warning_ignore("integer_division")
        var cells := offset / edge
        for grid_pos: Vector2i in chunks:
            fresh[grid_pos + cells] = (chunks[grid_pos] as SaChunk).duplicate_chunk()
        return fresh
    return SaCrop.new(document).shifted(chunks, schema, scale(), offset)


## The map, in document pixels, that puts *from* onto a canvas of *canvas* by
## *fit*: stretched to fill it, or the largest that fits with the ratio kept,
## centred. `SaImageImport.fit_image`'s arithmetic, on a rectangle.
static func fit_map(from: Rect2i, canvas: Vector2i, fit: SaImageImport.Fit) -> Transform2D:
    var factor := Vector2(canvas) / Vector2(from.size)
    var at := Vector2.ZERO
    if fit == SaImageImport.Fit.INSIDE:
        var least := minf(factor.x, factor.y)
        var size := Vector2i(maxi(1, roundi(from.size.x * least)), maxi(1, roundi(from.size.y * least)))
        factor = Vector2(float(size.x) / from.size.x, float(size.y) / from.size.y)
        at = Vector2(SaCrop.offset_for(size, canvas, Vector2i(1, 1)))
    return Transform2D(Vector2(factor.x, 0.0), Vector2(0.0, factor.y), at - Vector2(from.position) * factor)


## Layer via Copy and Layer via Cut: the selected part of *layer* copied, and
## cleared from it too when *cutting*, then put down right above it named after it,
## as Paste puts a layer down. Answers the new layer, or null when the
## selection reached none of *layer*'s paint or the cut was refused.
## *seamless* with *cutting* is Layer via Seamless Cut, whose new layer is as
## opaque as the stack needs to look as it did over the soft hole.
##
## **The shared clipboard is left as it was.** The pixels go through a
## clipboard made for the press and dropped after it, so what Copy left there
## is still there to paste. Each door records a step of its own, and the caller gathers
## them into one.
##
## **In place, every texel at its own coordinates.** Paste's rule
## centres a copy whose bounds reach past the canvas, which a lasso drawn over
## the edge makes, and that rule is for a copy from another painting.
static func to_new_layer(document: SaDocument, layer: SaLayer, cutting: bool, seamless: bool = false) -> SaLayer:
    var held := SaClipboard.new(Vector2i.ZERO, true)
    var lifted := held.cut(document, layer, seamless) if cutting else (held.copy(document, layer) > 0)
    return held.paste(document, "%s copy" % layer.name) if lifted else null


## The masks a copy or a cut reads: *selection* itself, or a selection of
## nothing, which masks nothing, while Select All's stands. Select All means
## everything on the layer, past the canvas edge too, and its chunks cover only
## the canvas.
static func _masks(selection: SaSelection) -> SaSelection:
    return SaSelection.new() if selection.selects_everything() else selection


## A layer dropped on another document's tab: the whole of *layer*, whatever
## *source* has selected, put down on top of *target* under its name, through
## a clipboard made for the drop so what Copy left is still there to paste.
## Converted into *target*'s colour space and refused across depths the way
## Paste is, and one Add Layer step in *target*'s history. Only a paint layer
## goes, because a group, a generated, scene, simulated or effect layer is more
## than its chunks. Its mask stays behind, as a copy's does. Answers the new
## layer, or null when nothing was put down.
##
## A layer inside a group goes as a top level layer on top of *target*, with
## its own opacity and blend mode and none of its groups', since those belong
## to the groups that stay behind. On top whatever is active in *target*,
## because a new layer lands above the active one and inside its group: the
## topmost layer is made active first, and the copy then lands above it, and
## undoing the drop leaves that layer active. A paint layer with no paint goes
## as an empty layer of its name, where a paste of nothing puts nothing down.
static func copy_layer_across(source: SaDocument, layer: SaLayer, target: SaDocument) -> SaLayer:
    if source == null or target == null or layer == null or source == target:
        return null
    var plain := not (layer.is_group or layer.is_generated() or layer.is_adjustment() or layer.is_effect())
    if not plain or layer.is_scene() or layer.simulation != null or not layer.layer_type.is_empty():
        SaProblems.refuse("Layers", TranslationServer.translate("Only a paint layer can be copied to another document."))
        return null
    var held := SaClipboard.new(source.canvas_size)
    held.space = source.color_space
    for spec: SaFieldSpec in layer.schema:
        if spec.id != SaFieldSpec.MASK:
            held.schema.append(spec)
    held.bounds = Rect2i(Vector2i.ZERO, source.canvas_size)
    for grid_pos: Vector2i in layer.chunks:
        var taken := layer.duplicate_chunk(grid_pos)
        taken.fields.erase(SaFieldSpec.MASK)
        held.chunks[grid_pos] = taken
    var stack := SaLayerOps.new(target).layers()
    if not stack.is_empty():
        # The topmost child is top level, a group standing above its members.
        target.set_active_layer(stack[-1])
    var pasted: SaLayer = null
    if held.is_empty():
        pasted = SaLayerOps.new(target).add(&"", null, layer.resolution_scale)
        if pasted != null:
            pasted.name = held._free_name(target, str(layer.name))
            target.active_layer_changed.emit(pasted)
    else:
        pasted = held.paste(target, str(layer.name))
    if pasted != null:
        pasted.opacity = layer.opacity
        pasted.blend_mode = layer.blend_mode
    return pasted


## The document *layer* belongs to, found up its parents, because a layer
## inside a group has the group for its parent. Null for a layer in no document.
static func document_of(layer: SaLayer) -> SaDocument:
    var node: Node = layer
    while node != null and not node is SaDocument:
        node = node.get_parent()
    return node as SaDocument


## One masked kernel over *local* of *source*, into *destination* when the
## kernel has one. The dispatch starts on a workgroup boundary and the push
## constant carries the rectangle's end, so the kernel stops where the copy does.
##
## **Not an [SaChunkWalk], and `cut` above is.** The two look alike and are not:
## a cut rewrites the chunk it walks, which is what the walk binds at 0, and a
## copy reads one chunk and writes a fresh one field by field. The walk binds
## its extra bindings once per stop rather than once per field, so the copy's
## destination, which is a different texture for every field of the chunk, has
## nowhere to go in it. Giving the walk a per-field binding hook for one caller
## would put a second loop variable inside the door, and the copy is nine lines.
func _dispatch(
    compute: SaCompute, kernel: String, source: SaTexture, mask: SaTexture, local: Rect2i, destination: SaTexture
) -> void:
    var workgroup := SaCompute.WORKGROUP_SIZE
    var start := Vector2i(
        floori(float(local.position.x) / workgroup) * workgroup, floori(float(local.position.y) / workgroup) * workgroup
    )
    var covered := Vector2i(local.end.x - start.x, local.end.y - start.y)
    compute.use_storage_format(source.format)
    compute.set_texture(0, source.rid)
    compute.set_texture(SaSelection.BINDING, mask.rid)
    if destination != null:
        compute.set_texture(DESTINATION_BINDING, destination.rid)
    compute.set_push_constant_float_array(PackedFloat32Array([start.x, start.y, covered.x, covered.y]))
    compute.dispatch_kernel(kernel, SaCompute.groups_for(covered.x), SaCompute.groups_for(covered.y), 1)


func _copy() -> SaCompute:
    if _copy_compute == null:
        _copy_compute = SaCompute.new("copy_masked")
    return _copy_compute


func _seamless() -> SaCompute:
    if _seamless_compute == null:
        _seamless_compute = SaCompute.new("seamless_copy_masked")
    return _seamless_compute


func _cut() -> SaCompute:
    if _cut_compute == null:
        _cut_compute = SaCompute.new("cut_masked")
    return _cut_compute


func _height() -> SaCompute:
    if _height_compute == null:
        _height_compute = SaCompute.new("height_masked")
    return _height_compute


## The texels a document pixel of what the clipboard holds: its chunks' own
## `resolution_scale`, which a copy takes from its layer, and 1.0 when empty.
func scale() -> float:
    for grid_pos: Vector2i in chunks:
        return (chunks[grid_pos] as SaChunk).resolution_scale
    return 1.0


## Whether any copied chunk holds a height.
func _holds_height() -> bool:
    for grid_pos: Vector2i in chunks:
        if (chunks[grid_pos] as SaChunk).has_field(SaFieldSpec.HEIGHT):
            return true
    return false


## A child name no layer of *document* has yet: the base, then the base with 2, 3
## and so on, the way the layer operations number theirs.
func _free_name(document: SaDocument, base: String) -> String:
    var taken: Dictionary[String, bool] = {}
    for child in document.get_children():
        taken[str(child.name)] = true
    if not taken.has(base):
        return base
    var number := 2
    while taken.has("%s %d" % [base, number]):
        number += 1
    return "%s %d" % [base, number]


## The desktop clipboard as text, through the engine. Only a text is ever
## written to it here, so nothing of the canvas is read back.
class DesktopClipboard:
    extends RefCounted

    ## Whether the display server has a clipboard to write and read back.
    func readable() -> bool:
        return DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)

    func write(content: String) -> void:
        DisplayServer.clipboard_set(content)

    func text() -> String:
        return DisplayServer.clipboard_get()
