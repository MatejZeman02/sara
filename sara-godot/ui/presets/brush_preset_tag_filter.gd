## The preset chooser's tag filter: every tag off, shown only or hidden, several
## at once, kept in the painter's settings.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Out of `brush_presets_chooser.gd` for the reason `SaBrushPresetStars` is: the
## chooser owns a grid and which filters it is under, the profile owns which tags
## are on (`SaSettings.preset_tag_filter`), and this owns the rule between them,
## the words the tag button says, the mark each row of its list carries and the
## line the grid shows when the tags leave nothing. The chooser gains the calls.
##
## **Three states, one click each.** A press on a tag's row moves it from off to
## show only, from show only to hide, and from hide back to off, so a painter
## can show only the sketch brushes, or filter out every filter brush. A
## preset passes when it carries every tag shown only and none of the hidden ones.
##
## **The marks read apart in grey.** A tag shown only carries the open eye and a
## hidden one the crossed eye, two shapes rather than two colours, and an off tag
## carries none, so a greyscale shot tells the three apart.
##
## **A tag the library does not carry filters nothing.** The profile may name a
## tag a module brought and the store has not read yet at the moment a chooser is
## first built, so the profile keeps it and the rule leaves it out until a preset
## carries it again. Clearing drops every one.
##
## **A bundle is a word as a tag is.** The bundle a preset came from is one more
## of its words, under [constant BUNDLE_PREFIX], so the chooser lists each under
## a heading of Bundles and the rule, the three states and the profile take it
## unchanged, so a bundle filters the chooser the way a tag does.
##
## **So is an engine.** The engine a preset was written for, stamp, noise,
## filter or liquify, is a word under [constant ENGINE_PREFIX] beside its
## bundle. The two are its auto tags: read off the preset, listed under headings
## of their own after the stored tags, filtered and combined as a tag is, and
## never stored, renamed or deleted, which `SaPresetTagMap` holds on the store's
## side.
class_name SaBrushPresetTagFilter
extends RefCounted

## The grid has to be built again: the profile's tags moved, here or in the
## other host's chooser.
signal changed

## The two words a tag's state is stored under. Off is no entry at all.
const SHOW: String = "show"
const HIDE: String = "hide"

## The icon each state's row carries, by state. Two shapes, so grey reads them.
const ICONS: Dictionary = {SHOW: "guivisibilityvisible", HIDE: "guivisibilityhidden"}

## What a bundle's word in the filter begins with, so a bundle and a tag of
## the same name are two words and the filter keeps each apart. The bundle is a
## word of a preset beside its tags, `bundle:Sara Basic`, and from there
## on it is filtered, cycled, stored and cleared as a tag is.
const BUNDLE_PREFIX: String = "bundle:"

## What an engine's word begins with, `engine:noise`, for the reason a
## bundle's has a prefix.
const ENGINE_PREFIX: String = "engine:"

## The line the grid shows when the tags leave no preset, with the press that
## clears them. Public because a test and a scenario read and press it.
var empty_box: VBoxContainer = null
var empty_line: Label = null
var clear_button: Button = null

## The profile's filter as the last build saw it, so a profile load that wrote the
## same filter again rebuilds nothing.
var _seen: Dictionary = {}


func _init() -> void:
    empty_box = VBoxContainer.new()
    empty_box.name = "ChooserTagsEmpty"
    empty_box.visible = false
    empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
    empty_line = SaMake.label(empty_box, "ChooserTagsEmptyLine", "")
    empty_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    empty_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(empty_line, "text_muted")
    clear_button = SaMake.button(empty_box, "ChooserTagsClear", tr("Clear the tags"))
    clear_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    clear_button.pressed.connect(_on_clear_pressed)


## The state of every tag *carried* holds that is on, tag to `SHOW` or `HIDE`.
## A tag the library does not carry is left out, as the header says.
static func states(carried: PackedStringArray) -> Dictionary:
    var out: Dictionary = {}
    var stored: Dictionary = SaSettings.preset_tag_filter
    for tag: String in carried:
        var state := String(stored.get(tag, ""))
        if state == SHOW or state == HIDE:
            out[tag] = state
    return out


## The state *tag* is in, empty for off.
static func state_of(tag: String) -> String:
    return String(SaSettings.preset_tag_filter.get(tag, ""))


## Whether a preset carrying *preset_tags* passes *on*, the answer of `states`.
static func passes(on: Dictionary, preset_tags: PackedStringArray) -> bool:
    for tag: String in on:
        if (on[tag] == SHOW) != preset_tags.has(tag):
            return false
    return true


## The filter's word for the bundle titled *title*.
static func bundle_word(title: String) -> String:
    return BUNDLE_PREFIX + title


## Whether *word* is a bundle's rather than a tag's.
static func is_bundle(word: String) -> bool:
    return word.begins_with(BUNDLE_PREFIX)


## The filter's word for the engine *engine*.
static func engine_word(engine: StringName) -> String:
    return ENGINE_PREFIX + String(engine)


## Whether *word* is an auto tag's, a bundle's or an engine's, which no hand
## renames or deletes.
static func is_auto(word: String) -> bool:
    return is_bundle(word) or word.begins_with(ENGINE_PREFIX)


## The words *preset_tags*, the bundle *title* and the *engine* make, the list
## [method passes] reads for one preset.
static func words_of(preset_tags: PackedStringArray, title: String, engine: StringName = &"") -> PackedStringArray:
    var words := preset_tags.duplicate()
    if not title.is_empty():
        words.append(bundle_word(title))
    if not String(engine).is_empty():
        words.append(engine_word(engine))
    return words


## *word* as the painter reads it: a tag as it is, a bundle by its title, an
## engine by its name, `SaPresetStore.engine_label`'s "Noise", and a tag that
## names what a conversion or an import did not carry in the painter's language.
static func label_of(word: String) -> String:
    if word.begins_with(ENGINE_PREFIX):
        return SaPresetStore.engine_label(StringName(word.trim_prefix(ENGINE_PREFIX)))
    return word.trim_prefix(BUNDLE_PREFIX) if is_bundle(word) else SaTagLabels.label(word)


## The auto words *store*'s presets make, sorted: the bundles' first and the
## engines' after, as two lists, the order the tag list draws them in. Off the
## store's one load per preset, as its tags are.
static func auto_words(store: SaPresetStore) -> Array[PackedStringArray]:
    var bundles: Dictionary[String, bool] = {}
    var engines: Dictionary[String, bool] = {}
    for stored_name: String in store.list_names():
        var title := store.origin_for(stored_name)[0]
        if not title.is_empty():
            bundles[bundle_word(title)] = true
        var engine := store.engine_for(stored_name)
        if not String(engine).is_empty():
            engines[engine_word(engine)] = true
    var titles := PackedStringArray(bundles.keys())
    titles.sort()
    var ids := PackedStringArray(engines.keys())
    ids.sort()
    return [titles, ids]


## The auto word *wanted* names, by its word, by the label a painter reads or
## by an engine's id, `engine:noise`, `Noise` or `noise`, or empty when none
## does.
static func auto_named(store: SaPresetStore, wanted: String) -> String:
    for words: PackedStringArray in auto_words(store):
        for word: String in words:
            if wanted in [word, label_of(word), word.trim_prefix(ENGINE_PREFIX)]:
                return word
    return ""


## Moves *tag* one state on, off to show only to hide to off, and answers the
## state it is in now.
func cycle(tag: String) -> String:
    var now := state_of(tag)
    var next := SHOW if now.is_empty() else (HIDE if now == SHOW else "")
    put(tag, next)
    return next


## Puts *tag* in *state*, `SHOW`, `HIDE` or empty for off, through the profile.
func put(tag: String, state: String) -> void:
    var stored: Dictionary = SaSettings.preset_tag_filter.duplicate()
    if state.is_empty():
        stored.erase(tag)
    else:
        stored[tag] = state
    _write(stored)


## Shows only *tag* and turns every other one off, or turns all off when *tag* is
## empty. What a scenario's `{"preset": {"tag": ...}}` and the bar's hand-over
## mean, since both name one tag.
func only(tag: String) -> void:
    _write({} if tag.is_empty() else {tag: SHOW})


## Carries the state of *from* over to *to*, which a rename by the tag gesture
## asks, so the filter follows the word the painter changed.
func renamed(from: String, to: String) -> void:
    var stored: Dictionary = SaSettings.preset_tag_filter.duplicate()
    if from == to or not stored.has(from):
        return
    stored[to] = stored[from]
    stored.erase(from)
    _write(stored)


## Turns every tag off, which the empty line's press and the list's All row ask.
func clear() -> void:
    _write({})


## Writes *stored* to the profile. The chooser that asked rebuilds by itself, so
## this one's own write is taken as seen and only the other host's chooser hears it.
func _write(stored: Dictionary) -> void:
    if stored == SaSettings.preset_tag_filter:
        return
    _seen = stored.duplicate()
    SaSettings.preset_tag_filter = stored


## The empty line's press. Nothing else on the line rebuilds the grid, so it says so.
func _on_clear_pressed() -> void:
    clear()
    changed.emit()


## Called by the chooser as it starts a build, so a profile load that changed
## nothing is told apart from one that did.
func begin_build() -> void:
    _seen = SaSettings.preset_tag_filter.duplicate()


## The words on the closed tag button for *on*: All, the one tag shown only by
## itself, or every tag on with the hidden ones marked as left out.
func button_words(on: Dictionary) -> String:
    if on.is_empty():
        return tr("Tag: All")
    if on.size() == 1 and on.values()[0] == SHOW:
        return tr("Tag: %s") % label_of(on.keys()[0])
    return tr("Tags: %s") % summary(on)


## Every tag on, the shown ones by name and the hidden ones as "not" the name,
## for the button and the empty line.
func summary(on: Dictionary) -> String:
    var parts: PackedStringArray = []
    for tag: String in on:
        parts.append(label_of(tag) if on[tag] == SHOW else tr("not %s") % label_of(tag))
    return ", ".join(parts)


## Brings the empty line to what the grid shows: drawn when the store holds
## presets, the grid lists none and a tag is on, saying which tags are on.
func show_empty(listed_none: bool, on: Dictionary) -> void:
    empty_box.visible = listed_none and not on.is_empty()
    if empty_box.visible:
        empty_line.text = tr("No preset passes the tags %s.") % summary(on)


## Hears the profile while *on*, which the chooser says while it is in the tree.
func listen(on: bool) -> void:
    var hearing := SaSettings.changed.is_connected(_on_settings_changed)
    if on and not hearing:
        SaSettings.changed.connect(_on_settings_changed)
    elif not on and hearing:
        SaSettings.changed.disconnect(_on_settings_changed)


func _on_settings_changed(property: StringName) -> void:
    if property == &"preset_tag_filter" and SaSettings.preset_tag_filter != _seen:
        changed.emit()


## What a dump reads: every tag on in the profile, carried or not.
func report() -> Dictionary:
    return SaSettings.preset_tag_filter.duplicate()
