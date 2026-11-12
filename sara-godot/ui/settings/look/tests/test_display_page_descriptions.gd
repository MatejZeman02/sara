## Preferences > Display says what each View transform row does, and says it
## once.
##
## The View transform dropdown explains what each one is and means for the
## user. The page carried an explanation, in the
## description beside the control, and it was a paraphrase of four of the six
## rows written on the page itself. It named Display, Roll off highlights, Raw
## and False Colour, said nothing about Lightness Check or Soft Proof, and could
## say nothing at all about a mode a module registers.
##
## So the fix is not more text on the page, it is the text moving to where the
## View menu already reads it. These assert that half: every row a person can
## pick has a sentence and the sentence is the registry's. The assembled page is
## proved on the running app by scenarios/display-page-explain.json, because a
## settings page built in a test is handed no registries and a tooltip is not in
## a screenshot either way.
extends "res://tests/test_framework.gd"


func _registries() -> SaRegistries:
    var registries := SaRegistries.new()
    registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    registries.register_builtins()
    return registries


## Every row of the dropdown, in the order the page builds them: the one that
## is not a mode, then every registered mode.
func _row_ids(registry: SaViewTransformRegistry) -> Array[StringName]:
    var ids: Array[StringName] = SaDisplayPage.PLAIN_ROWS.duplicate()
    for descriptor in registry.list_modes():
        ids.append(descriptor.id)
    return ids


func test_every_row_of_the_dropdown_has_a_sentence() -> void:
    var registry := _registries().view_transforms
    var ids := _row_ids(registry)
    assert_eq(ids.size(), 6, "Six rows: the ordinary view and the five modes")
    for id in ids:
        assert_true(not registry.tooltip_for(id).is_empty(), "'%s' says what it does" % id)


## The point of the change. The sentence a mode shows on this page is the one its
## descriptor carries, which is the one `ui/menus/view_menu.gd` puts on its own
## row, so the two surfaces cannot drift apart.
func test_a_mode_says_the_same_thing_here_as_in_the_view_menu() -> void:
    var registry := _registries().view_transforms
    for descriptor in registry.list_modes():
        assert_eq(registry.tooltip_for(descriptor.id), descriptor.tooltip, "%s reads its own descriptor" % descriptor.id)
    var rolloff := registry.get_descriptor(SaDisplayPage.ROLLOFF_ID)
    assert_not_null(rolloff, "The roll-off is a registered toggle, not a row the page invented")
    assert_eq(registry.tooltip_for(SaDisplayPage.ROLLOFF_ID), rolloff.tooltip, "and the switch's sentence reads it")


## The ordinary view is the one row with no descriptor, because it is the absence
## of a mode and nothing registers it. Its sentence is a constant on the registry
## rather than a string on the page, so the page holds no copy of anything.
func test_the_ordinary_view_takes_its_sentence_from_the_registry() -> void:
    var registry := SaViewTransformRegistry.new()
    assert_eq(
        registry.tooltip_for(SaViewTransformRegistry.NORMAL),
        SaViewTransformRegistry.NORMAL_TOOLTIP,
        "No mode is still a row, and it says what it does"
    )
    assert_eq(SaDisplayPage.PLAIN_ROWS[0], SaViewTransformRegistry.NORMAL, "and it is the page's first row")


## A mode nobody has written a page row for is described anyway, which is the
## whole reason the text moved. A paraphrase on the page could not do this.
func test_a_module_s_mode_is_described_without_the_page_being_touched() -> void:
    var registry := SaViewTransformRegistry.new()
    var descriptor := SaViewTransformDescriptor.create(&"mixing", "Mixing", SaViewTransformDescriptor.Kind.MODE)
    descriptor.tooltip = "The canvas as the mixing module would paint it."
    assert_true(registry.register(descriptor, &"a-module"), "The mode registers through the public door")
    assert_eq(registry.tooltip_for(&"mixing"), descriptor.tooltip, "and the dropdown would say what it does")
    assert_true(_row_ids(registry).has(&"mixing"), "because it is one of the rows")


## An id nobody registered is "" rather than an error, so a page that outlives a
## module's unload shows a row with no sentence instead of failing to build.
func test_an_unknown_id_is_empty_rather_than_a_failure() -> void:
    assert_eq(SaViewTransformRegistry.new().tooltip_for(&"nothing_here"), "", "Nothing registered, nothing said")


## The dump asks the page for its own report, so a capture taken with
## Preferences shut carries an empty section rather than a missing key.
func test_the_state_dump_section_is_empty_when_the_page_is_not_open() -> void:
    var window := Window.new()
    assert_eq(SaDisplayPage.capture_state(window), {}, "No page, no rows")
    window.free()
