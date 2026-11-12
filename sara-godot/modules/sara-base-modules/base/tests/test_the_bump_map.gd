## The bump map, a light over the height the normal map reads.
##
## The row's own clause: the face tilted towards the light is brighter than the
## flat region, the face tilted away is darker, and a depth of 0.1 is nearly
## flat. Every reading is off one ridge, a tent peaking in the middle of the
## chunk, so the two faces compared stand at the same height and their source
## colour is one and the same: what differs between them is which way they lean.
extends "res://tests/test_framework.gd"

const MapBench = preload("res://modules/sara-base-modules/base/tests/map_bench.gd")
const BumpMapFilter = preload("res://modules/sara-base-modules/base/usual/bump_map.gd")

const REQUIRES_GPU := true

## The light from the upper left at 45 degrees, and a depth that leans the faces
## far enough that the two answers are a tenth apart rather than a hair.
const WANTED := {"azimuth": 135.0, "elevation": 45.0, "depth": 20.0, "ambient": 0.2}
## The same light over a depth the row calls nearly flat.
const SHALLOW := {"azimuth": 135.0, "elevation": 45.0, "depth": 0.1, "ambient": 0.2}
const ROW := 128

var _bench: MapBench = null


func before_each() -> void:
    _bench = MapBench.new(MapBench.RIDGE, BumpMapFilter.new())


func after_each() -> void:
    _bench.release()
    _bench = null


## The answer at the texel that leans towards the light, which is where the
## ridge climbs to the right and so faces the light standing to the left.
func _lit() -> Color:
    return _bench.answer(Vector2i(MapBench.CLIMBING, ROW))


## The answer at the texel that leans away from it, the other side of the peak.
func _shadowed() -> Color:
    return _bench.answer(Vector2i(MapBench.FALLING, ROW))


## The answer over the same light and a height that is flat everywhere.
func _flat(params: Dictionary) -> Color:
    _bench.repaint(MapBench.FLAT)
    _bench.attach(params)
    return _bench.answer(Vector2i(128, ROW))


func test_the_record_keeps_the_four_numbers_it_was_handed() -> void:
    assert_eq(_bench.attach(WANTED), WANTED, "What the filter answers back is what the record holds")


func test_a_face_turned_towards_the_light_is_brighter_than_a_flat_one() -> void:
    _bench.attach(WANTED)
    var lit := _lit()
    var flat := _flat(WANTED)
    assert_true(lit.r > flat.r + 0.02, "The ridge's left face leans into the light: %s against %s" % [lit, flat])


func test_a_face_turned_away_is_darker() -> void:
    _bench.attach(WANTED)
    var shadowed := _shadowed()
    var flat := _flat(WANTED)
    assert_true(shadowed.r < flat.r - 0.02, "Its right face leans away from it: %s against %s" % [shadowed, flat])


func test_the_two_faces_stand_at_one_height_and_still_differ() -> void:
    _bench.attach(WANTED)
    assert_almost_eq(
        MapBench.height_at(MapBench.RIDGE, MapBench.CLIMBING, ROW),
        MapBench.LEANING_HEIGHT,
        1e-6,
        "The tent is symmetric, so the two faces stand at one height"
    )
    assert_almost_eq(
        MapBench.height_at(MapBench.RIDGE, MapBench.FALLING, ROW),
        MapBench.LEANING_HEIGHT,
        1e-6,
        "and what separates their two answers is which way they lean"
    )
    assert_true(_lit().r > _shadowed().r + 0.02, "The lit face is the brighter one: %s against %s" % [_lit(), _shadowed()])


func test_a_shallow_depth_is_nearly_flat() -> void:
    _bench.attach(SHALLOW)
    var lit := _lit()
    var flat := _flat(SHALLOW)
    assert_almost_eq(lit.r, flat.r, 0.001, "At a depth of a tenth the relief is a hair: %s against %s" % [lit, flat])


func test_the_shade_darkens_and_never_clamps() -> void:
    _bench.repaint(MapBench.ABOVE_ONE)
    _bench.attach(WANTED)
    var bright := _bench.answer(Vector2i(128, ROW))
    assert_almost_eq(
        MapBench.height_at(MapBench.ABOVE_ONE, 128, ROW),
        MapBench.BRIGHT,
        1e-6,
        "The chunk holds a colour above one, which nothing read back has clamped"
    )
    assert_true(bright.r > 1.0, "A shaded colour above one stays above one (hard rule 5): %s" % bright)
    assert_true(bright.r < MapBench.BRIGHT, "and the light still darkens it: %s" % bright)
