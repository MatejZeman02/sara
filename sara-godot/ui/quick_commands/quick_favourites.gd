## Quick Favourites: the commands a painter added from a menu row's right
## click, in the order they were added, and the list Shift+Q opens of them.
## Blender's Quick Favourites on Q is the inspiration, on Shift+Q here because Q
## alone is the Pan tool, and no code of Blender's is taken.
##
## **Kept with the shortcut profile**, in a `favourites` section of the
## profile's own file beside its `chords`, so a painter who switches to the
## Photoshop map for a colleague switches favourites with it, and
## `SaShortcutStore` rewrites only the chords when a rebind saves the file.
##
## **A shipped profile is forked by the first favourite**, the way the first
## rebind forks it (`SaShortcutStore.remember_edit`): the build's own maps are
## tables rather than files, so there is nowhere to keep a list under them, and
## the fork is the painter's copy that has somewhere.
##
## A command a module took away with it stays in the file and is left off the
## list, so loading the module again brings the favourite back.
class_name QuickFavourites
extends RefCounted

const SECTION := "favourites"
const KEY := "commands"
## The row the list shows while it holds nothing, which says how to fill it.
const EMPTY_ROW := &"quick_none"


## The profile the settings name, spelt the way the store names it.
static func profile() -> String:
    var active := SaSettings.shortcuts_profile
    return SaShortcutStore.DEFAULT_PROFILE if active.is_empty() or active == "default" else active


## The commands kept for *of_profile*, the profile in use when empty, in the
## order they were added.
static func listed(of_profile: String = "") -> Array[StringName]:
    var out: Array[StringName] = []
    var active := of_profile if not of_profile.is_empty() else profile()
    var config := ConfigFile.new()
    if SaShortcutStore.is_shipped(active) or config.load(SaShortcutStore.path_for(active)) != OK:
        return out
    var stored: Variant = config.get_value(SECTION, KEY, [])
    if stored is Array:
        for command_id: Variant in stored:
            out.append(StringName(str(command_id)))
    return out


## Adds *command_id* at the end, and answers false when it was there already.
static func add(command_id: StringName) -> bool:
    var kept := _kept_where_written()
    if command_id.is_empty() or kept.has(command_id):
        return false
    kept.append(command_id)
    return _write(kept)


## Takes *command_id* off the list, and answers false when it was not on it.
static func remove(command_id: StringName) -> bool:
    var kept := _kept_where_written()
    if not kept.has(command_id):
        return false
    kept.erase(command_id)
    return _write(kept)


## What the file a change is written to holds already: the profile in use, or
## the fork of a shipped one, which may be there from an earlier visit and
## keeps its favourites through the fork made again over it.
static func _kept_where_written() -> Array[StringName]:
    return listed(SaShortcutStore.target_profile(profile()))


## Writes *kept* into the profile's file, forking a shipped profile first.
static func _write(kept: Array[StringName]) -> bool:
    var active := profile()
    var target := SaShortcutStore.target_profile(active)
    var path := SaShortcutStore.path_for(target)
    if target != active or not FileAccess.file_exists(path):
        SaShortcutStore.save_profile(target)
        if SaSettings.shortcuts_profile != target:
            SaSettings.shortcuts_profile = target
            EventBus.shortcuts_changed.emit()
    var config := ConfigFile.new()
    if config.load(path) != OK:
        return false
    var ids: Array[String] = []
    for command_id: StringName in kept:
        ids.append(String(command_id))
    config.set_value(SECTION, KEY, ids)
    return config.save(path) == OK


## Fills *list* with a row for each favourite *commands* still has, its chord
## at the right and dimmed where it cannot run, or with one dimmed row saying
## how to add one.
static func fill(list: SaChoicePopup, commands: SaCommandRegistry) -> void:
    list.clear()
    list.add_section(list.tr("Quick Favourites"))
    for command_id: StringName in listed():
        var descriptor := commands.get_descriptor(command_id) if commands != null else null
        if descriptor == null:
            continue
        var chord := chord_of(commands, command_id)
        list.add_row(command_id, list.tr(descriptor.menu_label()), false, false, "", chord, not descriptor.is_enabled())
    if list.row_ids().is_empty():
        list.add_row(EMPTY_ROW, list.tr("Right-click a menu row to add it here"), false, false, "", "", true)


## The first chord *command_id* answers to, as its menu row names it: the
## command's own, or the `project.godot` action of its name the row falls back
## to, which is where Undo and Redo keep theirs (`SaMenu.chord_of`).
static func chord_of(commands: SaCommandRegistry, command_id: StringName) -> String:
    var chord := commands.chord_text(command_id, 1) if commands != null else ""
    if chord.is_empty() and InputMap.has_action(command_id):
        chord = SaCommandRegistry.format_events(InputMap.action_get_events(command_id), 1)
    return chord
