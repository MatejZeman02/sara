## The stock presets' stored tags brought to the seven words a build ships, one
## a preset, and the rule that no tag a preset shows by itself is ever stored.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Too many words make the tags no help to filter by. A preset shows its bundle
## and its engine as tags of their own, read off its file, so a stored tag that
## says either is a second spelling of one fact. The stock tables carry seven
## words, one on each preset, the one that says what a painter reaches for it
## to do, so a toggle shows one part of the library and not most of it. A store
## installed under the vocabularies before them, the ten, the twenty and the
## forty-odd before those, keeps the old words on every preset it holds,
## because a preset in the store is the painter's. This maps them.
##
## **Only a stock preset, and only a stock word.** A preset is stock when its
## bundle is one the recipes of the install name, or when it names no bundle
## and the ledger records Sara writing it, [method _stock]. Each of its tags
## that a stock vocabulary ever carried becomes its word in [constant RENAMED]
## or goes, and a tag that was never a stock word is the painter's and stays,
## `mine` beside `paint`. Of the stock words left, one stays,
## [method one_stock]. An import's preset and the painter's own are never read
## past their title.
##
## **The file's line, not a load and a save**, as `SaPresetBundleMap` writes the
## bundle's: the `metadata/tags` line is written in the text and nothing else,
## so the values the painter set stay, and a copy that was Sara's untouched
## before is recorded as Sara's after, so the next build may still replace it
## with its recipe.
##
## **Once per preset.** The stock presets mapped are listed in a file of the
## folder, [constant DONE_FILE], so a later start reads no preset and a stock
## word the painter types again by hand is kept. A line names the preset and
## not its bundle alone, because one bundle's presets come from the tables of
## several engines and each table is installed on a call of its own: Sara
## Advanced Paint's stamp presets and its noise presets, Sara Filters' filter
## and liquify ones. A record by bundle left the second table's presets with
## their old words, found on a long-used store.
##
## A class of its own beside the store, which stands at its line budget and
## gains only the calls.
class_name SaPresetTagMap
extends RefCounted

## The file of the presets folder that lists the stock presets mapped, one
## `bundle/name` a line.
## Named for the seven, so a store the ten's map recorded in `tags.mapped` is
## mapped once more and a store mapped to the seven is not.
const DONE_FILE: String = "tags-seven.mapped"

## The seven stock words, in the order that settles a preset left carrying two
## of them when its recipe's word is not among them.
const STOCK_WORDS: PackedStringArray = ["lines", "paint", "soft", "texture", "scatter", "blend", "eraser"]

## Every word a stock table ever carried to the one of the seven it became, empty
## for a word dropped because an auto tag says it or the stock set no longer has
## one like it. A word the seven keep maps to itself, so the table is the whole
## of the stock vocabulary and anything not in it is a painter's tag. What hard
## and wet said about a preset belongs in its description.
const RENAMED: Dictionary[String, String] = {
    # The seven.
    "lines": "lines",
    "paint": "paint",
    "soft": "soft",
    "texture": "texture",
    "scatter": "scatter",
    "blend": "blend",
    "eraser": "eraser",
    # The ten that came before the seven.
    "hard": "paint",
    "wet": "paint",
    "nature": "scatter",
    # The vocabulary of twenty that came before the ten.
    "ink": "lines",
    "pencil": "lines",
    "flat": "paint",
    "spray": "soft",
    "grain": "texture",
    "rework": "blend",
    "warp": "blend",
    "foliage": "scatter",
    "sky": "scatter",
    "fill": "",
    # A tag's word and not the adjust engine's id, which the colour lookup's
    # suite tells apart by the empty word it maps to.
    "adjust": "",
    # The vocabulary before the twenty, as a long-used store carried it.
    "drawn": "",
    "noise": "",
    "filter": "",
    "liquify": "",
    "spatter": "scatter",
    "random": "scatter",
    "smudge": "blend",
    "blur": "blend",
    "twirl": "blend",
    "push": "blend",
    "shrink": "blend",
    "grow": "blend",
    "smooth": "blend",
    "reconstruct": "blend",
    "bristle": "paint",
    "impasto": "paint",
    "dry": "texture",
    "charcoal": "texture",
    "masked": "texture",
    "height": "texture",
    "marker": "lines",
    "pen": "lines",
    "air": "soft",
    "edges": "",
    "edge": "",
    "corners": "",
    "colour": "",
    "picture": "",
    "screen": "",
    "round": "",
    "sharpen": "",
}


## *tags* with every stock word mapped by [constant RENAMED] and every word that
## names one of *auto* dropped, sorted and without repeats. A word compared in
## lower case, since a tag is typed and an auto tag is a title.
static func mapped(tags: PackedStringArray, auto: PackedStringArray) -> PackedStringArray:
    var out := PackedStringArray()
    for tag: String in tags:
        var said: String = RENAMED.get(tag.to_lower(), tag)
        if not said.is_empty() and not names_auto(said, auto) and not out.has(said):
            out.append(said)
    out.sort()
    return out


## *tags* with one stock word left among the painter's, sorted. The word is the
## first of *recipe*'s stock words that *tags* carries, the one the preset's
## recipe says it is for, and failing that the first of [constant STOCK_WORDS]
## that *tags* carries, so an eraser a painter also tagged soft stays an eraser.
## *tags* with no stock word takes *recipe*'s first, so a stock preset always
## carries one.
static func one_stock(tags: PackedStringArray, recipe: PackedStringArray) -> PackedStringArray:
    var out := PackedStringArray()
    var carried := PackedStringArray()
    for tag: String in tags:
        if STOCK_WORDS.has(tag):
            carried.append(tag)
        elif not out.has(tag):
            out.append(tag)
    var kept := ""
    for word: String in recipe:
        if kept.is_empty() and STOCK_WORDS.has(word) and (carried.has(word) or carried.is_empty()):
            kept = word
    for word: String in STOCK_WORDS:
        if kept.is_empty() and carried.has(word):
            kept = word
    if not kept.is_empty():
        out.append(kept)
    out.sort()
    return out


## Whether *tag* says what one of *auto*, the engines and bundle titles of a
## store, already says.
static func names_auto(tag: String, auto: PackedStringArray) -> bool:
    for word: String in auto:
        if tag.to_lower() == word.to_lower():
            return true
    return false


## Whether *tag* is a word *store* shows as an auto tag, which a painter's add
## or rename refuses, since an auto tag is read and never stored.
static func is_auto(store: SaPresetStore, tag: String) -> bool:
    return names_auto(tag, auto_words(store))


## Every engine and bundle title *store*'s presets show as auto tags, the words
## no stored tag may be.
static func auto_words(store: SaPresetStore) -> PackedStringArray:
    var words := PackedStringArray()
    for stored: String in store.list_names():
        for word: String in [String(store.engine_for(stored)), store.origin_for(stored)[0]]:
            if not word.is_empty() and not words.has(word):
                words.append(word)
    return words


## Maps the tags of every preset of *store* that *entries* name and file under
## the bundle the preset carries, once per preset, *ledger* being the store's record, and answers how many
## preset files it rewrote. A stock preset the map leaves with no stock word
## takes its recipe's, so every stock preset keeps one beside its auto tags.
static func carry_over(store: SaPresetStore, ledger: SaPresetLedger, entries: Array) -> int:
    var done := _done(store.dir)
    var recipes: Dictionary[String, Dictionary] = {}
    for raw_entry: Variant in entries:
        var entry := SaTyped.strings(raw_entry)
        var bundle := SaTyped.text_at(entry, "bundle", "")
        if not bundle.is_empty() and not done.has(_key(bundle, SaTyped.text_at(entry, "name", ""))):
            recipes[SaTyped.text_at(entry, "name", "")] = entry
    if recipes.is_empty():
        return 0
    # A fresh folder is made here rather than skipped, so its record is written
    # before the install fills it, and a stock word the painter adds in the
    # first session is not mapped away at the second start.
    if not DirAccess.dir_exists_absolute(store.dir) and DirAccess.make_dir_recursive_absolute(store.dir) != OK:
        return 0
    var auto := auto_words(store)
    for entry: Dictionary in recipes.values():
        auto.append_array(SaPresetBundleMap.formers_of(entry))
    var moved := 0
    for stored: String in store.list_names():
        if not recipes.has(stored) or not _stock(store, ledger, stored, recipes[stored]):
            continue
        var was := store.tags_for(stored)
        var listed: Array = recipes[stored].get("tags", [])
        var now := one_stock(mapped(was, auto), mapped(PackedStringArray(listed), auto))
        if now != was and _rewrite(store, ledger, stored, now):
            moved += 1
    for stored: String in recipes:
        done.append(_key(SaTyped.text_at(recipes[stored], "bundle", ""), stored))
    var file := FileAccess.open(store.dir.path_join(DONE_FILE), FileAccess.WRITE)
    if file != null:
        file.store_string("\n".join(done) + "\n")
        file.close()
    if moved > 0:
        store.forget_tags()
    return moved


## Whether *stored* is the stock preset *entry* is the recipe of: filed under
## its bundle, or filed under none and recorded as Sara's write in the bundle's
## record or a former's. The second is a copy from before a stock preset's file
## named its bundle, which the painter changed since, so `SaPresetBundleMap`
## leaves it unfiled. Fourteen presets of one long-used store were such, Sketch
## and Streaks among them, and their words are Sara's as much as a filed copy's are.
## A word that was never a stock one stays on it as on any preset.
static func _stock(store: SaPresetStore, ledger: SaPresetLedger, stored: String, entry: Dictionary) -> bool:
    var bundle := SaTyped.text_at(entry, "bundle", "")
    var filed := store.origin_for(stored)[0]
    if filed == bundle:
        return true
    if not filed.is_empty():
        return false
    var records := PackedStringArray([bundle])
    records.append_array(SaPresetBundleMap.formers_of(entry))
    for record: String in records:
        if not ledger.written(record, stored)[1].is_empty():
            return true
    return false


## The line of [constant DONE_FILE] for the preset *stored* of the bundle
## *bundle*.
static func _key(bundle: String, stored: String) -> String:
    return bundle + "/" + stored


## The stock presets of the folder *dir* mapped already, as [method _key] writes them.
static func _done(dir: String) -> PackedStringArray:
    var out := PackedStringArray()
    for line: String in FileAccess.get_file_as_string(dir.path_join(DONE_FILE)).split("\n", false):
        if not line.strip_edges().is_empty():
            out.append(line.strip_edges())
    return out


## Writes *tags* as the `metadata/tags` line of *stored*'s file, or takes the
## line out when they are none, and moves the record of Sara's write with it
## when the file was Sara's untouched.
static func _rewrite(store: SaPresetStore, ledger: SaPresetLedger, stored: String, tags: PackedStringArray) -> bool:
    var path := store.dir.path_join(SaPresetStore.sanitize_name(stored) + SaPresetStore.EXTENSION)
    var before := SaPresetLedger.fingerprint(path)
    var text := FileAccess.get_file_as_string(path)
    var found := RegEx.create_from_string("(?m)^metadata/%s = .*$" % SaPresetMeta.TAGS_META).search(text)
    if found == null:
        return false
    var quoted := PackedStringArray()
    for tag: String in tags:
        quoted.append('"%s"' % tag.replace("\\", "\\\\").replace('"', '\\"'))
    var line := "metadata/%s = PackedStringArray(%s)" % [SaPresetMeta.TAGS_META, ", ".join(quoted)]
    var end := found.get_end()
    if tags.is_empty():
        line = ""
        end = mini(end + 1, text.length())
    text = text.substr(0, found.get_start()) + line + text.substr(end)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    var bundle := store.origin_for(stored)[0]
    var held := ledger.written(bundle, stored)
    if not before.is_empty() and before == held[0]:
        ledger.record_written(bundle, stored, SaPresetLedger.fingerprint(path), held[1])
    return true
