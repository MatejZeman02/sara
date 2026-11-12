## A `kernel` step takes `"history": false` and records no undo
## step, so the twenty reruns of `sara.bench` leave a painter's history as the
## cell's one run left it, and `"step"` names the one step a rerun that changes
## the picture records for all of them.
##
## Built like the GPU time suite: the driver with no run, handed the document. Every
## pixel assertion reads the chunk back the way an export does, the one readback
## hard rule 1 permits a test.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const KernelDriver := preload("res://harness/sa_kernel_driver.gd")
const SaExportScript = preload("res://core/export/sa_export.gd")

## Writes the colour it reads, scaled, so a rerun into the layer it reads
## changes it each time and a rerun into another layer does not.
const HALVE := """kernel halve

image src: readonly
image dst

params:
    float scale

def halve():
    vec4 c = image_load(src, pixel)
    image_store(dst, pixel, vec4(c.rgb * scale, c.a))
"""

const PAINT := Color(0.8, 0.4, 0.2, 1.0)

## The scale a run applies, gentle enough that twenty-one of them are still far
## from the zero a half-float tolerance could not tell them from.
const SCALE := 0.9

## The runs of a bench, as `bench` sends them by default.
const RUNS := 20

var _easel: SaEasel = null
var _doc: SaDocument = null
var _paint: SaLayer = null
var _driver: KernelDriver = null


func before_each() -> void:
    _easel = SaEasel.create_default(Vector2i(512, 512))
    _doc = _easel.document
    _paint = _doc.active_layer
    _paint.get_or_create_chunk(Vector2i(0, 0)).clear(PAINT)
    _driver = KernelDriver.new(null)


func after_each() -> void:
    _easel.free()
    _easel = null
    _doc = null
    _paint = null
    _driver = null


func _spec(extra: Dictionary = {}) -> Dictionary:
    var spec := {"source": HALVE, "name": "halve", "layer": String(_paint.name), "params": {"scale": SCALE}}
    spec.merge(extra, true)
    return spec


func _texel(layer: SaLayer) -> Color:
    var image := SaExportScript.get_texture_image_float(layer.chunks[Vector2i.ZERO].field(SaFieldSpec.ALBEDO))
    return image.get_pixel(7, 9)


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 2e-3 and absf(a.g - b.g) < 2e-3 and absf(a.b - b.b) < 2e-3 and absf(a.a - b.a) < 2e-3


func _steps() -> int:
    return _doc.history.step_count()


func _scaled(times: int) -> Color:
    var factor := pow(SCALE, times)
    return Color(PAINT.r * factor, PAINT.g * factor, PAINT.b * factor, 1.0)


func test_twenty_reruns_with_history_off_leave_the_one_step_of_the_run() -> void:
    var first := _driver.run_on(_doc, _spec())
    assert_true(bool(first["ok"]), "the kernel ran: %s" % [first])
    var into := KernelDriver.layer_of(_doc, String(first["into"]))
    var after_the_run := _steps()
    assert_true(after_the_run > 0, "and recorded its steps")

    for _i in RUNS:
        var again := _driver.run_on(_doc, _spec({"history": false}))
        assert_true(bool(again["ok"]), "a rerun ran: %s" % [again])
        assert_eq(again["into"], first["into"], "into the layer the first wrote")

    assert_eq(_steps(), after_the_run, "twenty reruns added no step to the history")
    assert_eq(_doc.history.dropped_steps, 0, "and dropped none of the painter's")
    assert_true(_near(_texel(into), _scaled(1)), "while the layer holds the kernel's picture")
    _doc.undo()
    assert_false(into.chunks.has(Vector2i.ZERO), "and one undo gives back the picture before the kernel")
    assert_true(_near(_texel(_paint), PAINT), "with the layer it read as it was")


func test_a_run_without_the_key_records_as_it_did() -> void:
    _driver.run_on(_doc, _spec())
    var after_the_run := _steps()
    for _i in 3:
        _driver.run_on(_doc, _spec())
    assert_eq(_steps(), after_the_run + 3, "each rerun that does not ask otherwise is a step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Kernel halve", "called after the kernel")


func test_history_true_is_the_default_spelt_out() -> void:
    _driver.run_on(_doc, _spec())
    var after_the_run := _steps()
    _driver.run_on(_doc, _spec({"history": true}))
    assert_eq(_steps(), after_the_run + 1, "one more step")


func test_a_step_name_names_the_step_a_run_records() -> void:
    _driver.run_on(_doc, _spec({"step": "Bench halve"}))
    assert_eq(_doc.undo_redo.get_current_action_name(), "Bench halve", "the history lists it by that name")


func test_a_name_does_not_make_a_run_with_history_off_record() -> void:
    _driver.run_on(_doc, _spec())
    var after_the_run := _steps()
    _driver.run_on(_doc, _spec({"history": false, "step": "Bench halve"}))
    assert_eq(_steps(), after_the_run, "history off wins")


func test_a_run_into_another_layer_is_not_in_place() -> void:
    var verdict := _driver.run_on(_doc, _spec())
    assert_false(bool(verdict["in_place"]), "it read one layer and wrote another: %s" % [verdict])


func test_a_run_into_the_layer_it_reads_is_in_place() -> void:
    var verdict := _driver.run_on(_doc, _spec({"into": String(_paint.name)}))
    assert_true(bool(verdict["in_place"]), "it wrote what it read: %s" % [verdict])


func test_a_run_into_a_layer_an_input_reads_is_in_place() -> void:
    var into := SaLayerOps.new(_doc).add(&"", null)
    into.name = "Inputs"
    var spec := _spec({"into": "Inputs", "inputs": {"other": {"layer": "Inputs"}}})
    var source := HALVE.replace("image dst", "image other: readonly\nimage dst")
    spec["source"] = source.replace(
        "vec4 c = image_load(src, pixel)", "vec4 c = image_load(src, pixel) + image_load(other, pixel) * 0.0"
    )
    var verdict := _driver.run_on(_doc, spec)
    assert_true(bool(verdict["ok"]), "the kernel ran: %s" % [verdict])
    assert_true(bool(verdict["in_place"]), "an input is a read: %s" % [verdict])


func test_reruns_that_change_the_picture_are_one_step_named_after_the_bench() -> void:
    var spec := _spec({"into": String(_paint.name)})
    var first := _driver.run_on(_doc, spec)
    assert_true(bool(first["in_place"]), "the run says a rerun starts from what it wrote")
    var after_the_run := _steps()

    var recorded := _driver.run_on(_doc, _spec({"into": String(_paint.name), "step": "Bench halve"}))
    assert_true(bool(recorded["ok"]), "the first rerun ran: %s" % [recorded])
    for _i in RUNS - 1:
        _driver.run_on(_doc, _spec({"into": String(_paint.name), "history": false}))

    assert_eq(_steps(), after_the_run + 1, "twenty reruns are one step")
    assert_eq(_doc.undo_redo.get_current_action_name(), "Bench halve", "named after the bench")
    assert_true(_near(_texel(_paint), _scaled(1 + RUNS)), "the layer holds the last rerun's picture")
    _doc.undo()
    assert_true(_near(_texel(_paint), _scaled(1)), "one undo gives back the picture before the first rerun")
    _doc.redo()
    assert_true(_near(_texel(_paint), _scaled(1 + RUNS)), "and one redo the picture after the last")
