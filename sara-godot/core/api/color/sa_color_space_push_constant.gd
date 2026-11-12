## The push-constant tails a composite or a conversion kernel reads, and the
## conversion matrix they carry. Split out of `sa_color_space.gd`. Static
## helpers taking the space or spaces as arguments, because `SaColorSpace` is
## a value type that composes nothing.
class_name SaColorSpacePushConstant
extends RefCounted

## How many floats [method to_push_constant] writes.
const PUSH_CONSTANT_FLOATS: int = 24

## How many floats [method to_conversion_push_constant] writes.
const CONVERSION_PUSH_CONSTANT_FLOATS: int = 20

## How many tails [method to_push_constant] has built since the process started,
## which a suite reads before and after a composite to count the builds a
## composite cost. Written here only.
static var builds: int = 0


## Nine floats, three per column, matching a `float[9]` on the GLSL side.
##
## Not a `mat3`. std430 pads every `mat3` column out to 16 bytes, so a matrix
## declared that way spends 48 bytes carrying 36, and the composite block held two
## of them. Declaring the arrays instead, whose std430 stride is 4, is what freed
## the room the coordinate system needed. Nothing packs this for us: the compiler
## never reads the `Params` block, so the order here and the order there are
## matched by hand and by the asserts below.
static func _append_basis(into: PackedFloat32Array, basis: Basis) -> void:
    for column: Vector3 in SaColorSpaceGlsl.basis_columns(basis):
        into.append(column.x)
        into.append(column.y)
        into.append(column.z)


## `space` as the tail of a composite kernel's push constant.
##
## Both matrices go out as nine floats each, matching a `float[9]` on the GLSL
## side, rather than a `mat3`, which std430 stores as three columns each padded
## out to 16 bytes, 48 bytes carrying 36, twice over. The 24 bytes this saves
## are what the coordinate system takes in the block, which is 112 bytes, under
## the 128 Vulkan guarantees.
##
## Then the document's transfer curve as four numbers rather than a flag naming
## one, which is what lets a document declare a curve the kernel has never heard
## of, and last the coordinate system, which says whether the numbers in the
## chunks are RGB at all.
##
## Sending the matrices rather than generating them into the shader is the whole
## decision here. A generated include is global to the compiler, and Sara already
## runs two easels at once, so a compile-time colour space would be one
## document's answer applied to both.
static func to_push_constant(space: SaColorSpace) -> PackedFloat32Array:
    builds += 1
    var packed := PackedFloat32Array()
    _append_basis(packed, space.to_linear_srgb_matrix())
    _append_basis(packed, space.from_linear_srgb_matrix())
    packed.append_array(space.transfer.to_params())
    packed.append(float(space.coordinates))
    packed.append(0.0)
    assert(packed.size() == PUSH_CONSTANT_FLOATS, "Colour space push constant tail is the wrong size")
    return packed


## The matrix taking `source`'s linear RGB into `target`'s, white point adapted.
##
## Exactly the identity when the two share a gamut, rather than whatever
## `M.inverse() * M` rounds to. A conversion that only changes the transfer curve
## must not shift the primaries by a hair, and the same insistence is why
## `to_linear_srgb_matrix` tests the gamut before building a matrix.
static func conversion_matrix(source: SaColorSpace, target: SaColorSpace) -> Basis:
    if target == null:
        return Basis.IDENTITY
    # A non-RGB side has no linear RGB of its own for a matrix to start or finish
    # in. Oklab is absolute, defined against linear sRGB, so the matrix carries
    # only the half of the journey that is still a gamut rotation and the kernel
    # does the cube root at whichever end asked for it.
    var source_is_rgb := source.coordinates == SaColorSpace.Coordinates.RGB
    var target_is_rgb := target.coordinates == SaColorSpace.Coordinates.RGB
    if not source_is_rgb and not target_is_rgb:
        return Basis.IDENTITY
    if not source_is_rgb:
        return target.from_linear_srgb_matrix()
    if not target_is_rgb:
        return source.to_linear_srgb_matrix()
    if source.shares_gamut(target):
        return Basis.IDENTITY
    return source.to_space_matrix(target)


## The push constant `convert_color_space.gmacs` reads: the matrix from `source`
## into `target`, then which transfer curve sits on each side.
##
## 80 bytes: the matrix, both curves in full, then which coordinate
## system sits on each side. The kernel decodes out of the source curve, applies
## the matrix and encodes into the target's, so both curves are needed and they
## are frequently different. sRGB to Linear sRGB is a transfer change with an
## identity matrix, and sRGB to ACEScg changes both.
##
## The two coordinate flags tell the kernel which end needs the cube root instead
## of a curve. [method conversion_matrix] has already narrowed the matrix to
## whatever gamut rotation is left over once that is accounted for.
static func to_conversion_push_constant(source: SaColorSpace, target: SaColorSpace) -> PackedFloat32Array:
    var packed := PackedFloat32Array()
    _append_basis(packed, conversion_matrix(source, target))
    packed.append_array(source.transfer.to_params())
    packed.append_array(target.transfer.to_params() if target != null else source.transfer.to_params())
    packed.append(float(source.coordinates))
    packed.append(float(target.coordinates if target != null else source.coordinates))
    packed.append(0.0)
    assert(packed.size() == CONVERSION_PUSH_CONSTANT_FLOATS, "Conversion push constant is the wrong size")
    return packed
