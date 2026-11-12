## What a preset says about itself in its own file: the six metadata keys, which
## engine it belongs to, and where it came from under what licence.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Why one file.** The engine and the provenance were two files of fifty lines
## each, cut out of `sa_preset_store.gd` to keep it under a line count, and with
## the store they declared six keys in three places, the bundle's twice. Every
## key here is a fact about a preset's own file rather than a brush setting, so
## it is metadata that `SaPresetStore.copy_settings()` never carries, and the
## sentence and the engine are both decided from that file and nothing else. One
## class states each key once and answers both questions.
##
## Everything is static, because what a preset says about itself is a fact about
## a file rather than a thing with state. Through the translation server, because
## a static function has no `tr`.
class_name SaPresetMeta
extends RefCounted

## Where a preset's tags live inside its own file. Godot writes metadata into a
## `.tres` as `metadata/tags`, so a preset carries its own tags and there is no
## index file beside the directory to fall out of step with it.
const TAGS_META: StringName = &"tags"

## Where a preset names the engine it was written for, rather than leaving it to
## the `script_class` of its header, which nothing reads, an accident a second
## engine would turn into a bug: `copy_settings`
## writes whatever names match and drops the rest without a word.
const ENGINE_META: StringName = &"engine"

## Where a preset says what it lays and what it is for, a sentence or three:
## the first line of a cell's tooltip, the brush editor's text box, and what the
## door lists beside the name so a script picks without rehearsing. Written by
## the painter in the editor or by a module's recipe, and a fact about the file
## like the tags, so `SaPresetStore.copy_settings()` never carries it and a save
## over the same name keeps it.
const DESCRIPTION_META: StringName = &"description"

## Where a shipped preset's sentence lived before [constant DESCRIPTION_META],
## read as its description by a file that has no other, so a profile whose
## stock presets were written by an older build keeps saying what each is for.
## Nothing writes it any more, and a recipe's `about` is written as the
## description.
const ABOUT_META: StringName = &"about"

## Which bundle a preset came from, holding the bundle's title. The key
## `SaKppImport` writes from a Krita bundle's own title as well, so a preset Sara
## shipped and one imported from a Krita bundle answer alike.
const BUNDLE_META: StringName = &"bundle"

## The licence a bundle states for the presets it carries.
## `SaPresetStore.install_shipped` writes it from the line the recipe table names
## the bundle's under, and `SaKppImport` from a bundle's `meta.xml`.
const LICENCE_META: StringName = &"licence"

## The file an imported preset came from. `SaKppImport.SOURCE_META` is the same
## string, spelled there rather than asked of core because a module's import
## writes it, and the chooser's suite holds the two spellings together.
const SOURCE_META: StringName = &"imported_from"

## The version of the bundle a preset came from, as its table declares it.
const BUNDLE_VERSION_META: StringName = &"bundle_version"

## Who made the bundle a preset came from, as its table declares it.
const BUNDLE_AUTHOR_META: StringName = &"bundle_author"

## The bundle's own sentence, what the whole bundle holds, beside the preset's
## `about`, which says what the one preset paints.
const BUNDLE_ABOUT_META: StringName = &"bundle_about"

## The bundle's fields a recipe table may name on an entry beside `bundle`,
## each written onto the preset under its own key by
## `SaPresetStore.install_shipped`. The entry's key is the metadata's, so a
## table spells each once and the store copies what it finds.
const BUNDLE_FIELDS: Array[StringName] = [BUNDLE_VERSION_META, BUNDLE_AUTHOR_META, BUNDLE_ABOUT_META]

## The keys [method origin] reads, in the order it answers them.
const ORIGIN_KEYS: Array[StringName] = [
    BUNDLE_META, LICENCE_META, SOURCE_META, BUNDLE_VERSION_META, BUNDLE_AUTHOR_META, BUNDLE_ABOUT_META
]

## The keys a preset converted to another engine takes from the one it came
## from: where it came from and what it says it is for, which a conversion
## changes neither of.
const CONVERTED_KEYS: Array[StringName] = [BUNDLE_META, LICENCE_META, SOURCE_META, DESCRIPTION_META]

## The constant a settings script declares its engine under, `&"stamp"` on the
## stamp brush's. Off the script rather than out of a registry, because the store
## is handed a settings resource and nothing else.
const ENGINE_CONSTANT: String = "PRESET_ENGINE"


## What one preset says of itself that the tag row and the presets docker ask
## for, read off one load, which `SaPresetStore` keeps per name. A preset that
## is not there says nothing. Here rather than in the store, because every
## field is one of this class's keys read off the file.
class Facts:
    var tags := PackedStringArray()
    var engine: StringName = &""
    var description: String = ""
    var origin := SaPresetMeta.origin(null)
    var erases: bool = false

    func _init(preset: Resource) -> void:
        if preset == null:
            return
        if preset.has_meta(SaPresetMeta.TAGS_META):
            var held: PackedStringArray = preset.get_meta(SaPresetMeta.TAGS_META)
            tags = held
            tags.sort()
        engine = StringName(str(preset.get_meta(SaPresetMeta.ENGINE_META, "")))
        description = SaPresetMeta.description_of(preset)
        origin = SaPresetMeta.origin(preset)
        var mode: Variant = preset.get("blend_mode")
        erases = mode != null and StringName(str(mode)) == SaLayer.BLEND_MODE.ERASE


## The engine *settings* belongs to: the `PRESET_ENGINE` its script or a script it
## extends declares, else its script's class name, else empty.
##
## The class name is the fallback so a third-party settings script that declares
## nothing still has an id that is its own, and a preset of it is still told apart
## from a stamp preset.
static func engine_of(settings: Resource) -> StringName:
    var script: Script = settings.get_script() if settings != null else null
    var engine := declared_engine(script)
    if not String(engine).is_empty() or script == null:
        return engine
    return script.get_global_name()


## The `PRESET_ENGINE` *script* or a script it extends declares, or empty.
static func declared_engine(script: Script) -> StringName:
    var walk := script
    while walk != null:
        var constants := walk.get_script_constant_map()
        if constants.has(ENGINE_CONSTANT):
            return StringName(str(constants[ENGINE_CONSTANT]))
        walk = walk.get_base_script()
    return &""


## An engine's id the way a painter reads it, `stamp` as "Stamp". Made from the id
## rather than looked up, so a module's engine is named without registering a
## name.
static func engine_name(engine: StringName) -> String:
    var words := String(engine).capitalize()
    if words.is_empty():
        return TranslationServer.translate("Unknown")
    return TranslationServer.translate(words)


## What *preset* says it lays and what it is for, as its file holds it, or
## empty. The older key is the answer of a file that has only that.
static func description_of(preset: Resource) -> String:
    if preset == null:
        return ""
    if preset.has_meta(DESCRIPTION_META):
        return SaTyped.text(preset.get_meta(DESCRIPTION_META, ""))
    return SaTyped.text(preset.get_meta(ABOUT_META, ""))


## A description as the painter reads it. Through the catalogue, so a stock
## preset's sentence, which the template collects from its recipe, reads in the
## painter's language, while a painter's own text has no entry there and comes
## back as written.
static func description_said(text: String) -> String:
    return "" if text.is_empty() else String(TranslationServer.translate(text))


## The line saying where *preset* came from, or empty when its own file says
## nothing: the tooltip of a cell in the chooser's grid, and the dimmed line
## under it.
##
## **A bundle first**, because that is the answer a painter about to ship a
## picture wants: the licence the bundle states covers every preset in it. A
## preset with no bundle but a source is an import whose bundle said nothing about
## itself, and the file it came from is all there is left to say. A preset with
## neither is one a painter saved themselves, which says nothing, and that is the
## honest answer and the reason both hosts show no line rather than an empty one.
static func provenance_line(preset: Resource) -> String:
    return provenance_said(origin(preset))


## What *preset* says of where it came from, kept apart from the line itself so
## a store that caches it writes the line in the language of the moment it is
## asked for rather than of the moment it read the file. Six strings, in the
## order of [constant ORIGIN_KEYS]: the bundle, its licence, the source file,
## the bundle's version, its author and its sentence, each empty when the file
## does not say.
static func origin(preset: Resource) -> PackedStringArray:
    var found := PackedStringArray()
    for key: StringName in ORIGIN_KEYS:
        found.append(SaTyped.text(preset.get_meta(key, "")) if preset != null else "")
    return found


## The provenance line [method origin]'s strings make, in the current language.
##
## A bundle that names its version is read with it, "From Sara Basic 1.0",
## which is how a painter tells two releases of one bundle apart, and one that
## names its author says by whom.
static func provenance_said(found: PackedStringArray) -> String:
    var bundle := found[0]
    if found.size() > 3 and not bundle.is_empty() and not found[3].is_empty():
        bundle = "%s %s" % [bundle, found[3]]
    if not bundle.is_empty():
        var licence := found[1]
        var author := found[4] if found.size() > 4 else ""
        if author.is_empty():
            if licence.is_empty():
                return TranslationServer.translate("From %s") % bundle
            return TranslationServer.translate("From %s, %s") % [bundle, licence]
        if licence.is_empty():
            return TranslationServer.translate("From %s by %s") % [bundle, author]
        return TranslationServer.translate("From %s by %s, %s") % [bundle, author, licence]
    var source := found[2]
    if source.is_empty():
        return ""
    return TranslationServer.translate("Imported from %s") % source
