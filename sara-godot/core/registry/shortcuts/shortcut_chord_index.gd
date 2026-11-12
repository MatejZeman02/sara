## Which actions answer to which chord, read off the `InputMap` once. Private to
## the chord store's folder: `SaShortcutStore.all_conflicts` and a profile switch
## ask through it.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## `SaShortcutStore.conflicts` reads every action's chords to answer one chord,
## which is right for one question and quadratic for a whole map. Marking the
## Keyboard Shortcuts page asked it for every chord of every action, and a switch
## to Krita asked it again for every chord the profile claims, so a switch took
## 25 s on Linux and half a minute on Windows. Read once, each
## question is a lookup.
class_name SaShortcutChordIndex
extends RefCounted

## chord text -> the actions answering to it, in the order the `InputMap`
## listed them when this was read.
var _by_chord: Dictionary[String, Array] = {}
## action -> the chords it answered to when this read it.
var _by_action: Dictionary[StringName, Array] = {}


func _init() -> void:
    for action: StringName in InputMap.get_actions():
        _add(action)


## The actions other than *ignore* that answer to *chord*, by the rules of
## `SaShortcutStore.conflicts`: an action *ignore* is one gesture with, or shares
## a key with on purpose, is not one of them.
func conflicts(chord: String, ignore: StringName = &"") -> Array[String]:
    var out: Array[String] = []
    var paired := SaShortcutStore.paired_with(ignore)
    var shared := SaShortcutStore.gesture_paired_with(ignore)
    for action: StringName in _by_chord.get(chord, []):
        if action == ignore or paired.has(action) or shared.has(action):
            continue
        out.append(String(action))
    return out


## Every action that answers to a chord another one also answers to, as
## `{action: [the others]}`, what `SaShortcutStore.all_conflicts` answers.
func clashes() -> Dictionary[String, Array]:
    var out: Dictionary[String, Array] = {}
    for action: StringName in _by_action:
        var clashing: Array[String] = []
        for chord: String in _by_action[action]:
            for other: String in conflicts(chord, action):
                if not clashing.has(other):
                    clashing.append(other)
        if not clashing.is_empty():
            out[String(action)] = clashing
    return out


## Reads again every action `SaShortcutStore.set_chords` on *action* writes,
## its aliases and the other half of its pair with theirs, so a question after
## a rewrite answers from the map as it is now.
func reread_after_writing(action: StringName) -> void:
    var written: Array[StringName] = [action]
    written.append_array(SaShortcutStore.aliases_of(action))
    for partner: StringName in SaShortcutStore.paired_with(action):
        written.append(partner)
        written.append_array(SaShortcutStore.aliases_of(partner))
    for each: StringName in written:
        for chord: String in _by_action.get(each, []):
            _by_chord[chord].erase(each)
        _by_action.erase(each)
        _add(each)


func _add(action: StringName) -> void:
    if SaShortcutStore.is_engine_action(action) or not InputMap.has_action(action):
        return
    var chords: Array[String] = []
    for chord: String in SaShortcutStore.chords_for(action):
        if chords.has(chord):
            continue
        chords.append(chord)
        if not _by_chord.has(chord):
            _by_chord[chord] = []
        _by_chord[chord].append(action)
    _by_action[action] = chords
