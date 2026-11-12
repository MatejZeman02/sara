## The blend menu's sections, its favourites, and what a module mode does.
##
## The control is one BlendModeButton in both places a mode is picked, so every
## assertion here about the bar's menu is also one about the Layers docker's,
## bar the one thing they differ in: Erase.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const REQUIRES_GPU := true


func _button(include_hidden: bool = true) -> BlendModeButton:
    var button := BlendModeButton.new()
    button.registry = Fixtures.make_registries().blend_modes
    button.include_hidden_in_layers = include_hidden
    button.refresh()
    return button


## The rows the list draws, in order. The list is a column of controls
## rather than a `PopupMenu`, so a section's labels come off the button rather
## than off a submenu.
func _labels(button: BlendModeButton, section: String) -> Array[String]:
    return button.section_labels(section)


## Every built-in names a section, which is the half of this that a flat list of twenty
## would not say.
func test_every_builtin_mode_is_in_a_named_section() -> void:
    var button := _button()
    var titles := button.section_titles()
    assert_eq(
        titles,
        ["Normal", "Erase", "Darken", "Lighten", "Contrast", "Comparative", "Colour"] as Array[String],
        "Krita's groups, in the order the sort keys give, and no Other while every mode has a category"
    )

    var counted := 0
    for title in titles:
        counted += button.section_labels(title).size()
    assert_eq(counted, button.mode_ids().size(), "Every mode is in exactly one section")
    assert_eq(_labels(button, "Normal").size(), 4, "Normal holds the plain one and the three named spaces")
    assert_true(_labels(button, "Darken").has("Multiply"), "Multiply darkens")
    assert_true(_labels(button, "Colour").has("Saturation"), "and Saturation is a component")
    button.free()


## A module mode that says nothing about grouping is still
## reachable, in the section that exists for exactly that.
func test_a_mode_with_no_category_lands_in_other() -> void:
    var registries := Fixtures.make_registries()
    var mode := SaBlendModeDescriptor.create(&"uncategorised", "multiply")
    mode.display_name = "Uncategorised"
    mode.sort_order = 900
    assert_eq(mode.category, &"general", "A descriptor names no section by default")
    assert_eq(mode.section(), SaBlendModeDescriptor.CATEGORY_OTHER, "which resolves to Other")
    registries.context.for_module(&"third-party").register_blend_mode(mode)

    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.refresh()
    assert_eq(button.section_titles()[-1], "Other", "Other is the last section, and only exists when something is in it")
    assert_true(_labels(button, "Other").has("Uncategorised"), "and the mode is in it")

    # A category nobody has a title for is the same case: a menu cannot show a
    # section it cannot name.
    mode.category = &"nonesuch"
    assert_eq(mode.section(), SaBlendModeDescriptor.CATEGORY_OTHER, "An unknown category is Other too")
    button.free()


## The favourites are a section of their own at the top, from the settings.
func test_the_favourites_sit_above_the_sections() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["normal", "multiply"]

    var button := _button()
    assert_eq(button.favorite_ids(), [&"normal", &"multiply"] as Array[StringName], "Two favourites, in the order kept")
    var popup := button.popup
    assert_eq(popup.section_titles()[0], "Favourites", "The first heading is the favourites' own")
    var ids := popup.row_ids()
    assert_eq(ids[0], &"normal_fav", "then the first favourite, as its own row")
    assert_eq(ids[1], &"multiply_fav", "then the second")

    SaSettings.blend_favorites = []
    assert_true(button.favorite_ids().is_empty(), "The button follows the setting")
    assert_false(popup.section_titles()[0] == "Favourites", "and shows no heading over an empty section")

    SaSettings.blend_favorites = was
    button.free()


## Ticking the box on a mode's own row writes the setting, which is what survives
## a restart. Were the list a submenu, this would mean opening a second one that listed every
## mode again and finding the same name in it.
func test_a_tick_on_the_mode_s_own_row_moves_the_setting() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["normal"]

    var button := _button()
    var popup := button.popup
    assert_not_null(popup.check_box(&"screen"), "Screen's own row carries a box")
    assert_false(popup.is_checked(&"screen"), "and is not a favourite yet")

    assert_true(popup.press_check(&"screen"), "The box takes a press")
    assert_true(SaSettings.blend_favorites.has("screen"), "The tick wrote the setting")
    assert_true(button.favorite_ids().has(&"screen"), "and the rebuilt menu shows it")

    SaSettings.toggle_blend_favorite(&"screen")
    assert_false(SaSettings.blend_favorites.has("screen"), "and a second tick takes it off again")

    SaSettings.blend_favorites = was
    button.free()


## Erase is a brush concept, so the Layers docker's menu is without it, in its
## sections and in its favourites both.
func test_the_layer_menu_has_no_erase_even_as_a_favourite() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["normal", "erase"]

    var bar_menu := _button(true)
    var layer_menu := _button(false)
    assert_true(bar_menu.section_titles().has("Erase"), "The bar's menu has the Erase section")
    assert_false(layer_menu.section_titles().has("Erase"), "The layer menu has not")
    assert_true(bar_menu.favorite_ids().has(&"erase"), "Erase is a favourite on the bar")
    assert_false(layer_menu.favorite_ids().has(&"erase"), "and is dropped from the layer menu's favourites")

    SaSettings.blend_favorites = was
    bar_menu.free()
    layer_menu.free()


## Choosing announces the id, never an index, and the button says what is chosen.
func test_choosing_a_mode_announces_its_id() -> void:
    var button := _button()
    var announced: Array[StringName] = []
    button.mode_selected.connect(func(mode_id: StringName) -> void: announced.append(mode_id))

    var popup := button.popup
    var darken := button.section_ids("Darken")
    assert_true(popup.press_row(darken[0]), "The first darkening row takes a press")
    assert_eq(announced, [&"multiply"] as Array[StringName], "The first of the darkening modes is Multiply")
    assert_eq(button.current, &"multiply", "The button holds it")
    assert_eq(button.text, "Multiply", "and shows it")
    assert_true(popup.is_marked(darken[0]), "The chosen one is the row the list draws marked")

    assert_true(button.select_mode(&"screen"), "Setting it from code works")
    assert_eq(announced.size(), 1, "and says nothing, because only the painter's own click should")
    assert_false(popup.is_marked(darken[0]), "and the mark left the row the chosen mode is not on")
    button.free()


## Plain Normal's label names the space it is mixing in, which is the one thing
## the old dropdown did that a section must not lose.
func test_plain_normal_still_names_the_document_space() -> void:
    var button := _button()
    button.space = SaColorSpace.oklab()
    button.refresh()
    assert_true(_labels(button, "Normal").has("Normal (Oklab)"), "On an Oklab document Normal says Oklab")
    button.space = SaColorSpace.srgb()
    button.refresh()
    assert_true(_labels(button, "Normal").has("Normal (sRGB)"), "and on an sRGB one, sRGB")
    button.free()


## The list is a child of the button, which is what lets the theme pass in SaUI
## reach it: the pass walks `get_children()`, and a popup it missed drew at the
## engine's default size beside a control at the theme's.
func test_the_list_is_a_child_the_theme_pass_walks() -> void:
    var button := _button()
    var named: Array[String] = []
    for child in button.get_children():
        named.append(child.name)
    assert_true(named.has("BlendChoicePopup"), "The list is a child of the button")

    # A rebuild refills the one list rather than building a second, which is
    # what a list of submenus would need a free for.
    var before := button.get_children().size()
    button.registry = Fixtures.make_registries().blend_modes
    button.refresh()
    assert_eq(button.get_children().size(), before, "A rebuild leaves one list, not two")
    assert_false(button.section_labels("Normal").is_empty(), "and the sections are still findable by title")
    button.free()


## The rule the list keeps, and the one `harness/drivers/tests/test_menu_choice.gd` fails a run over from
## the other side: nothing in the list is a radio item, and the chosen row says
## so by being drawn differently rather than by a dot beside every row that is
## not.
func test_the_list_draws_the_chosen_row_marked() -> void:
    var was: Array = SaSettings.blend_favorites
    SaSettings.blend_favorites = ["multiply"]

    var button := _button()
    var popup := button.popup
    assert_true(button.select_mode(&"multiply"), "Multiply is choosable")

    assert_true(popup.is_marked(&"multiply"), "Its own row is marked")
    assert_true(popup.is_marked(&"multiply_fav"), "and so is its row in the favourites, being the same mode")
    assert_false(popup.is_marked(&"screen"), "and nothing else is")

    for id in popup.row_ids():
        var row := popup.label_button(id)
        assert_false(row.toggle_mode, "No row is a toggle, so none of them can carry a radio dot: %s" % id)

    SaSettings.blend_favorites = was
    button.free()
