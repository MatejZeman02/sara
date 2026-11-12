## The vector module keeps loading and its tools and layer kind are not offered
## to a painter until Show experimental tools is on.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The Text tool draws through the vector layer, so the module cannot go. A
## fresh profile's toolbox and Layer menu leave the Shape and Object tools and
## the vector kind out, the registry and the tool machine still hold them for
## the door and for a document that already has a vector layer, and the switch
## brings them back.
extends "res://tests/test_framework.gd"

const REQUIRES_GPU := true

const Fixtures = preload("res://tests/fixtures.gd")
const Module = preload("res://modules/sara-base-modules/vector/module.gd")
const ToolBoxDockerScript = preload("res://ui/dockers/toolbox/toolbox_docker.gd")

var _surface: SaSurface = null
var _registries: SaRegistries = null
var _module: SaModule = null
var _was_on := false


func before_each() -> void:
    _was_on = SaSettings.experimental_tools
    SaSettings.experimental_tools = false
    _surface = Fixtures.make_surface(Vector2i(256, 256))
    _registries = Fixtures.make_registries(_surface)
    _module = Module.new()
    _module.context = _registries.context.for_module(&"vector")
    _module.register(_module.context)


func after_each() -> void:
    SaSettings.experimental_tools = _was_on
    Fixtures.teardown(_surface, null)
    _surface = null
    _registries = null
    _module = null


func _ids(descriptors: Array) -> Array:
    return descriptors.map(func(descriptor: Object) -> StringName: return descriptor.id)


func test_a_fresh_profile_offers_no_vector_tool_and_the_switch_brings_them_back() -> void:
    var tools := _registries.tools
    assert_false(SaSettings.experimental_tools, "The switch is off on a fresh profile")
    assert_false(_ids(tools.list_tools()).has(&"vector_shape"), "the Shape tool is not in the toolbox's list")
    assert_false(_ids(tools.list_tools()).has(&"vector_object"), "nor is the Object tool")
    assert_true(tools.has(&"vector_shape") and tools.has(&"vector_object"), "yet both stay registered for the door")
    SaSettings.experimental_tools = true
    assert_true(_ids(tools.list_tools()).has(&"vector_shape"), "the switch brings the Shape tool back")
    assert_true(_ids(tools.list_tools()).has(&"vector_object"), "and the Object tool")


func test_the_toolbox_draws_no_button_for_a_vector_tool_until_the_switch_is_on() -> void:
    var docker := ToolBoxDockerScript.new() as ToolBoxDocker
    docker.rebuild_from_registry(_registries.tools)
    assert_true(docker.tools_in_category_of("vector_shape").is_empty(), "no button holds the Shape tool")
    SaSettings.experimental_tools = true
    docker.rebuild_from_registry(_registries.tools)
    assert_true(docker.tools_in_category_of("vector_shape").has("vector_shape"), "the switch gives it a button")
    docker.free()


func test_the_vector_layer_kind_is_not_added_by_a_painter_but_is_still_known() -> void:
    var kinds := _registries.layer_types
    var addable := _ids(SaLayerMenuRows.addable(kinds))
    assert_false(addable.has(&"vector"), "the Layer menu and the layers arrow do not offer a vector layer")
    var found := false
    for row: SaSearchRegistry.Row in kinds.search_rows():
        found = found or row.title.contains("Vector")
    assert_false(found, "nor does the search")
    assert_true(kinds.has(&"vector"), "yet the kind is registered, so a document holding one opens and the door adds one")
    SaSettings.experimental_tools = true
    assert_true(_ids(SaLayerMenuRows.addable(kinds)).has(&"vector"), "the switch offers it again")
