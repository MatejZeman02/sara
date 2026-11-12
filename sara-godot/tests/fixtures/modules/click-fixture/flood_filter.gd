## A filter that floods from the pixel clicked in its preview.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The shape of an area aware fill: a dialog with a click, not a tool. The
## preview reports the pixel clicked and the filter reruns from it. `ui.click(&"seed")` asks the
## dialog's picture for the click, and `run` reads the seed like any other
## parameter, through the CPU door, the loop a student single-steps.
##
## A four-way flood over the texels whose colour lies within the tolerance of
## the seed's, each painted in the fill colour. Before the first click the seed
## is `(-1, -1)`, outside every layer, and the run shows the layer as it is.
extends SaFilter

## How many runs flooded, and the seed the last of them read, so a suite reads
## the run that followed a click.
var floods: int = 0
var last_seed: Vector2i = Vector2i(-1, -1)


func title() -> String:
    return "Flood from click"


func sentence() -> String:
    return "Fill the area around the pixel clicked in the preview with one colour."


## The picture is declared and named, so the door's `filter` step reaches it
## as `{"widget": "picture", "click": [x, y]}`. A filter that declares none is
## given one after its rows, which answers a click the same way.
func build(ui: SaDialog) -> void:
    ui.click(&"seed")
    ui.slider("Tolerance", 0.0, 1.0, 0.2, {"step": 0.01, "decimals": 2})
    ui.color("Fill", Color(0.9, 0.2, 0.1, 1.0))
    ui.thumbnail().named(&"picture")


func run(ctx: SaFilterContext) -> void:
    var pixels := ctx.read_pixels(0)
    if pixels == null:
        return
    var held: Array = parameter(&"seed")
    var clicked := Vector2i(int(held[0]), int(held[1]))
    var start := clicked - ctx.rect.position
    if Rect2i(Vector2i.ZERO, pixels.get_size()).has_point(start):
        floods += 1
        last_seed = clicked
        print("Flood from click: floods from %s over %s" % [clicked, ctx.rect])
        flood(pixels, start, float(parameter(&"tolerance")), parameter(&"fill") as Color)
    ctx.write_pixels(pixels)


## Paints *fill* over every texel of *pixels* joined to *start*, left, right,
## up or down, through texels within *tolerance* of the colour at *start* in
## every channel.
static func flood(pixels: Image, start: Vector2i, tolerance: float, fill: Color) -> void:
    var size := pixels.get_size()
    var wanted := pixels.get_pixelv(start)
    var seen := PackedByteArray()
    seen.resize(size.x * size.y)
    seen[start.y * size.x + start.x] = 1
    var waiting: Array[Vector2i] = [start]
    while not waiting.is_empty():
        var at: Vector2i = waiting.pop_back()
        pixels.set_pixelv(at, fill)
        for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
            var next := at + step
            if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
                continue
            var index := next.y * size.x + next.x
            if seen[index] == 1:
                continue
            seen[index] = 1
            if _near(pixels.get_pixelv(next), wanted, tolerance):
                waiting.append(next)


static func _near(colour: Color, wanted: Color, tolerance: float) -> bool:
    return (
        absf(colour.r - wanted.r) <= tolerance
        and absf(colour.g - wanted.g) <= tolerance
        and absf(colour.b - wanted.b) <= tolerance
        and absf(colour.a - wanted.a) <= tolerance
    )
