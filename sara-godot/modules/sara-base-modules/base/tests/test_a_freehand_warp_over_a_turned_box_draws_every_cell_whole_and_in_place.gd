## A Freehand warp over a box the transform tool has turned. Each cell of the
## at-rest grid over a turned quad is a parallelogram up to float32 rounding,
## and the kernel's inverse bilinear has to read it as one: the plain
## quadratic formula took the difference of two numbers of the cell's area
## that agree to within its tiny twist, and left holes and slid pictures in
## every cell a drag did not reach.
##
## The picture lifted is a gradient whose red and green are the texel's own
## place in the box, so a texel the pass draws says where it read from, and a
## blank one is a hole.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const SIDE := 800
const BOX := Rect2i(400, 400, SIDE, SIDE)
const CANVAS := Vector2i(1600, 1600)
## How far from where it belongs a drawn texel may have read, in texels of
## the box. The pass reads bilinearly between texel centres and a linear
## gradient comes out of that exact, so what is left is float32 rounding of a
## place some hundreds of texels out, measured at 0.0004 texels on the GPU this
## was written on. A twentieth of a texel leaves room for another GPU's
## rounding and is still thousands of times finer than the slide this
## test guards against.
const PLACE_BOUND := 0.05


func _gradient() -> Image:
    var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBAF)
    for y in SIDE:
        for x in SIDE:
            image.set_pixel(x, y, Color((x + 0.5) / SIDE, (y + 0.5) / SIDE, 0.0, 1.0))
    return image


func _turned(angle_degrees: float) -> PackedVector2Array:
    var centre := Vector2(BOX.get_center())
    var out := PackedVector2Array()
    for corner: Vector2 in SaHomography.corners_of(BOX):
        out.append(centre + (corner - centre).rotated(deg_to_rad(angle_degrees)))
    return out


## The chunks' texels read back once each, keyed by the chunk's place.
class Readback:
    var pixel := 0
    var texel_bytes := 0
    var _data: Dictionary[Vector2i, PackedByteArray] = {}
    var _layer: SaLayer

    func _init(layer: SaLayer) -> void:
        _layer = layer

    func color_at(at: Vector2i) -> Color:
        if pixel == 0:
            for chunk: SaChunk in _layer.chunks.values():
                pixel = chunk.pixel_size()
                break
        if pixel == 0:
            return Color(0, 0, 0, 0)
        var grid_pos := Vector2i(floori(float(at.x) / pixel), floori(float(at.y) / pixel))
        if not _data.has(grid_pos):
            var chunk: SaChunk = _layer.chunks.get(grid_pos, null)
            var device := GlobalShaderCompiler.get_rd()
            _data[grid_pos] = PackedByteArray() if chunk == null else device.texture_get_data(chunk.albedo().rid, 0)
        var data: PackedByteArray = _data[grid_pos]
        if data.is_empty():
            return Color(0, 0, 0, 0)
        @warning_ignore("integer_division")
        texel_bytes = data.size() / (pixel * pixel)
        var local := at - grid_pos * pixel
        var offset := (local.y * pixel + local.x) * texel_bytes
        var out := Color()
        for channel in 4:
            if texel_bytes == 16:
                out[channel] = data.decode_float(offset + channel * 4)
            else:
                out[channel] = data.decode_half(offset + channel * 2)
        return out


## Lifts the gradient, lays *mesh* over it and draws the pass, answering the
## easel, which the caller frees, and the layer the pass drew on.
func _warp(mesh: PackedVector2Array) -> Array:
    var easel := SaEasel.create_default(CANVAS)
    var document := easel.document
    SaImageImport.upload(document, document.active_layer, _gradient(), BOX.position)
    document.selection.select_rect(BOX)
    var moving := SaTransform.new(document)
    assert_true(moving.lift(document.active_layer, BOX), "There is something to lift")
    moving.preview_mesh(mesh)
    assert_true(moving.is_warped(), "and the pass is under a mesh")
    moving.tick()
    return [easel, moving, document.stroke_layer]


## The place in the box, in texels from its top left, that the turned square
## carries to the document texel *at*, by turning back about the centre.
func _home_of(at: Vector2i, angle_degrees: float) -> Vector2:
    var centre := Vector2(BOX.get_center())
    var world := Vector2(at) + Vector2(0.5, 0.5)
    return centre + (world - centre).rotated(-deg_to_rad(angle_degrees)) - Vector2(BOX.position)


## The texels the turned square can reach, a texel wider on each side.
func _reach(angle_degrees: float) -> Rect2i:
    var corners := _turned(angle_degrees)
    var low := corners[0]
    var high := corners[0]
    for corner: Vector2 in corners:
        low = low.min(corner)
        high = high.max(corner)
    return Rect2i(Vector2i(low.floor()) - Vector2i.ONE, Vector2i((high - low).ceil()) + Vector2i(3, 3))


func _blank_inside(angle_degrees: float) -> int:
    var parts := _warp(SaTransformMesh.grid_over(_turned(angle_degrees)))
    var read := Readback.new(parts[2])
    var reach := _reach(angle_degrees)
    var blank := 0
    for y in range(reach.position.y, reach.end.y):
        for x in range(reach.position.x, reach.end.x):
            var home := _home_of(Vector2i(x, y), angle_degrees)
            if home.x < 1.0 or home.y < 1.0 or home.x > SIDE - 1.0 or home.y > SIDE - 1.0:
                continue
            if read.color_at(Vector2i(x, y)).a < 0.99:
                blank += 1
    parts[1].cancel()
    (parts[0] as SaEasel).free()
    return blank


func test_the_at_rest_grid_over_a_square_turned_seven_degrees_leaves_no_hole() -> void:
    assert_eq(_blank_inside(7.0), 0, "No texel inside the square turned 7 degrees is blank")


func test_the_at_rest_grid_over_a_square_turned_twenty_five_degrees_leaves_no_hole() -> void:
    assert_eq(_blank_inside(25.0), 0, "No texel inside the square turned 25 degrees is blank")


func test_a_dragged_corner_leaves_the_cell_across_from_it_where_it_was() -> void:
    var angle := 7.0
    var mesh := SaTransformMesh.grid_over(_turned(angle))
    mesh[0] += Vector2(-120.0, -60.0)
    var parts := _warp(mesh)
    var read := Readback.new(parts[2])
    var checked := 0
    var blank := 0
    var worst := 0.0
    var half := SIDE / 2.0
    var reach := _reach(angle)
    for y in range(reach.position.y, reach.end.y):
        for x in range(reach.position.x, reach.end.x):
            var home := _home_of(Vector2i(x, y), angle)
            if home.x < half + 1.0 or home.y < half + 1.0 or home.x > SIDE - 1.0 or home.y > SIDE - 1.0:
                continue
            checked += 1
            var color := read.color_at(Vector2i(x, y))
            if color.a < 0.99:
                blank += 1
                continue
            var read_from := Vector2(color.r, color.g) * SIDE
            worst = maxf(worst, (read_from - home).length())
    assert_true(checked > 150000, "The bottom right cell, across from the dragged corner, was read whole (%d texels)" % checked)
    assert_eq(blank, 0, "none of it is blank")
    assert_true(worst <= PLACE_BOUND, "and every texel holds what it held before the drag, the worst %.4f texels off" % worst)
    parts[1].cancel()
    (parts[0] as SaEasel).free()
