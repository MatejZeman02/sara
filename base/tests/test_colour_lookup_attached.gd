## The colour lookup works attached. Its record keeps the painter's numbers
## through a save and a load, and the composite the loaded record evaluates to is
## the one the attached record drew.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const WANTED := {
    "palette": ["#1f6fd0ff", "#e04020ff"],
    "bands":
    [
        {"shadows": 0.5, "midtones": 1.0, "highlights": 0.5, "influence": 1.0},
        {"shadows": 1.0, "midtones": 0.8, "highlights": 0.2, "influence": 1.5},
    ],
}

var _trip: RoundTrip = null


func before_each() -> void:
    _trip = RoundTrip.new(SaColorLookupFilter.new(), OWNER)


func after_each() -> void:
    _trip.release()
    _trip = null


func test_the_filter_answers_the_numbers_it_was_handed() -> void:
    _trip.filter.set_parameters(WANTED)
    var kept := _trip.filter.parameters()
    for name: String in WANTED:
        assert_eq(kept.get(name), WANTED[name], "%s comes back as it went in" % name)


func test_attached_it_survives_a_save_and_a_load() -> void:
    var plain := _trip.texels()
    var kept := _trip.attach(WANTED)
    var before := _trip.texels()
    assert_true(RoundTrip.distance(plain, before) > 0.01, "Attached, it moves the composite: %s to %s" % [plain, before])
    var loaded := _trip.round_trip()
    assert_eq(loaded, kept, "The loaded record keeps the numbers it was attached with")
    var after := _trip.texels()
    assert_true(RoundTrip.distance(before, after) < 1e-5, "and draws the same texels: %s against %s" % [before, after])
