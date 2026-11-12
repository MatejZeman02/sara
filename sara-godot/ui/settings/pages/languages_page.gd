## Preferences > Languages: the language Sara speaks, picked from English and
## every locale a module registered a catalogue for, and below it the
## catalogues themselves in the order they were registered, each with its
## module and its file.
##
## Every language but English is a module. A pick writes
## `SaSettings.ui_language`, which `SaSettingsApply` sets on `TranslationServer`
## at once, and the page then asks the window to draw it again, so its own words
## are the first on screen in the new language and no restart is ever asked for.
## The order of the list is the order a later catalogue wins in where two carry
## one sentence, which is what a translator comes here to read.
##
## Registered through the door a module's page uses, by [SaBuiltinPages], with
## the window's translation registry handed in. A page built with none lists
## English alone.
class_name SaLanguagesPage
extends SaSettingsPage

## The language changed, so the page is drawn again in it. The window owns
## the drawing.
signal rebuild_requested

## The page's title in the sidebar, the English a door names it by.
const TITLE := "Languages"

## The locale Sara's own British English is stored under, which needs no
## catalogue of a module's.
const ENGLISH := SaSettingsValues.BRITISH

## The catalogues the page lists, or null for a page built with no registry.
var _registry: SaTranslationRegistry = null


## *registry* is set before `super()`, because the base class declares the
## page in its `_init`. The page is drawn again when a module brings or takes
## a catalogue while it is open.
func _init(registry: SaTranslationRegistry = null) -> void:
    _registry = registry
    super()
    if _registry != null:
        _registry.changed.connect(_on_catalogues_changed)


func build(ui: SaPage) -> void:
    var language := ui.section("Language")
    (
        language
        . choice("Language", choices(_registry, SaSettings.ui_language), SaSettings, ^"ui_language")
        . named(&"language")
        . node("LanguageOpt")
        . words("locale translation english")
        . explain(tr("The language Sara's windows speak. It switches at once, with no restart."))
    )

    var listed := ui.section("Catalogues")
    listed.note(
        tr(
            (
                "Every language but English comes from a module. Where two catalogues carry the same sentence, "
                + "the one lower in this list is shown."
            )
        )
    )
    var english := tr("Built in. Untranslated text is shown in English.")
    listed.custom("English", _line(english))
    for entry: Dictionary in _registry.catalogues() if _registry != null else []:
        var place := int(entry["place"])
        var title := "%d. %s" % [place, tr(TranslationServer.get_locale_name(String(entry["locale"])))]
        listed.custom(title, _line(catalogue_line(entry))).named(StringName("catalogue_%d" % place))
    if not ui.row_changed.is_connected(_on_row_changed):
        ui.row_changed.connect(_on_row_changed)


## The choices of the Language row: British English first, then each registered
## locale in the order its first catalogue came, and *stored* last when it
## names a locale no module brings now, so the row still shows what is kept.
static func choices(registry: SaTranslationRegistry, stored: String = ENGLISH) -> Array:
    var out: Array = [{"id": ENGLISH, "label": TranslationServer.get_locale_name(ENGLISH)}]
    var locales := registry.locales() if registry != null else PackedStringArray()
    for locale: String in locales:
        out.append({"id": locale, "label": TranslationServer.get_locale_name(locale)})
    if stored != ENGLISH and not locales.has(stored):
        var missing := TranslationServer.translate("%s, with no catalogue loaded")
        out.append({"id": stored, "label": missing % TranslationServer.get_locale_name(stored)})
    return out


## What a catalogue's line says beside its place and language: the module it
## came with, its file when it was read from one, and how many sentences it
## carries.
static func catalogue_line(entry: Dictionary) -> String:
    var module := String(entry["module"])
    var source := String(entry["source"]).get_file()
    var sentences := int(entry["sentences"])
    var from := TranslationServer.translate("From the module %s.") % module
    if not source.is_empty():
        from = TranslationServer.translate("From the module %s, in %s.") % [module, source]
    return from + " " + TranslationServer.translate_plural("%d sentence", "%d sentences", sentences) % sentences


## A dimmed line of text that wraps in the row's control column.
static func _line(text: String) -> Label:
    var line := Label.new()
    line.text = text
    line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return line


## A new language is drawn on the page at once.
func _on_row_changed(key: StringName, _value: Variant) -> void:
    if key == &"language":
        rebuild_requested.emit()


## A catalogue came or went while the page was built: its rows are declared
## again, and the window is asked for nothing.
func _on_catalogues_changed() -> void:
    page.rebuild()
