## The box blur works attached. Its record keeps the radius
## through a save and a load, and the composite the loaded record evaluates to
## is the one the attached record drew. The first filter to read its
## neighbours, so the texels read sit on the seams between chunks of two
## colours as well as at their centres.
extends "res://tests/test_framework.gd"

const RoundTrip = preload("res://modules/sara-base-modules/base/tests/attached_round_trip.gd")
const BoxBlurFilter = preload("res://modules/sara-base-modules/base/usual/box_blur_filter.gd")

const REQUIRES_GPU := true

const OWNER := &"sara-base-modules"
const WANTED := {"radius": 6.0}
## Just either side of the seam between the first two chunks, where a blur
## that lost its neighbours would read one colour.
const SEAM: Array[Vector2i] = [Vector2i(254, 128), Vector2i(258, 128)]

var _trip: RoundTrip = null


func before_each() -> void:
    ModuleLoader.module_dirs[OWNER] = "res://modules/sara-base-modules/base"
    _trip = RoundTrip.new(BoxBlurFilter.new(), OWNER)


func after_each() -> void:
    _trip.release()
    _trip = null


func _seam() -> Array[Color]:
    var out: Array[Color] = []
    for at in SEAM:
        out.append(RoundTrip.Bench.texel(_trip.easel.output, at))
    return out


func test_the_filter_answers_the_radius_it_was_handed() -> void:
    var blur := BoxBlurFilter.new()
    assert_eq(blur.parameters(), {"radius": 3.0}, "With no dialog ever built it answers its default")
    blur.set_parameters(WANTED)
    assert_eq(blur.parameters(), WANTED, "and the radius it was handed")
    blur.set_parameters({})
    assert_eq(blur.parameters(), {"radius": 3.0}, "and a record that names none reads as the default")


func test_attached_it_survives_a_save_and_a_load() -> void:
    var plain := _trip.texels()
    var plain_seam := _seam()
    var kept := _trip.attach(WANTED)
    var before := _trip.texels()
    var before_seam := _seam()
    assert_true(RoundTrip.distance(plain_seam, before_seam) > 0.01, "Attached, it blurs across the seam")
    assert_true(RoundTrip.distance(plain, before) < 1e-5, "and leaves the middle of a flat chunk as it was")
    # A radius of one would read nearly the same at the centres, so the seam is
    # where a load that lost the record's radius shows.
    var loaded := _trip.round_trip({"radius": 1.0})
    assert_eq(loaded, kept, "The loaded record keeps the radius it was attached with")
    _composite()
    var after_seam := _seam()
    assert_true(
        RoundTrip.distance(before_seam, after_seam) < 1e-5, "and draws the same seam: %s against %s" % [before_seam, after_seam]
    )
    assert_true(RoundTrip.distance(before, _trip.texels()) < 1e-5, "and the same centres")


func _composite() -> void:
    RoundTrip.Bench.composite(_trip.easel)
