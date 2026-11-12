## A layer whose blend mode no loaded module registers is named in the problems
## when its document opens.
##
## A public build carries no mixing module, so a document painted with
## its blend opens there with its layers kept and drawn as Normal. The rebind the
## app runs on every open is what knows a mode is missing, so it says so once
## for each such mode, naming the mode and the layers set to it, and keeps the
## layer's id so the next save writes it back.
extends "res://tests/test_framework.gd"

const MIXING: StringName = &"mixing_blend"

var _registry: SaBlendModeRegistry = null
var _was_announcing: bool = true
var _problems_before: int = 0


func before_each() -> void:
    _was_announcing = SaProblems.announce
    SaProblems.announce = false
    _problems_before = SaProblems.pending.size()
    _registry = SaBlendModeRegistry.new()
    _registry.register(SaBlendModeDescriptor.create(&"normal", "multiply"), &"probe")


func after_each() -> void:
    SaProblems.pending = SaProblems.pending.slice(0, _problems_before)
    SaProblems.announce = _was_announcing
    _registry = null


func _layer(layer_name: String, mode: StringName) -> SaLayer:
    var layer := SaLayer.new()
    layer.name = layer_name
    layer.blend_mode = mode
    return layer


func _said() -> PackedStringArray:
    return SaProblems.pending.slice(_problems_before)


func test_a_mode_no_module_registers_is_named_once_with_its_layers() -> void:
    var layers: Array = [_layer("Glaze", MIXING), _layer("Ground", &"normal"), _layer("Scumble", MIXING)]
    _registry.rebind(layers)
    var said := _said()
    assert_eq(said.size(), 1, "One line for the one missing mode: %s" % [said])
    if said.size() == 1:
        assert_true(said[0].contains("'mixing_blend'"), "naming the mode, '%s'" % said[0])
        assert_true(said[0].contains("'Glaze'") and said[0].contains("'Scumble'"), "and both layers set to it")
        assert_false(said[0].contains("'Ground'"), "and not the layer whose mode is registered")
    assert_eq((layers[0] as SaLayer).blend_mode, MIXING, "The layer keeps its mode, so a save writes it back")
    for layer: SaLayer in layers:
        layer.free()


func test_a_document_whose_modes_are_all_registered_says_nothing() -> void:
    var layer := _layer("Ground", &"normal")
    _registry.rebind([layer])
    assert_eq(_said(), PackedStringArray(), "Nothing is missing, so nothing is said")
    layer.free()


func test_a_registry_with_no_mode_yet_says_nothing() -> void:
    var empty := SaBlendModeRegistry.new()
    var layer := _layer("Glaze", MIXING)
    empty.rebind([layer])
    assert_eq(_said(), PackedStringArray(), "A run with nothing loaded names no layer")
    layer.free()
