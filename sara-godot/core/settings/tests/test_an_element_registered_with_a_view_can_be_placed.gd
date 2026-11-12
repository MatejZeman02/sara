## An element registered with a view can be placed, and one without cannot.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The maintainers' ruling 1 of 2026-10-07: "what can be placed is exactly the
## registered layout elements", and a module adds placeable elements through
## the same door. So the module here is a test module whose `register` makes a
## category and two elements through `SaSettings`, the calls a third party
## makes, one with a view and one with none. The drag bar, the grip and the top
## bar's Second Row are where things go rather than things, so a view handed
## for one of them is refused.
extends "res://tests/test_framework.gd"

## The test module's category and its two elements, with the titles
## Preferences shows for them.
const CATEGORY := "D1ViewsFixture"
const CATEGORY_TITLE := "Views Fixture"
const VIEWED := "Probe"
const VIEWED_TITLE := "Probe Slider"
const BARE := "Bare"


## A module as a third party writes one: it registers its category, an element
## with a view and an element with none, and tries to hand the three places a
## view. Kept alive by the suite, because a loaded module is kept by the loader
## and its views are its own methods.
class ViewsModule:
    extends SaModule

    func get_id() -> StringName:
        return &"d1-views-fixture"

    func get_name() -> String:
        return "Views Fixture"

    func register(_ctx: SaContext) -> void:
        SaSettings.register_layout_category(CATEGORY, CATEGORY_TITLE, ["Drag Handle", "Resizer", VIEWED, BARE])
        SaSettings.register_layout_element(CATEGORY, VIEWED, VIEWED_TITLE, false, "", _build_probe)
        SaSettings.register_layout_element(CATEGORY, BARE, "Bare Row")
        SaSettings.register_layout_element(CATEGORY, "Drag Handle", "Drag Handle", false, "", _build_probe)
        SaSettings.register_layout_element(CATEGORY, "Resizer", "Resizer", false, "", _build_probe)
        var row := SaSettings.ROW_SENTINEL
        SaSettings.register_layout_element("TopMenuBar", row, row, false, "", _build_probe)

    func _build_probe() -> Control:
        var slider := HSlider.new()
        slider.name = "ProbeSlider"
        return slider


var _module: ViewsModule = null
var _announced: Array = []


func before_each() -> void:
    _announced.clear()
    SaSettings.element_view_registered.connect(_on_view_registered)
    _module = ViewsModule.new()
    _module.register(SaContext.new())


## Takes back everything the module registered, so the autoload, which outlives
## the suite, holds what it held before.
func after_each() -> void:
    SaSettings.element_view_registered.disconnect(_on_view_registered)
    for element: String in [VIEWED, BARE, "Drag Handle", "Resizer"]:
        SaSettings.unregister_layout_element(CATEGORY, element)
    SaSettings.unregister_layout_element("TopMenuBar", SaSettings.ROW_SENTINEL)
    SaSettings.unregister_layout_category(CATEGORY)
    _module = null


func _on_view_registered(category: String, element: String) -> void:
    _announced.append([category, element])


## The category as the placeable list holds it, or empty.
func _listed(category: String) -> Dictionary:
    for entry: Dictionary in SaSettings.placeable_elements():
        if entry["id"] == category:
            return entry
    return {}


func test_the_element_with_a_view_is_placeable_under_its_title() -> void:
    assert_true(SaSettings.is_placeable(CATEGORY, VIEWED), "The element the module handed a view is placeable")
    var listed := _listed(CATEGORY)
    assert_false(listed.is_empty(), "Its category is among the placeable elements")
    assert_eq(listed.get("title"), CATEGORY_TITLE, "under the title the module gave the category")
    var elements: Array = listed.get("elements", [])
    assert_eq(elements, [{"id": VIEWED, "title": VIEWED_TITLE}], "and holds that element under its own title, alone")


func test_a_view_is_built_fresh_each_time() -> void:
    var first := SaSettings.build_element_view(CATEGORY, VIEWED)
    var second := SaSettings.build_element_view(CATEGORY, VIEWED)
    assert_true(first is HSlider, "The first build is the module's control")
    assert_true(second is HSlider, "and so is the second")
    assert_true(first != second, "two builds are two controls, not one handed out twice")
    if first != null:
        first.free()
    if second != null:
        second.free()


func test_an_element_with_no_view_is_not_placeable() -> void:
    assert_false(SaSettings.is_placeable(CATEGORY, BARE), "An element registered with no view is not placeable")
    assert_null(SaSettings.build_element_view(CATEGORY, BARE), "and builds nothing")
    assert_true(SaSettings.get_layout_order(CATEGORY).has(BARE), "though it is still a row of its category")


func test_the_places_are_not_placeable_even_with_a_view() -> void:
    assert_false(SaSettings.is_placeable(CATEGORY, "Drag Handle"), "The Drag Handle is where things go, view or not")
    assert_false(SaSettings.is_placeable(CATEGORY, "Resizer"), "and so is the Resizer")
    assert_false(SaSettings.is_placeable("TopMenuBar", SaSettings.ROW_SENTINEL), "and the top bar's Second Row")
    assert_null(SaSettings.build_element_view(CATEGORY, "Drag Handle"), "a place builds nothing")
    for entry: Dictionary in SaSettings.placeable_elements():
        for element: Dictionary in entry["elements"]:
            assert_false(
                SaSettings.ELEMENT_PLACES.has(element["id"]), "%s is listed as placeable under %s" % [element["id"], entry["id"]]
            )


func test_a_view_that_registers_is_announced_once() -> void:
    assert_eq(_announced, [[CATEGORY, VIEWED]], "The one view that took is announced, the places and the bare row are not")
    SaSettings.register_layout_element(CATEGORY, VIEWED, VIEWED_TITLE, false, "", _module._build_probe)
    assert_eq(_announced.size(), 1, "and a second registration of the same view is not announced again")


func test_a_view_goes_with_its_element() -> void:
    SaSettings.unregister_layout_element(CATEGORY, VIEWED)
    assert_false(SaSettings.is_placeable(CATEGORY, VIEWED), "An element taken back is no longer placeable")
    assert_true(_listed(CATEGORY).is_empty(), "and a category with nothing placeable is not listed")
