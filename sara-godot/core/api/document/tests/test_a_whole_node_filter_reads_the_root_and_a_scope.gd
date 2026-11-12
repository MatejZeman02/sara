## A pass that reads the whole node has three nodes with no chunk of their own
## to gather, and each of them draws nothing until it has one:
## the document's root, whose composite is the canvas, a group holding the
## active layer, composited a chunk at a time into a scratch, and a layer under
## a live stroke, whose stroke is a buffer of its own until it commits. Before
## this row each was reported once and skipped.
##
## The same fixture again, a shift whose reach is the whole node, so a texel reads
## a source as far away as it likes. The root reads the canvas gathered over the
## dirty set, which the document already widened to every chunk it holds, and a
## scope and a stroked layer read the [SaFilterChain.Halo] their sweep fills.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")
const WholeShiftFilter = preload("res://tests/fixtures/modules/whole-fixture/whole_shift_filter.gd")

const REQUIRES_GPU := true

const OWNER: StringName = &"whole-fixture"
const KEY: StringName = &"whole-fixture.whole_fixture_shift"
const RED := Color(1.0, 0.0, 0.0, 1.0)
const GREEN := Color(0.0, 1.0, 0.0, 1.0)
const YELLOW := Color(1.0, 0.8, 0.2, 1.0)
## Two chunks to the right, as far as the fixture reads.
const SHIFT := {"offset_x": 512.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
## The same filter reading the texel it stands on, which is what the live
## stroke's case needs: what the node shows at a texel is what it shows there.
const IN_PLACE := {"offset_x": 0.0, "offset_y": 0.0, "mode": 0, "reach": SaNeighbourhoodPass.WHOLE_NODE}
const PROBE := Vector2i(10, 128)
## The texel the live-stroke read uses the live stroke at: well inside a chunk and
## nowhere near a seam.
const INSIDE := Vector2i(100, 128)
const FAR := Vector2i(2, 0)
## The far chunk of the second row, which reads the paint of its own row: a
## gather that copies each chunk to its own place answers both, and one that
## copies the canvas whole answers neither.
const BELOW := Vector2i(2, 1)
const PAINTED_BELOW := Vector2i(0, 1)


func _shows(easel: SaEasel, at: Vector2i, expected: Color, what: String) -> void:
    var found := Bench.texel(easel.output, at)
    assert_almost_eq(found.r, expected.r, 0.01, "%s, red at %s: %s" % [what, at, found])
    assert_almost_eq(found.g, expected.g, 0.01, "%s, green at %s: %s" % [what, at, found])
    assert_almost_eq(found.b, expected.b, 0.01, "%s, blue at %s: %s" % [what, at, found])
    assert_almost_eq(found.a, expected.a, 0.01, "%s, alpha at %s: %s" % [what, at, found])


## An easel three chunks wide and two tall whose one layer holds the paint at
## (0, 0) and (0, 1) and an empty chunk two chunks to the right of each, the
## shape the whole-node suite uses: the far chunks are positions the node holds, so the
## shift's source is read there rather than past the edge of what was gathered.
## Two rows, so a gather that puts a chunk anywhere but its own place is caught.
func _bench() -> SaEasel:
    var made := Bench.easel(Vector2i(3 * SaChunk.SIZE, 2 * SaChunk.SIZE))
    made.compositor.filter_chain.registry.register(WholeShiftFilter.new(), OWNER)
    var layer := made.document.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(GREEN)
    layer.get_or_create_chunk(PAINTED_BELOW).clear(RED)
    layer.get_or_create_chunk(FAR).clear(Color.TRANSPARENT)
    layer.get_or_create_chunk(BELOW).clear(Color.TRANSPARENT)
    return made


## A whole-node filter on the root runs over the canvas once the document has
## composited every layer into it, and the canvas is where the root's source is:
## before this row the gather found no chunk and the canvas kept its composite.
func test_the_root_reads_the_canvas_two_chunks_away() -> void:
    var easel := _bench()
    SaFilterOps.new(easel.document).attach(null, KEY, SHIFT)
    Bench.composite(easel)
    _shows(easel, FAR * SaChunk.SIZE + PROBE, GREEN, "The root's shift shows the paint two chunks from where it was painted")
    _shows(easel, BELOW * SaChunk.SIZE + PROBE, RED, "and the same in the row below, each chunk where the gather put it")
    _shows(easel, PROBE, Color(0, 0, 0, 0), "and the painted chunk reads past the canvas's left edge, transparent")
    easel.free()


## A scope stores nothing either, and its composite is built a chunk at a time,
## so its whole-node pass reads the halo the sweep fills of it.
func test_a_scope_reads_its_members_two_chunks_away() -> void:
    var easel := _bench()
    var doc := easel.document
    var member := doc.get_node("Background") as SaLayer
    var group := SaLayerOps.new(doc).group_layers([member])
    doc.set_active_layer(member)
    SaFilterOps.new(doc).attach(group, KEY, SHIFT)
    Bench.composite(easel)
    _shows(easel, FAR * SaChunk.SIZE + PROBE, GREEN, "The group's shift shows the paint two chunks from where it was painted")
    _shows(easel, BELOW * SaChunk.SIZE + PROBE, RED, "and the same in the row below, each chunk where the sweep put it")
    _shows(easel, PROBE, Color(0, 0, 0, 0), "and the painted chunk reads past the group's left edge, transparent")
    easel.free()


## The layer being painted is the third case, in a milder form: what it stores
## holds no live stroke until the commit, so a whole-node gather taken from the
## layer alone reads the paint the stroke will leave. The halo it fills holds
## the two composited, which is what the pass reads now.
func test_the_texel_mid_stroke_is_the_same_after_the_commit() -> void:
    var easel := _stroke_bench()
    var at := Vector2i(SaChunk.SIZE, 0) + INSIDE
    _shows(easel, at, YELLOW, "Mid-stroke the whole-node shift reads the live stroke, not the layer without it")
    # A position the stroke never reached is read through the same gather, so
    # the halo holds the layer's own paint there as well.
    _shows(easel, PROBE, GREEN, "and a chunk the stroke left alone still shows the layer")

    var live := Bench.texel(easel.output, at)
    easel.document.commit_stroke()
    Bench.composite(easel)
    var committed := Bench.texel(easel.output, at)
    assert_almost_eq(committed.r, live.r, 0.01, "Red after the commit: %s against %s" % [committed, live])
    assert_almost_eq(committed.g, live.g, 0.01, "Green after the commit: %s against %s" % [committed, live])
    assert_almost_eq(committed.b, live.b, 0.01, "Blue after the commit: %s against %s" % [committed, live])
    assert_almost_eq(committed.a, live.a, 0.01, "Alpha after the commit: %s against %s" % [committed, live])
    easel.free()


## Green in both chunks of the active layer with the shift attached to it, and
## the stroke's own buffer holding the yellow over the right chunk, which is the
## picture the commit will leave.
func _stroke_bench() -> SaEasel:
    var made := Bench.easel(Vector2i(2 * SaChunk.SIZE, SaChunk.SIZE))
    made.compositor.filter_chain.registry.register(WholeShiftFilter.new(), OWNER)
    var doc := made.document
    var layer := doc.get_node("Background") as SaLayer
    for grid_pos: Vector2i in layer.chunks.keys():
        layer.chunks.erase(grid_pos)
    layer.get_or_create_chunk(Vector2i(0, 0)).clear(GREEN)
    layer.get_or_create_chunk(Vector2i(1, 0)).clear(GREEN)
    doc.set_active_layer(layer)
    SaFilterOps.new(doc).attach(layer, KEY, IN_PLACE)
    doc.stroke_layer.get_or_create_chunk(Vector2i(1, 0)).clear(YELLOW)
    doc.stroke_layer.visible = true
    Bench.composite(made)
    return made


## What the sweep answers a whole-node pass: every position the stroke holds
## and the dirty ring, each over its whole chunk. A layer's chunk outside both
## is read from the layer itself.
func test_a_whole_node_sweep_covers_every_position_the_node_holds() -> void:
    var easel := _stroke_bench()
    var dirty: Dictionary[Vector2i, Rect2i] = {Vector2i(0, 0): Rect2i(8, 8, 16, 16)}
    var swept := SaFilterChain.stroke_sweep(easel.document, dirty)
    assert_true(swept.has(Vector2i(1, 0)), "The chunk the stroke holds is swept")
    assert_true(swept.has(Vector2i(0, 0)), "and the dirty one the layer holds")
    assert_eq(swept.get(Vector2i(0, 0), Rect2i()), SaDocument.WHOLE_CHUNK, "over the whole chunk, not over the region alone")
    easel.free()
