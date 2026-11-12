## A gather over the whole node clears only the positions its node holds no
## chunk at, one chunk-sized dispatch each, rather than the whole rectangle the
## node spans in one dispatch.
##
## Two chunks at opposite corners of a four by four grid are the shape two
## strokes in opposite corners of a canvas make: the span is sixteen chunks, two
## of them are copied and the other fourteen are cleared one at a time. The one
## clear over the span was the whole canvas in a single dispatch, and every
## chunk the node did hold was then written a second time by its own copy, which
## is hard rule 2 over a rectangle nobody painted.
##
## [SaNeighbourhoodPass.Runner.gather] and [method SaFilterHalo.gathered] are
## the two gathers, and each is counted on its own: dispatches per kernel and
## workgroups per dispatch, so "one chunk each" is a number rather than a claim.
## What is wanted out of a texture is read before the assertion, because a
## texture still referenced while a test asserts comes out of the process alive.
extends "res://tests/test_framework.gd"

const Bench = preload("res://tests/fixtures/attached_filter_bench.gd")

const REQUIRES_GPU := true

const FORMAT: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
const RED := Color(1.0, 0.0, 0.0, 1.0)
const BLUE := Color(0.0, 0.0, 1.0, 1.0)
## A four by four span, the smallest rectangle two chunks in opposite corners
## make with room between them.
const SQUARE: int = 4
const FAR := Vector2i(SQUARE - 1, SQUARE - 1)
## The cells of that span a node of two chunks holds no chunk at.
const UNHELD: int = SQUARE * SQUARE - 2
## Well inside a chunk and nowhere near its edge.
const INSIDE := Vector2i(5, 5)

var _runner: SaNeighbourhoodPass.Runner = null
var _layer: SaLayer = null
var _halo: SaFilterHalo = null


func before_each() -> void:
    _runner = SaNeighbourhoodPass.Runner.new()
    _layer = _two_corners()


func after_each() -> void:
    _runner = null
    if _halo != null:
        # The halo would free it too, on its own way out.
        _halo.layer = null
        _halo = null
    if _layer != null:
        _layer.free()
        _layer = null


## A layer holding a painted chunk at each corner [const FAR] is a corner of.
func _two_corners() -> SaLayer:
    var made := SaLayer.new()
    made.schema = SaFieldSpec.default_schema(FORMAT)
    made.get_or_create_chunk(Vector2i.ZERO).clear(RED)
    made.get_or_create_chunk(FAR).clear(BLUE)
    return made


## The workgroups one chunk-sized dispatch of a kernel takes, which is what
## tells a clear of one cell from the one clear over the whole span.
func _cell_groups() -> int:
    return SaCompute.groups_for(SaChunk.SIZE) * SaCompute.groups_for(SaChunk.SIZE)


## What the kernel *key* spent since the counters were last reset, on *field*.
func _spent(key: String, field: String) -> int:
    var entry: Dictionary = SaCompute.kernel_counters().get(key, {})
    return int(entry.get(field, 0))


## Whether *spent* is *count* dispatches of one cell each.
func _one_cell_each(spent: int, count: int) -> bool:
    return spent == count * _cell_groups()


func test_two_corners_clear_fourteen_cells_and_copy_two() -> void:
    SaCompute.reset_counters()
    var whole := _runner.gather(_layer.chunks.keys(), _layer.get_field, FORMAT)
    var span := whole.texture.size
    var origin := whole.origin
    whole.texture = null
    whole = null
    assert_eq(span, Vector2i(SaChunk.SIZE, SaChunk.SIZE) * SQUARE, "The gather spans the four by four rectangle")
    assert_eq(origin, Vector2i.ZERO, "and its first texel stands for the document's origin")
    assert_eq(_spent("clear/clear_chunk", "dispatches"), UNHELD, "Fourteen cells are cleared, a dispatch each")
    assert_true(_one_cell_each(_spent("clear/clear_chunk", "workgroups"), UNHELD), "and every one of them one cell")
    assert_eq(_spent("copy_region/copy_region", "dispatches"), 2, "The two chunks the node holds are copied")
    assert_true(_one_cell_each(_spent("copy_region/copy_region", "workgroups"), 2), "each of them one cell")


func test_the_zeros_land_where_the_node_holds_nothing() -> void:
    var whole := _runner.gather(_layer.chunks.keys(), _layer.get_field, FORMAT)
    var near := Bench.texel(whole.texture, INSIDE)
    var far := Bench.texel(whole.texture, FAR * SaChunk.SIZE + INSIDE)
    var empty := Bench.texel(whole.texture, Vector2i(SaChunk.SIZE, 0) + INSIDE)
    whole.texture = null
    whole = null
    assert_eq(near, RED, "The gathered texture holds the near corner's paint")
    assert_eq(far, BLUE, "and the far corner's, in its own place")
    assert_eq(empty, Color(0, 0, 0, 0), "and a position the node holds no chunk at reads as nothing")


func test_a_gather_over_one_held_position_clears_nothing() -> void:
    SaCompute.reset_counters()
    var whole := _runner.gather([Vector2i.ZERO], _layer.get_field, FORMAT)
    var side := whole.texture.size
    whole.texture = null
    whole = null
    assert_eq(side, Vector2i(SaChunk.SIZE, SaChunk.SIZE), "A node whose span is one chunk gathers that chunk")
    assert_eq(_spent("clear/clear_chunk", "dispatches"), 0, "and clears nothing, since it holds every cell it spans")


func test_a_halo_clears_its_own_span_the_same_way() -> void:
    _halo = SaFilterHalo.new()
    _halo.layer = _layer
    _halo.begin({Vector2i.ZERO: true, FAR: true})
    SaCompute.reset_counters()
    _halo.gathered(FORMAT)
    assert_eq(_spent("clear/clear_chunk", "dispatches"), UNHELD, "A halo over two corners clears the fourteen unheld cells")
    assert_true(_one_cell_each(_spent("clear/clear_chunk", "workgroups"), UNHELD), "a cell each")
    assert_eq(_spent("copy_region/copy_region", "dispatches"), 2, "and copies the two it does hold")
    assert_true(_one_cell_each(_spent("copy_region/copy_region", "workgroups"), 2), "each of them one cell")


func test_a_halo_lets_a_later_gather_clear_and_copy_nothing() -> void:
    _halo = SaFilterHalo.new()
    _halo.layer = _layer
    _halo.begin({Vector2i.ZERO: true, FAR: true})
    _halo.gathered(FORMAT)
    SaCompute.reset_counters()
    var again := _halo.gathered(FORMAT)
    var shown := again != null and again.texture != null
    assert_true(shown, "The halo answers the second gather with the texture it already has")
    assert_eq(_spent("clear/clear_chunk", "dispatches"), 0, "and clears nothing, every cell being held or already blank")
    assert_eq(_spent("copy_region/copy_region", "dispatches"), 0, "and copies nothing, having copied both chunks already")
