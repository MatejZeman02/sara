## The revised CAM16 and its Helmholtz-Kohlrausch J_HK, written out again in
## GDScript's double precision so a suite can read what a kernel wrote without
## the library that wrote it. The papers, the viewing conditions and the
## constants are those of `shaders/compute/libs/cam16_hellwig.gmacs`, and
## `scripts/cam16_hellwig_fixtures.py` prints the same numbers.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends RefCounted

const F_L := 0.4641590666
const A_W := 31.72966961
const CZ := 1.329777365

## Linear sRGB to the adapted cone responses, rows as the maths writes them.
const CONE := [
    [31.03809561, 61.74241445, 7.219499942],
    [15.13160913, 76.47207082, 8.39633005],
    [2.579436306, 13.63145739, 83.78911631],
]


static func _compress(x: float) -> float:
    var p := pow(F_L * absf(x) / 100.0, 0.42)
    return signf(x) * 400.0 * p / (27.13 + p)


static func _eccentricity(h: float) -> float:
    return (
        1.0
        - 0.0582 * cos(h)
        - 0.0258 * cos(2.0 * h)
        - 0.1347 * cos(3.0 * h)
        + 0.0289 * cos(4.0 * h)
        - 0.1475 * sin(h)
        - 0.0308 * sin(2.0 * h)
        + 0.0385 * sin(3.0 * h)
        + 0.0096 * sin(4.0 * h)
    )


static func hk_hue_term(h: float) -> float:
    return -0.160 * cos(h) + 0.132 * cos(2.0 * h) - 0.405 * sin(h) + 0.080 * sin(2.0 * h) + 0.792


## J, C and h in radians of the linear sRGB colour *rgb*, as a Vector3.
static func jch(rgb: Vector3) -> Vector3:
    var ra: Array[float] = []
    for row: Array in CONE:
        ra.append(_compress(row[0] * rgb.x + row[1] * rgb.y + row[2] * rgb.z))
    var a := ra[0] - 12.0 * ra[1] / 11.0 + ra[2] / 11.0
    var b := (ra[0] + ra[1] - 2.0 * ra[2]) / 9.0
    var h := fposmod(atan2(b, a), TAU)
    var achromatic := 2.0 * ra[0] + ra[1] + 0.05 * ra[2]
    var j := 100.0 * signf(achromatic) * pow(absf(achromatic) / A_W, CZ)
    var m := 43.0 * _eccentricity(h) * sqrt(a * a + b * b)
    return Vector3(j, 35.0 * m / A_W, h)


## J_HK, the lightness *rgb* shows with its chroma's brightness counted.
static func lightness_hk(rgb: Vector3) -> float:
    var read := jch(rgb)
    return read.x + hk_hue_term(read.z) * pow(maxf(read.y, 0.0), 0.587)
