## Declaring a filter builds its rows over a dialog nobody shows and frees what
## they made. Attaching Hue/Saturation/Lightness printed two engine errors at the
## first composite, because the walk that freed the controls put a freed one into
## a typed array. Every filter the base module registers is
## declared here, and the engine says nothing and keeps no node.
extends "res://tests/test_framework.gd"

const BaseModule = preload("res://modules/sara-base-modules/base/module.gd")


## The registries with the base module registered through the public door.
func _base_filters() -> SaFilterRegistry:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    var base := BaseModule.new()
    base.register(registries.context.for_module(base.get_id()))
    return registries.filters


## Declares a fresh copy of *filter*, the way `SaFilter._declare` does at the
## first composite after an attach, and answers the errors it logged and the
## nodes it left outside the tree. A pixel function is one class for every
## file, so its fresh copy is built from the file and the entry it was
## registered with, as Threshold has been.
func _declare(filter: SaFilter) -> Dictionary:
    var fresh: SaFilter = _fresh(filter)
    var errors := SaErrorCatcher.new()
    var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
    OS.add_logger(errors)
    SaDialog.declare_filter(fresh)
    OS.remove_logger(errors)
    var orphans_after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
    var caught := errors.described([SaErrorCatcher.ERROR])
    return {"errors": caught, "orphans": int(orphans_after - orphans_before), "settled": fresh.store.settled}


func _fresh(filter: SaFilter) -> SaFilter:
    var pixel := filter as SaPixelFilter
    if pixel != null:
        return SaPixelFilter.new(pixel.pixels.path, pixel.entry_title, pixel.margin, pixel.entry_family)
    return filter.get_script().new()


func test_the_base_module_registers_filters_to_declare() -> void:
    var keys := _base_filters().list_keys()
    assert_true(keys.size() >= 18, "The base module registers its filters, %d of them" % keys.size())
    assert_true(keys.has(&"sara-base-modules.hue_saturation_lightness"), "Hue/Saturation/Lightness among them: %s" % [keys])


func test_hue_saturation_lightness_declares_without_an_error() -> void:
    var filters := _base_filters()
    var declared := _declare(filters.get_filter(&"sara-base-modules.hue_saturation_lightness"))
    assert_eq(declared["errors"], PackedStringArray(), "Declaring it logs no engine error")
    assert_eq(declared["orphans"], 0, "and leaves no control outside the tree")


func test_every_base_filter_declares_without_an_error_or_a_leaked_control() -> void:
    var filters := _base_filters()
    for key: StringName in filters.list_keys():
        var declared := _declare(filters.get_filter(key))
        assert_eq(declared["errors"], PackedStringArray(), "%s declares with no engine error" % key)
        assert_eq(declared["orphans"], 0, "%s leaves no control outside the tree" % key)
        assert_true(declared["settled"], "%s has its store settled" % key)
