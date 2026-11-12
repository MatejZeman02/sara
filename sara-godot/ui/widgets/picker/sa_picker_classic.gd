## The classic picker's maths: plain HSV and HSL in the sRGB encoding and the
## HSV triangle's corner weights.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `sa_picker_shape.gd`, which the three classic shapes took past the
## 700-line advisory, and cut by what it owns: this file knows nothing about a
## frame, a ring or a cursor, it answers with numbers. The shader
## `shaders/ui/hsv_picker.gdshader` holds the same formulas and the same three
## corners, so what the cursor stands on is what the shader drew there.
class_name SaPickerClassic
extends RefCounted

## The HSV triangle's three corners in the area's own unit square, on the
## circle of radius a half around its centre: the hue at the top, white
## bottom left and black bottom right. The shader holds the same three.
const TRI_HUE := Vector2(0.5, 0.0)
const TRI_WHITE := Vector2(0.066987, 0.75)
const TRI_BLACK := Vector2(0.933013, 0.75)

const OkhslConversionsScript = preload("res://utils/okhsl_conversions.gd")
## What a miss in Oklab lightness counts for against one in chroma when Keep
## chroma looks for the nearest point of an HSV hue, see [method lc_miss].
const LIGHTNESS_WEIGHT := 10.0
## The eight ways the search below tries, the diagonals included, because the
## valley of a heavy lightness weight runs across both axes at once.
const COMPASS: Array[Vector2] = [
    Vector2(1, 0),
    Vector2(-1, 0),
    Vector2(0, 1),
    Vector2(0, -1),
    Vector2(1, 1),
    Vector2(-1, -1),
    Vector2(1, -1),
    Vector2(-1, 1),
]


## Plain HSL to the sRGB encoding, the textbook formula, which is what a
## classic picker draws and what its painters expect a lightness of a half
## to be.
static func hsl_to_srgb(h: float, s: float, l: float) -> Color:
    var c := (1.0 - absf(2.0 * l - 1.0)) * s
    var base := Color.from_hsv(h, 1.0, 1.0)
    return Color((base.r - 0.5) * c + l, (base.g - 0.5) * c + l, (base.b - 0.5) * c + l, 1.0)


## The sRGB encoding back to plain HSL, as hue, saturation and lightness. The
## hue of a grey is reported as zero and left to the caller, the way the
## engine's own `Color.h` leaves it.
static func srgb_to_hsl(col: Color) -> Vector3:
    var top := maxf(col.r, maxf(col.g, col.b))
    var bottom := minf(col.r, minf(col.g, col.b))
    var l := (top + bottom) * 0.5
    var span := 1.0 - absf(2.0 * l - 1.0)
    var s := (top - bottom) / span if span > 1e-6 else 0.0
    return Vector3(col.h, clampf(s, 0.0, 1.0), clampf(l, 0.0, 1.0))


## The HSV triangle's corner weights for a point in the area's unit square:
## how much of the hue, of white and of black it is, as `[hue, white, black]`.
## Off the triangle a weight goes negative, which is what the drag clamps.
static func triangle_weights(uv: Vector2) -> Vector3:
    var v0 := TRI_WHITE - TRI_HUE
    var v1 := TRI_BLACK - TRI_HUE
    var v2 := uv - TRI_HUE
    var d00 := v0.dot(v0)
    var d01 := v0.dot(v1)
    var d11 := v1.dot(v1)
    var d20 := v2.dot(v0)
    var d21 := v2.dot(v1)
    var denom := d00 * d11 - d01 * d01
    var white := (d11 * d20 - d01 * d21) / denom
    var black := (d00 * d21 - d01 * d20) / denom
    return Vector3(1.0 - white - black, white, black)


## The point in the area's unit square where the HSV triangle shows
## saturation *s* at value *v*: value is what is not black, and saturation is
## the hue's share of the rest, so the weights are the three products.
static func triangle_point(s: float, v: float) -> Vector2:
    var hue_w := s * v
    var white_w := v * (1.0 - s)
    var black_w := 1.0 - v
    return TRI_HUE * hue_w + TRI_WHITE * white_w + TRI_BLACK * black_w


## **Keep chroma on a classic shape.** The saturation and value of the
## colour at HSV hue *h* whose Oklab lightness and chroma are nearest *kept*,
## given as lightness then chroma, by the measure of [method lc_miss].
##
## The hue is the pointer's and stays it, so the ring's cursor never leaves the
## pointer, and only the point in the area moves. One HSV hue is not one Oklab
## hue, so its plane may not hold the kept pair, and then the answer is the
## nearest it does hold, which on a narrow hue is a point on the area's edge.
## The HSL square asks the same and reads its own two axes off the colour,
## because one hue's plane holds the same colours in either model and HSL's
## has a crease at a lightness of a half that stalls the search.
##
## A compass search from *start*, halving its step down to a hundred
## thousandth: in saturation and value the colour is smooth and the distance
## has one valley over the plane. The kept pair itself is a point of distance
## nought, so a turn back to the first hue finds the first colour.
static func nearest_to_lc(h: float, kept: Vector2, start: Vector2) -> Vector2:
    var at := start.clamp(Vector2.ZERO, Vector2.ONE)
    var here := lc_miss(h, at, kept)
    var step := 0.125
    while step > 1e-5:
        var moved := false
        for dir: Vector2 in COMPASS:
            var next := (at + dir * step).clamp(Vector2.ZERO, Vector2.ONE)
            var there := lc_miss(h, next, kept)
            if there < here:
                at = next
                here = there
                moved = true
        if not moved:
            step *= 0.5
    return at


## How far the colour of HSV hue *h* at saturation and value *sv* is from
## *kept*, with a miss in lightness worth [constant LIGHTNESS_WEIGHT] times one
## in chroma. The Oklab shapes hold the lightness and give up chroma where the
## gamut is narrow, and so does this, or a pale yellow turned to cyan would
## grow darker to keep its chroma.
static func lc_miss(h: float, sv: Vector2, kept: Vector2) -> float:
    var lch := OkhslConversionsScript.srgb_to_oklch(Color.from_hsv(h, sv.x, sv.y))
    return Vector2((lch.z - kept.x) * LIGHTNESS_WEIGHT, lch.y - kept.y).length()
