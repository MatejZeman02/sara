## The `preset` step's listing: every brush preset a tool takes, or every one
## there is, each with its engine, its tags and what it says it is for.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A script picked a preset by its name and rehearsed it to learn what
## it lays, and a name says less than it seems: Dry Strokes laid near white
## because its blend mode was said nowhere. A preset's description is the
## sentence the painter reads first in its tooltip, so the door hands a script
## the same sentence before it picks.
##
## A class of its own beside the other drivers rather than more lines in the
## `preset` step, which saves, loads and deletes through the bar. This asks the
## store and changes nothing. A key of that step rather than a kind of its own,
## because the list of kinds the door answers is held under a small model's
## context and had no room for another.
class_name SaPresetListDriver
extends RefCounted


## The listing `{"preset": {"list": ...}}` answers: the brush presets of one
## tool, of one engine or of every tool, each with its engine, its tags and its
## description, and nothing changed.
##
## `{"preset": {"list": "brush"}}` lists the presets the Brush tool takes, which
## is every brush engine's, `{"preset": {"list": "stamp"}}` the presets of the
## stamp engine, and `{"preset": {"list": ""}}` every preset there is. A word
## that names a registered tool is read as the tool, else as an engine. The
## answer is one line, `SaCapture: preset_list` and a JSON array of `{"name",
## "engine", "tags", "description"}` in the order the store lists them, where
## the description is the text the cell's tooltip opens on and empty for a
## preset that says nothing. The same description is in `pick_preset`'s answer.
static func capture_list(tree: SceneTree, wanted: String) -> String:
    var presets := ToolOptionsPresets.in_tree(tree.root)
    if presets == null or presets.preset_store == null:
        return "SaCapture: preset_list found no preset store, so there is nothing to list"
    var main_node := tree.current_scene
    var tools: SaToolRegistry = null
    if main_node != null and "registries" in main_node:
        var registries: SaRegistries = main_node.registries
        tools = registries.tools if registries != null else null
    return "SaCapture: preset_list %s" % JSON.stringify(rows(presets.preset_store, engines_wanted(tools, wanted)))


## The engines *wanted* asks for: the presets' engines of a tool's brush engines
## when it names a tool, itself when it names anything else, and none, meaning
## every engine, when it is empty.
static func engines_wanted(tools: SaToolRegistry, wanted: String) -> Array[StringName]:
    var engines: Array[StringName] = []
    var word := StringName(wanted.strip_edges())
    if String(word).is_empty():
        return engines
    if tools == null or not tools.has(word):
        engines.append(word)
        return engines
    for engine_id: StringName in tools.engines_of(word):
        var descriptor := tools.get_descriptor(engine_id)
        if descriptor != null and not String(descriptor.preset_engine).is_empty():
            if not engines.has(descriptor.preset_engine):
                engines.append(descriptor.preset_engine)
    return engines


## One row per preset of *store* whose engine is among *engines*, or of every
## preset when *engines* is empty.
static func rows(store: SaPresetStore, engines: Array[StringName]) -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    for stored_name: String in store.list_names():
        var engine := store.engine_for(stored_name)
        if not engines.is_empty() and not engines.has(engine):
            continue
        var said := SaPresetStore.description_said(store.about_for(stored_name))
        var tags := Array(store.tags_for(stored_name))
        found.append({"name": stored_name, "engine": String(engine), "tags": tags, "description": said})
    return found
