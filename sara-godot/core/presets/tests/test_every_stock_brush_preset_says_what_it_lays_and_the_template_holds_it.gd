## Every stock brush preset says what it lays and what it is for, and the
## message template holds each sentence, so a Czech painter reads it in Czech.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter, 2026-11-09: "every brush preset should hold a description that
## will show as a tooltip, or inside the brush editor (for user to edit) and for
## scripts via doors to know what they are picking." A fresh install has
## something to say only if every recipe a module ships carries a sentence.
##
## **The shelves are found as the install finds them**, every role whose name
## starts `shipped_presets` once the packaged modules are loaded, so an engine
## added later is walked without this file naming it. The four shelves of
## today are named as well, so a loader that registered nothing cannot pass by
## walking no recipe at all.
##
## **The template is read as written**, `translations/sara.pot`. Most stock
## sentences open on "A" and a word, which the template writer has to read as a
## label beside a capital and a small letter, or the tooltip asks the catalogue
## for a sentence no catalogue holds and a Czech painter reads it in English.
extends "res://tests/test_framework.gd"

## Loading the modules builds their engines, which needs a RenderingDevice.
const REQUIRES_GPU := true

## The start of every role a shelf of stock presets is registered under.
const SHELF_ROLE_PREFIX: String = "shipped_presets"

## The shelves of today, which the walk has to reach.
const KNOWN_SHELVES: Array[String] = [
    "res://modules/sara-base-modules/stamp-brush/presets/sa_shipped_presets.gd",
    "res://modules/sara-base-modules/filter-brush/presets/filter_brush_presets.gd",
    "res://modules/sara-base-modules/base/liquify/liquify_presets.gd",
    "res://modules/sara-noise-brush-engine/presets/noise_presets.gd",
]

## The template every message Sara shows is collected into.
const TEMPLATE: String = "res://translations/sara.pot"

## The fewest stock presets the walk has to find, a floor well under today's
## 76 so a shelf that loses its table fails here rather than passing on less.
const FEWEST_PRESETS: int = 60

static var scratch_root: String = SaDataRoot.path("test_descriptions/modules")

var _registries: SaRegistries


func before_each() -> void:
    _registries = SaRegistries.new()
    _registries.build_context(func() -> Variant: return null, func() -> Array: return [])
    ModuleLoader.user_modules_root = scratch_root
    ModuleLoader.verbose = false
    ModuleLoader.load_and_register_modules(_registries.context)
    ModuleLoader.verbose = true


func after_each() -> void:
    ModuleLoader.unload_all()
    ModuleLoader.user_modules_root = SaDataRoot.path(ModuleLoader.USER_MODULES_FOLDER)
    _registries = null


## The scripts of every shelf the loaded modules registered.
func _shelves() -> Array[Script]:
    var shelves: Array[Script] = []
    for role: StringName in _registries.roles.list_roles():
        if String(role).begins_with(SHELF_ROLE_PREFIX):
            var script := _registries.roles.script_for(role)
            if script != null and not shelves.has(script):
                shelves.append(script)
    return shelves


## Every stock recipe of every shelf, as the install reads them.
func _recipes() -> Array[Dictionary]:
    var all: Array[Dictionary] = []
    for shelf: Script in _shelves():
        for recipe: Dictionary in shelf.call("entries"):
            all.append(recipe)
    return all


## A recipe's sentence, under `description` or the older `about`, the way
## `SaPresetStore.install_shipped` reads it.
func _description(recipe: Dictionary) -> String:
    return String(recipe.get("description", recipe.get("about", ""))).strip_edges()


## Every message of the template, joined across its continued lines.
func _template_messages() -> Dictionary[String, bool]:
    var messages: Dictionary[String, bool] = {}
    var text := FileAccess.get_file_as_string(TEMPLATE)
    var message := ""
    var reading := false
    for line: String in text.split("\n"):
        if line.begins_with("msgid "):
            message = String(JSON.parse_string(line.substr(6)))
            reading = true
        elif reading and line.begins_with('"'):
            message += String(JSON.parse_string(line))
        else:
            if reading and not message.is_empty():
                messages[message] = true
            reading = false
    return messages


func test_the_walk_reaches_every_shelf_of_today() -> void:
    var paths: Array[String] = []
    for shelf: Script in _shelves():
        paths.append(shelf.resource_path)
    for known: String in KNOWN_SHELVES:
        assert_true(paths.has(known), "the walk reaches %s, found %s" % [known, paths])
    assert_true(
        _recipes().size() >= FEWEST_PRESETS, "and %d stock presets or more, found %d" % [FEWEST_PRESETS, _recipes().size()]
    )


func test_every_stock_preset_carries_a_description() -> void:
    var bare: Array[String] = []
    for recipe: Dictionary in _recipes():
        if _description(recipe).is_empty():
            bare.append(String(recipe.get("name", "")))
    assert_eq(bare, [] as Array[String], "every stock preset says what it lays and what it is for")


func test_the_template_holds_every_stock_description() -> void:
    var messages := _template_messages()
    assert_true(messages.size() > 1000, "the template is read, %d messages" % messages.size())
    var missing: Array[String] = []
    for recipe: Dictionary in _recipes():
        var said := _description(recipe)
        if not said.is_empty() and not messages.has(said):
            missing.append(String(recipe.get("name", "")))
    assert_eq(missing, [] as Array[String], "the template holds every stock preset's description")


func test_a_description_opening_on_a_and_a_word_reads_as_a_label() -> void:
    var opening_on_a := 0
    var messages := _template_messages()
    for recipe: Dictionary in _recipes():
        var said := _description(recipe)
        if said.begins_with("A ") and messages.has(said):
            opening_on_a += 1
    assert_true(opening_on_a > 0, "a sentence opening on A and a word is in the template, %d of them" % opening_on_a)
