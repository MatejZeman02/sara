## The `pick_preset` step: a brush preset picked by its name, or one at random,
## through the Brush Presets docker.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## The step that reads as one from the step list. `presets_docker`'s `apply` and
## `preset`'s `load` also load a preset by name, but a name there has to match
## the stored one exactly, and a miss does not say what is on offer.
##
## A class of its own beside the docker rather than more lines in it, because
## this owns one decision,
## which preset a name or a seed comes to. The pick itself is the docker's
## `apply_preset`, the path a click on a cell takes, so under a tool that takes
## no presets it puts the brush in the hand as a painter's click does.
class_name SaPresetPick
extends RefCounted

const PresetEngineMarks := preload("res://ui/dockers/presets/preset_engine_marks.gd")

## The name that asks for a preset at random, in any case.
const RANDOM := "random"


## Picks a brush preset by name: or one at random, the way a click on its cell
## in the Brush Presets docker does.
##
## `{"pick_preset": "Inked Pen"}` matches a preset the grid shows exactly
## first, then ignoring case and the spaces around it. A name that matches
## nothing changes nothing and answers with the presets on offer.
## `{"pick_preset": "Random"}`, in any case, picks one of the presets the grid
## shows that is not dimmed, so the pick paints with a tool there is, and
## `{"pick_preset": {"name": "Random", "seed": 7}}` picks the same one on every
## run. Without a seed one is drawn and named in the answer, so a run can be
## repeated. A preset stored under the name Random is reached through
## `{"presets_docker": {"apply": "Random"}}`. The answer names the preset
## picked, the seed when it was random, the tool in hand after the pick, and
## the preset's description when it has one.
static func capture_pick(tree: SceneTree, spec: Variant) -> String:
    var docker := tree.root.find_child(SaDockerIds.BRUSH_PRESETS, true, false) as BrushPresetsDocker
    if docker == null:
        return "SaCapture: no Brush Presets docker, so there is no preset to pick"
    return pick(docker, spec)


## The pick against *docker*, which a suite hands in directly. *spec* is a name,
## or a Dictionary with `name` and an optional `seed`.
static func pick(docker: BrushPresetsDocker, spec: Variant) -> String:
    var wanted := String((spec as Dictionary).get("name", "")) if spec is Dictionary else String(spec)
    var shown := docker.chooser.visible_names() if docker.chooser != null else [] as Array[String]
    if wanted.strip_edges().to_lower() == RANDOM:
        return _pick_at_random(docker, shown, spec)
    var found := match_name(wanted, shown)
    if found.is_empty():
        var offer := JSON.stringify(shown)
        return "SaCapture: pick_preset found no preset named '%s' and changed nothing, on offer %s" % [wanted, offer]
    if not docker.apply_preset(found):
        return "SaCapture: pick_preset could not apply '%s'" % found
    return "SaCapture: pick_preset picked '%s' by name, tool in hand %s%s" % [found, tool_in_hand(docker), said(docker, found)]


## The stored name *wanted* comes to among *shown*: an exact match first, then
## one ignoring case and the spaces around it, or empty when none does.
static func match_name(wanted: String, shown: Array[String]) -> String:
    if shown.has(wanted):
        return wanted
    var loose := wanted.strip_edges().to_lower()
    for stored_name: String in shown:
        if stored_name.strip_edges().to_lower() == loose:
            return stored_name
    return ""


## The presets of *shown* the tool in front of the painter takes, which are the
## cells the docker does not dim, in the order the grid shows them.
static func lit_names(docker: BrushPresetsDocker, shown: Array[String]) -> Array[String]:
    var presets := ToolOptionsPresets.in_tree(docker)
    var lit: Array[String] = []
    if presets == null:
        return lit
    var takes := docker.tool_engines()
    for stored_name: String in shown:
        if not PresetEngineMarks.is_foreign(presets.preset_store.engine_for(stored_name), takes):
            lit.append(stored_name)
    return lit


static func _pick_at_random(docker: BrushPresetsDocker, shown: Array[String], spec: Variant) -> String:
    var lit := lit_names(docker, shown)
    if lit.is_empty():
        return "SaCapture: pick_preset found no preset the tool in hand takes, on offer %s" % JSON.stringify(shown)
    var rng := RandomNumberGenerator.new()
    var given: Variant = (spec as Dictionary).get("seed") if spec is Dictionary else null
    if given == null:
        # Drawn here and named in the answer, so the run that took it can be
        # repeated with the seed written into the step.
        rng.randomize()
        rng.seed = rng.randi()
    else:
        rng.seed = int(given)
    var drawn := int(rng.seed)
    var found := lit[rng.randi_range(0, lit.size() - 1)]
    if not docker.apply_preset(found):
        return "SaCapture: pick_preset could not apply '%s', drawn at random with seed %d" % [found, drawn]
    return (
        "SaCapture: pick_preset picked '%s' at random with seed %d of %d lit presets, tool in hand %s%s"
        % [found, drawn, lit.size(), tool_in_hand(docker), said(docker, found)]
    )


## What *stored_name* says it lays and what it is for, as the end of a pick's
## answer, `, description "..."` with the text quoted as JSON, or nothing for a
## preset that says nothing. The text a cell's tooltip opens on, so a script
## reads what the painter reads.
static func said(docker: BrushPresetsDocker, stored_name: String) -> String:
    var presets := ToolOptionsPresets.in_tree(docker)
    var text := presets.preset_store.about_for(stored_name) if presets != null else ""
    return ", description %s" % JSON.stringify(SaPresetStore.description_said(text)) if not text.is_empty() else ""


## The tool the bar's machine holds, which is what the next press reaches, or
## `<none>` in a host with no bar.
static func tool_in_hand(docker: BrushPresetsDocker) -> String:
    var node: Node = ToolOptionsPresets.in_tree(docker)
    while node != null and not node is ToolOptionsBar:
        node = node.get_parent()
    var bar := node as ToolOptionsBar
    if bar == null or bar.target_tool_machine == null:
        return "<none>"
    return String(bar.target_tool_machine.active_tool_name)
