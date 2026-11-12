## The tool options bar's controls that come and go by a rule of their own: a
## control whose spec carries a `shown_when` is on the bar only while the rule
## holds on the tool that owns it, the rule the Tool Options docker and the brush
## editor already honour.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Paint and Smudge is the first such control on the bar,
## there for a brush whose Smudge Pickup is ticked and gone for one that does not
## smudge. A preset load moves the answer with no tool change, so the bar reads
## [method answers] after every sync, and lays itself out again when one
## [method moved].
##
## **Static, with the answers held by the bar.** An instance would hold the bar
## that built it, a back reference the structure suite drains, and the one
## thing to remember between syncs is a dictionary the bar can keep itself.
class_name SaToolOptionsRules
extends RefCounted


## Whether *control*'s rule holds on *bar*, true for a control with none.
static func holds(bar: ToolOptionsBar, control: Control) -> bool:
    for key: StringName in bar.options.keys():
        if bar.options.control(key) == control:
            return holds_for(bar, key)
    return true


## Whether the rule of the control for *key* holds on the tool that owns it,
## read through the owner because the brush's controls stay on the bar whatever
## tool is chosen.
static func holds_for(bar: ToolOptionsBar, key: StringName) -> bool:
    var spec := _ruled(bar, key)
    if spec == null:
        return true
    var id := bar.owner_of(key)
    var tool := bar.owner_tool(key)
    var options := bar.options
    var own := func(asked: StringName) -> Variant: return options.read(asked, tool, id)
    return spec.shown_under(SaOptionSpec.reading_settings(own, tool.get("settings") if tool != null else null))


## What every ruled control on *bar* answers now, by key.
static func answers(bar: ToolOptionsBar) -> Dictionary[StringName, bool]:
    var out: Dictionary[StringName, bool] = {}
    for key: StringName in bar.options.keys():
        if _ruled(bar, key) != null:
            out[key] = holds_for(bar, key)
    return out


## Whether an answer in *now* differs from the one *before* held for its key.
## A key *before* never held moves nothing, because the layout that drew the
## bar asked [method holds] itself.
static func moved(before: Dictionary[StringName, bool], now: Dictionary[StringName, bool]) -> bool:
    for key: StringName in now:
        if before.has(key) and before[key] != now[key]:
            return true
    return false


## The spec the owner of *key* declared, when it carries a rule, or null.
static func _ruled(bar: ToolOptionsBar, key: StringName) -> SaOptionSpec:
    var spec := bar.options.spec_for(key, bar.owner_of(key))
    return spec if spec != null and not spec.shown_when.is_empty() else null
