## The layer kind a frame another program sends lands in, Blender's camera
## view first, and the render passes import after it.
##
## The layer stores chunks like paint, so the compositor, the fold, the save
## and the export read it as any layer, and only who writes the chunks
## differs: this writer, handed a frame's bytes by whatever received them.
## The kind lives in the skeleton rather than in the module that receives
## Blender's frames, because the render passes import lands its passes in the
## same kind, and a module reaches it by the
## role [constant ROLE] and never by this class's name.
##
## **A frame** is half float RGBA in linear light, rows from the top, at its
## place in the document, the document's size or smaller. Its primaries come
## with it as an `SaColorSpace`, and a frame in another space than the
## document's is converted on the card after the upload, unclamped, rule 5.
## It may carry a depth, one float a texel, which goes into the [constant
## DEPTH] field, a field that is not colour and that the compositor never
## reads, where the passes import and the paint that follows a camera find it.
##
## **Rule 1.** A frame is an upload, bytes from the CPU written into a texture
## on the card, and nothing comes back: the upload goes into a staging texture
## the writer keeps, and a kernel copies it into the chunks.
##
## **Rule 3.** A chunk is allocated only where the frame's alpha is above
## zero, which the writer reads off the frame's bytes while they are still on
## the CPU, and a chunk the last frame filled and this one leaves empty is
## let go, so the layer holds the last frame and nothing of the one before.
@tool
class_name SaFrameLayer
extends RefCounted

## The type's id, persisted in a `.sad`.
const TYPE_ID: StringName = &"frame"
## The role a module asks the context for, `SaContext.engine_for`.
const ROLE: StringName = &"frame_layer"
## The field a frame's depth lands in, one float a texel, never composited.
const DEPTH: StringName = &"depth"
const DEPTH_FORMAT: int = RenderingDevice.DATA_FORMAT_R32_SFLOAT
## The format a frame's colour arrives in, eight bytes a texel.
const FRAME_FORMAT: int = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
const COLOR_BYTES: int = 8
const DEPTH_BYTES: int = 4
## The kernel beside this file that copies a rectangle of the staging texture
## into a chunk and converts it into the document's space on the way.
const SHADER_NAME := "frame_copy"
## The frame's binding in the kernel, which keeps the staging format whatever
## the chunk's is.
const SOURCE_BINDING := 1

## The staging textures of the last frame's size, kept so a stream of frames
## of one size makes them once.
var _colour_stage: SaTexture = null
var _depth_stage: SaTexture = null
var _compute: SaCompute = null


## The kind as it registers through the door, rule 6: the colour field every
## layer has and a depth field that is allocated only where a frame brought
## one.
static func descriptor() -> SaLayerTypeDescriptor:
    var schema: Array[SaFieldSpec] = [SaFieldSpec.albedo(), SaFieldSpec.sparse(DEPTH, DEPTH_FORMAT)]
    var made := SaLayerTypeDescriptor.create(TYPE_ID, schema)
    made.display_name = "Frame Layer"
    made.icon_name = "Camera3D"
    made.hint = "Holds the last frame another program sent it, such as Blender's camera view. Paint on a layer above it."
    made.under_paint = true
    return made


## Whether *layer* is of this kind.
static func holds(layer: SaLayer) -> bool:
    return layer != null and layer.layer_type == TYPE_ID


## Writes one frame into *layer* of *document*: *place* is where it stands in
## the document and its size, *colour* its RGBA half floats, *space* the space
## its numbers are in, and *depth* its depths or nothing. Answers an empty
## line when it landed and a sentence saying why when it did not.
func write(
    document: SaDocument,
    layer: SaLayer,
    place: Rect2i,
    colour: PackedByteArray,
    space: SaColorSpace,
    depth: PackedByteArray = PackedByteArray()
) -> String:
    var refusal := _refusal(document, layer, place, colour, space, depth)
    if not refusal.is_empty():
        return refusal
    var rd := GlobalShaderCompiler.get_rd()
    _stage(rd, place.size, not depth.is_empty())
    rd.texture_update(_colour_stage.rid, 0, colour)
    if not depth.is_empty():
        rd.texture_update(_depth_stage.rid, 0, depth)
    if _compute == null:
        _compute = SaCompute.new(SHADER_NAME)
    var occupied := occupied_chunks(place, colour)
    var changed: Dictionary[Vector2i, Rect2i] = {}
    var whole := Rect2i(Vector2i.ZERO, Vector2i(SaChunk.SIZE, SaChunk.SIZE))
    for grid_pos: Vector2i in layer.chunks.keys():
        if not occupied.has(grid_pos):
            layer.set_chunk(grid_pos, null)
            changed[grid_pos] = whole
    var tail := space.to_conversion_push_constant(document.color_space)
    var same := SaColorSpace.linear_srgb().to_conversion_push_constant(SaColorSpace.linear_srgb())
    for grid_pos: Vector2i in occupied:
        var corner := grid_pos * SaChunk.SIZE
        var inside := place.intersection(Rect2i(corner, whole.size))
        var local := Rect2i(inside.position - corner, inside.size)
        var chunk := layer.get_or_create_chunk(grid_pos)
        # The frame may cover a chunk in part, and what the last frame left
        # in the rest is not this frame's.
        chunk.clear(SaFieldSpec.NO_PAINT)
        _copy(layer.get_or_create_field(grid_pos), _colour_stage, inside.position - place.position, local, tail)
        if not depth.is_empty():
            _copy(layer.get_or_create_field(grid_pos, DEPTH), _depth_stage, inside.position - place.position, local, same)
        layer.mark_unresolved(grid_pos)
        changed[grid_pos] = whole
    if not changed.is_empty():
        document.invalidate_chunk_regions(changed, layer)
        _refold(document, layer, changed)
    return ""


## Folds again each cache that baked *layer* over the chunks a frame *changed*.
## A frame layer sits under the layer the brush is on, where the fold keeps
## everything in one cache, and a mark at the layer redraws that cache's
## chunks as they were folded, so without this the canvas showed the
## Background and never the frame.
static func _refold(document: SaDocument, layer: SaLayer, changed: Dictionary[Vector2i, Rect2i]) -> void:
    if document.fold == null or document.compositor == null:
        return
    var positions: Dictionary[Vector2i, bool] = {}
    for grid_pos: Vector2i in changed:
        positions[grid_pos] = true
    document.invalidate_chunks(document.fold.refold(document, document.compositor, layer, positions).keys(), layer)


## Why a frame cannot land, or an empty line when it can.
static func _refusal(
    document: SaDocument, layer: SaLayer, place: Rect2i, colour: PackedByteArray, space: SaColorSpace, depth: PackedByteArray
) -> String:
    if GlobalShaderCompiler.get_rd() == null:
        return "There is no rendering device to upload the frame to."
    if document == null or not holds(layer) or layer.get_parent() != document:
        return "The frame has no frame layer of the document to land in."
    # A frame is copied texel for texel into chunks of the document's
    # density, so a layer at another one would take nothing, and a frame
    # answered as landed would leave the painter with no view and no reason.
    if not is_equal_approx(layer.resolution_scale, 1.0):
        return (
            "The frame layer is at %s times the document's resolution, and a frame lands only at the document's own."
            % layer.resolution_scale
        )
    for chunk: SaChunk in layer.chunks.values():
        if chunk != null and chunk.pixel_size() != SaChunk.SIZE:
            return (
                "The frame layer holds chunks of %d texels across, and a frame lands only in chunks of the document's %d."
                % [chunk.pixel_size(), SaChunk.SIZE]
            )
    if space == null or space.coordinates != SaColorSpace.Coordinates.RGB or not space.is_linear():
        return "A frame is linear RGB in a space it names, and this one names none."
    if place.size.x <= 0 or place.size.y <= 0:
        return "The frame is empty."
    if place.size.x > document.canvas_size.x or place.size.y > document.canvas_size.y:
        return (
            "The frame is %d by %d and the document %d by %d, and a frame is the document's size or smaller."
            % [place.size.x, place.size.y, document.canvas_size.x, document.canvas_size.y]
        )
    if not Rect2i(Vector2i.ZERO, document.canvas_size).encloses(place):
        return "The frame stands partly outside the document."
    var texels := place.size.x * place.size.y
    if colour.size() != texels * COLOR_BYTES:
        return (
            "The frame's colour is %d bytes and %d texels of half float RGBA are %d."
            % [colour.size(), texels, texels * COLOR_BYTES]
        )
    if not depth.is_empty() and depth.size() != texels * DEPTH_BYTES:
        return "The frame's depth is %d bytes and %d texels of float are %d." % [depth.size(), texels, texels * DEPTH_BYTES]
    return ""


## Makes the staging textures for a frame of *size*, keeping the ones of the
## last frame when it was the same size.
func _stage(rd: RenderingDevice, size: Vector2i, with_depth: bool) -> void:
    if _colour_stage == null or _colour_stage.size != size or _colour_stage.rd != rd:
        _colour_stage = SaTexture.new(size, FRAME_FORMAT)
        _depth_stage = null
    if with_depth and (_depth_stage == null or _depth_stage.size != size):
        _depth_stage = SaTexture.new(size, DEPTH_FORMAT)


## One dispatch: the rectangle of *source* at *from*, of *local*'s size, into
## *target* at *local*'s place, through the conversion *tail*.
func _copy(target: SaTexture, source: SaTexture, from: Vector2i, local: Rect2i, tail: PackedFloat32Array) -> void:
    if target == null:
        return
    _compute.use_storage_format(target.format)
    _compute.use_binding_format(SOURCE_BINDING, source.format)
    _compute.set_image("target", target)
    _compute.set_image("source", source)
    _compute.set_push_constant_float_array(push_constant(from, local, tail))
    _compute.dispatch_kernel(SHADER_NAME, SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)


## The block `frame_copy.gmacs` reads: where the rectangle starts in the frame
## and in the chunk, its size, and the conversion *tail* into the document,
## 112 bytes.
static func push_constant(source_origin: Vector2i, local: Rect2i, tail: PackedFloat32Array) -> PackedFloat32Array:
    var packed := PackedFloat32Array(
        [
            float(source_origin.x),
            float(source_origin.y),
            float(local.position.x),
            float(local.position.y),
            float(local.size.x),
            float(local.size.y),
        ]
    )
    packed.append_array(tail)
    while packed.size() % 4 != 0:
        packed.append(0.0)
    return packed


## The grid positions of the chunks *place* touches where the frame's alpha,
## in *colour*, is above zero somewhere, read on the CPU before the upload.
##
## A row of a chunk whose bytes are all zero is passed over at the speed of
## `count`, since a transparent texel of a premultiplied frame is four zeros,
## and a row that holds anything is read texel by texel until its first
## alpha above zero. A half's sign is its top bit, so the top sixteen bits of
## a texel read as a signed number are above zero exactly when its alpha is.
static func occupied_chunks(place: Rect2i, colour: PackedByteArray) -> Dictionary[Vector2i, bool]:
    var occupied: Dictionary[Vector2i, bool] = {}
    var first := Vector2i(floori(place.position.x / float(SaChunk.SIZE)), floori(place.position.y / float(SaChunk.SIZE)))
    var last := Vector2i(floori((place.end.x - 1) / float(SaChunk.SIZE)), floori((place.end.y - 1) / float(SaChunk.SIZE)))
    var row_bytes := place.size.x * COLOR_BYTES
    for grid_y in range(first.y, last.y + 1):
        for grid_x in range(first.x, last.x + 1):
            var grid_pos := Vector2i(grid_x, grid_y)
            var inside := place.intersection(Rect2i(grid_pos * SaChunk.SIZE, Vector2i(SaChunk.SIZE, SaChunk.SIZE)))
            var from := inside.position - place.position
            for y in range(from.y, from.y + inside.size.y):
                var start := y * row_bytes + from.x * COLOR_BYTES
                var row := colour.slice(start, start + inside.size.x * COLOR_BYTES)
                if row.count(0) == row.size():
                    continue
                if _any_alpha(row.to_int64_array()):
                    occupied[grid_pos] = true
                    break
    return occupied


static func _any_alpha(texels: PackedInt64Array) -> bool:
    for texel: int in texels:
        if (texel >> 48) > 0:
            return true
    return false
