## One dispatch of the `warp` kernel: a rectangle of a destination chunk drawn
## out of the lifted picture through a mesh of side by side control points.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Beside `warp.gmacs` in the transform's `warps` folder, and a folder below
## `sa_transform.gd`, the one caller.
##
## The sibling of `SaResampleKernel`, for the map that is not a matrix: the
## points are where the grid over the lifted picture went, nine for Freehand
## and a dense grid for the cage, and the kernel finds each texel's cell and
## its place in it. The rectangle is the dirty rect, hard rule 2, and the
## dispatch is the same shape as the resample's so `SaTransform` calls one or
## the other per chunk and nothing else changes.
##
## **The points ride in a storage buffer**, which `points_buffer` writes once
## per map and every chunk's dispatch binds, since a dense mesh is far past
## the 128 bytes a push constant holds.
class_name SaWarpKernel
extends RefCounted


## The buffer of *mesh*'s points in texels, *scale* texels a document pixel,
## or null when the mesh is no grid or there is no device.
static func points_buffer(mesh: PackedVector2Array, scale: float) -> SaCompute.Buffer:
    if SaTransformMesh.side_of(mesh) < 2 or GlobalShaderCompiler.get_rd() == null:
        return null
    var data := PackedFloat32Array()
    for point: Vector2 in mesh:
        data.append(point.x * scale)
        data.append(point.y * scale)
    return SaCompute.Buffer.new(data.to_byte_array())


## *points* is the buffer `points_buffer` wrote, and *side* the mesh's points
## along a side. *curve* is `SaResampleKernel.curve_for`'s, the identity for a
## mask.
static func dispatch(
    compute: SaCompute,
    target: SaTexture,
    source: SaTexture,
    points: SaCompute.Buffer,
    side: int,
    world: Vector2,
    local: Rect2i,
    nearest: bool,
    curve := SaResampleKernel.IDENTITY
) -> void:
    if compute == null or target == null or source == null or points == null or side < 2:
        return
    if not target.rid.is_valid() or not source.rid.is_valid() or not points.rid.is_valid():
        return
    if local.size.x <= 0 or local.size.y <= 0:
        return
    compute.use_storage_format(target.format)
    compute.set_texture(0, source.rid)
    compute.set_texture(1, target.rid)
    compute.set_storage("grid", points.rid)
    var data := PackedFloat32Array(
        [
            local.position.x,
            local.position.y,
            local.size.x,
            local.size.y,
            world.x,
            world.y,
            source.size.x,
            source.size.y,
        ]
    )
    data.append(float(side))
    data.append(1.0 if nearest else 0.0)
    data.append(0.0)
    data.append(0.0)
    data.append_array(PackedFloat32Array([curve.x, curve.y, curve.z, curve.w]))
    compute.set_push_constant_float_array(data)
    compute.dispatch_kernel("warp", SaCompute.groups_for(local.size.x), SaCompute.groups_for(local.size.y), 1)
