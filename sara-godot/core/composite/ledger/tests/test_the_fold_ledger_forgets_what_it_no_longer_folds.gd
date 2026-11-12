## The fold's ledger knows every mask a folded step read, the
## layer's and, for a clipping base's step, those of the base and of every step
## clipped to it, and none after it forgets.
##
## The layers stay nobody's children and hold no chunk, so nothing here touches
## a device. The effect layer's half is asserted where it is made, in the
## effect layer's own suite.
extends "res://tests/test_framework.gd"

var _layers: Array[SaLayer] = []


func after_each() -> void:
    for layer in _layers:
        layer.free()
    _layers = []


func _layer_with_mask() -> SaLayer:
    var layer := SaLayer.new()
    layer.mask = SaMask.new()
    _layers.append(layer)
    return layer


func test_a_noted_step_folds_its_own_mask_and_its_bases() -> void:
    var layer := _layer_with_mask()
    var base := _layer_with_mask()
    var other := _layer_with_mask()
    var ledger := SaFoldLedger.new()
    var clipped: Array[Dictionary] = [SaLayerStack.entry(layer, SaLayer.BLEND_MODE.NORMAL, 1.0)]
    ledger.note(
        SaLayerStack.clip_group(SaLayerStack.entry(base, SaLayer.BLEND_MODE.NORMAL, 1.0), SaLayer.BLEND_MODE.NORMAL, 1.0, clipped)
    )
    assert_true(ledger.folds(layer.mask), "The clipped step's own mask is baked")
    assert_true(ledger.folds(base.mask), "The clip base's mask is baked too")
    assert_false(ledger.folds(other.mask), "A mask no step read is not")
    assert_false(ledger.folds(null), "No mask is never baked")
    assert_false(ledger.folds_effect(layer), "A plain layer is no effect")


func test_forget_leaves_nothing_folded() -> void:
    var layer := _layer_with_mask()
    var ledger := SaFoldLedger.new()
    ledger.note({SaLayerStack.LAYER: layer})
    ledger.forget()
    assert_false(ledger.folds(layer.mask), "A forgotten mask is not baked")
    assert_true(ledger.masks.is_empty() and ledger.effects.is_empty(), "Nothing is left")
