## A blend mode keeps its English name in the tooltip under another language.
##
## The blend mode names are translated, and the English is kept in the tooltip for
## the blend modes only, because a painter following an English tutorial
## searches for Multiply and has to find it. The Czech catalogue of
## `tests/fixtures/modules/language-fixture/` carries the blend list's words.
##
## Read off the rows' `tooltip_text` rather than off a tooltip on screen, for the
## reason `test_the_blend_list_tells_its_normals_and_its_marks_apart.gd` gives:
## it is the property the engine draws one from.
extends "res://tests/test_framework.gd"

const Fixtures = preload("res://tests/fixtures.gd")
const LanguageFixture = preload("res://tests/fixtures/modules/language-fixture/module.gd")
const REQUIRES_GPU := true

## A mode no catalogue has a word for, the way a module's own mode arrives.
const UNTRANSLATED := &"t6_untranslated"


## The fixture module registered into *registries* the way the loader does it,
## with a context of its own, which `remove_all_registrations` empties again.
func _register_fixture(registries: SaRegistries) -> SaContext:
    var module: SaModule = LanguageFixture.new()
    var scoped := registries.context.for_module(module.get_id())
    module.context = scoped
    module.register(scoped)
    return scoped


## The skeleton's modes and one more under Other, registered through a
## module's door as a third party's would be, with no sentence and no word in
## any catalogue.
func _registries() -> SaRegistries:
    var registries := Fixtures.make_registries()
    var mode := SaBlendModeDescriptor.create(UNTRANSLATED, "multiply")
    mode.display_name = "Untranslated Blend"
    assert_true(registries.context.for_module(&"t6-module").register_blend_mode(mode), "a module's mode registers")
    return registries


func _button(registries: SaRegistries, space: SaColorSpace) -> BlendModeButton:
    var button := BlendModeButton.new()
    button.registry = registries.blend_modes
    button.include_hidden_in_layers = true
    button.space = space
    button.refresh()
    return button


func _tip(button: BlendModeButton, row_id: StringName) -> String:
    return button.popup.label_button(row_id).tooltip_text


## The first case: under Czech, Multiply's row reads its Czech
## name, its hover holds "Multiply", and a search for "Multiply" finds it, as
## does a search for the Czech.
func test_under_czech_multiply_reads_czech_and_its_hover_and_search_keep_the_english() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    var button := _button(registries, SaColorSpace.srgb())
    var popup := button.popup

    assert_eq(popup.label_button(&"multiply").text, "Násobit", "Multiply's row reads its Czech name")
    var tip := _tip(button, &"multiply")
    assert_true(tip.begins_with("Násobit\n"), "its hover leads with the Czech name: %s" % tip)
    assert_true(tip.contains("Multiply"), "and holds the English one: %s" % tip)
    assert_true(tip.contains("\nAnglicky: Multiply\n"), "on a line of its own that says it is the English")
    var czech := "\nZtmavuje násobením obou barev, jako inkousty položené přes sebe, a bílá nic nemění."
    assert_true(tip.ends_with(czech), "and ends on the sentence in Czech: %s" % tip)
    assert_true(button.section_titles().has("Darken"), "the sections are still keyed by their English")
    assert_eq(button.section_labels("Darken")[0], "Násobit", "and their labels read in Czech")

    assert_true(button.select_mode(&"multiply"), "Multiply is chosen")
    assert_eq(button.text, "Násobit", "and the button reads it in Czech")
    assert_true(button.tooltip_text.contains("Anglicky: Multiply"), "with the English in its own hover")

    popup.filter("Multiply")
    assert_true(popup.is_row_shown(&"multiply"), "a search for the English finds the row")
    assert_false(popup.is_row_shown(&"screen"), "and leaves out a row it does not name")
    popup.filter("násob")
    assert_true(popup.is_row_shown(&"multiply"), "so does a search for the Czech")
    assert_false(popup.is_row_shown(&"darken"), "which the English Darken does not match")
    popup.filter("")
    assert_true(popup.is_row_shown(&"screen"), "and an empty search puts the list back")

    var normal := _tip(button, &"normal")
    assert_eq(popup.label_button(&"normal").text, "Normální (sRGB)", "plain Normal keeps the space's name in its bracket")
    assert_true(normal.contains("\nAnglicky: Normal\n"), "and its hover keeps its English name: %s" % normal)
    assert_true(normal.ends_with(" Na tomto dokumentu míchá v sRGB."), "and says its space in Czech")

    button.free()
    scoped.remove_all_registrations()
    TranslationServer.set_locale(locale)


## A name the catalogue has no word for keeps its English and adds no line,
## so the hover a module's mode had is the hover it still has.
func test_a_name_the_catalogue_has_no_word_for_reads_as_it_did() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale(LanguageFixture.LOCALE)
    var button := _button(registries, SaColorSpace.srgb())
    var descriptor := registries.blend_modes.get_descriptor(UNTRANSLATED)

    assert_eq(button.popup.label_button(UNTRANSLATED).text, "Untranslated Blend", "the row keeps its English")
    var was := descriptor.tip_for(SaColorSpace.srgb())
    assert_eq(_tip(button, UNTRANSLATED), was, "and its hover is what it was, no English line")

    button.free()
    scoped.remove_all_registrations()
    TranslationServer.set_locale(locale)


## The second clause: under English, with the Czech catalogue registered, every
## row's label and hover read as they read today, which is the descriptor's own
## `label_for` and `tip_for` word for word.
func test_under_english_every_row_reads_as_it_did() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale("en")
    for space: SaColorSpace in [SaColorSpace.srgb(), SaColorSpace.oklab()]:
        var button := _button(registries, space)
        var popup := button.popup
        for row_id: StringName in popup.row_ids():
            var descriptor := registries.blend_modes.get_descriptor(BlendModeButton.mode_of_row(row_id))
            assert_eq(popup.label_button(row_id).text, descriptor.label_for(space), "%s's label is as it was" % row_id)
            assert_eq(_tip(button, row_id), descriptor.tip_for(space), "and its hover on %s" % space.blend_space_name())
        assert_true(_tip(button, &"multiply").begins_with("Multiply\nDarkens"), "Multiply's hover has no English line of its own")
        button.free()
    scoped.remove_all_registrations()
    TranslationServer.set_locale(locale)


## A switch of locale while the button is in the tree writes the list again in
## the new language, with no rebinding, and a switch back writes it in English.
func test_a_switch_of_locale_writes_the_list_again() -> void:
    var registries := _registries()
    var scoped := _register_fixture(registries)
    var locale := TranslationServer.get_locale()
    TranslationServer.set_locale("en")
    var button := _button(registries, SaColorSpace.srgb())
    # Parented to an autoload, because the runner calls this from its own
    # `_ready` and a parent mid-`_ready` rejects `add_child`.
    EventBus.add_child(button)
    assert_true(button.select_mode(&"multiply"), "Multiply is chosen under English")
    assert_eq(button.text, "Multiply", "and reads in English")

    TranslationServer.set_locale(LanguageFixture.LOCALE)
    assert_eq(button.popup.label_button(&"multiply").text, "Násobit", "the switch writes the row in Czech")
    assert_eq(button.text, "Násobit", "and the button, still on Multiply")
    assert_eq(button.current, &"multiply", "which the switch did not move")

    TranslationServer.set_locale("en")
    assert_eq(button.popup.label_button(&"multiply").text, "Multiply", "and the switch back writes it in English")

    EventBus.remove_child(button)
    button.free()
    scoped.remove_all_registrations()
    TranslationServer.set_locale(locale)
