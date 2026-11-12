## Search folds case by the painter's locale, so "izmir" finds
## "İzmir" under Turkish.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter who types "izmir" must find "İzmir", and one who types
## "ısı" must find "ISI"". Both searches are read here under `tr`, the command
## search through `SaSearchIndex.narrowed` over rows a source of the suite's own
## hands it, and Preferences' through `SaSettingsSearch.apply` over pages built
## off the tree with real rows. Under `en_GB` the same searches over ASCII rows
## have to find what `to_lower()` found before the fold, query by query.
extends "res://tests/test_framework.gd"

## Rows with a Turkish capital, and rows of plain ASCII as Sara's own read.
const TURKISH_ROWS := ["İzmir", "ISI", "Ilgaz"]
const ASCII_ROWS := ["Brush Size", "Image Size", "Invert Colours", "Layer Mask", "Open Image", "Pen Pressure"]

## `{query: the rows it finds}` under `tr`.
const TURKISH_FINDS := {
    "izmir": ["İzmir"],
    "İZMİR": ["İzmir"],
    "ısı": ["ISI"],
    "isi": [],
    "ılgaz": ["Ilgaz"],
}

## The queries read under `en_GB`, each against what `to_lower()` found.
const ASCII_QUERIES := ["image", "IMAGE", "i", "in", "size", "pen", "open", "la mask", "Invert c", "x", ""]

var _locale_before := ""


## A source answering the search's contract with one command row per title.
class Rows:
    extends RefCounted
    var titles: Array

    func _init(named: Array) -> void:
        titles = named

    func search_rows() -> Array[SaSearchRegistry.Row]:
        var out: Array[SaSearchRegistry.Row] = []
        for title: String in titles:
            out.append(SaSearchRegistry.Row.new(SaSearchRegistry.TOOL, title, "", func() -> void: pass))
        return out


func before_each() -> void:
    _locale_before = TranslationServer.get_locale()


func after_each() -> void:
    TranslationServer.set_locale(_locale_before)


func test_the_command_search_finds_izmir_and_isi_under_turkish() -> void:
    TranslationServer.set_locale("tr")
    var rows := SaSearchIndex.new(SaContext.new(), [Rows.new(TURKISH_ROWS)]).entries()
    for query: String in TURKISH_FINDS:
        var found := _titles(SaSearchIndex.narrowed(rows, query))
        assert_eq(found, TURKISH_FINDS[query], "the command search for %s under tr" % query)


func test_preferences_search_finds_izmir_and_isi_under_turkish() -> void:
    TranslationServer.set_locale("tr")
    for query: String in TURKISH_FINDS:
        assert_eq(_settings_find(TURKISH_ROWS, query), TURKISH_FINDS[query], "Preferences' search for %s under tr" % query)


func test_the_command_search_under_english_finds_what_it_found_before() -> void:
    TranslationServer.set_locale("en_GB")
    var rows := SaSearchIndex.new(SaContext.new(), [Rows.new(ASCII_ROWS)]).entries()
    for query: String in ASCII_QUERIES:
        var found := _titles(SaSearchIndex.narrowed(rows, query))
        assert_eq(found, _found_before(query, true), "the command search for '%s' under en_GB" % query)


func test_preferences_search_under_english_finds_what_it_found_before() -> void:
    TranslationServer.set_locale("en_GB")
    for query: String in ASCII_QUERIES:
        if query.strip_edges().is_empty():
            continue
        var found := _settings_find(ASCII_ROWS, query)
        assert_eq(found, _found_before(query, false), "Preferences' search for '%s' under en_GB" % query)


## The fold follows a switch of language with nothing rebuilt.
func test_the_fold_follows_a_switch_of_locale() -> void:
    TranslationServer.set_locale("tr")
    assert_eq(SaSettingsSearch.fold("ISI"), "ısı", "I is dotless under tr")
    TranslationServer.set_locale("az_AZ")
    assert_eq(SaSettingsSearch.fold("İzmir"), "izmir", "İ is dotted under az")
    TranslationServer.set_locale("en_GB")
    assert_eq(SaSettingsSearch.fold("ISI"), "isi", "I is dotted under en_GB")
    for title: String in ASCII_ROWS:
        assert_eq(SaSettingsSearch.fold(title), title.to_lower(), "%s folds as to_lower() did" % title)


## What the searches found with `to_lower()` before the fold: every word of the
## query starts a word of the row, the command search ranking a title that
## starts with the query first and one with a word starting so next. Preferences
## lists the pages in their order, and its query is one string.
func _found_before(query: String, ranked: bool) -> Array:
    var needle := query.strip_edges().to_lower()
    if needle.is_empty():
        return ASCII_ROWS.duplicate()
    var parts := needle.split(" ", false) if ranked else PackedStringArray([needle])
    var buckets: Array = [[], [], []]
    for title: String in ASCII_ROWS:
        var words := title.to_lower()
        var found := true
        for part: String in parts:
            found = found and SaSettingsSearch.matches(words if ranked else "%s %s" % [words, words], part)
        if not found:
            continue
        var rank := 2
        if ranked and words.begins_with(needle):
            rank = 0
        elif ranked and SaSettingsSearch.matches(words, parts[0]):
            rank = 1
        buckets[rank].append(title)
    return buckets[0] + buckets[1] + buckets[2]


## The pages Preferences' search leaves for *query*, each page titled by one of
## *titles* and holding one row of the same title.
func _settings_find(titles: Array, query: String) -> Array:
    var scroll := ScrollContainer.new()
    var search := SaSettingsSearch.new(titles, scroll, _page_of)
    search.apply(query)
    var shown := Array(search._shown)
    search.field.free()
    scroll.free()
    return shown


## A page off the tree holding one real row titled *category*.
func _page_of(category: String) -> Control:
    var page := VBoxContainer.new()
    SaSettingsRows.row(page, category, "", Control.new())
    return page


static func _titles(entries: Array) -> Array:
    var out := []
    for entry: SaSearchIndex.Entry in entries:
        out.append(entry.title)
    return out
