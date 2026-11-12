## A pass that reads the whole node, on the root, rewrites only where a change
## of the picture under it lands. Until then the document made
## every chunk the root held stale for any paint, because the chain gathered the
## canvas over the dirty set, and a stroke under an attached kaleidoscope or
## wrap rewrote all of them on every composite.
##
## A canvas of five by four chunks, each held by the Background in a colour of
## its own, carries the kaleidoscope or the wrap on the root. A small square is
## painted and redrawn alone: the kernel runs on fewer chunks than the canvas
## has, the square shows where the filter carries it, and the redraw is the
## bytes a composite of everything gives. The fold's boxes and the root's
## stale set are read on the CPU as well.
##
## SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const Kaleidoscope = preload("res://modules/sara-base-modules/kaleidoscope/kaleidoscope.gd")

const REQUIRES_GPU := true

const GRID := Vector2i(5, 4)
const SIX_MIRRORS := {"mirrors": 6, "angle": 0.0, "centre_x": 50.0, "centre_y": 50.0}
const WRAP_OWNER: StringName = &"sara-base-modules"
const GREEN := Color(0.1, 0.9, 0.2, 1.0)
## Right of the centre at (640, 512) and a little below it, about ten degrees
## into the first of the twelve wedges six mirrors make, which is the wedge
## every texel reads.
const IN_WEDGE := Rect2i(900, 560, 24, 24)
## Up and left of the centre, in a wedge nothing reads.
const OFF_WEDGE := Rect2i(400, 300, 24, 24)

var _easel: SaEasel = null
var _layer: SaLayer = null


func after_each() -> void:
    _layer = null
    if _easel != null:
        _easel.free()
    _easel = null


## An easel whose Background holds every chunk, each its own colour.
func _bench() -> SaDocument:
    _easel = Bench.easel(GRID * SaChunk.SIZE)
    _layer = _easel.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in _layer.chunks.keys():
        _layer.chunks.erase(grid_pos)
    for y in GRID.y:
        for x in GRID.x:
            var tint := Color(float(x) / GRID.x, float(y) / GRID.y, 0.5, 1.0)
            _layer.get_or_create_chunk(Vector2i(x, y)).clear(tint)
    return _easel.document


## The root carrying the kaleidoscope, composited whole.
func _kaleidoscope() -> void:
    var doc := _bench()
    # The kernels' owner is the folder under modules, sara-base-modules, which
    # a filter registered by hand has to tell the loader.
    ModuleLoader.module_dirs[&"kaleidoscope"] = "res://modules/sara-base-modules/kaleidoscope"
    _easel.compositor.filter_chain.registry.register(Kaleidoscope.new(), &"kaleidoscope")
    SaFilterOps.new(doc).attach(null, &"kaleidoscope.kaleidoscope", SIX_MIRRORS)
    Bench.composite(_easel)


## The root carrying a wrap by *offset*, composited whole.
func _wrap(offset: Vector2i) -> void:
    var doc := _bench()
    var filter := SaWrapOffsetFilter.new()
    _easel.compositor.filter_chain.registry.register(filter, WRAP_OWNER)
    SaFilterOps.new(doc).attach(null, SaFilterRegistry.key_for(WRAP_OWNER, filter), {"offset_x": offset.x, "offset_y": offset.y})
    Bench.composite(_easel)


## Paints *area*, in document pixels inside one chunk, green, and redraws what
## that dirtied, answering the dispatches of the kernels whose names end in
## *kernel* the redraw took.
func _paint(area: Rect2i, kernel: String) -> int:
    var grid_pos := Vector2i((Vector2(area.position) / SaChunk.SIZE).floor())
    var local := Rect2i(area.position - grid_pos * SaChunk.SIZE, area.size)
    var texture := _layer.get_or_create_chunk(grid_pos).field(SaFieldSpec.ALBEDO)
    var rd := GlobalShaderCompiler.get_rd()
    var bytes := rd.texture_get_data(texture.rid, 0)
    var texel := SaFieldSpec.BYTES_PER_TEXEL.get(texture.format, 16) as int
    var one := SaTexture.new(Vector2i.ONE, texture.format)
    one.clear(GREEN)
    var green := rd.texture_get_data(one.rid, 0)
    for y in range(local.position.y, local.end.y):
        for x in range(local.position.x, local.end.x):
            var at := (y * texture.size.x + x) * texel
            for i in texel:
                bytes[at + i] = green[i]
    rd.texture_update(texture.rid, 0, bytes)
    _easel.document.invalidate_chunk_regions({grid_pos: local})
    var before := _tally(kernel)
    _easel.process_pending_composite()
    return _tally(kernel) - before


static func _tally(kernel: String) -> int:
    var count := 0
    for key: String in SaCompute.by_kernel:
        if key.ends_with("/" + kernel):
            count += int((SaCompute.by_kernel[key] as Dictionary)["dispatches"])
    return count


func _bytes() -> PackedByteArray:
    return GlobalShaderCompiler.get_rd().texture_get_data(_easel.output.rid, 0)


## Whether the canvas shows the green at *at*, which comes back through a
## float texture and so is compared near rather than exactly.
func _green(at: Vector2i) -> bool:
    var shown := Bench.texel(_easel.output, at)
    return shown.is_equal_approx(GREEN) or Vector4(shown.r - GREEN.r, shown.g - GREEN.g, shown.b - GREEN.b, 0.0).length() < 1e-5


## Whether what the redraw shows is what a composite of everything gives.
func _matches_everything() -> bool:
    var shown := _bytes()
    Bench.composite(_easel)
    return shown == _bytes()


func test_a_stroke_in_the_folded_wedge_rewrites_where_the_fold_carries_it() -> void:
    _kaleidoscope()
    var took := _paint(IN_WEDGE, "kaleidoscope")
    var chunks := GRID.x * GRID.y
    assert_true(took > 0, "The kaleidoscope ran")
    assert_true(took <= 12, "on %d chunks of the canvas's %d, where it ran on every one before" % [took, chunks])
    # The square's middle turned a third of a turn round the centre, two
    # wedges on, where a texel reads it back.
    var centre := Vector2(GRID * SaChunk.SIZE) / 2.0
    var middle := Vector2(IN_WEDGE.get_center()) - centre
    var turned := Vector2i((centre + middle.rotated(TAU / 3.0)).round())
    assert_true(_green(turned), "The green shows a third of a turn round")
    assert_true(_matches_everything(), "and the redraw is the bytes a composite of everything gives")


func test_a_stroke_no_wedge_reads_rewrites_itself_alone() -> void:
    _kaleidoscope()
    var took := _paint(OFF_WEDGE, "kaleidoscope")
    assert_eq(took, 1, "A square nothing reads redraws the one chunk it is in")
    assert_true(_matches_everything(), "and the redraw is the bytes a composite of everything gives")


func test_a_stroke_under_a_wrap_on_the_root_rewrites_where_it_lands() -> void:
    _wrap(Vector2i(300, 200))
    var took := _paint(IN_WEDGE, "wrap_offset")
    # The square lands across the seam between (4, 2) and (4, 3).
    assert_eq(took, 3, "The wrap ran on the painted chunk and the two it lands on")
    var lands := IN_WEDGE.position + Vector2i(300, 200) + Vector2i(4, 4)
    assert_true(_green(lands), "The green shows where the wrap carries it")
    assert_true(_matches_everything(), "and the redraw is the bytes a composite of everything gives")


## The second composite after one of everything keeps the gather, so a second
## stroke is as small as the first and still exact.
func test_the_gather_is_kept_for_the_next_stroke() -> void:
    _kaleidoscope()
    _paint(IN_WEDGE, "kaleidoscope")
    var took := _paint(IN_WEDGE.grow(-4), "kaleidoscope")
    assert_true(took < GRID.x * GRID.y, "The second stroke ran on %d chunks" % took)
    assert_true(_matches_everything(), "and is the bytes a composite of everything gives")


func test_the_fold_lands_a_change_in_the_wedge_twice_a_mirror_line() -> void:
    var centre := Vector2(640, 512)
    var boxes := Kaleidoscope.folded_boxes(IN_WEDGE, Vector2i(1280, 1024), centre, 0.0, 6)
    assert_eq(boxes.size(), 12, "Six mirror lines carry it to twelve boxes")
    var middle := Vector2(IN_WEDGE.get_center()) - centre
    var mirrored := Vector2i((centre + Vector2(middle.x, -middle.y)).round())
    var found := false
    for box in boxes:
        found = found or box.has_point(mirrored)
    assert_true(found, "and one of them holds its mirror image across the first line")
    var off := Kaleidoscope.folded_boxes(OFF_WEDGE, Vector2i(1280, 1024), centre, 0.0, 6)
    assert_eq(off, [], "A change off the wedge lands nowhere")


## The root under a wrap makes stale where the paint lands, as a layer does,
## where it made every position stale before.
func test_the_root_under_a_wrap_makes_stale_only_where_it_lands() -> void:
    var recorded := SaNeighbourhoodPass.new(
        "fixture", "fixture", {}, SaNeighbourhoodPass.WHOLE_NODE, {}, SaNeighbourhoodPass.WRITES_DISPLACED
    )
    recorded.displacement = Vector2i(384, 128)
    var record := SaAttachedFilter.new(&"fixture.wrap")
    record.cached_pass = recorded
    var records: Array[SaAttachedFilter] = [record]
    var held: Dictionary[Vector2i, bool] = {}
    for y in 2:
        for x in 3:
            held[Vector2i(x, y)] = true
    var painted: Dictionary[Vector2i, Rect2i] = {Vector2i.ZERO: Rect2i(0, 0, 10, 10)}
    var stale := SaNeighbourhoodPass.stale_under(records, held, painted, Vector2i(3, 2) * SaChunk.SIZE)
    assert_eq(stale.keys(), [Vector2i(1, 0)], "The paint lands in the chunk at (1, 0) and nothing else is stale")
