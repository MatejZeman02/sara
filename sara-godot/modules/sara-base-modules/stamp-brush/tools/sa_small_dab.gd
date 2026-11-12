## How a dab under the pixel mode's size is drawn, for a brush that enters the
## mode and for one that stays out of it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A pen enters the mode and a brush does not.** A brush whose Sharpness row
## stands at one, every texel opaque or clear and every centre on the grid, is
## drawn exactly as `SaDabGeometry` draws a small dab: under three pixels across
## it snaps to the grid and paints whole texels, a single-pixel editor, and
## Inked Pen is that pen. Every other brush draws a thin line antialiased,
## because whole texels at a shallow slope are runs of equal pixels stepping a
## row at a time, the comb an Eraser at radius 0.8 to 1.25 would draw. A preset can
## refuse the mode outright with `pixel_mode_when_small`, as Fill does, whose
## painter asks for a dash twice its radius tall at every radius.
##
## **Out of the mode is not enough on its own.** A hard dab's antialiasing ramp
## lies inside its rim, `brush_tip.gmacs` measuring the edge a pixel in from it,
## so a dab draws a little thinner than its radius, and a thin one most of all,
## where the ramp is most of the dab. A horizontal Fill dash a third of a texel
## off a row's centre lays about two thirds of the rows its radius asks at
## radius 0.5, and climbs towards the full count as the radius grows. So a dab
## out of the mode is drawn a little wider than asked, by [constant GROWTH] in
## pixels of radius, and the growth falls away from the mode's edge to nothing
## at [constant GROWTH_GONE_AT].
##
## The four places the mode is entered all ask here or read the same switch,
## the centre's snap, the drawn size, the push constant's threshold and the
## walk's step, because the step is measured off the drawn size and none of
## the four may disagree with the others. All four read the Sharpness row, not
## a dab's own, so no dab of a stroke enters the mode alone.
class_name SaSmallDab
extends RefCounted

## How much wider than asked a dab out of the mode is drawn, in pixels of
## radius, up to the mode's edge.
##
## An eighth, measured on the real brush and the real GPU against the same dash
## laid at four heights within a texel. A tenth leaves the smallest radius
## visibly short of its rows and three twentieths overshoots the larger ones,
## and an eighth holds every radius from 0.5 to 1.5 within a few per cent of
## twice its radius. A dash centred on a row at radius 0.5 stays the worst case
## whatever the growth, because the whole dab lands on one row and the ramp has
## nowhere else to put its share.
const GROWTH: float = 0.125

## The radius the growth begins to fall away at, the mode's own edge. A dash
## three pixels tall is radius 1.5, so it is the last one drawn at the whole
## growth.
const GROWTH_FULL_UNTIL: float = SaDabGeometry.PIXEL_MODE_DIAMETER * 0.5

## The radius the growth is gone at, in pixels, so a Fill from here up is drawn
## at exactly the size asked, which is what a painter wants of every radius
## above the small dashes.
##
## Half a pixel above the mode's edge rather than at it. A growth that stopped
## at 1.5 would draw the line a quarter row thinner the moment the size passed
## 1.5, and a painter dragging Size up would see it narrow. Over half a pixel
## the line still widens at three quarters of the rate it did, and by radius 2
## the dab is the one the size asks for.
const GROWTH_GONE_AT: float = 2.0

## The Sharpness row a brush is a pen at, and from which it enters the mode.
const PEN_SHARPNESS: float = 1.0


## Whether *settings* enters the pixel mode under its size on a layer of
## *density* texels to a document pixel, a pen unless its preset refuses the
## mode. A `Resource`, because the tool's own default is the older
## `brush_settings.gd`, which has no Sharpness row and so is no pen.
##
## **A layer finer than the document never enters it.** The mode snaps to the
## document's pixels and paints one of them under three across, which a plain
## layer shows as the one texel it has there. On a double resolution layer the
## same snap put the centre between two texels and the binarised dab took one
## or two whole document pixels by where its size fell, so a pen at radius 1.2
## laid a line twice as heavy as on a plain layer, and one at radius 0.8 a
## quarter lighter than asked. Out of the mode the dab keeps its binarised edge
## on the finer texels and lays the width its size asks.
static func enters_mode(settings: Resource, density: float = 1.0) -> bool:
    if density > 1.0:
        return false
    if "pixel_mode_when_small" in settings and not bool(settings.get(&"pixel_mode_when_small")):
        return false
    return "sharpness" in settings and float(settings.get(&"sharpness")) >= PEN_SHARPNESS


## The diameter the pixel mode is asked about for a dab of *diameter*: the dab's
## own for a brush that enters it, and the "did not say" of `SaDabGeometry`
## for one that stays out, which keeps the Sharpness row the whole answer.
static func mode_diameter(settings: Resource, diameter: float, density: float = 1.0) -> float:
    return diameter if enters_mode(settings, density) else -1.0


## The diameter a dab of *diameter* document pixels is drawn at: the mode's
## floor for a brush in it, and the growth for one out of it.
static func drawn_diameter(settings: Resource, diameter: float, density: float = 1.0) -> float:
    if enters_mode(settings, density):
        return SaDabGeometry.drawn_diameter(diameter)
    var radius := diameter * 0.5
    var share := clampf((GROWTH_GONE_AT - radius) / (GROWTH_GONE_AT - GROWTH_FULL_UNTIL), 0.0, 1.0)
    return diameter + 2.0 * GROWTH * share


## *center* pulled towards the document's pixel grid by
## `SaDabGeometry.snap_to_pixels` with *sharpness* and the pixel mode's
## *diameter*, on a layer of *density* texels to a document pixel.
##
## **A finer layer is not snapped.** A sharp dab is binarised at its half
## coverage contour, so where its centre sits decides how many whole texels it
## lays across a line, and a snapped centre always sits at the same place. On a
## plain layer that place is a texel's centre, the pixel editor a pen is. On a
## layer at 2.0 the document's pixel centres lie on the seam between two
## texels, so a snapped dab lays a whole document pixel or two and never what
## lies between, and the texel centres of its own grid give one and a half or
## two and a half. Measured at radius 0.8 to 2 either is up to a fifth off the
## width asked. Left where the pen put it, the binarised dab covers more texels
## at one place and fewer at the next, and the line averages to its width with
## the finer texels as its edge.
static func snap(center: Vector2, sharpness: float, diameter: float, density: float) -> Vector2:
    if density > 1.0:
        return center
    return SaDabGeometry.snap_to_pixels(center, sharpness, diameter)
