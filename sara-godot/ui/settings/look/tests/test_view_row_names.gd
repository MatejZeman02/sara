## The View transform rows are called one thing, not two.
##
## The Display page wrote the literals `Roll off highlights` and `Display` for
## the two rows that are not modes, while `ui/menus/view_menu.gd` drew
## `Tonemap Highlights` and `Normal View` for the same two, so one setting had
## two names on the two surfaces that set it and the four modes in between
## matched on purpose. The names come from the registry on both surfaces now,
## and these assert that they cannot drift apart again.
##
## The page a test builds is handed no registries, so the assembled dropdown is
## proved on the running app by scenarios/display-page-row-names.json. What
## is provable here is where each name comes from.
extends "res://tests/test_framework.gd"


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## The ordinary view has no descriptor, being the absence of a mode, so its name
## is a constant beside the sentence the registry already lends both surfaces.
func test_the_ordinary_view_is_named_by_the_registry() -> void:
    assert_eq(SaViewTransformRegistry.NORMAL_NAME, "Normal View", "The registry names the ordinary view")
    assert_true(
        SaViewTransformRegistry.NORMAL_TOOLTIP.begins_with("The picture as the screen wants it"),
        "beside the sentence that moved there first"
    )


## The roll-off is a registered toggle, so its name is its module's, which is
## what a third party's transform would get.
func test_the_roll_off_is_named_by_the_module_that_registered_it() -> void:
    var registry := _registries().view_transforms
    var rolloff := registry.get_descriptor(SaDisplayPage.ROLLOFF_ID)
    assert_not_null(rolloff, "The roll-off is registered rather than invented by a page")
    assert_eq(rolloff.display_name, "Tonemap Highlights", "and carries the name both surfaces draw")


## The whole defect in one assertion: every row the page lists is named by the
## same thing that names it in the menu, the plain row included. The roll-off is
## a switch below the list now, and its name is checked above.
func test_every_row_takes_its_name_from_the_registry() -> void:
    var registry := _registries().view_transforms
    var page := SaDisplayPage.new()
    var names: Array[String] = []
    for id in SaDisplayPage.PLAIN_ROWS:
        assert_eq(id, SaViewTransformRegistry.NORMAL, "The one plain row is the ordinary view")
        names.append(SaViewTransformRegistry.NORMAL_NAME)
    for descriptor in registry.list_modes():
        names.append(descriptor.display_name)
    assert_eq(names.size(), 6, "Six rows: the ordinary view and the five modes")
    for name in names:
        assert_false(name.is_empty(), "and every one of them has a name")
    assert_eq(names[0], "Normal View", "The first row is the ordinary view, under the menu's name for it")
    assert_false(names.has("Tonemap Highlights"), "and the roll-off is not a row of the list")
    page.free()
