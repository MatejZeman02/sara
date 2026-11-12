## A stroke across the seam lands whole on both sides.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## On a document whose projection wraps in x, `SaPaintContext.for_regions`
## lands a region that crosses the left or right edge also a canvas width the
## other way, each copy folded inside the canvas with its own targets and dirty
## rectangles, and composed with the symmetry's images. A flat document is
## clipped at its edge as it always was. The dabs are read on a canvas whose
## width is a multiple of the chunk's side and on one whose width is not,
## where the last chunk holds an overhang past the edge.
extends "res://tests/test_framework.gd"

## The dabs are real dispatches read back off the GPU.
const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const StateNoiseBrushScript = preload("res://modules/sara-noise-brush-engine/state_noise_brush.gd")
const StateBrushScript = preload("res://modules/sara-base-modules/stamp-brush/tools/state_brush.gd")
const GammaFloatScript = preload("res://modules/sara-base-modules/stamp-brush/tools/gamma_float.gd")

## Twice as wide as tall, and not a whole number of chunks across, so the last
## column of chunks reaches past the right edge.
const ODD := Vector2i(400, 200)
## Twice as wide as tall on the chunk grid, so the right edge is a chunk's.
const EVEN := Vector2i(512, 256)
## The dab's radius in document pixels.
const RADIUS := 24.0
## How far apart the two halves of the seam's dab and the whole dab painted
## in the middle may read. The dab kernel runs at float precision on both, so
## a gap or a second coverage moves a texel by a tenth or more.
const SAME := 0.0005


## The colour *layer* holds at document pixel *at*, clear where no chunk is.
func _texel(layer: SaLayer, at: Vector2i) -> Color:
    var grid := Vector2i(floori(float(at.x) / layer.CHUNK_SIZE), floori(float(at.y) / layer.CHUNK_SIZE))
    var chunk: SaChunk = layer.chunks.get(grid)
    if chunk == null:
        return Color(0.0, 0.0, 0.0, 0.0)
    var texture := chunk.albedo()
    @warning_ignore("integer_division")
    var local := (at - grid * layer.CHUNK_SIZE) * chunk.pixel_size() / layer.CHUNK_SIZE
    var bytes := GlobalShaderCompiler.get_rd().texture_get_data(texture.rid, 0)
    return SaFieldSpec.decode_texel(bytes, texture.format, local.y * texture.size.x + local.x)


## The alpha *layer* holds at document pixel *at*, zero where no chunk is.
func _alpha(layer: SaLayer, at: Vector2i) -> float:
    return _texel(layer, at).a


## A surface of *size* whose document is equirectangular, or flat when *wraps*
## is false.
func _surface(size: Vector2i, wraps: bool) -> SaSurface:
    var surface := Fixtures.make_surface(size)
    # The built-in blend modes, as `main.gd` wires them. A compositor without
    # the registry resolves every mode to Normal, and an eraser, which gathers
    # in the stroke buffer and lands under Erase at the commit since wash became
    # the brush's default, would composite as an ordinary stroke and leave
    # the paint standing.
    surface.easel.compositor.set_registry(Fixtures.make_registries(surface).blend_modes)
    if wraps:
        surface.easel.document.projection = SaProjection.new(SaProjection.Equirectangular.new())
    return surface


## One soft dab at half opacity centred on *at*, in document pixels, so a texel
## two landings covered reads more than one covered once.
func _dab(surface: SaSurface, at: Vector2) -> void:
    (surface.view as Fixtures.FakeView).mouse_position = at
    var brush := StateBrushScript.new()
    brush.surface = surface
    var canvas := surface.easel.document.canvas_size
    brush.settings.radius = RADIUS / mini(canvas.x, canvas.y)
    brush.settings.opacity = 0.5
    brush.settings.opacity_by_pressure = false
    brush.settings.hardness = GammaFloatScript.new(0.3, 1.0)
    brush.settings.stabilizer_amount = 0.0
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    # A press with no pressure reads as a pen's hover, whose dab waits for the
    # first motion, so one motion where the press was lays it.
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    brush.handle_input(motion)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)


## The grid positions of every chunk *layer* holds.
func _grids(layer: SaLayer) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    out.assign(layer.chunks.keys())
    return out


## The context's own targets and dirty rectangles for a region across the
## right edge: the copy lands at the left edge, told how far it moved, and no
## target stands on a chunk past either edge.
func test_a_region_across_the_right_edge_lands_folded_inside_the_canvas() -> void:
    for size: Vector2i in [ODD, EVEN]:
        var surface := _surface(size, true)
        var doc := surface.easel.document
        var centre := Vector2(size.x, 100.0)
        var paint := SaPaintContext.for_region(doc, Rect2(centre - Vector2(20, 20), Vector2(40, 40)), false)
        var left: SaPaintContext.Target = null
        var right: SaPaintContext.Target = null
        for target in paint.targets:
            assert_true(target.grid_pos.x >= 0, "%s: no target stands left of the canvas" % size)
            assert_true(target.grid_pos.x * paint.chunk_size < size.x, "%s: no target stands right of the canvas" % size)
            if target.grid_pos == Vector2i.ZERO:
                left = target
            elif target.grid_pos == Vector2i(floori(float(size.x - 1) / paint.chunk_size), 0):
                right = target
        assert_not_null(left, "%s: the copy lands in the left edge's chunk" % size)
        assert_not_null(right, "%s: the region itself lands in the right edge's chunk" % size)
        if left == null or right == null:
            Fixtures.teardown(surface)
            continue
        assert_eq(left.wrap_offset, Vector2(-size.x, 0.0), "%s: the copy is a canvas width to the left" % size)
        assert_eq(left.local_center, Vector2(0.0, 100.0), "%s: and centred on the left edge" % size)
        assert_eq(right.wrap_offset, Vector2.ZERO, "%s: the region itself did not move" % size)
        assert_eq(paint.targets.size(), 2, "%s: one chunk each side, and none past the edge" % size)
        var dirty: Dictionary = paint._invalidated
        assert_true(dirty.has(Vector2i.ZERO) and dirty.has(right.grid_pos), "%s: each landing has its own dirty rectangle" % size)
        var left_box: Rect2i = dirty.get(Vector2i.ZERO, Rect2i())
        assert_eq(left_box.position.x, 0, "%s: the copy's starts at the left edge" % size)
        assert_true(left_box.end.x <= 32, "%s: and reaches no further than the dab and a workgroup" % size)
        var flat := _surface(size, false)
        var clipped := SaPaintContext.for_region(flat.easel.document, Rect2(centre - Vector2(20, 20), Vector2(40, 40)), false)
        assert_eq(clipped.targets.size(), 1, "%s: a flat document lands the region once" % size)
        assert_false(clipped._invalidated.has(Vector2i.ZERO), "%s: and dirties nothing at the left edge" % size)
        Fixtures.teardown(flat)
        Fixtures.teardown(surface)


## The polar kind wraps in x as the equirectangular one does, and a region
## across the left edge lands its copy a canvas width to the right.
func test_a_polar_document_lands_a_region_across_the_left_edge_at_the_right() -> void:
    var surface := _surface(EVEN, true)
    var doc := surface.easel.document
    doc.projection = SaProjection.new(SaProjection.Polar.new())
    assert_eq(doc.projection.wrapping, SaProjection.Wrap.X, "a polar document wraps in x")
    var paint := SaPaintContext.for_region(doc, Rect2(Vector2(-20, 80), Vector2(40, 40)), false)
    var moved: Array[Vector2] = []
    var grids: Array[Vector2i] = []
    for target in paint.targets:
        moved.append(target.wrap_offset)
        grids.append(target.grid_pos)
    assert_eq(paint.targets.size(), 2, "the region and its copy, and nothing past the left edge")
    assert_true(grids.has(Vector2i.ZERO), "the region itself lands in the left edge's chunk")
    assert_true(grids.has(Vector2i(floori(float(EVEN.x) / paint.chunk_size) - 1, 0)), "its copy in the right edge's chunk")
    assert_true(moved.has(Vector2(EVEN.x, 0.0)), "a canvas width to the right")
    Fixtures.teardown(surface)


## The wrap is the canvas's, so on a layer with a live move each landing is
## found in document pixels and only then taken into the layer's own: the
## region at the right edge lands in the layer's chunk under it, and its copy
## at the left edge in the chunk the move holds left of the layer's first,
## which the canvas shows. A stamp at the pointer through `local_point` lands
## at each target's own centre, the copy's moved a canvas width.
func test_the_wrap_lands_through_a_layers_live_move() -> void:
    var surface := _surface(EVEN, true)
    var doc := surface.easel.document
    var move := Vector2(40.0, 0.0)
    var middle := Vector2(EVEN) * 0.5
    var map := SaLiveTransform.composed(move, 0.0, Vector2.ONE, middle)
    assert_true(SaLiveTransform.put(doc, doc.active_layer, map), "the move is put on")
    var centre := Vector2(EVEN.x, 100.0)
    var paint := SaPaintContext.for_region(doc, Rect2(centre - Vector2(20, 20), Vector2(40, 40)), true)
    var by_grid: Dictionary[Vector2i, SaPaintContext.Target] = {}
    for target in paint.targets:
        by_grid[target.grid_pos] = target
    assert_eq(paint.targets.size(), 2, "the region and its copy, one chunk each")
    var region: SaPaintContext.Target = by_grid.get(Vector2i(1, 0))
    var copy: SaPaintContext.Target = by_grid.get(Vector2i(-1, 0))
    assert_not_null(region, "the region lands in the layer's chunk under the right edge")
    assert_not_null(copy, "its copy in the chunk the move shows at the left edge")
    if region == null or copy == null:
        Fixtures.teardown(surface)
        return
    assert_eq(region.wrap_offset, Vector2.ZERO, "the region itself did not move")
    assert_eq(copy.wrap_offset, Vector2(-EVEN.x, 0.0), "the copy is a canvas width to the left")
    for target: SaPaintContext.Target in [region, copy]:
        var stamped := paint.local_point(target, centre)
        assert_true(
            stamped.distance_to(target.local_center) < 0.001,
            "a stamp at the pointer lands at the target's centre, %s against %s" % [stamped, target.local_center]
        )
    Fixtures.teardown(surface)


## One dab centred on the right edge reads its left half at the right edge and
## its right half at the left edge, texel for texel what a whole dab in the
## middle reads either side of its centre, so the two meet with no gap and no
## double coverage. On a flat document the same dab is clipped at the edge.
func test_a_dab_on_the_seam_lands_whole_on_both_sides() -> void:
    for size: Vector2i in [ODD, EVEN]:
        var middle := Vector2(size.x * 0.5, size.y * 0.5)
        var whole := _surface(size, false)
        _dab(whole, middle)
        var seam := _surface(size, true)
        _dab(seam, Vector2(size.x, middle.y))
        var clipped := _surface(size, false)
        _dab(clipped, Vector2(size.x, middle.y))
        var centred := whole.easel.document.active_layer
        var wrapped := seam.easel.document.active_layer
        var flat := clipped.easel.document.active_layer
        var worst := 0.0
        var lit := 0
        for row: int in [0, 7, 15]:
            var y := int(middle.y) + row
            for i in int(RADIUS) + 4:
                var inside_left := _alpha(centred, Vector2i(int(middle.x) - 1 - i, y))
                var inside_right := _alpha(centred, Vector2i(int(middle.x) + i, y))
                worst = maxf(worst, absf(_alpha(wrapped, Vector2i(size.x - 1 - i, y)) - inside_left))
                worst = maxf(worst, absf(_alpha(wrapped, Vector2i(i, y)) - inside_right))
                var kept := _alpha(flat, Vector2i(size.x - 1 - i, y))
                assert_almost_eq(kept, inside_left, SAME, "%s: a flat document keeps the left half" % size)
                assert_eq(_alpha(flat, Vector2i(i, y)), 0.0, "%s: and clips the right half at the edge" % size)
                if inside_right > 0.0:
                    lit += 1
        assert_true(lit > 30, "%s: the middle dab covers the texels read, %d of them" % [size, lit])
        assert_true(worst <= SAME, "%s: the seam's halves read as the whole dab, %.6f apart at most" % [size, worst])
        assert_true(_alpha(wrapped, Vector2i(0, int(middle.y))) > 0.2, "%s: the right half starts on the left edge" % size)
        assert_eq(_alpha(wrapped, Vector2i(int(RADIUS) + 3, int(middle.y))), 0.0, "%s: and ends at its radius" % size)
        for grid in _grids(wrapped):
            var inside := grid.x >= 0 and grid.x * wrapped.CHUNK_SIZE < size.x
            assert_true(inside, "%s: no chunk is stored past the canvas, %s" % [size, grid])
        Fixtures.teardown(clipped)
        Fixtures.teardown(seam)
        Fixtures.teardown(whole)


## With the vertical mirror on, top becoming bottom, one dab on the seam lands
## four times: its two halves at the top and their mirror's two at the bottom.
func test_the_symmetry_and_the_wrap_compose_into_four_landings() -> void:
    var surface := _surface(ODD, true)
    var doc := surface.easel.document
    doc.symmetry.reset_axes(Vector2(ODD))
    doc.symmetry.mirror_vertical = true
    _dab(surface, Vector2(ODD.x, 50.0))
    var layer := doc.active_layer
    var landings := {
        "the top right": Vector2i(ODD.x - 2, 50),
        "the top left": Vector2i(1, 50),
        "the bottom right": Vector2i(ODD.x - 2, ODD.y - 50),
        "the bottom left": Vector2i(1, ODD.y - 50),
    }
    for where: String in landings:
        assert_true(_alpha(layer, landings[where]) > 0.2, "A landing at %s" % where)
    var count := 0
    for x in range(0, ODD.x, 4):
        for y: int in [50, ODD.y - 50]:
            if _alpha(layer, Vector2i(x, y)) > 0.0:
                count += 1
    assert_true(count > 0 and _alpha(layer, Vector2i(ODD.x >> 1, 50)) == 0.0, "and nothing between them")
    assert_eq(_alpha(layer, Vector2i(ODD.x >> 1, ODD.y - 50)), 0.0, "nor between their mirrors")
    Fixtures.teardown(surface)


## The noise brush lays a stretch of its own path rather than a dab, and finds
## each texel's place on it through the target's chunk and the wrap's offset,
## so a stroke it draws across the seam lands on both sides too.
func test_a_noise_stroke_across_the_seam_lands_on_both_sides() -> void:
    var surface := _surface(ODD, true)
    var brush := StateNoiseBrushScript.new()
    brush.surface = surface
    brush.stroke_seed = 7
    brush.settings.opacity = 1.0
    brush.settings.hardness = 1.0
    brush.settings.strength = 0.0
    brush.settings.strength_option.enabled = false
    brush.settings.radius = 12.0 / ODD.y
    var from := Vector2(ODD.x - 40.0, 100.0)
    var to := Vector2(ODD.x + 40.0, 100.0)
    brush.begin_stroke(from, 1.0)
    for i in range(1, 21):
        brush.add_sample(from.lerp(to, float(i) / 20.0), 1.0)
    brush.end_stroke()
    var layer := surface.easel.document.active_layer
    assert_true(_alpha(layer, Vector2i(ODD.x - 20, 100)) > 0.5, "The noise stroke paints before the seam")
    assert_true(_alpha(layer, Vector2i(20, 100)) > 0.5, "and goes on past it at the left edge")
    assert_eq(_alpha(layer, Vector2i(80, 100)), 0.0, "and stops where it stopped")
    Fixtures.teardown(surface)


## The smudge lays what it carries through the same targets, so a blue smudge
## dragged out of red paint across the seam leaves red at the left edge.
func test_a_smudge_across_the_seam_drags_paint_onto_the_far_side() -> void:
    var surface := _surface(ODD, true)
    var doc := surface.easel.document
    doc.active_layer.get_or_create_chunk(Vector2i(1, 0)).albedo().clear(Color(1.0, 0.0, 0.0, 1.0))
    var brush := StateBrushScript.new()
    brush.surface = surface
    brush.settings.radius = RADIUS / ODD.y
    brush.settings.opacity = 1.0
    brush.settings.opacity_by_pressure = false
    brush.settings.hardness = GammaFloatScript.new(1.0, 1.0)
    brush.settings.stabilizer_amount = 0.0
    brush.settings.color = Color(0.0, 0.0, 1.0, 1.0)
    # The layer rather than the composite, which the red put straight into the
    # chunk never reached.
    brush.settings.smudge_sample_merged = false
    brush.settings.smudge_pickup_option.enabled = true
    # A pure smudge, as an unticked colour rate is.
    brush.settings.smudge_color_rate_option.enabled = false
    brush.settings.smudge_length_option.enabled = true
    var view := surface.view as Fixtures.FakeView
    var from := Vector2(ODD.x - 60.0, 100.0)
    var to := Vector2(ODD.x + 10.0, 100.0)
    view.mouse_position = from
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    brush.handle_input(press)
    for i in range(0, 15):
        view.mouse_position = from.lerp(to, float(i) / 14.0)
        var motion := InputEventMouseMotion.new()
        motion.pressure = 1.0
        brush.handle_input(motion)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    brush.handle_input(lift)
    var layer := doc.active_layer
    assert_eq(_alpha(layer, Vector2i(40, 100)), 0.0, "The left edge holds nothing out of the smudge's reach")
    var dragged := _texel(layer, Vector2i(3, 100))
    var red := dragged.a > 0.1 and dragged.r > 0.1 and dragged.g < 0.01
    assert_true(red, "and red where the smudge crossed the seam onto it, %s" % dragged)
    Fixtures.teardown(surface)


## The eraser paints straight in and keeps to paint that is there, and it
## lands across the seam the same way: a dab of paint on the seam is taken off
## both sides by one eraser dab there.
func test_an_eraser_on_the_seam_takes_paint_off_both_sides() -> void:
    var surface := _surface(ODD, true)
    var doc := surface.easel.document
    doc.active_layer.get_or_create_chunk(Vector2i.ZERO).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    doc.active_layer.get_or_create_chunk(Vector2i(1, 0)).albedo().clear(Color(1.0, 1.0, 1.0, 1.0))
    (surface.view as Fixtures.FakeView).mouse_position = Vector2(ODD.x, 100.0)
    var eraser := StateBrushScript.new()
    eraser.surface = surface
    eraser.settings.radius = RADIUS / ODD.y
    eraser.settings.opacity = 1.0
    eraser.settings.opacity_by_pressure = false
    eraser.settings.hardness = GammaFloatScript.new(1.0, 1.0)
    eraser.eraser_toggled = true
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    eraser.handle_input(press)
    var motion := InputEventMouseMotion.new()
    motion.pressure = 1.0
    eraser.handle_input(motion)
    var lift := InputEventMouseButton.new()
    lift.button_index = MOUSE_BUTTON_LEFT
    lift.pressed = false
    eraser.handle_input(lift)
    var layer := doc.active_layer
    assert_true(_alpha(layer, Vector2i(ODD.x - 3, 100)) < 0.01, "The eraser takes the paint off the right edge")
    assert_true(_alpha(layer, Vector2i(2, 100)) < 0.01, "and off the left edge across the seam")
    assert_eq(_alpha(layer, Vector2i(ODD.x >> 1, 100)), 1.0, "and leaves the middle")
    Fixtures.teardown(surface)
