## Two adjust records made by one engine keep their own tables. The filter
## chain caches one record per attached filter and runs them all through the
## registry's single instance, so a table written in place gave every layer
## the colour balance of whichever layer was recorded last.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true


func _shadow_red(recorded: SaPointPass) -> float:
    var buffer := recorded.buffers[SaPointAdjust.TABLE_BINDING] as SaCompute.Buffer
    var bytes := buffer.read(SaPointAdjust.BALANCE_BASE * 4, 4)
    return bytes.decode_float(0)


func test_an_earlier_record_keeps_its_table() -> void:
    var engine := SaPointAdjust.new()
    var space := SaColorSpace.srgb()
    var first := engine.record(SaPointAdjust.COLOR_BALANCE, {"shadows_cr": 0.5}, space)
    var second := engine.record(SaPointAdjust.COLOR_BALANCE, {"shadows_cr": -0.25}, space)
    assert_not_null(first, "the first record is made")
    assert_not_null(second, "the second record is made")
    if first == null or second == null:
        return
    assert_almost_eq(_shadow_red(second), -0.25, 1e-6, "the second record reads its own shift")
    assert_almost_eq(_shadow_red(first), 0.5, 1e-6, "the first record still reads its own shift after the second")


func test_a_record_outlives_the_engine() -> void:
    var recorded := SaPointAdjust.new().record(SaPointAdjust.COLOR_BALANCE, {"shadows_cr": 0.75}, SaColorSpace.srgb())
    assert_not_null(recorded, "the record is made")
    if recorded != null:
        assert_almost_eq(_shadow_red(recorded), 0.75, 1e-6, "the table is there once the engine is gone")
