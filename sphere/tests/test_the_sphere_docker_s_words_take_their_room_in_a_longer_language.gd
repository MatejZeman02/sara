## The Sphere docker's title and sentence fit its 150 pixels
## in a language longer than English.
##
## Under the test language the one-word title was wider than the bar leaves it,
## so `DockerWindow`'s English width broke it inside itself, and the sentence
## under it showed 5 of its 8 lines. Where the words are not English the title
## now keeps its one line and the sentence asks for every line, and the window
## grows to them. In English both are as they were, which is what keeps every
## English pixel where it stood.
##
## The docker is built detached, as the panorama suite beside this one builds it,
## because a docker is a `Window` and adding one in a headless run hangs, so the
## window's growth is the scenario's to show:
## `scenarios/the-sphere-docker-s-title-and-sentence-fit-its-150-pixels-in-a-language-longer-than-english.py`.
## The catalogue is made here, so the suite leans on no module.
extends "res://tests/test_framework.gd"

const SphereDocker = preload("res://modules/sara-base-modules/sphere/sphere_docker.gd")

## The ball composes the canvas's shader.
const REQUIRES_GPU := true

const LOCALE := "eo"
const FLAT := "The Sphere shows panoramas, and this one is flat."
const LONG_TITLE := "‹Šþĥéřéжщы›"
const LONG_FLAT := "‹Ťĥéжщ Šþĥéřéжщы šĥóŵšжщ þáñóřáмášжщыю, áñďжщ ťĥíšжщ óñéжщ íšж ƒłáťжщ.›"
## The width the sentence has in the docker as it ships, 150 less its margins.
const SHIPPED_WIDTH := 142.0

var _catalogue: Translation
var _locale_before := ""
var _host: Node = null
var _canvas: SaCanvas = null
var _docker: SphereDocker = null


func before_each() -> void:
    _locale_before = TranslationServer.get_locale()
    _catalogue = Translation.new()
    _catalogue.locale = LOCALE
    _catalogue.add_message(FLAT, LONG_FLAT)
    TranslationServer.add_translation(_catalogue)
    _host = Node.new()
    _host.name = "SphereWordsTestHost"
    EventBus.add_child(_host)
    _canvas = SaCanvas.new()
    _canvas.canvas_size = Vector2i(256, 128)
    _host.add_child(_canvas)
    _docker = SphereDocker.new(SaSurface.create(&"sphere", _canvas.ensure_easel(), SaCanvasView.for_canvas(_canvas)))


func after_each() -> void:
    TranslationServer.set_locale(_locale_before)
    TranslationServer.remove_translation(_catalogue)
    if _docker != null:
        _docker.free()
        _docker = null
    if _host != null:
        _host.free()
        _host = null


## The locale set, and the docker told of it as the engine tells it.
func _speak(locale: String) -> void:
    TranslationServer.set_locale(locale)
    _docker.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
    _docker.sync()
    _docker.fit_words()


func _title() -> Label:
    return _docker.drag_handle.find_child("TitleLabel", true, false) as Label


## The sentence's height at the width it ships with, against the height of
## every line it breaks into there.
func _sentence_heights() -> Vector2:
    var words := _docker.sentence
    words.visible = true
    words.size = Vector2(SHIPPED_WIDTH, 0.0)
    words.update_minimum_size()
    var lines := words.get_line_count()
    var every_line := lines * words.get_line_height() + maxi(lines - 1, 0) * words.get_theme_constant("line_spacing")
    return Vector2(words.get_minimum_size().y, every_line)


func test_in_english_the_title_is_held_and_the_sentence_cut_only_where_it_must() -> void:
    _speak("en")
    var title := _title()
    assert_eq(title.text, "Sphere", "the English title")
    assert_true(
        title.autowrap_mode != TextServer.AUTOWRAP_OFF, "the title is held at its English width and wraps, as every docker's"
    )
    assert_eq(_docker.sentence.text, FLAT, "the flat document's sentence in English")
    assert_eq(_docker.sentence.text_overrun_behavior, SaTheme.TEXT_CUT, "the sentence is cut in a docker made smaller, as before")


func test_a_one_word_title_longer_than_english_keeps_its_one_line() -> void:
    _catalogue.add_message("Sphere", LONG_TITLE)
    _speak(LOCALE)
    var title := _title()
    assert_eq(title.text, LONG_TITLE, "the title in the catalogue's words")
    assert_eq(title.autowrap_mode, TextServer.AUTOWRAP_OFF, "one word does not break inside itself")
    assert_eq(title.custom_minimum_size.x, 0.0, "and is not held at the English width")
    title.size = Vector2(title.get_minimum_size().x, 0.0)
    assert_eq(title.get_line_count(), 1, "so the title asks for the width of its one line")


func test_a_title_of_several_words_still_wraps_between_them() -> void:
    _catalogue.add_message("Sphere", "Šþĥéřé ‹ƀáłł›")
    _speak(LOCALE)
    assert_true(_title().autowrap_mode != TextServer.AUTOWRAP_OFF, "words can wrap between each other, so the hold stays")


func test_a_sentence_longer_than_english_asks_for_every_line() -> void:
    _speak(LOCALE)
    assert_eq(_docker.sentence.text, LONG_FLAT, "the sentence in the catalogue's words")
    assert_eq(_docker.sentence.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "nothing trims it")
    var heights := _sentence_heights()
    assert_true(heights.y > 0.0, "the sentence breaks into lines")
    assert_eq(heights.x, heights.y, "and it asks for the height of every one of them")


func test_back_in_english_the_sentence_is_cut_again_where_it_must() -> void:
    _speak(LOCALE)
    _speak("en")
    assert_eq(_docker.sentence.text, FLAT, "English again")
    assert_eq(_docker.sentence.text_overrun_behavior, SaTheme.TEXT_CUT, "and cut only in a docker made smaller")


func test_the_english_refusal_is_the_source_text() -> void:
    TranslationServer.set_locale(LOCALE)
    var document := _canvas.document
    assert_eq(SphereDocker.refusal_for(document), LONG_FLAT, "the catalogue's by default")
    assert_eq(SphereDocker.refusal_for(document, SphereDocker._as_written), FLAT, "and the source as written")
    assert_eq(SphereDocker.refusal_for(null, SphereDocker._as_written), "There is no document to show.", "with no document too")
