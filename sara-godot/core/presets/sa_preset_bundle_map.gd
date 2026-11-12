## The bundle names a build's recipes carry, put on a painter's store that was
## installed under the names before them.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Sara's seven old stock bundles are three now, Sara Basic, Sara Filters and
## Sara Advanced Paint, and one of the seven was split between two of them. A
## recipe says where it came from as `formerly`, one old name or a list of them,
## so a table is the whole of the mapping and core names no stock bundle: a
## module that renames its own bundle later says so on its recipes the same way.
##
## **Two records move, and each preset file.** The store's ledger takes each old
## bundle's record into the new one's, [method SaPresetLedger.adopt], so no
## preset the painter deleted comes back. Then every preset whose `bundle` names
## an old bundle the ledger just took is moved to its new one: the recipe of its
## own name says which, and a preset no recipe names, a copy the painter saved
## of a stock one, goes where most of its old bundle went. A preset whose bundle
## is not an old stock one, an import or the painter's own, is never read past
## its title.
##
## **The file's lines, not a load and a save.** The bundle's four lines are
## written in the text of the `.tres` and nothing else is touched, so a preset
## the painter edited keeps every value they set, and the store's migrations,
## which a load runs, are not written into it. A copy that was Sara's untouched
## before the move is recorded as Sara's after it, by its new fingerprint, so
## the next build may still replace it with a corrected recipe.
##
## **Once.** The scan runs only on the ask where some old record was taken, the
## first start of the build that renamed it, so every start after it costs no
## file read. That scan moves the presets of every old name, not only of the
## ones whose record grew the new one: a long-used store held Sara Essentials
## and Sara basic, the second's names already in the first's record, and its
## eleven presets stayed under Sara basic until it did.
##
## A class of its own beside the store, which stands at its line budget and
## gains only the call.
class_name SaPresetBundleMap
extends RefCounted

## The keys of the lines a moved preset takes from its new bundle: the title,
## then the bundle's own fields. The licence is the preset's and stays, because
## one bundle may now carry recipes under two licences.
const CARRIED: Array[StringName] = [
    SaPresetMeta.BUNDLE_META,
    SaPresetMeta.BUNDLE_VERSION_META,
    SaPresetMeta.BUNDLE_AUTHOR_META,
    SaPresetMeta.BUNDLE_ABOUT_META,
]

## The entry key a recipe names its old bundles under.
const FORMERLY: String = "formerly"


## The old bundle names *entry* lists under `formerly`, a single name or a list,
## in the order the table gives them.
static func formers_of(entry: Dictionary) -> PackedStringArray:
    var raw: Variant = entry.get(FORMERLY, "")
    var out := PackedStringArray()
    if raw is String or raw is StringName:
        out.append(SaTyped.text(raw))
    elif raw is Array or raw is PackedStringArray:
        for former: Variant in raw:
            out.append(SaTyped.text(former))
    var kept := PackedStringArray()
    for former: String in out:
        if not former.strip_edges().is_empty() and not kept.has(former):
            kept.append(former)
    return kept


## Moves *store*'s record and presets from the old bundle names *entries* list to
## the ones they carry now, *ledger* being the store's own record, and answers
## how many preset files it rewrote.
static func carry_over(store: SaPresetStore, ledger: SaPresetLedger, entries: Array) -> int:
    # Old title -> preset name -> the recipe that names both.
    var by_name: Dictionary[String, Dictionary] = {}
    # Old title -> new bundle -> how many of its recipes went there.
    var tally: Dictionary[String, Dictionary] = {}
    var taken := PackedStringArray()
    for raw_entry: Variant in entries:
        var entry := SaTyped.strings(raw_entry)
        var bundle := SaTyped.text_at(entry, "bundle", "")
        for former: String in formers_of(entry):
            if ledger.adopt(bundle, former) and not taken.has(former):
                taken.append(former)
            if not by_name.has(former):
                by_name[former] = {}
                tally[former] = {}
            by_name[former][SaTyped.text_at(entry, "name", "")] = entry
            tally[former][bundle] = SaTyped.whole(tally[former].get(bundle, 0)) + 1
    if taken.is_empty():
        return 0
    var moved := 0
    for stored: String in store.list_names():
        var title := store.origin_for(stored)[0]
        if not by_name.has(title):
            continue
        var entry: Dictionary = by_name[title].get(stored, _most_of(by_name[title], tally[title]))
        if _rewrite(store, ledger, stored, entry):
            moved += 1
    store.forget_tags()
    return moved


## The first recipe of the new bundle most of an old one's recipes went to, the
## home of a preset no recipe of its name was found for.
static func _most_of(named: Dictionary, counts: Dictionary) -> Dictionary:
    var best := ""
    for bundle: String in counts:
        if best.is_empty() or SaTyped.whole(counts[bundle]) > SaTyped.whole(counts[best]):
            best = bundle
    for entry: Dictionary in named.values():
        if SaTyped.text_at(entry, "bundle", "") == best:
            return entry
    return {}


## Writes *entry*'s bundle lines into the file of *stored*, and moves the record
## of Sara's write with it when the file was Sara's untouched. False when there
## is nothing to write or the file would not take it.
static func _rewrite(store: SaPresetStore, ledger: SaPresetLedger, stored: String, entry: Dictionary) -> bool:
    var bundle := SaTyped.text_at(entry, "bundle", "")
    if bundle.is_empty():
        return false
    var path := store.dir.path_join(SaPresetStore.sanitize_name(stored) + SaPresetStore.EXTENSION)
    var before := SaPresetLedger.fingerprint(path)
    var text := FileAccess.get_file_as_string(path)
    if text.is_empty():
        return false
    for key: StringName in CARRIED:
        var value := bundle if key == SaPresetMeta.BUNDLE_META else SaTyped.text_at(entry, String(key), "")
        if not value.is_empty():
            text = _with_line(text, key, value)
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(text)
    file.close()
    var held := ledger.written(bundle, stored)
    if not before.is_empty() and before == held[0]:
        ledger.record_written(bundle, stored, SaPresetLedger.fingerprint(path), held[1])
    return true


## *text* with its `metadata/<key>` line saying *value*, the line written after
## the bundle's own when the file has none.
static func _with_line(text: String, key: StringName, value: String) -> String:
    var line := 'metadata/%s = "%s"' % [key, value.replace("\\", "\\\\").replace('"', '\\"')]
    var found := RegEx.create_from_string('(?m)^metadata/%s = "(?:[^"\\\\]|\\\\.)*"' % key).search(text)
    if found != null:
        return text.substr(0, found.get_start()) + line + text.substr(found.get_end())
    var title := RegEx.create_from_string('(?m)^metadata/%s = "(?:[^"\\\\]|\\\\.)*"' % SaPresetMeta.BUNDLE_META).search(text)
    if title == null:
        return text
    return text.substr(0, title.get_end()) + "\n" + line + text.substr(title.get_end())
