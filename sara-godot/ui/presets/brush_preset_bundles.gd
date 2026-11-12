## The Brush Presets panel's bundle menu: every bundle the library holds, each
## with a tick, and a bundle unticked is unloaded.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## A painter loads and unloads a bundle in one click here. Out of
## `brush_presets_chooser.gd` for the reason
## `SaBrushPresetTagFilter` is: the chooser owns a grid and the filters it is
## under, the profile owns which bundles are off
## (`SaSettings.preset_bundles_off`), and this owns the menu and the rule
## between them. The chooser, the bar's quick picks and the search each gain
## one call to [method loaded].
##
## **Unloaded, not deleted.** A bundle unticked leaves its presets on disk and
## in the store, so a tick brings every one back as it was. Only what the
## painter is offered changes: the grid, the quick picks and the search.
##
## **The profile is the state.** The ticks are a list of titles turned off, so
## a bundle imported later starts loaded and a restart keeps what was unticked.
##
## **A preset of no bundle is always loaded.** The painter's own presets carry
## no bundle title and the menu has no row to untick them by.
class_name SaBrushPresetBundles
extends RefCounted

## A tick moved, here or in the other host's panel, so the grid is built again.
signal changed

## The menu. Its rows are checkable, and a press on a row's words ticks its box
## as on the Window menu, so the list stays open while a painter unticks two.
var button: SaChoiceButton = null

## The store the rows were last built from, for the count beside each title.
var _store: SaPresetStore = null


func _init(parent: Control) -> void:
    button = SaMake.choice(parent, "ChooserBundles")
    button.popup.one_of = false
    button.text = tr("Bundles")
    button.tooltip_text = tr("Tick a bundle to load its presets, untick it to put them away. Their files stay.")
    button.popup.marked.connect(_on_marked)
    # Heard only while the panel is on screen, so a closed panel's menu does not
    # rebuild a grid nobody sees, and the other host's tick reaches this one.
    follow(button, changed.emit)


## Whether *stored_name* in *store* is offered: its bundle is ticked, or it is
## of no bundle.
static func loaded(store: SaPresetStore, stored_name: String) -> bool:
    var off: Array = SaSettings.preset_bundles_off
    return off.is_empty() or not off.has(store.origin_for(stored_name)[0])


## Every bundle title *store* holds a preset of, to the names it holds, sorted.
static func bundles_of(store: SaPresetStore) -> Dictionary:
    var out: Dictionary = {}
    for stored_name: String in store.list_names():
        var title := store.origin_for(stored_name)[0]
        if not title.is_empty():
            # A packed array is a value, so the grown copy is put back.
            var names: PackedStringArray = out.get(title, PackedStringArray())
            names.append(stored_name)
            out[title] = names
    var sorted: Dictionary = {}
    var titles := PackedStringArray(out.keys())
    titles.sort()
    for title: String in titles:
        sorted[title] = out[title]
    return sorted


## Builds the rows again from *store*, one per bundle with its tick and the
## number of presets it holds at the row's right.
func rebuild(store: SaPresetStore) -> void:
    _store = store
    var bundles := bundles_of(store)
    var off: Array = SaSettings.preset_bundles_off
    button.popup.clear()
    for title: String in bundles:
        var count := (bundles[title] as PackedStringArray).size()
        button.popup.add_row(StringName(title), title, true, not off.has(title), "", str(count))
    button.visible = not bundles.is_empty()
    var unticked := 0
    for title: String in bundles:
        unticked += 1 if off.has(title) else 0
    button.text = (tr("Bundles") if unticked == 0 else tr_n("Bundles: %d off", "Bundles: %d off", unticked) % unticked)


## Ticks or unticks *title* through the profile, which is what a press on its
## row does and what a test asks.
func put(title: String, on: bool) -> void:
    var off: Array = SaSettings.preset_bundles_off.duplicate()
    if on != off.has(title):
        return
    if on:
        off.erase(title)
    else:
        off.append(title)
        off.sort()
    SaSettings.preset_bundles_off = off


func _on_marked(id: StringName, on: bool) -> void:
    put(String(id), on)


## Calls *on_change* each time the ticks move while *node* is in the tree. The
## bar's preset list is the other caller, which offers what the grid does.
static func follow(node: Node, on_change: Callable) -> void:
    var heard := func(property: StringName) -> void:
        if property == &"preset_bundles_off":
            on_change.call()
    var listen := func(on: bool) -> void:
        if on and not SaSettings.changed.is_connected(heard):
            SaSettings.changed.connect(heard)
        elif not on and SaSettings.changed.is_connected(heard):
            SaSettings.changed.disconnect(heard)
    node.tree_entered.connect(listen.bind(true))
    node.tree_exiting.connect(listen.bind(false))
    if node.is_inside_tree():
        listen.call(true)


## The state dump's record: the bundles of the bar's store, the titles turned
## off in the profile and the names the bar offers, empty before the bar is built.
static func capture_state(root: Node) -> Dictionary:
    var group := ToolOptionsPresets.in_tree(root)
    if group == null:
        return {}
    return {
        "bundles": report_of(group.preset_store),
        "off": SaSettings.preset_bundles_off.duplicate(),
        "offered": group.preset_names(),
    }


## What a dump reads: every bundle of *store* by title, whether it is loaded,
## and the presets it holds.
static func report_of(store: SaPresetStore) -> Dictionary:
    var out: Dictionary = {}
    if store == null:
        return out
    var bundles := bundles_of(store)
    for title: String in bundles:
        out[title] = {"loaded": not SaSettings.preset_bundles_off.has(title), "presets": bundles[title]}
    return out
