## The axis convention the normal map names, over a ramp rising towards the top
## of the canvas.
##
## This is the convention's own check and the reason it is named at all. v runs
## down the canvas, so a surface rising towards the top tilts its world normal
## down and reads green below the middle, 128 of 255. A painter exporting to an engine that
## reads the other way flips the green channel, and the flip is what the second half of
## this suite reads.
extends "res://tests/test_framework.gd"

const MapBench = preload("res://modules/sara-base-modules/base/tests/map_bench.gd")
const NormalMapFilter = preload("res://modules/sara-base-modules/base/usual/normal_map.gd")

const REQUIRES_GPU := true

const STRENGTH := 4.0
## Where a texel of the ramp is read, and which column. Every one of them is well
## inside the chunk, so the central difference reads paint above and below.
const ROWS := [64, 128, 192]
const COLUMN := 128
## The encoded zero and the reach of one either way, 128 and 127 of 255.
const MIDDLE := 128.0 / 255.0
const REACH := 127.0 / 255.0

var _bench: MapBench = null


func before_each() -> void:
    _bench = MapBench.new(MapBench.RAMP_TOP, NormalMapFilter.new())


func after_each() -> void:
    _bench.release()
    _bench = null


## The green a rise of *slope* grey levels a texel towards the top leaves: the
## encoded y of `normalize(vec3(0, slope * strength, 1))`.
static func _green(slope: float, strength: float) -> float:
    var lean := slope * strength
    return MIDDLE - REACH * lean / sqrt(1.0 + lean * lean)


func test_a_ramp_rising_towards_the_top_reads_green_below_the_middle() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    for row: int in ROWS:
        var answer := _bench.answer(Vector2i(COLUMN, row))
        assert_true(answer.g < MIDDLE, "The surface rises towards the top, so it faces down: %s" % answer)
        assert_almost_eq(
            answer.g, _green(MapBench.step(), STRENGTH), 0.0005, "one grey level a texel at strength four: %s" % answer
        )


func test_the_same_ramp_keeps_red_at_the_middle() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    for row: int in ROWS:
        var answer := _bench.answer(Vector2i(COLUMN, row))
        assert_almost_eq(answer.r, MIDDLE, 1e-5, "No slope runs across, so nothing leans left or right: %s" % answer)


func test_the_flip_puts_the_green_the_other_way_up() -> void:
    _bench.attach({"strength": STRENGTH, "flip": true})
    for row: int in ROWS:
        var answer := _bench.answer(Vector2i(COLUMN, row))
        assert_true(answer.g > MIDDLE, "DirectX's green reads the other way up: %s" % answer)
        assert_almost_eq(
            answer.g, 2.0 * MIDDLE - _green(MapBench.step(), STRENGTH), 0.0005, "and by the same amount: %s" % answer
        )


func test_the_flip_alone_moves_and_the_red_stays_where_it_was() -> void:
    _bench.attach({"strength": STRENGTH, "flip": false})
    var plain := _bench.answer(Vector2i(COLUMN, 128))
    _bench.attach({"strength": STRENGTH, "flip": true})
    var flipped := _bench.answer(Vector2i(COLUMN, 128))
    assert_almost_eq(flipped.r, plain.r, 1e-6, "Flipping the green leaves the red alone: %s against %s" % [flipped, plain])
    assert_almost_eq(flipped.b, plain.b, 1e-6, "and the blue: %s against %s" % [flipped, plain])


func test_the_rows_sentence_names_the_convention() -> void:
    var sentence := NormalMapFilter.new().sentence()
    assert_true(sentence.contains("+Y up"), "The sentence says which way the frame runs: %s" % sentence)
    assert_true(sentence.contains("below 0.5"), "and what a rise towards the top therefore reads: %s" % sentence)
