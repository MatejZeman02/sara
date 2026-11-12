## The test recipe of the drawn layer's suite: one rectangle of one colour,
## drawn through `SaVectorFill` at its exact coverage, the smallest recipe a
## module could register. It keeps every region it was asked to draw and
## every tile the kernel dispatched for it, so the suite reads what a redraw
## touched.
@tool
extends SaDrawnRecipe

## Where the rectangle stands, in document pixels.
var rect := Rect2(200.5, 40.5, 100.0, 60.0)
## Its colour in the document's space, alpha its opacity.
var paint := Color(0.9, 0.2, 0.1, 1.0)
## Every region [method draw] was handed, in document pixels.
var drawn: Array[Rect2i] = []
## Every tile the kernel dispatched, in document pixels.
var tiles: Array[Rect2i] = []

var _fill := SaVectorFill.new()


## The rectangle's pixels and one more each way, its edge.
func bounds() -> Rect2i:
    var start := Vector2i(floori(rect.position.x), floori(rect.position.y)) - Vector2i.ONE
    var end := Vector2i(ceili(rect.end.x), ceili(rect.end.y)) + Vector2i.ONE
    return Rect2i(start, end - start)


func draw(region: Rect2i, chunk: SaChunk) -> void:
    drawn.append(region)
    _fill.draw_region(chunk, region, SaVectorPath.rectangle(rect), paint)
    tiles.append_array(_fill.drawn_tiles)


## Moves the rectangle's corner to *at*, which an edit does through
## `SaDrawnLayer.edit`, and says what it touched.
func move_to(at: Vector2) -> void:
    var before := bounds()
    rect.position = at
    var touched: Array[Rect2i] = [before, bounds()]
    changed.emit(touched)


func to_json() -> Dictionary:
    return {
        "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
        "paint": [paint.r, paint.g, paint.b, paint.a],
    }


func from_json(saved: Dictionary) -> void:
    var r: Array = saved.get("rect", [])
    var p: Array = saved.get("paint", [])
    if r.size() == 4:
        rect = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
    if p.size() == 4:
        paint = Color(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
