## Cut, Copy and Paste while a mask is the paint target: the mask held as
## a grey picture, white where it shows and black where it hides, and a held
## picture written into a mask as the grey it shows.
##
## **The held mask is a picture like any other.** Copy draws the mask's coverage
## as an opaque grey into chunks of a layer in no document, then hands that
## layer to `SaClipboard.copy`, the copy every layer takes. The selection, Select
## All, the reach past the canvas, the colour space and the canvas size the copy
## came from are all that copy's, never a second version of them. So a Paste with
## a layer the target puts the grey down as a new paint layer by Paste's own
## path, as Photoshop does with a copied mask, and the grey travels to another
## document as any held picture does.
##
## **Through `SaMask`**, so a layer's mask, a group's and an attached filter's
## record's copy and take a paste alike. Where a mask holds no chunk it reads its
## rest, which `SaMask.absent` binds.
##
## **Paste into a mask** reads each held texel's lightness in the numbers the
## copy was taken in, `SaColorSpace.lightness`, the reading a brush on a mask
## takes from a colour, so a held colour picture lands as its grey and a held
## mask lands as itself. The held alpha mixes it in, and so does the selection
## when one stands. The copy lands where Paste would put it,
## `SaClipboard.offset_in`, which is in place for a copy from a canvas of this
## size, its own document among them. One history step, `PASTE_NAME`, and the
## owner's paint is never read or written.
##
## Everything stays in VRAM: two kernels of `mask_clipboard.gmacs` and the
## masked copy, never a readback (rule 1), each over one chunk (rule 2).
class_name SaMaskClipboard
extends RefCounted

## The history step a paste into a mask records.
const PASTE_NAME := "Paste into Mask"

## The bindings of `mask_clipboard.gmacs`, in the order it declares its images.
const PICTURE_BINDING: int = 0
const MASK_BINDING: int = 1
const SELECTION_BINDING: int = 2

var _document: SaDocument = null
var _compute: SaCompute = null


func _init(document: SaDocument) -> void:
    _document = document


## Holds *owner*'s mask in *held*, inside the selection or the whole of it with
## nothing selected, and answers the number of chunks held. *owner* is a layer,
## a group or an attached filter's record with a mask.
func copy(held: SaClipboard, owner: Object) -> int:
    var mask: SaMask = SaMaskOps.mask_of(owner)
    if held == null or mask == null or _document == null:
        return 0
    var space := _document.color_space
    var picture := SaLayer.new()
    picture.schema = SaFieldSpec.schema_for_space(space)
    var scale := 1.0
    if not mask.is_own() and is_instance_valid(mask.layer):
        scale = mask.layer.resolution_scale
    picture.resolution_scale = scale
    var tint := _tint(space)
    for grid_pos: Vector2i in _positions(mask):
        var chunk := SaChunk.create(picture.schema, scale)
        var albedo := chunk.field(SaFieldSpec.ALBEDO)
        if albedo == null:
            continue
        var coverage := mask.texture_for(grid_pos)
        _run("mask_to_grey", albedo, coverage if coverage != null else mask.absent(), _selection_everything(), tint)
        picture.set_chunk(grid_pos, chunk)
    var taken := held.copy(_document, picture)
    picture.free()
    # A selection that reaches past the canvas is held as far as the canvas,
    # so a paste back into this document lands in place, `offset_in`.
    held.bounds = held.bounds.intersection(Rect2i(Vector2i.ZERO, _document.canvas_size))
    return taken


## Copies *owner*'s mask into *held*, then hides the selected part of it, or all
## of it with nothing selected, through `SaMaskOps.clear`, the step the clear
## key takes on a mask. False when nothing was held or nothing hidden.
func cut(held: SaClipboard, owner: Object) -> bool:
    if copy(held, owner) == 0:
        return false
    return SaMaskOps.new(_document).clear(owner)


## Writes what *held* holds into *owner*'s mask as one step, and answers whether
## anything changed. A paint layer's mask is written at the chunks the layer
## holds, as a fill of its mask is, because a position with no paint has nothing
## to hide. A mask of its own is written wherever the copy lands.
func paste(held: SaClipboard, owner: Object) -> bool:
    var mask: SaMask = SaMaskOps.mask_of(owner)
    if held == null or held.is_empty() or mask == null or _document == null:
        return false
    var placed := _placed(held)
    var selection := _document.selection
    var narrowed := selection != null and selection.active and not selection.selects_everything()
    var state: Dictionary[Vector2i, Variant] = {}
    var tint := _weights(held.space if held.space != null else _document.color_space)
    for grid_pos: Vector2i in placed:
        if narrowed and not selection.chunks.has(grid_pos):
            continue
        if not mask.is_own() and (not is_instance_valid(mask.layer) or not mask.layer.chunks.has(grid_pos)):
            continue
        var picture := (placed[grid_pos] as SaChunk).field(SaFieldSpec.ALBEDO)
        if picture == null:
            continue
        state[grid_pos] = mask.duplicate_chunk(grid_pos)
        var coverage := mask.get_or_create(grid_pos)
        if coverage == null:
            state.erase(grid_pos)
            continue
        var selected := selection.texture_for(grid_pos) if narrowed else _selection_everything()
        _run("grey_into_mask", picture, coverage, selected, tint)
    if state.is_empty():
        return false
    mask.record_step(_document, PASTE_NAME, state)
    _document.mask_moved(mask, state.keys())
    _document.modified = true
    return true


## The grid positions a copy of *mask* reads: every chunk the selection holds
## when one stands, and otherwise the canvas together with every chunk the mask
## holds, past the canvas edge too.
func _positions(mask: SaMask) -> Array[Vector2i]:
    var selection := _document.selection
    var found: Dictionary[Vector2i, bool] = {}
    if selection != null and selection.active and not selection.selects_everything():
        for grid_pos: Vector2i in selection.chunks:
            found[grid_pos] = true
    else:
        for grid_pos: Vector2i in SaLayer.grid_positions(_document.canvas_size):
            found[grid_pos] = true
        for grid_pos: Vector2i in mask.grid_positions():
            found[grid_pos] = true
    return found.keys()


## The held chunks where a paste into this document puts them, by
## `SaClipboard.offset_in`. A whole number of chunks' shift reads the held
## chunks themselves, since the paste only reads them, and any other is
## re-tiled on the GPU by `SaCrop.shifted`.
func _placed(held: SaClipboard) -> Dictionary[Vector2i, SaChunk]:
    var offset := held.offset_in(_document)
    var edge := SaLayer.CHUNK_SIZE
    if offset.x % edge != 0 or offset.y % edge != 0:
        return SaCrop.new(_document).shifted(held.chunks, held.schema, held.scale(), offset)
    @warning_ignore("integer_division")
    var cells := offset / edge
    var placed: Dictionary[Vector2i, SaChunk] = {}
    for grid_pos: Vector2i in held.chunks:
        placed[grid_pos + cells] = held.chunks[grid_pos]
    return placed


## What a coverage of one is in *space*'s numbers: L of one in Oklab and white
## in RGB, whose lightness is one because a space's white has a Y of one.
static func _tint(space: SaColorSpace) -> Color:
    if space != null and space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return Color(1.0, 0.0, 0.0, 0.0)
    return Color(1.0, 1.0, 1.0, 0.0)


## What *space*'s stored numbers are weighed by to give their lightness, the
## sum `SaColorSpace.lightness` takes: Oklab's L alone, and an RGB space's row
## of Y. With no space, the mean of the three.
static func _weights(space: SaColorSpace) -> Color:
    if space == null:
        return Color(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0.0)
    if space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return Color(1.0, 0.0, 0.0, 0.0)
    var to_xyz := space.rgb_to_xyz()
    return Color(to_xyz.x.y, to_xyz.y.y, to_xyz.z.y, 0.0)


func _selection_everything() -> SaTexture:
    return _document.selection.everything()


## One kernel of `mask_clipboard.gmacs` over the whole of what it writes: the
## picture chunk for `mask_to_grey` and the mask chunk for `grey_into_mask`.
func _run(kernel: String, picture: SaTexture, coverage: SaTexture, selected: SaTexture, tint: Color) -> void:
    if _compute == null:
        _compute = SaCompute.new("mask_clipboard")
    var written := picture if kernel == "mask_to_grey" else coverage
    _compute.use_storage_format(picture.format)
    _compute.set_texture(PICTURE_BINDING, picture.rid)
    _compute.set_texture(MASK_BINDING, coverage.rid)
    _compute.set_texture(SELECTION_BINDING, selected.rid)
    _compute.set_push_constant_float_array(PackedFloat32Array([tint.r, tint.g, tint.b, tint.a]))
    _compute.dispatch_kernel(kernel, SaCompute.groups_for(written.size.x), SaCompute.groups_for(written.size.y), 1)
