## The thirteenth registry: the catalogues a module translates Sara with, one
## locale each, which [method SaContext.register_translation] fills and the
## Languages page in Preferences lists.
##
## English is not here and never can be: the English text is the key every
## catalogue maps from. A catalogue for `en` itself
## is refused for that reason, and a variant of English names its country,
## `en_US`, like any other locale.
##
## **The one registered last wins, by construction rather than by the engine's
## order.** `TranslationServer` asks its translations one after another and
## takes the first exact match, from a set whose order an erase reshuffles, so
## two catalogues of one locale installed side by side answer in an order
## nobody chose. The registry therefore installs one translation per locale,
## built from every catalogue of that locale in registration order, a later
## catalogue's sentence written over an earlier one's, and builds it again
## whenever a catalogue of that locale comes or goes. The plural rule is the
## newest catalogue's that states one.
class_name SaTranslationRegistry
extends RefCounted

## Registration and removal, after the installed translations are rebuilt.
signal changed

## `{"catalogue": Translation, "locale": String, "module": StringName,
## "source": String}` apiece, oldest first, which is the order the Languages
## page lists them in and the order a later one wins in.
var _catalogues: Array[Dictionary] = []

## Locale -> the one translation installed in `TranslationServer` for it.
var _installed: Dictionary[String, Translation] = {}


## Registers *catalogue*, a `Translation` or the path of a `.po` or `.mo`
## file, for *module_id*, and installs it at once. Refused for no catalogue,
## a path that loads none, a catalogue for English itself, and one already
## registered. Its time is the translations' share of the start's table.
func register(catalogue: Variant, module_id: StringName = &"") -> bool:
    var began := Time.get_ticks_usec()
    var registered := _register(catalogue, module_id)
    SaBootMarks.add_work(&"translations", began)
    return registered


## What [method register] does, timed around.
func _register(catalogue: Variant, module_id: StringName) -> bool:
    var source := ""
    var translation: Translation = null
    if catalogue is Translation:
        translation = catalogue
        source = translation.resource_path
    elif catalogue is String or catalogue is StringName:
        source = str(catalogue)
        translation = load(source) as Translation if ResourceLoader.exists(source) else null
    if translation == null:
        push_error("SaTranslationRegistry: '%s' is not a catalogue, a Translation or a .po file." % str(catalogue))
        return false
    var locale := translation.locale
    if locale == "en":
        push_error(
            (
                "SaTranslationRegistry: a catalogue for 'en' translates English into itself. "
                + "Give the .po a Language line, or name the variant's country, en_US."
            )
        )
        return false
    for held: Dictionary in _catalogues:
        if held["catalogue"] == translation:
            push_error("SaTranslationRegistry: that catalogue is already registered.")
            return false
    _catalogues.append({"catalogue": translation, "locale": locale, "module": module_id, "source": source})
    _install(locale)
    _tell_the_tree([locale])
    changed.emit()
    return true


## Removes every catalogue *module_id* registered and takes its sentences out
## of `TranslationServer`, leaving the other catalogues of each locale in.
func unregister_module(module_id: StringName) -> void:
    var kept: Array[Dictionary] = []
    var touched: Array[String] = []
    for held: Dictionary in _catalogues:
        if held["module"] != module_id:
            kept.append(held)
        elif not touched.has(held["locale"]):
            touched.append(held["locale"])
    if touched.is_empty():
        return
    _catalogues = kept
    for locale: String in touched:
        _install(locale)
    _tell_the_tree(touched)
    changed.emit()


## Every catalogue in registration order, as `{"place": int, "locale":
## String, "module": StringName, "source": String, "sentences": int}`, the
## place counted from one. The Languages page draws this list.
func catalogues() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for held: Dictionary in _catalogues:
        var translation: Translation = held["catalogue"]
        var entry: Dictionary = held.duplicate()
        entry.erase("catalogue")
        entry["place"] = out.size() + 1
        entry["sentences"] = translation.get_message_count()
        out.append(entry)
    return out


## The locales a catalogue is registered for, each once, in the order its
## first catalogue came.
func locales() -> PackedStringArray:
    var out := PackedStringArray()
    for held: Dictionary in _catalogues:
        var locale: String = held["locale"]
        if not out.has(locale):
            out.append(locale)
    return out


## The translation installed for *locale*, or null when no catalogue covers it.
func installed(locale: String) -> Translation:
    return _installed.get(locale, null)


## A registry dropped with catalogues still in takes them out of
## `TranslationServer` with it, so a suite's registry cannot leave a locale
## translated for the next suite.
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        for translation: Translation in _installed.values():
            TranslationServer.remove_translation(translation)
        _installed.clear()


## Tells every node in the tree that its words may read differently, when one
## of *touched* is the one `TranslationServer` reads now. The engine sends the
## notification on a change of locale and not on a translation added or
## removed, so a catalogue registered after the windows were built, which is
## every launch in a language other than English, left a docker's title and the
## menus' names in English until the next switch.
static func _tell_the_tree(touched: Array[String]) -> void:
    var loop := Engine.get_main_loop()
    var now := TranslationServer.get_locale()
    if loop != null and touched.any(func(locale: String) -> bool: return TranslationServer.compare_locales(locale, now) > 0):
        loop.notification(MainLoop.NOTIFICATION_TRANSLATION_CHANGED)


## Builds the one translation of *locale* again from its catalogues, oldest
## first so a later sentence is written over an earlier one, and swaps it in
## for the one installed. No catalogue left, nothing is installed.
func _install(locale: String) -> void:
    var previous: Translation = _installed.get(locale, null)
    if previous != null:
        TranslationServer.remove_translation(previous)
        _installed.erase(locale)
    var messages := {}
    var plural_rule := ""
    for held: Dictionary in _catalogues:
        if held["locale"] != locale:
            continue
        var translation: Translation = held["catalogue"]
        var sentences: Dictionary = translation.get(&"messages")
        messages.merge(sentences, true)
        if not translation.get_plural_rules_override().is_empty():
            plural_rule = translation.get_plural_rules_override()
    if messages.is_empty():
        return
    var merged := Translation.new()
    merged.locale = locale
    merged.set(&"messages", messages)
    merged.set_plural_rules_override(plural_rule)
    _installed[locale] = merged
    TranslationServer.add_translation(merged)
