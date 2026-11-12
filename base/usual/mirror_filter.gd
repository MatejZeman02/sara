## Filter > Mirror, the paint reflected about a line.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Every texel reads the point its mirror image across the line stands on, so
## what is on one side shows reflected on the other. The line is a point, as a
## percentage of the canvas so a resize keeps it where it was, and an angle in
## degrees, horizontal through the canvas's middle by default. The angle turns
## the line clockwise, since the canvas's y runs down. A fade takes the
## reflection out with its distance from the line, and a tint mixes a colour
## into it, so a reflection can read as water.
##
## **A mirror layer reads paint only.** An effect layer whose first record is
## this filter reads its input's paint alone, not the input's records or its
## mask, so what it reflects is what the painter laid down and not a stack of
## adjustments over it. [method reads_paint_alone] is how the effect layer
## asks, because the skeleton never names a module.
## Anywhere else, attached to a layer or applied once, it reflects what it is
## handed like any filter.
##
## **It reads the whole node and writes the canvas**, as the kaleidoscope does,
## since the reflection of a chunk lands on ground its node never allocated.
## A reflection is not a displacement, so the pass declares where a change lands
## through [member SaNeighbourhoodPass.carries], [method mirrored_boxes], and a
## stroke under it redraws the chunks its reflection touches and nothing else
## (hard rule 2).
extends SaFilter

const SHADER := "sara-base-modules/mirror"
const KERNEL := "mirror"

## The record's values as a fresh dialog opens them: the line through the
## canvas's middle, level, no fade, and a water blue that is not mixed in.
const DEFAULTS := {
    "point_x": 50.0,
    "point_y": 50.0,
    "angle": 0.0,
    "fade": 0,
    "tint": Color(0.35, 0.55, 0.7, 1.0),
    "tint_amount": 0,
}
## How far a typed point may sit off the canvas, as a percentage, so a line can
## run past an edge.
const POINT_REACH := 100.0
## The farthest a typed fade may reach, in document pixels.
const HARD_FADE := 16384


func id() -> StringName:
    return &"mirror"


func title() -> String:
    return "Mirror"


## No: a pixel reads its reflection across the mirror's line, which can be
## anywhere on the layer, so a brush has nothing local to paint.
func can_be_a_brush() -> bool:
    return false


## Listed under Distort in the Filter menu and the browser, beside Wrap Offset
## and Wobble, since it moves paint rather than changing its colour.
func family() -> StringName:
    return &"distort"


func sentence() -> String:
    return "Reflect the picture about a line, the way still water reflects what stands above it."


func build(ui: SaDialog) -> void:
    var point := {"hard_min": -POINT_REACH, "hard_max": 100.0 + POINT_REACH, "suffix": "%"}
    ui.slider("Point X", 0.0, 100.0, DEFAULTS["point_x"], point)
    ui.slider("Point Y", 0.0, 100.0, DEFAULTS["point_y"], point)
    ui.slider("Angle", -180.0, 180.0, DEFAULTS["angle"], {"suffix": "°"})
    ui.slider("Fade", 0, 2048, DEFAULTS["fade"], {"hard_max": HARD_FADE, "suffix": " px"})
    ui.color("Tint", DEFAULTS["tint"])
    ui.slider("Tint amount", 0, 100, DEFAULTS["tint_amount"], {"suffix": "%"})


func run(ctx: SaFilterContext) -> void:
    # The document's space, which `SaFilterContext` leaves its filters to read
    # off the document, so the picked tint is mixed in as the colour it names.
    var space: SaColorSpace = ctx.document.color_space if ctx.document != null else null
    var params := pass_params(parameters(), ctx.canvas_size(), space)
    ctx.neighbourhood_pass(SHADER, KERNEL, params, SaFilterContext.WHOLE_NODE, {}, SaFilterContext.WRITES_CANVAS)
    var recorded := ctx.point as SaNeighbourhoodPass
    if recorded != null:
        recorded.carries = mirrored_boxes.bind(params["point"], params["along"])


## Whether an effect layer whose first record is this filter reads its input's
## paint alone, which `SaEffectLayer` asks of the first record's filter.
func reads_paint_alone() -> bool:
    return true


## The line the painter drags on the canvas, for `SaEffectGuide`: `[point,
## angle]`, the point in document pixels on a canvas of *canvas* pixels and the
## angle in radians, clockwise.
func guide_line(values: Dictionary, canvas: Vector2i) -> Array:
    return [point_of(values, canvas), deg_to_rad(SaTyped.real(values.get("angle"), DEFAULTS["angle"]))]


## *values* with the line moved to *point*, in document pixels, at *angle*, in
## radians, the other half of `SaEffectGuide`'s protocol. The point is kept as
## a percentage of the canvas and the angle in degrees, wrapped to the slider's
## range.
func guide_values(values: Dictionary, canvas: Vector2i, point: Vector2, angle: float) -> Dictionary:
    var moved := values.duplicate(true)
    moved["point_x"] = point.x / float(maxi(canvas.x, 1)) * 100.0
    moved["point_y"] = point.y / float(maxi(canvas.y, 1)) * 100.0
    moved["angle"] = wrapf(rad_to_deg(angle), -180.0, 180.0)
    return moved


## *values*, the record's own units, as the kernel's params on a canvas of
## *canvas* document pixels stored in *space*: the line's point in document
## pixels and its direction as a unit vector, the fade in pixels, and the tint
## in the document's stored values with its amount as a fraction.
static func pass_params(values: Dictionary, canvas: Vector2i, space: SaColorSpace) -> Dictionary:
    var turn := deg_to_rad(SaTyped.real(values.get("angle"), DEFAULTS["angle"]))
    var tint := _colour(values.get("tint", DEFAULTS["tint"]))
    return {
        "point": point_of(values, canvas),
        "along": Vector2(cos(turn), sin(turn)),
        "fade": maxf(SaTyped.real(values.get("fade"), DEFAULTS["fade"]), 0.0),
        "tint": space.from_display(tint) if space != null else tint,
        "tint_amount": clampf(SaTyped.real(values.get("tint_amount"), DEFAULTS["tint_amount"]) / 100.0, 0.0, 1.0),
    }


## The line's point in document pixels on a canvas of *canvas* pixels.
static func point_of(values: Dictionary, canvas: Vector2i) -> Vector2:
    var across := SaTyped.real(values.get("point_x"), DEFAULTS["point_x"]) / 100.0
    var down := SaTyped.real(values.get("point_y"), DEFAULTS["point_y"]) / 100.0
    return Vector2(canvas.x * across, canvas.y * down)


## The document point *at* reflected across the line through *point* along the
## unit vector *along*, the kernel's `mirrored` on the CPU.
static func reflected(at: Vector2, point: Vector2, along: Vector2) -> Vector2:
    var away := at - point
    return point + 2.0 * away.dot(along) * along - away


## Where a change over *area* of the canvas shows once reflected across the
## line through *point* along *along*, for
## [member SaNeighbourhoodPass.carries]. *canvas* is not read, the caller cuts
## to it.
##
## A reflection is its own inverse, so the texels that read *area* are *area*
## reflected, and a rectangle's reflection lies inside the box round its four
## reflected corners. *area* grows by a texel first, because the kernel's read is
## bilinear and a texel is read from as far as one texel off, and the box by two
## more for the difference between the kernel's floats and these.
static func mirrored_boxes(area: Rect2i, _canvas: Vector2i, point: Vector2, along: Vector2) -> Array[Rect2i]:
    var grown := Rect2(area.grow(1))
    var box := Rect2(reflected(grown.position, point, along), Vector2.ZERO)
    for corner: Vector2 in [Vector2(grown.end.x, grown.position.y), grown.end, Vector2(grown.position.x, grown.end.y)]:
        box = box.expand(reflected(corner, point, along))
    var first := Vector2i(box.position.floor()) - Vector2i(2, 2)
    var out: Array[Rect2i] = [Rect2i(first, Vector2i(box.end.ceil()) + Vector2i(2, 2) - first)]
    return out


## *value* as a colour, whether the store handed the colour itself or a record
## read from a file holds its hex.
static func _colour(value: Variant) -> Color:
    if value is Color:
        return value
    var fallback: Color = DEFAULTS["tint"]
    return Color.from_string(str(value), fallback)
