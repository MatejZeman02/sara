## The height to normal map, over a ramp rising to the right.
##
## The row's own clause, clause by clause: red below the middle across a ramp
## that climbs to the right, green at the middle on the same ramp because it has
## no vertical slope at all, and a flat region answering exactly the identity
## normal. The middle is 128 of 255, the eight bit encoding where zero is 128
## and one is 255, so a flat texel never sits between two counts.
extends "res://tests/test_framework.gd"

const MapBench = preload("res://modules/sara-base-modules/base/tests/map_bench.gd")
const NormalMapFilter = preload("res://modules/sara-base-modules/base/usual/normal_map.gd")

const REQUIRES_GPU := true

## The strength every expectation below is built out of, half way up the row's
## own range and the number the dialog opens on.
const STRENGTH := 4.0
## Where a texel of the ramp is read, and which row. Every one of them is well
## inside the chunk, so the central difference reads paint on both sides.
const COLUMNS := [64, 128, 192]
const ROW := 128
## The encoded zero and the reach of one either way, 128 and 127 of 255.
const MIDDLE := 128.0 / 255.0
const REACH := 127.0 / 255.0

var _bench: MapBench = null


func before_each() -> void:
    _bench = MapBench.new(MapBench.RAMP_RIGHT, NormalMapFilter.new())


func after_each() -> void:
    _bench.release()
    _bench = null


## The red a slope of *slope* grey levels a texel leaves, at *strength*: the
## encoded x of `normalize(vec3(-slope * strength, 0, 1))`.
static func _red(slope: float, strength: float) -> float:
    var lean := slope * strength
    return MIDDLE - REACH * lean / sqrt(1.0 + lean * lean)


func test_the_record_evaluates_to_a_neighbourhood_pass() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    assert_true(_bench.record.cached_pass is SaNeighbourhoodPass, "The normal map records a neighbourhood pass")
    if _bench.record.cached_pass is SaNeighbourhoodPass:
        assert_eq(
            (_bench.record.cached_pass as SaNeighbourhoodPass).radius,
            1,
            "one texel either way, which is what a central difference reads"
        )
    assert_eq(_bench.layer.chunks.size(), 1, "and nothing was allocated for the read")


func test_the_record_keeps_the_two_numbers_it_was_handed() -> void:
    var wanted := {"strength": 7.5, "flip": true}
    assert_eq(_bench.attach(wanted), wanted, "What the filter answers back is what the record holds")


func test_a_ramp_rising_to_the_right_reads_red_below_the_middle() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    for column: int in COLUMNS:
        var answer := _bench.answer(Vector2i(column, ROW))
        assert_true(answer.r < MIDDLE, "The surface leans away from +X at column %d: %s" % [column, answer])
        assert_almost_eq(
            answer.r, _red(MapBench.step(), STRENGTH), 0.0005, "one grey level a texel at strength four: %s" % answer
        )


func test_the_same_ramp_keeps_green_at_the_middle() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    for column: int in COLUMNS:
        var answer := _bench.answer(Vector2i(column, ROW))
        assert_almost_eq(answer.g, MIDDLE, 1e-5, "No slope runs down v, so nothing tilts up or down: %s" % answer)


func test_a_flat_height_is_the_identity_normal() -> void:
    _bench.repaint(MapBench.FLAT)
    _bench.attach({"strength": STRENGTH, "flip": false})
    var answer := _bench.answer(Vector2i(ROW, ROW))
    assert_almost_eq(answer.r, MIDDLE, 1e-6, "Both slopes are exactly zero, so the normal is +Z: %s" % answer)
    assert_almost_eq(answer.g, MIDDLE, 1e-6, "and its encoded green is the middle: %s" % answer)
    assert_almost_eq(answer.b, 1.0, 1e-6, "and it points straight out of the surface: %s" % answer)
    assert_almost_eq(answer.a, 1.0, 1e-6, "with the source texel's own alpha kept: %s" % answer)


func test_the_composite_shows_what_the_chain_answers() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    var shown := _bench.composite(Vector2i(128, ROW))
    assert_almost_eq(shown.r, _red(MapBench.step(), STRENGTH), 0.005, "The canvas draws the same red: %s" % shown)
    assert_almost_eq(shown.g, MIDDLE, 0.005, "and the same green: %s" % shown)
