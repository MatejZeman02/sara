## The one writer of the `resample` kernel's push constant.
##
## Three places read a picture back through the inverse of a map, and each would
## otherwise write the twenty four floats out for itself: `SaTransform` for the
## transform tool's preview, `SaTransformSelection` for the mask that goes with
## it, and `SaResample` for Image > Scale. One door and three callers through
## it, so a change to the push constant is made once rather than in three
## files.
##
## The map arrives as `SaHomography.kernel_rows` answers it, already inverted
## and with the lifted picture's own origin folded in, so nothing here knows
## about angles, scales or the horizon.
class_name SaResampleKernel
extends RefCounted

## How the resample reads between texels. Bilinear is the default and
## nearest is the one filter that cannot invent a colour the picture did not
## hold, which is what pixel art wants.
##
## Here rather than on the transform engine, which lives in the base module,
## because a skeleton class reads this one. Image Size's `SaResample` and the
## tool's `filter_mode` both hold it, so the two cannot drift into two
## spellings of bilinear, and the two values keep their order because a saved
## `filter_mode` is an integer.
enum Filter { BILINEAR, NEAREST }

## The transfer curve that leaves a read on the stored values, as the four
## numbers `transfer_curve.gmacs` takes: a slope, a threshold, a gain and an
## exponent of one, nought and one and one, which that library returns as it
## was given.
const IDENTITY := Vector4(1.0, 0.0, 1.0, 1.0)

## The curve that marks an Oklab document. No transfer has a negative slope, so
## `transform_read.gmacs` reads it as the sign to decode through Oklab rather
## than through a transfer curve.
const OKLAB := Vector4(-1.0, 0.0, 1.0, 1.0)


## The curve a resample of *field_id* on a document in *space* reads through,
## as the four numbers the kernels take. The paint's colour of an RGB document
## is blended in linear light, so it is its transfer curve. A field that is not
## colour, a mask or a height, is a number rather than an encoded light, and
## reads on the stored values through [constant IDENTITY]. No space is the
## identity too. An Oklab document's colour is [constant OKLAB]: a mix of Oklab
## values is perceptual, but a resample averages light, and light is linear.
static func curve_for(space: SaColorSpace, field_id: StringName) -> Vector4:
    if space == null or space.transfer == null or field_id != SaFieldSpec.ALBEDO:
        return IDENTITY
    if space.coordinates == SaColorSpace.Coordinates.OKLAB:
        return OKLAB
    var curve := space.transfer
    return Vector4(curve.slope, curve.threshold, curve.gain, curve.exponent)


## One dispatch: *local* of *target*, read out of *source* through *rows*.
##
## *world* is the destination chunk's own origin in document pixels, *local* is
## the rectangle of the chunk to write, and *nearest* picks the filter the way
## [enum Filter] does. A null or invalid texture on either side is a
## no-op rather than an error, because a chunk holding no field the source has
## is an ordinary thing on a sparse grid. *curve* is [method curve_for]'s,
## the identity for a caller that reads a mask.
static func dispatch(
    compute: SaCompute,
    target: SaTexture,
    source: SaTexture,
    rows: Array,
    world: Vector2,
    local: Rect2i,
    nearest: bool,
    curve := IDENTITY
) -> void:
    if compute == null or target == null or source == null:
        return
    if not target.rid.is_valid() or not source.rid.is_valid():
        return
    if local.size.x <= 0 or local.size.y <= 0 or rows.size() != 4:
        return
    var row0: Vector2 = rows[0]
    var row1: Vector2 = rows[1]
    var shift: Vector2 = rows[2]
    var persp: Vector3 = rows[3]
    compute.use_storage_format(target.format)
    compute.set_texture(0, source.rid)
    compute.set_texture(1, target.rid)
    (
        compute
        . set_push_constant_float_array(
            PackedFloat32Array(
                [
                    local.position.x,
                    local.position.y,
                    local.size.x,
                    local.size.y,
                    world.x,
                    world.y,
                    source.size.x,
                    source.size.y,
                    row0.x,
                    row0.y,
                    row1.x,
                    row1.y,
                    shift.x,
                    shift.y,
                    1.0 if nearest else 0.0,
                    0.0,
                    persp.x,
                    persp.y,
                    persp.z,
                    0.0,
                    curve.x,
                    curve.y,
                    curve.z,
                    curve.w,
                ]
            )
        )
    )
    compute.dispatch_kernel("resample", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
