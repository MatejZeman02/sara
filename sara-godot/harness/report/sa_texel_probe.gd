## The `texel` step's readback: a document-space point read back off the GPU,
## the active layer's own value and the canvas's composited one, so a scenario
## asserts a number rather than a screenshot.
##
## **The one readback hard rule 1 permits**, which is why it is a step at all and
## why its answer is remembered rather than printed. The other way to read a
## few values is exporting a 32-bit float TIFF and parsing it in a script, tens
## of megabytes of proof for a handful of numbers. This is the readback the
## eyedropper already does at a click, `pick_color_at_pos` in
## `modules/sara-base-modules/base/tools/state_eyedropper.gd`, run from a
## scenario step instead.
##
## A class of its own rather than a fourth sibling of the state dump carrying its
## name and a suffix, or a bag of statics taking the runner back as a first
## argument. It reports no block of its own: the answer is
## left on the run as `last_texel` and the state report folds it in, the way
## `last_save` already is.
##
## Held by the step table like the drivers, rather than built per step by the
## runner with the runner handed in, which would be a back reference. The one-pixel `SaTexture` it copies through is
## still made per point and dropped with it (hard rule 4), so holding the probe
## holds nothing on the GPU.
##
## Reached by path from the table, not by class name, so no editor rescan stands
## between a fresh checkout and a capture.
extends RefCounted

class_name SaTexelProbe

## The canvas the points are read off. By path, the way the table reaches this
## file.
const CanvasDriver := preload("res://harness/drivers/sa_canvas_driver.gd")
const CaptureRun := preload("res://harness/sa_capture_run.gd")

## The run this reads for. Its tree is what the main canvas is found in, and its
## `last_texel` is where the answer is left for the dump.
var _run: CaptureRun = null


func _init(run: CaptureRun) -> void:
    _run = run


## Reads two colours at document points: at each of `[[x, y], ...]`.
##
## One line is printed so a run log carries the numbers without a JSON file open
## beside it.
##
## The one place hard rule 1 permits a read back off the GPU, which is why it is
## a step at all and why its answer is remembered on the run rather than only
## printed.
func read(points: Array) -> Array:
    var canvas := CanvasDriver.main_canvas()
    var doc: SaDocument = canvas.document if canvas != null else null
    var out: Array = []
    for entry: Variant in points:
        var pos := Vector2i(int(entry[0]), int(entry[1]))
        out.append(_read_point(doc, canvas, pos))
    print("SaCapture: texel %s" % JSON.stringify(out))
    _run.last_texel = out
    return out


## One point's answer, both colours null when there is nothing to read: no
## document, or the point is off the canvas.
##
## **`layer` is straight alpha and `composited` is the flattened stack**, which is
## two answers to two questions and was filed as one wrong answer. A texel
## inside a Cut reads alpha zero with its colour still in `r`, `g` and `b`, because
## `cut_masked.gmacs` scales the alpha and keeps the colour the way the eraser
## does, and `composited` at the same point reads the ground because a texel with
## no alpha contributes nothing. A reader comparing the two colours and not their
## alphas sees a stale layer that is not there.
##
## Static because it needs no runner and the suite grades it without one: it is
## the arithmetic under [method read], and a fixture can hand it a document and a
## canvas that never entered a tree.
static func _read_point(doc: SaDocument, canvas: SaCanvas, pos: Vector2i) -> Dictionary:
    var result := {"x": pos.x, "y": pos.y, "layer": null, "composited": null}
    if doc == null:
        return result
    var doc_size: Vector2i = doc.canvas_size
    if pos.x < 0 or pos.x >= doc_size.x or pos.y < 0 or pos.y >= doc_size.y:
        return result
    var layer := doc.active_layer
    if layer != null:
        # The grid is in document pixels, 256 of them to a chunk whatever its
        # scale, and the texel under the point is found in the chunk's own
        # texels (hard rule 3).
        var grid := Vector2i(int(floor(pos.x / float(layer.CHUNK_SIZE))), int(floor(pos.y / float(layer.CHUNK_SIZE))))
        var local := pos - grid * layer.CHUNK_SIZE
        var chunk: SaChunk = layer.chunks.get(grid, null)
        # The albedo field, the same one the eyedropper reads: a layer whose
        # colour is derived has already resolved it, so this is the pixel the
        # compositor paints rather than the concentrations behind it.
        var albedo := layer.get_field(grid)
        if albedo != null:
            var refused := _unplaced(chunk, albedo)
            if refused.is_empty():
                result["layer"] = _color(_read_pixel(albedo, _texel_under(chunk, local)))
                # Texels across the chunk read, 512 on a double resolution layer.
                result["texels"] = chunk.pixel_size()
            else:
                result["unplaced"] = refused
        # The coverage of the layer's mask, one where it holds nothing, and
        # absent from the answer for a layer that has no mask.
        if layer.mask != null:
            var coverage := layer.mask.texture_for(grid)
            # A mask of its own keeps its chunks, and a mask in the field
            # form is a field of the layer's chunk, whose `chunks` it leaves
            # empty.
            var cover_chunk: SaChunk = layer.mask.chunks.get(grid, chunk)
            result["mask"] = 1.0
            if coverage != null and _unplaced(cover_chunk, coverage).is_empty():
                result["mask"] = _read_pixel(coverage, _texel_under(cover_chunk, local)).r
        # The thickness, zero where the chunk holds none, and absent for a
        # layer that carries no height.
        if layer.carries_height():
            var height := layer.get_field(grid, SaFieldSpec.HEIGHT)
            result["height"] = 0.0
            if height != null and _unplaced(chunk, height).is_empty():
                result["height"] = _read_pixel(height, _texel_under(chunk, local)).r
    if canvas != null and canvas.easel != null:
        # The picture at the point, where the window may have left it held.
        canvas.easel.flush(Rect2i(pos, Vector2i.ONE))
    var composited: SaTexture = canvas.easel.output if canvas != null and canvas.easel != null else null
    if composited != null:
        result["composited"] = _color(_read_pixel(composited, pos))
    if canvas != null and canvas.is_inside_tree():
        result["displayed"] = _displayed(canvas, doc_size, pos)
    return result


## The texel of *chunk* under the document pixel at *local*, its offset from
## the chunk's corner in document pixels.
##
## A chunk covers 256 document pixels and holds `pixel_size()` texels across
## them, 512 at a scale of 2.0 and 128 at 0.5. The pixel's centre is what is
## placed, so on a double layer the answer is the lower right of the pixel's
## four texels and on a half layer the one texel the pixel shares with three
## others, rather than the local offset read as a texel, which on a double
## layer is the texel of the point halfway to the chunk's corner.
static func _texel_under(chunk: SaChunk, local: Vector2i) -> Vector2i:
    var edge := chunk.pixel_size()
    var per_pixel := float(edge) / float(SaChunk.SIZE)
    var at := ((Vector2(local) + Vector2(0.5, 0.5)) * per_pixel).floor()
    return Vector2i(clampi(int(at.x), 0, edge - 1), clampi(int(at.y), 0, edge - 1))


## Why *texture* cannot be read as *chunk*'s field, or empty when it can.
##
## A chunk that is missing, or whose texture is not the `pixel_size()` its
## scale names, has no texel the probe can put under a document point, and a
## guess would answer for another point. The answer
## names the scale so a walk sees which layer it read.
static func _unplaced(chunk: SaChunk, texture: SaTexture) -> String:
    if chunk == null:
        return "no chunk holds the texture"
    if texture.size != Vector2i(chunk.pixel_size(), chunk.pixel_size()):
        var words := "a chunk at scale %s holds %d texels across, its texture %d"
        return words % [chunk.resolution_scale, chunk.pixel_size(), texture.size.x]
    return ""


## What the window shows at *pos*, off the frame it last drew, or null off the
## frame.
##
## The stored texel after the view's whole chain: the document's gamut into
## linear sRGB, the proof, the display profile and the curve. A soft proof moves
## this and moves neither of the two above, so it is the only one of the three
## that can say a proof did something. Eight bits, because the frame is.
static func _displayed(canvas: SaCanvas, doc_size: Vector2i, pos: Vector2i) -> Variant:
    var viewport := canvas.get_viewport()
    var frame := viewport.get_texture().get_image() if viewport != null else null
    if frame == null:
        return null
    var local := (Vector2(pos) + Vector2(0.5, 0.5)) * canvas.size / Vector2(doc_size)
    var at := Vector2i((viewport.get_final_transform() * (canvas.get_global_transform_with_canvas() * local)).floor())
    if at.x < 0 or at.y < 0 or at.x >= frame.get_width() or at.y >= frame.get_height():
        return null
    return _color(frame.get_pixelv(at))


## One texel off *source*, copied through a one-pixel readback texture the way
## `state_eyedropper.gd`'s own `_read_pixel` does.
static func _read_pixel(source: SaTexture, at: Vector2i) -> Color:
    if source == null or not source.rid.is_valid():
        return Color.TRANSPARENT
    var rd := GlobalShaderCompiler.get_rd()
    var readback := SaTexture.new(Vector2i.ONE, source.format)
    rd.texture_copy(source.rid, readback.rid, Vector3(at.x, at.y, 0), Vector3.ZERO, Vector3.ONE, 0, 0, 0, 0)
    var data := rd.texture_get_data(readback.rid, 0)
    if data.size() < SaFieldSpec.BYTES_PER_TEXEL.get(source.format, 0):
        return Color.TRANSPARENT
    return SaFieldSpec.decode_texel(data, source.format)


## Prints the height span: the lowest and highest height the main document's
## active layer holds, and how many texels stand below *under* millimetres,
## printed rather than remembered because a scenario reads it off the run log
## beside the shot it explains.
func height_span(under: float) -> String:
    var doc := _run.main_document()
    if doc == null or doc.active_layer == null:
        return "SaCapture: no active layer to read"
    var lowest := INF
    var highest := -INF
    var lowered := 0
    for grid: Vector2i in doc.active_layer.chunks:
        var height := doc.active_layer.get_field(grid, SaFieldSpec.HEIGHT)
        if height == null:
            continue
        var bytes := GlobalShaderCompiler.get_rd().texture_get_data(height.rid, 0)
        for i in height.size.x * height.size.y:
            var value := bytes.decode_half(i * 2)
            lowest = minf(lowest, value)
            highest = maxf(highest, value)
            lowered += 1 if value < under else 0
    return "SaCapture: height from %.4f to %.4f, %d texels below %s mm" % [lowest, highest, lowered, under]


static func _color(c: Color) -> Dictionary:
    return {"r": c.r, "g": c.g, "b": c.b, "a": c.a}
