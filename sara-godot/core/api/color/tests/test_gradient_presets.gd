## The gradient's saved half of memory: the named gradients kept for later.
##
## A painter's clause: "Also we need to save the customized gradients for
## future use." The other half, the endpoint alphas that survive a restart, is
## the gradient tool's rule and moved with it into the base module, so its cases are `test_gradient_ends.gd` there.
##
## No GPU. A ramp and a directory, and the kernel that draws a ramp is
## `test_color_ramp.gd`'s.
extends "res://tests/test_framework.gd"

const ScratchFolder := preload("res://tests/fixtures/scratch_folder.gd")

## Never the real `user://gradient_presets`, for the reason
## `test_brush_presets.gd` gives: a suite that wrote there would leave test
## rubbish in the painter's own list.
static var scratch_dir: String = SaDataRoot.path("test_gradient_presets")


func before_each() -> void:
    ScratchFolder.clear(scratch_dir)


func after_each() -> void:
    ScratchFolder.clear(scratch_dir)


func _store() -> SaPresetStore:
    var store := SaPresetStore.new()
    store.dir = scratch_dir
    return store


# --- The saved gradients -------------------------------------------------------


## The other clause. A ramp goes to disk under a name and comes back as itself,
## stops, positions and alphas.
func test_a_gradient_round_trips_through_disk() -> void:
    var store := _store()
    var ramp := SaColorRamp.from_pair(Color("#e8b23c"), Color("#2f4fd0"))
    ramp.set_stop_alpha(1, 0.0)
    ramp.add_stop(0.45, Color("#20c040"))

    assert_eq(store.save_preset("Sunset", SaGradientPreset.from_ramp(ramp)), "Sunset", "Saving reports its name")
    assert_true(Array(store.list_names()).has("Sunset"), "and the library lists it")

    var loaded := (store.load_preset("Sunset") as SaGradientPreset).to_ramp()
    assert_eq(loaded.size(), 3, "Three stops came back")
    assert_almost_eq(loaded.position_of(1), 0.45, 1e-6, "the middle one where it was put")
    assert_almost_eq(loaded.color_of(1).g, Color("#20c040").g, 1e-4, "its colour with it")
    assert_almost_eq(loaded.color_of(2).a, 0.0, 1e-6, "and the far end still faded out")


## Float, not eight-bit. A ramp written as a hex string comes back a different
## colour, which would make a saved gradient quietly lossy (hard rule 5).
func test_a_saved_colour_is_not_rounded_to_eight_bits() -> void:
    var store := _store()
    var ramp := SaColorRamp.from_pair(Color(0.1234567, 0.7654321, 0.3141592, 1.0), Color.WHITE)
    store.save_preset("Precise", SaGradientPreset.from_ramp(ramp))

    var loaded := (store.load_preset("Precise") as SaGradientPreset).to_ramp()
    assert_almost_eq(loaded.color_of(0).r, 0.1234567, 1e-6, "The red survived")
    assert_almost_eq(loaded.color_of(0).g, 0.7654321, 1e-6, "and the green")
    assert_almost_eq(loaded.color_of(0).b, 0.3141592, 1e-6, "and the blue")


func test_a_saved_gradient_can_be_deleted() -> void:
    var store := _store()
    store.save_preset("Gone", SaGradientPreset.from_ramp(SaColorRamp.from_pair(Color.RED, Color.BLUE)))
    assert_true(store.has_preset("Gone"), "It is there")

    assert_true(store.delete_preset("Gone"), "and it deletes")
    assert_false(store.has_preset("Gone"), "leaving nothing behind")
    assert_false(store.delete_preset("Gone"), "and deleting it again does nothing")


## The gradient library is its own directory. One directory holding both kinds
## of resource would offer a painter a brush in the gradient list, because
## `list_names` reads a directory rather than a type.
func test_the_gradient_store_is_a_directory_of_its_own() -> void:
    assert_true(SaPresetStore.for_gradients().dir != SaPresetStore.default_dir(), "Not the brush presets")
    assert_eq(SaPresetStore.for_gradients().dir, SaPresetStore.gradient_dir(), "but the gradient ones")


## A file that holds nothing a ramp can be built from falls back rather than
## leaving a control with one stop and no way back.
func test_an_empty_preset_falls_back_rather_than_breaking_the_control() -> void:
    var fallback := SaColorRamp.from_pair(Color.RED, Color.BLUE)
    var ramp := SaGradientPreset.new().to_ramp(fallback)
    assert_eq(ramp, fallback, "An empty preset answers the fallback")
    assert_true(SaGradientPreset.new().to_ramp().size() >= SaColorRamp.MIN_STOPS, "and with none, two stops")
