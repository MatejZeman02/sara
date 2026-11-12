## The layer step's refusal names the step once.
##
## The line opens `SaCapture: layer` and the door raises it from there, so a
## refusal carrying "layer step: " in front of its sentence read "layer: layer
## step: there is no layer named ...".
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")


func test_a_missing_layer_is_refused_in_one_plain_sentence() -> void:
    var registries := Fixtures.make_registries()
    var easel := SaEasel.create_default(Vector2i(256, 256))
    easel.compositor.set_registry(registries.blend_modes)
    var line := SaCaptureLayers.run(easel.document, {"of": "From numbers", "opacity": 0.5})
    easel.free()
    var said: Variant = JSON.parse_string(line.trim_prefix("SaCapture: layer "))
    assert_true(said is Dictionary, "The step answers JSON: %s" % line)
    var error := String((said as Dictionary).get("error", ""))
    assert_true(error.contains("From numbers"), "The line names the layer: %s" % error)
    assert_false(error.contains("layer step"), "and does not name the step: %s" % error)
