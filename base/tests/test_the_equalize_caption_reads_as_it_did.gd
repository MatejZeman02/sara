## The Equalize caption is one message with its channel written in, so a
## language with cases can decline the channel's name, and under British
## English it reads as the sentence it was made from.
extends "res://tests/test_framework.gd"

var _locale := ""


func before_each() -> void:
    _locale = TranslationServer.get_locale()
    TranslationServer.set_locale("en_GB")


func after_each() -> void:
    TranslationServer.set_locale(_locale)


func test_the_caption_reads_as_the_generic_sentence_with_the_channel_s_title() -> void:
    var title := String(SaPointAdjust.CHANNEL_TITLES[SaLevelsPanel.MAP_CHANNEL])
    assert_eq(
        TranslationServer.translate(SaLevelsPanel.EQUALIZED_CAPTION),
        TranslationServer.translate("Equalized using %s") % TranslationServer.translate(title),
        "The caption names the channel the map is counted on, as it did"
    )
