## The ledger counts pipeline loads and their time, so a perf window says
## whether a stroke paid for its pipelines.
extends "res://tests/test_framework.gd"

## Needs a RenderingDevice. The runner skips this suite without one.
const REQUIRES_GPU := true


func test_a_new_compute_is_one_load() -> void:
    SaCompute.reset_counters()
    assert_eq(int(SaCompute.counters()["pipeline_loads"]), 0, "A reset zeroes the loads")
    assert_eq(int(SaCompute.counters()["pipeline_load_usec"]), 0, "and their time")
    var comp := SaCompute.new("composite")
    assert_true(comp.pipelines.kernels.size() > 0, "The shader loaded")
    assert_eq(int(SaCompute.counters()["pipeline_loads"]), 1, "Making a compute is one load")
    assert_true(int(SaCompute.counters()["pipeline_load_usec"]) >= 0, "and its time is counted, never negative")


func test_a_new_format_is_another_load_and_the_same_one_is_not() -> void:
    var comp := SaCompute.new("composite")
    SaCompute.reset_counters()
    comp.use_storage_format(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
    comp.use_storage_format(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    var after_two := int(SaCompute.counters()["pipeline_loads"])
    comp.use_storage_format(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
    assert_eq(int(SaCompute.counters()["pipeline_loads"]), after_two, "Asking again for the format it has loads nothing")
    assert_true(after_two >= 1, "and a change of format is a load")
    SaCompute.reset_counters()
