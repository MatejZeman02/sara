## The Info docker's Blend row reads the label the blend dropdown shows (d45).
##
## It capitalized the registry id, so the module's Hard Mix read with the course prefix
## beside a Layers docker reading Hard Mix, `normal_srgb` read "Normal Srgb"
## where the dropdown says sRGB Normal, and plain Normal lost the bracket that
## names the space it mixes in. Every case is asserted against a
## `BlendModeButton` over the same registry, because agreeing with the dropdown
## is the claim and a literal alone would pass while the two drifted apart.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const DOCKER := preload("res://ui/dockers/panels/info_docker.gd")

## A module's mode, now that Hard Mix is the skeleton's: the test module that
## ships a blend kernel of its own.
const FixtureModule = preload("res://tests/fixtures/blend-kernel/modules/blend-kernel-fixture/module.gd")
const MODE_ID: StringName = FixtureModule.MODE_ID

var _registries: SaRegistries = null
var _module: SaModule = null
var _scoped: SaContext = null


func before_each() -> void:
    _registries = Fixtures.make_registries()
    _module = FixtureModule.new()
    _scoped = _registries.context.for_module(_module.get_id())
    _module.context = _scoped
    _module.register(_scoped)


func after_each() -> void:
    if _module != null and _module.context != null:
        _module.unregister(_scoped)
        _scoped.remove_all_registrations()
        _module.context = null
    _module = null
    _scoped = null
    _registries = null


## What the Layers docker's dropdown reads for *mode_id* in a document of *space*.
func _dropdown_label(mode_id: StringName, space: SaColorSpace) -> String:
    var button := BlendModeButton.new()
    button.registry = _registries.blend_modes
    button.include_hidden_in_layers = false
    button.space = space
    button.refresh()
    var label := String(button.text) if button.select_mode(mode_id) else ""
    button.free()
    return label


func test_the_row_reads_each_mode_as_the_dropdown_does() -> void:
    var registry := _registries.blend_modes
    var srgb := SaColorSpace.srgb()
    var cases: Array = [
        [&"normal", srgb, "Normal (sRGB)", "plain Normal keeps the bracket naming the space it mixes in"],
        [&"normal_srgb", srgb, "sRGB Normal", "a built-in whose id is not its name reads as its name"],
        [&"multiply", srgb, "Multiply", "a built-in whose id is its name is unchanged"],
        [&"hard_mix", srgb, "Hard Mix", "Hard Mix, once a module's mode, carries no prefix"],
        [MODE_ID, srgb, "Kept Hard Mix", "and a module's mode reads as the module named it"],
        [&"normal", SaColorSpace.oklab(), "Normal (Oklab)", "and the bracket follows the document"],
    ]
    for entry: Array in cases:
        var shown := _dropdown_label(entry[0], entry[1])
        assert_eq(shown, entry[2], "The dropdown reads '%s' for %s" % [entry[2], entry[0]])
        assert_eq(SaInfoSection.blend_text(entry[0], registry, entry[1]), shown, "The Blend row agrees: " + String(entry[3]))


## A layer from a module that is not installed keeps its type id and its mode id
## (a missing module is not a failed load), and no dropdown has a label
## for that id, so the row falls back to the id in words rather than going blank.
func test_an_id_no_registry_holds_reads_as_the_id() -> void:
    assert_eq(
        SaInfoSection.blend_text(&"gone_module_glow", _registries.blend_modes, SaColorSpace.srgb()),
        "Gone Module Glow",
        "An unknown id is shown in words"
    )
    assert_eq(SaInfoSection.blend_text(&"multiply", null, null), "Multiply", "and so is any id with no registry to ask")


## The row itself, through the function the ticker calls, for the built-in and
## the module's mode.
func test_the_active_layer_section_writes_the_label() -> void:
    var docker: InfoDocker = DOCKER.new()
    var layer := SaLayer.new()
    layer.name = "Layer 1"
    var value: Label = docker._section_boxes["Active layer"].rows["Blend"][1]

    layer.blend_mode = &"normal_srgb"
    docker._section_boxes["Active layer"]._active_layer_rows(layer, _registries.blend_modes, SaColorSpace.srgb())
    assert_eq(value.text, "sRGB Normal", "The row names the built-in by its label")

    layer.blend_mode = MODE_ID
    docker._section_boxes["Active layer"]._active_layer_rows(layer, _registries.blend_modes, SaColorSpace.srgb())
    assert_eq(value.text, "Kept Hard Mix", "and the module's mode by its own")

    layer.free()
    docker.free()
