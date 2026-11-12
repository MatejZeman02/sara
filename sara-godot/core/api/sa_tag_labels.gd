## How a preset's stored tag reads in the painter's language, asked of the
## modules that write tags of their own.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A tag is stored as one stable word, since the filter, a rename and the
## profile name it, and it is turned into its line when it is shown. The words
## of a tag belong to the module that writes it, so a module registers a
## labeller for the prefix its tags begin with, and the presets chooser, which
## may not name a module, asks here. A tag no labeller claims is shown as it
## is, which is every tag a painter wrote.
##
## Static, as `SaProblems` is: the chooser's `label_of` is a static
## function with no context to hand.
class_name SaTagLabels
extends RefCounted


## One module's labeller for the tags that begin with a prefix.
class Entry:
    var prefix: String
    var labeller: Callable
    var module: StringName

    func _init(for_prefix: String, by: Callable, owner_id: StringName) -> void:
        prefix = for_prefix
        labeller = by
        module = owner_id


## In registration order.
static var _entries: Array[Entry] = []


## Registers *labeller*, a callable taking a stored tag and answering the line
## to show, for every tag that begins with *prefix*, owned by *module_id*.
## Refused for an empty prefix and an invalid callable.
static func register(prefix: String, labeller: Callable, module_id: StringName = &"") -> bool:
    if prefix.is_empty() or not labeller.is_valid():
        push_error("SaTagLabels: a labeller needs a prefix and a callable.")
        return false
    _entries.append(Entry.new(prefix, labeller, module_id))
    return true


## Removes every labeller *module_id* registered.
static func unregister_module(module_id: StringName) -> void:
    var kept: Array[Entry] = []
    for entry: Entry in _entries:
        if entry.module != module_id:
            kept.append(entry)
    _entries = kept


## *tag* as the painter reads it: through the labeller of its prefix, or as it
## is when none claims it.
static func label(tag: String) -> String:
    for entry: Entry in _entries:
        if tag.begins_with(entry.prefix):
            var shown: String = entry.labeller.call(tag)
            return shown
    return tag
