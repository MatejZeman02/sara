## The layer kind browser titles a shipped kind with its whole sentence, so a
## language with cases can translate it.
##
## "Add %s" with "Effect Layer" dropped in gives Czech the kind's name in its
## dictionary form, "Přidat Vrstva efektu", where the sentence wants another
## ending. A catalogue holding the whole "Add Effect Layer" is read whole, a
## module's own kind still reads the generic sentence with its name dropped in,
## and with no catalogue both titles read as they did.
extends "res://tests/test_framework.gd"

## A locale no catalogue of the tree holds, so the test's own is the only one.
const LOCALE := "cs_CZ"
const WHOLE := "Přidat vrstvu efektu"
const GENERIC := "Přidat %s"
const WORD := "Vrstva efektu"

var _locale := ""
var _catalogue: Translation = null
var _browser: SaLayerKindBrowser = null


func before_each() -> void:
    _locale = TranslationServer.get_locale()
    _browser = SaLayerKindBrowser.new()


func after_each() -> void:
    _browser.free()
    if _catalogue != null:
        TranslationServer.remove_translation(_catalogue)
        _catalogue = null
    TranslationServer.set_locale(_locale)


## The title the browser shows once opened for *kind*, detached and so left shut.
func _title_for(kind: SaLayerTypeDescriptor) -> String:
    _browser.open_for(null, kind, SaLayerTypeRegistry.new())
    return _browser.title


## A kind a module registers, which no table of Sara's knows.
func _module_kind() -> SaLayerTypeDescriptor:
    var made := SaLayerTypeDescriptor.create(&"glow", SaFieldSpec.default_schema())
    made.display_name = "Glow Layer"
    made.input = SaLayerTypeDescriptor.INPUT_NAMED
    return made


func test_a_catalogue_s_whole_sentence_titles_the_shipped_kind() -> void:
    _catalogue = Translation.new()
    _catalogue.locale = LOCALE
    _catalogue.add_message("Add Effect Layer", WHOLE)
    _catalogue.add_message("Add %s", GENERIC)
    _catalogue.add_message("Effect Layer", WORD)
    TranslationServer.add_translation(_catalogue)
    TranslationServer.set_locale(LOCALE)
    assert_true(WHOLE != GENERIC % WORD, "The catalogue's whole sentence differs from its generic form")
    assert_eq(_title_for(SaEffectLayer.descriptor()), WHOLE, "and the browser's title reads the whole sentence")
    assert_eq(_title_for(_module_kind()), GENERIC % "Glow Layer", "while a module's own kind reads the generic sentence")


func test_with_no_catalogue_the_title_reads_as_it_did() -> void:
    TranslationServer.set_locale(LOCALE)
    var effect := SaEffectLayer.descriptor()
    assert_eq(_title_for(effect), "Add %s" % effect.display_name, "The shipped kind's title reads as before")
    assert_eq(_title_for(SaBackdropLayer.descriptor()), "Add Adjustment Layer", "and so does the adjustment layer's")
    assert_eq(_title_for(_module_kind()), "Add Glow Layer", "and a module's own kind's")
