## The rows the search lists that no registry holds: every brush preset in the
## store and every row a menu draws with no command behind it, each a source of
## `SaSearchRegistry.Row` answering `search_rows` as a registry does, handed to
## the walk by [method sources]. And what picking a kind of layer does, which
## the layer type registry's rows are bound to where the app wires the search.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **A pick is the door the painter's own press takes.** A preset is loaded by
## the bar's preset group, `ToolOptionsPresets.load_preset`, which a cell of the
## Brush Presets docker calls too. A preset of another engine the tool in hand
## paints switches to that engine, and under a tool that takes no presets the
## surface switches to the tool that does, the rule that call has always kept.
## A layer kind is the Layer menu's own row number pressed on the menu, so a
## kind that holds filters opens the browser as the menu does. Any other row is
## pressed on its popup, which is a click on it.
##
## **Every preset, not the engine in hand alone.** The store lists every
## engine's presets, and a painter who knows a preset's name should not have to
## know which tool paints it first.
class_name SaSearchActions
extends RefCounted

## What each kind says it is on its row.
const PRESET := "Brush Preset"
const LAYER := SaSearchRegistry.LAYER
const MENU := "Menu"

## Where a preset lives, the docker that shows it.
const PRESETS_PLACE := "Brush Presets"


## The sources the walk reads after the registries: the presets, then the
## menus' own rows. *menus* is the bar's menu objects by title, as
## `SaSearchIndex.entries` takes them, and may be empty, which lists no menu row.
static func sources(context: SaContext, menus: Dictionary) -> Array:
    return [Presets.new(), MenuRows.new(menus, context.layer_types)]


## The bar's menus by title, as [method sources] takes them, or none with no bar.
static func menus_of(bar: TopMenuBar) -> Dictionary:
    var menus := {}
    if bar == null:
        return menus
    for named: String in TopMenuBar.MENU_NAMES:
        if bar.menu(named) != null:
            menus[named] = bar.menu(named)
    return menus


## The bar the main window shows, the current scene's or the first in the tree,
## or null in a tree that has none.
static func bar_in(tree: SceneTree) -> TopMenuBar:
    if tree == null:
        return null
    var scene := tree.current_scene
    var bar := scene.get("custom_title_bar") as TopMenuBar if scene != null else null
    if bar == null:
        for node in tree.root.find_children("*", "PanelContainer", true, false):
            bar = node as TopMenuBar
            if bar != null:
                break
    return bar


## Adds a layer of *kind* as the Layer menu's row for it does, pressing that row
## on the bar's Layer menu, or with no bar through the rows the menu draws from,
## on the main document. What the layer type registry's `search_pick` is bound
## to, with the app's command registry held weakly in *commands*, since the
## registries hold the bound call.
static func add_kind(kind: StringName, kinds: SaLayerTypeRegistry, commands: WeakRef) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var layer_menu := menus_of(bar_in(tree)).get("Layer") as SaLayerMenu
    var at := addable(kinds).map(func(descriptor: SaLayerTypeDescriptor) -> StringName: return descriptor.id).find(kind)
    if layer_menu != null and at != -1:
        layer_menu.on_id_pressed(SaLayerMenuRows.FIRST_KIND + at)
        return
    var scene := tree.current_scene if tree != null else null
    var canvas := scene.call("get_canvas") as SaCanvas if scene != null and scene.has_method("get_canvas") else null
    if canvas != null:
        SaLayerMenuRows.new(canvas.document, commands.get_ref() as SaCommandRegistry, kinds).run(kind, scene)


## The kinds the Layer menu draws as kind rows, `SaLayerMenuRows`' list with the
## plain layer left out, because New Layer is a command and so a row already.
static func addable(kinds: SaLayerTypeRegistry) -> Array[SaLayerTypeDescriptor]:
    var out: Array[SaLayerTypeDescriptor] = []
    for descriptor: SaLayerTypeDescriptor in SaLayerMenuRows.addable(kinds):
        if descriptor.id != SaLayerTypeDescriptor.PLAIN:
            out.append(descriptor)
    return out


## Every preset in the bar's preset group's store, the group handed in or the
## one in the tree.
class Presets:
    extends RefCounted
    var _group: ToolOptionsPresets

    func _init(group: ToolOptionsPresets = null) -> void:
        _group = group

    func search_rows() -> Array[SaSearchRegistry.Row]:
        var out: Array[SaSearchRegistry.Row] = []
        var group := _group
        if group == null:
            var tree := Engine.get_main_loop() as SceneTree
            group = ToolOptionsPresets.in_tree(tree.root) if tree != null else null
        if group == null:
            return out
        var store := group.preset_store
        for stored_name: String in store.names_tagged(""):
            if not SaBrushPresetBundles.loaded(store, stored_name):
                continue
            var engine := String(store.engine_for(stored_name))
            var sentence := " ".join([store.about_for(stored_name), engine.capitalize(), "brush preset"])
            var act := SaSearchActions._load_preset.bind(group, stored_name)
            out.append(SaSearchRegistry.Row.new(PRESET, stored_name, tr(PRESETS_PLACE), act, &"", sentence))
        return out


## Every row a menu drew with no command behind it, a View toggle, a recent
## file, a gamut to convert to: the rows a command row cannot stand for. A
## branch is left out, since what it opens is listed, and so is a kind of
## layer, which the layer type registry's rows are. So is a dimmed row with no
## box, which is a placeholder such as File's "No recent files" and acts on
## nothing, while a dimmed tick row is listed dimmed, as its menu draws it. A
## row gives way to an earlier row of its title, the Tools menu's Brush being
## the Brush's row found twice.
class MenuRows:
    extends RefCounted
    var _menus: Dictionary
    var _kinds: SaLayerTypeRegistry

    func _init(menus: Dictionary, kinds: SaLayerTypeRegistry) -> void:
        _menus = menus
        _kinds = kinds

    func search_rows() -> Array[SaSearchRegistry.Row]:
        var out: Array[SaSearchRegistry.Row] = []
        var kinds := SaSearchActions.addable(_kinds).size() if _kinds != null else 0
        for title: String in _menus:
            var menu := _menus[title] as SaMenu
            if menu == null or menu.popup == null:
                continue
            for popup: SaChoicePopup in SaMenu.lists_of(menu.popup):
                _add_rows(out, menu, popup, title, kinds)
        return out

    ## The rows of *popup*, the menu *title*'s own list or one of its
    ## submenus, the loupe has no command for and finds as rows.
    func _add_rows(out: Array[SaSearchRegistry.Row], menu: SaMenu, popup: SaChoicePopup, title: String, kinds: int) -> void:
        for row_id: StringName in popup.row_ids():
            var number := SaMenu.id_of(row_id)
            var first := SaLayerMenuRows.FIRST_KIND
            var a_kind := menu is SaLayerMenu and number >= first and number < first + kinds
            var button := popup.label_button(row_id)
            if a_kind or button == null or button.text.is_empty() or popup.is_branch(row_id):
                continue
            if popup.is_disabled(row_id) and popup.check_box(row_id) == null:
                continue
            if not menu.row_command(row_id).is_empty():
                continue
            var act := SaSearchActions._press.bind(popup, row_id)
            var place := TopMenuBar.menu_title(title)
            var live := not popup.is_disabled(row_id)
            var said := button.tooltip_text
            out.append(SaSearchRegistry.Row.new(MENU, button.text, place, act, &"", said, live, &"", &"", true))


static func _load_preset(group: ToolOptionsPresets, stored_name: String) -> void:
    if is_instance_valid(group):
        group.load_preset(stored_name)


## Presses *row_id* on *popup*, as a click on it would, deferred so the press
## lands after the search that asked has closed.
static func _press(popup: SaChoicePopup, row_id: StringName) -> void:
    if is_instance_valid(popup):
        popup.press_row.call_deferred(row_id)
