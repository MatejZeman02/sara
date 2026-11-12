## A dab painted through a live transform: its frame taken back through the
## map, so a stroke on a moved, turned or scaled layer lands in the layer's own
## pixels at the size and the angle it has under the pointer.
##
## A dab's frame, its turn, its mirror and its half extent, is one 2 by 2 map,
## the kernel's: a texel's offset from the dab's centre is the turn of the
## mirrored half extent. The map's linear part taken back is applied over it,
## and [method frame] takes the product apart into a turn, a mirror and two
## lengths again. A move, a turn and a scale, a mirror among them, give every
## tip exactly. A skew gives an ellipse exactly as well, and a rectangle, a
## spiked shape or a picture through the nearest turn and scale, since the
## kernel has no skew. A perspective, which the brush is refused, gives its
## affine part.
##
## Stateless, and named only by `SaLiveTransform`, whose [method
## SaLiveTransform.dab] hands it the map.
class_name SaLiveDab
extends RefCounted

## How small one of a dab's two kinds of change may be, against its larger
## length, for [method frame] to read the dab as a turn and a scale alone, or
## as a mirror and a scale alone.
const ALONE := 1.0e-6
## The floats of a dab's push constant [method back] rewrites, at the indices
## `SaDabGeometry.pack` writes them: the half extent, the cosine and the sine
## of the turn, and the falloff the half extent gives.
const EXTENT := 8
const TURN := 10
const FALLOFF := 27


## *data*, a dab's push constant packed in the document's frame, with its half
## extent, its turn and its mirror taken through *inverse*, a map's inverse,
## into the layer's own pixels, and its falloff following the half extent. The
## centre and the offset are already the paint context's target's, in the
## layer's pixels.
static func back(inverse: Basis, data: PackedFloat32Array) -> PackedFloat32Array:
    var bits := int(data[SaDabGeometry.MIRROR_INDEX] + 0.5)
    var cosine := data[TURN]
    var sine := data[TURN + 1]
    var across := data[EXTENT] * (-1.0 if (bits & 1) != 0 else 1.0)
    var down := data[EXTENT + 1] * (-1.0 if (bits & 2) != 0 else 1.0)
    # The kernel's frame: these two columns take the tip's unit square to the
    # dab.
    var tip := Transform2D(Vector2(cosine, sine) * across, Vector2(-sine, cosine) * down, Vector2.ZERO)
    var m := inverse
    var linear := Transform2D(Vector2(m.x.x, m.x.y) / m.z.z, Vector2(m.y.x, m.y.y) / m.z.z, Vector2.ZERO)
    var taken := frame(linear * tip)
    var turn := taken[0]
    var half := Vector2(taken[1], taken[2])
    var falloff := SaDabGeometry.falloff_radius(half)
    var mapped := data.duplicate()
    mapped[EXTENT] = half.x
    mapped[EXTENT + 1] = half.y
    mapped[TURN] = cos(turn)
    mapped[TURN + 1] = sin(turn)
    mapped[SaDabGeometry.MIRROR_INDEX] = taken[3]
    mapped[FALLOFF] = falloff.x
    mapped[FALLOFF + 1] = falloff.y
    return mapped


## *linear*, a 2 by 2 linear map, as the dab the kernel draws: a turn, then a
## mirror, then two half lengths, as `[turn, across, down, mirror bits]`. Its
## singular values in closed form, the 2 by 2 case of Blinn's, whose turn on
## the tip's own side the kernel has no room for. That turn is made as small as
## swapping the two lengths makes it, an eighth of a turn at most, and nought
## where the map is a turn and a scale alone or a mirror and a scale alone,
## where any turn on that side can be moved to the other.
static func frame(linear: Transform2D) -> PackedFloat32Array:
    var e := (linear.x.x + linear.y.y) * 0.5
    var f := (linear.x.x - linear.y.y) * 0.5
    var g := (linear.x.y + linear.y.x) * 0.5
    var h := (linear.x.y - linear.y.x) * 0.5
    var turning := Vector2(e, h).length()
    var stretching := Vector2(f, g).length()
    var mirrored := atan2(g, f)
    var kept := atan2(h, e)
    var turn := (kept + mirrored) * 0.5
    var rest := (kept - mirrored) * 0.5
    var lengths := Vector2(turning + stretching, turning - stretching)
    if stretching <= ALONE * lengths.x:
        turn = kept
        rest = 0.0
    elif turning <= ALONE * lengths.x:
        turn = mirrored
        rest = 0.0
    while rest > PI / 4.0:
        turn += PI / 2.0
        rest -= PI / 2.0
        lengths = Vector2(lengths.y, lengths.x)
    while rest < -PI / 4.0:
        turn -= PI / 2.0
        rest += PI / 2.0
        lengths = Vector2(lengths.y, lengths.x)
    var bits := (1 if lengths.x < 0.0 else 0) | (2 if lengths.y < 0.0 else 0)
    return PackedFloat32Array([turn, absf(lengths.x), absf(lengths.y), float(bits)])
