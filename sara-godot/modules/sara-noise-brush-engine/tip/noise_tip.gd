## The noise brush's tip as one point of the stroke takes it: stretched along
## the pen's lean, the generator its box is cut by, and how far past the
## nearest point of the path it reaches.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Out of the stroke's state, beside the rows that load a tip.** The tip's
## arithmetic sits with the Tip row of `tip_row.gd` rather than in
## `state_noise_brush.gd`, so the tip is read in one place. Static, because
## every answer here is the tip's own numbers and the state holds what changes
## over a stroke.
extends RefCounted

const NoiseBrushSettingsScript = preload("res://modules/sara-noise-brush-engine/noise_brush_settings.gd")

## How far a tip's two half extents may differ, as a share of the larger, and
## the tip still count as round, and the pixels a non-round tip's reach is
## given beyond its half extents for the antialiased rim.
const ROUND_EPSILON: float = 0.01
const REACH_MARGIN: float = 2.0


## The tip of *half_extent* turned by *radians*, stretched along the lean of a
## pen tilted by *tilt* degrees by *amount* of
## [constant NoiseBrushSettingsScript.TILT_STRETCH], answered as its new half
## extent in x and y and its new angle in z.
##
## The stretch is a linear map, one plus the amount along the lean and one
## across it, and the tip it makes is the kernel's ellipse or box again: the
## map times the tip's own is split into a turn, two radii and a second turn,
## and the radii and the first turn are the new tip. Exact for an ellipse,
## whose shape the second turn cannot change, and the nearest box for a box.
## The axis that was the longer stays the tip's x or y as it was, so a tip
## under no stretch comes back as it went in.
##
## **A tip that *shows_angle* keeps it**. The split's first turn is the lean's
## own line for a square picture, so without this an image tip turns with the
## pen's azimuth under a lean rather than staying where the painter set it. A
## tip whose angle shows, as [method shows_angle] answers, comes back at
## *radians* unchanged, its radii the lengths the leaned map gives its own two
## axes. A round tip keeps the ellipse along the lean, since a circle has no
## angle to lose.
static func stretch(half_extent: Vector2, radians: float, tilt: Vector2, amount: float, keeps_angle: bool = false) -> Vector3:
    if amount <= 0.0 or tilt.length() < 0.001:
        return Vector3(half_extent.x, half_extent.y, radians)
    var lean := tilt.normalized()
    var grow := amount * NoiseBrushSettingsScript.TILT_STRETCH
    if keeps_angle:
        var own := lean.rotated(-radians)
        return Vector3(half_extent.x * (1.0 + grow * own.x * own.x), half_extent.y * (1.0 + grow * own.y * own.y), radians)
    # The tip's own map, a turn of its radii, then the stretch along the lean.
    var turn := Transform2D(radians, Vector2.ZERO)
    var tip := Transform2D(turn.x * half_extent.x, turn.y * half_extent.y, Vector2.ZERO)
    var along := Transform2D(
        Vector2(1.0 + grow * lean.x * lean.x, grow * lean.x * lean.y),
        Vector2(grow * lean.x * lean.y, 1.0 + grow * lean.y * lean.y),
        Vector2.ZERO
    )
    if keeps_angle:
        return Vector3((along * tip.x).length(), (along * tip.y).length(), radians)
    var map := along * tip
    # The two by two split: a is x.x, b is y.x, c is x.y and d is y.y.
    var e := 0.5 * (map.x.x + map.y.y)
    var f := 0.5 * (map.x.x - map.y.y)
    var g := 0.5 * (map.x.y + map.y.x)
    var h := 0.5 * (map.x.y - map.y.x)
    var q := sqrt(e * e + h * h)
    var r := sqrt(f * f + g * g)
    var angle := 0.5 * (atan2(h, e) + atan2(g, f))
    var major := q + r
    var minor := absf(q - r)
    var radii := Vector2(major, minor)
    if half_extent.y > half_extent.x:
        radii = Vector2(minor, major)
        angle -= 0.5 * PI
    # A half turn is the same box, so the one nearest the tip's own angle is
    # taken, and a picture tip is never flipped over by a slight lean.
    angle += PI * roundf((radians - angle) / PI)
    return Vector3(radii.x, radii.y, angle)


## The generator *tip*'s box is cut by, when the kernel paints it with
## *generator*. The door boxes an ellipse for every generator but the image's,
## whose rectangle it boxes by its corners, and a rectangle tip fills one as
## well, so turned it reaches past the ellipse's box and would be clipped there.
static func box_generator(tip: Resource, generator: int) -> int:
    if tip.shape != 0:
        return SaDabGeometry.Generator.IMAGE
    return generator


## How far *tip* at *half_extent* reaches from its centre in pixels when what
## it gives a texel is the greatest over the path and not the nearest point's,
## and nought for a round tip, whose coverage is the same either way. A box, an
## image and an ellipse are not round, and the margin is the antialiased rim.
static func reach(tip: Resource, generator: int, half_extent: Vector2) -> float:
    if not shows_angle(tip, generator, half_extent):
        return 0.0
    return half_extent.length() + REACH_MARGIN


## Whether *tip* at *half_extent*, painted with *generator*, shows the angle it
## is turned by: a picture, a rectangle, or an ellipse whose two half extents
## differ, and not a circle, which looks the same at every angle.
static func shows_angle(tip: Resource, generator: int, half_extent: Vector2) -> bool:
    if tip.shape != 0 or generator == SaDabGeometry.Generator.IMAGE:
        return true
    return absf(half_extent.x - half_extent.y) > ROUND_EPSILON * maxf(half_extent.x, half_extent.y)
