## A pen source registers through the door, the tenth registry.
##
## A module reading the pen outside Godot puts its source on `SaPenRegistry`
## through `SaContext.register_pen_source`, the way any module registers
## anything, and the tool machine and a brush module ask the registry without
## naming the module.
## Unloading the module takes the source with it.
extends "res://tests/test_framework.gd"


class Known:
    extends SaPenSource

    var pen := SaPenSource.State.new()

    func now() -> SaPenSource.State:
        return pen.copy()


func test_a_module_registers_a_source_and_the_registry_answers_it() -> void:
    var registries := SaRegistries.new()
    var context := registries.build_context(Callable(), Callable())
    assert_eq(context.pens, registries.pens, "The context carries the app's pen registry")
    assert_null(registries.pens.now(), "With no source the registry knows nothing")
    var scoped := context.for_module(&"linux_pen")
    var source := Known.new()
    source.pen.barrels = 1 << SaPenSource.Barrel.SECOND
    assert_true(scoped.register_pen_source(source), "A module registers its source")
    assert_eq(registries.pens.source(), source, "and the registry answers it")
    assert_true(registries.pens.now().held(SaPenSource.Barrel.SECOND), "with the state it reads")
    var brush := context.for_module(&"sara-stamp-brush")
    assert_true(brush.pens.now().held(SaPenSource.Barrel.SECOND), "and a brush module's own context reads it unnamed")
    scoped.remove_all_registrations()
    assert_null(registries.pens.source(), "Unloading the module takes its source")


func test_the_newest_source_is_asked() -> void:
    var pens := SaPenRegistry.new()
    var older := Known.new()
    var newer := Known.new()
    newer.pen.touching = true
    pens.register(older, &"first")
    pens.register(newer, &"second")
    assert_true(pens.now().touching, "The newest source answers")
    pens.unregister_module(&"second")
    assert_false(pens.now().touching, "and the older one once it goes")


func test_the_state_is_a_copy() -> void:
    var source := Known.new()
    var pens := SaPenRegistry.new()
    pens.register(source)
    var read := pens.now()
    read.barrels = 7
    assert_eq(source.pen.barrels, 0, "A reader writing its copy changes nothing of the source")
