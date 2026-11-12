## The reorderable layout registry behind Preferences: what a category holds,
## what it is called, and what the painter hid or moved.
##
## Its own class because it is a registry with one entry point per operation
## rather than a preference with a setter. The four const dictionaries are the
## bulk of it, and `SaSettings` aliases each one, which keeps
## `SaSettings.DEFAULT_ORDERS` working for the four suites that read it.
##
## Handed the file and the values it works on rather than the autoload that
## built it, so it never reaches back into an untyped `Node`. A write goes into
## the dictionaries here, then into the file's [member SaSettingsFile.config]
## and its save, and out on this class's own [signal profile_changed], which the
## autoload relays. The file announces a read and a reset, and this reads or
## empties its three sections on them.
##
## `@tool` because the autoload that builds it is.
@tool
class_name SaSettingsLayout
extends RefCounted

## An order, a visibility or a per-docker option moved, so a surface built from
## the layout rebuilds. Relayed by the autoload as its own `profile_changed`.
signal profile_changed

## The three sections of the profile this registry keeps.
const SECTIONS: Array[String] = ["profile_order", "profile_visibility", "profile_docker_option"]

## Elements a fresh profile hides. A profile that chose to hide a menu keeps
## that choice. The five under ColorPicker leave the preview and the selector
## alone in a fresh colour docker: a fresh profile reads these rather than
## `layouts/default.cfg`, which says the same five.
##
## No tool's option is here. Thirteen of them once were, from the stabilizer's
## two and Hardness to the eyedropper's and the selection tools' rows and Flow,
## every one a module's judgement written in the skeleton, and a third-party
## tool had no way to make the same one. A tool says it on its own spec now,
## `SaOptionSpec.bar_hidden`, and the bar hands it on in
## `register_layout_element`.
##
## On the bar, Mirror V and Environment View: one mirror is enough on a fresh
## bar, and the switch between a flat and an environment view is a thing a
## painter goes looking for. A painter who turns either on keeps it, since a stored visibility wins.
const DEFAULT_HIDDEN := {
    "TopMenuBar": ["Environment View", "Mirror V"],
    "ColorPicker": ["Paint Exposure", "Swatches", "Recent Colours", "Hex Input", "RGB Sliders", "OK-HSV Sliders"],
}

## What a fresh profile hides on one platform only, platform -> category ->
## [element], read on top of `DEFAULT_HIDDEN`. On Android the canvas is turned
## with two fingers, so the bar's Rotation and its reset cost room a tablet
## does not have. The desktop keeps both.
const PLATFORM_HIDDEN := {
    "Android": {"TopMenuBar": ["Rotation", "Reset Rotation"]},
}

## The entry in the top bar's order that everything after sits on the second
## row. One string in the array rather than a second list, because the drag
## list already moves things past it. Right after the last menu by default, so
## a fresh bar's first row is the menus and the window buttons and every tool
## option is on the second, which a fresh profile shows.
const ROW_SENTINEL := "Second Row"

const DEFAULT_ORDERS := {
    "TopMenuBar":
    [
        "File",
        "Edit",
        "View",
        "Window",
        # The Dockers menu is gone, its rows moved into Window. No entry for it
        # here: a default order naming a button nobody builds is a Preferences
        # row for a control that does not exist. A profile that already has the
        # name is migrated by version 14.
        "Image",
        "Layer",
        "Select",
        # Additive, so no SETTINGS_VERSION bump: a profile written before this
        # has no entry for the name, and `get_layout_order` seats a menu a
        # stored order lacks among the menus, after the nearest menu before it
        # here that the profile has.
        "Tools",
        # The Settings menu stood here until its rows moved into Help. No
        # entry for it, for the reason the Dockers menu's line above gives, and
        # a profile that has the name is migrated by version 20.
        "Filter",
        "Modules",
        "Help",
        # The head of the tool options, where the second row starts, so
        # everything but the menus and the window's buttons is on it. A stored
        # order keeps its sentinel where it is, since `get_layout_order` hands
        # a stored array back as it was written, and the shipped layouts carry
        # this place in their own orders.
        ROW_SENTINEL,
        # New in the preset work, and deliberately without a SETTINGS_VERSION
        # bump: nothing was renamed, so a profile written before this simply has
        # no entry for it. `get_layout_order` appends what a stored order lacks,
        # so such a profile has the preset group at the end of the list rather
        # than here, where it can be reordered and hidden like any other.
        "Brush Presets",
        # A tool's own controls once sat here and after the sentinel,
        # seventeen option keys from the blend mode to the wand's tolerance. A
        # tool names the element its control follows on its own spec,
        # `SaOptionSpec.bar_after`, so the stamp brush's row still opens after
        # Brush Presets and the eyedropper's after the stabiliser toggle
        # without the skeleton spelling a module's key.
        "Keep Blend Mode",
        # The canvas rotation, then the symmetry three and the stabiliser
        # toggle, after the brush's own controls on the second row, and on the
        # first row's middle with the second row off. The stabiliser's two rows
        # open after Reset Rotation and the eyedropper's and the selection
        # tools' after the toggle, by their own `bar_after`. Rotation follows no
        # tool, so the end of the row is where a painter who turns the canvas
        # can put it and leave it.
        #
        # Added without a SETTINGS_VERSION bump, for the reason "Brush Presets"
        # above carries: nothing was renamed, and a profile written before this
        # simply has no entry for either, so `get_layout_order` appends both.
        # The Flat or Environment switch opens the view's group, here and not
        # anchored on Reset Rotation, where the stabiliser's rows anchor too.
        "Environment View",
        # The document's Double Resolution switch, in the view's group beside
        # the other switch that belongs to the document. Page Edges is not in
        # this list but anchored after Environment View through
        # `register_layout_element`'s *after*, which places it in a stored
        # order too, so the three stand in that order. Added without a
        # SETTINGS_VERSION bump, for the reason "Brush Presets" above carries.
        "Double Resolution",
        "Rotation",
        "Reset Rotation",
        "Mirror H",
        "Mirror V",
        "Radial",
        # The stabiliser's quick toggle, beside the symmetry three because it
        # is the same kind of switch. Added without a SETTINGS_VERSION bump,
        # for the reason "Brush Presets" above carries.
        "Stabilizer Toggle",
        # Undo and Redo, at the row's right end where a right hand holding a
        # pen reaches, since a tablet with no keyboard had undo two menus away.
        # Added without a SETTINGS_VERSION bump, as "Brush Presets" above was.
        "Undo",
        "Redo",
    ],
    # The shape first and the dropdown that names it under it, then the pair,
    # the swatches, the recent colours and the hex box. Godot's own picker was
    # once last here, because it was taller than the docker's default size
    # leaves for it and whatever followed it was drawn past the bottom edge.
    # "HSV Wheel" keeps its stored name though it is seven shapes now: a
    # stored profile carries the string. The row reads "Picker Shape",
    # from `ELEMENT_TITLES` below.
    "ColorPicker":
    [
        "Drag Handle",
        "Resizer",
        "HSV Wheel",
        # The paint exposure in stops, under the shape, and hidden on a fresh
        # profile as the bar's Exposure is, leaving the preview and the selector
        # alone. Version 21 seats it here in a stored order.
        "Paint Exposure",
        # No "Picker Type" here: the dropdown is a per-docker option on the
        # Colour Picker page and not a part of the docker. An element row answers
        # whether a part of the docker is drawn. Version 13 of the profile takes
        # it out of a stored order, or the row would offer a switch that moves
        # nothing.
        "Selected Colour Preview",
        "Swatches",
        "Recent Colours",
        "Hex Input",
        # The numeric sliders, last because they are the row a painter reaches
        # for when the shape is not precise enough rather than the one they live
        # in, and because three stacked sliders are the tallest thing in the
        # docker.
        "RGB Sliders",
        "OK-HSV Sliders",
    ],
    "LayersDocker": ["Drag Handle", "Resizer", "Blend Mode", "Opacity", "Layer List", "Actions"],
    "ToolBoxDocker":
    [
        "Drag Handle",
        "Resizer",
        "Brush Tool",
        "Bucket Fill Tool",
        "Gradient Tool",
        "Eraser Tool",
        "Eyedropper Tool",
        "Pan Tool",
        "Zoom Tool",
        "Marquee Tool",
        # The ellipse beside the rectangle, additive and without a
        # SETTINGS_VERSION bump for the reason the magic wand's row gives.
        "Ellipse Select Tool",
        "Lasso Tool",
        # The polygon beside the freehand outline, additive and without a
        # SETTINGS_VERSION bump for the reason the magic wand's row gives.
        "Polygonal Lasso Tool",
        # The magnetic beside the polygon, additive and without a
        # SETTINGS_VERSION bump for the reason the magic wand's row gives.
        "Magnetic Lasso Tool",
        "Magic Wand Tool",
        # The magic wand, in the selection group's own order rather than
        # appended: additive and without a SETTINGS_VERSION bump, the same way
        # the transform's row below carries, because `get_layout_order`
        # appends a row a stored order predates.
        "Patch Tool",
        "Crop Tool",
        # The crop tool. Additive, and without a SETTINGS_VERSION bump: a
        # stored order that predates it gets the row appended by
        # `get_layout_order`, which is the same reason "Brush Presets"
        # carries above.
        "Transform Tool",
        # The assistants last, where a profile without the row has always drawn
        # it, so naming it moves nothing. Additive, for the crop's reason.
        "Assistants Tool",
        # No Liquify Tool, an engine of the Brush that version 22 takes out.
    ],
    # One row per section of the panel, rather than the single "Telemetry Stats"
    # that switched all of them off together. The strings are
    # `InfoDocker.SECTIONS`' titles, and version 9 renames a stored profile onto
    # them. The order here is the order the sections are drawn in, so moving a
    # row in Preferences moves the section in the docker, among the four above
    # the Performance fold or the four inside it. The document leads and the
    # engine's four follow, and a stored order keeps its own, which the fold
    # puts on the same side of the line either way.
    "InfoDocker":
    [
        "Drag Handle",
        "Resizer",
        "Document",
        "Colour space",
        "Active layer",
        "Selected colours",
        "Build",
        "Input",
        "History",
        "GPU",
        # Not a section: the last three pop-up messages and a Copy button, drawn
        # at the foot whatever its place in the list, so a painter can hide it.
        "Messages",
    ],
    # Every row of the Minimap an element, so a painter can keep the map
    # alone. All four are shown on a fresh profile and a stored order that
    # predates them gets them appended, so nothing moves for one who never
    # opens the page.
    "MinimapDocker": ["Drag Handle", "Resizer", "Flip Buttons", "Proof", "Proof Gamut", "Map"],
}

## The three kinds a per-docker option can be.
##
## `choice` is one of a named set and **stores its key rather than its index**,
## which is the trap `color_picker_shape` already avoids: a value added to the
## middle of the list later would renumber every value after it and quietly
## change what a stored profile means. `count` is a whole number between a floor
## and a ceiling. `switch` is on or off, which the maximise button is the first
## of: a docker-specific yes or no that is not a row in the element list.
const OPTION_CHOICE := &"choice"
const OPTION_COUNT := &"count"
const OPTION_SWITCH := &"switch"

## Display name for each reorderable category.
##
## The single place a category is declared, rather than a list of page titles
## in Preferences and a second dictionary mapping them back, which would make a
## docker an addition in three places. Adding a key here and to DEFAULT_ORDERS
## is the whole of it, and `test_settings_categories` fails if the two disagree.
const CATEGORY_TITLES := {
    "TopMenuBar": "Top Bar",
    "ColorPicker": "Colour Picker",
    "LayersDocker": "Layers",
    "ToolBoxDocker": "Toolbox",
    "InfoDocker": "Info",
    "MinimapDocker": "Minimap",
}

## The row label of a built-in element whose stored name says something the
## screen should not. The stored name stays, being what a profile and the
## shipped layouts carry, so a new label costs no migration. "HSV Wheel" is
## seven shapes in four models, and the sliders are OKHSV, spelled the way the
## Type list spells it. The stabiliser's quick toggle reads Stabilizer, as the
## bar does, because "Toggle" names the widget rather than what it does.
const ELEMENT_TITLES := {
    "ColorPicker": {"HSV Wheel": "Picker Shape", "OK-HSV Sliders": "OKHSV Sliders"},
    "TopMenuBar": {"Stabilizer Toggle": "Stabilizer"},
}

## The profile on disk, for the three sections and the save.
var _file: SaSettingsFile

## The preferences, for an option a spec backs with a setting.
var _values: SaSettingsValues

## Stored order per category, and stored visibility per category and
## element. `SaSettings` hands both out under their old names, because
## `test_sa_settings` reaches into the second one directly.
var orders: Dictionary[String, Array] = {}
var visibilities: Dictionary[String, Dictionary] = {}

## Stored value per per-docker option, category -> {key: value}. Public for the
## same reason the two above are: the persistence half fills it from the config
## file and the reset half empties it.
var docker_option_values: Dictionary[String, Dictionary] = {}

## Categories contributed at runtime, a registered docker's Preferences page.
##
## Instance state, not static, even though it extends two consts. Every caller
## reaches it through the autoload, and a static member called that way is a
## STATIC_CALLED_ON_INSTANCE warning at every call site.
var _runtime_orders: Dictionary[String, Array] = {}
var _runtime_titles: Dictionary[String, String] = {}

## Elements contributed at runtime to a category that already exists, the way
## the tool options bar contributes a row per option key a tool declared:
## category -> [element]. Appended to the order after the defaults, so a
## module's control can be moved and hidden like a built-in's.
var _runtime_elements: Dictionary[String, Array] = {}
## What Preferences calls an element whose stored name is not readable on its
## own: category -> {element: title}. A generated key such as `radius` is a
## poor row label, and this is where the bar says "Size (Brush, Eraser)".
var _element_titles: Dictionary[String, Dictionary] = {}
## Elements contributed at runtime that a fresh profile hides, category ->
## {element: true}. What `DEFAULT_HIDDEN` says for the skeleton's own
## elements, said by the module that owns the element.
var _fresh_hidden: Dictionary[String, Dictionary] = {}
## The element a runtime element follows on a fresh bar, category ->
## {element: anchor}.
var _anchors: Dictionary[String, Dictionary] = {}
## What a runtime category was registered for, category -> a weak reference to
## it, when the registration named one. The category is taken back the next
## time the categories are read or registered after that holder is freed, so a
## `Main` a suite builds and frees takes its dockers' pages with it instead of
## leaving them in the autoload for every later suite to read.
var _runtime_holders: Dictionary[String, WeakRef] = {}
## The platform whose fresh profile this is, `OS.get_name()` unless the one
## who builds it names another, which is how a suite reads Android's defaults
## on a desktop. It picks the row of `PLATFORM_HIDDEN` that applies.
var _platform: String


## Gives `category_id` a reorderable Preferences page. The const categories and
## earlier registrations win: returns false when the id is already taken. With
## a *holder* the page lasts as long as that object does, and without one until
## it is taken back.
func register_layout_category(category_id: String, title: String, elements: Array, holder: Object = null) -> bool:
    _take_back_orphans()
    if category_id.is_empty() or elements.is_empty():
        return false
    if DEFAULT_ORDERS.has(category_id) or _runtime_orders.has(category_id):
        return false
    _runtime_orders[category_id] = elements.duplicate()
    _runtime_titles[category_id] = title
    if holder != null:
        _runtime_holders[category_id] = weakref(holder)
    _refile(category_id)
    return true


## Takes back every runtime category whose holder has been freed.
func _take_back_orphans() -> void:
    for category_id: String in _runtime_holders.keys():
        if _runtime_holders[category_id].get_ref() == null:
            unregister_layout_category(category_id)


## Files what the profile holds for *category* under it, when its id has an
## underscore.
##
## `_read` splits a stored `category_element` key at its first underscore,
## which is the right split only for an id without one. A module's docker may
## be `my_docker`, and its visibilities and options came back filed under `my`,
## so the docker lost them on every launch. The whole id is known once it
## registers, and a value already in memory is newer than the file's.
func _refile(category: String) -> void:
    if not category.contains("_"):
        return
    var config := _file.config
    var sections: Dictionary[String, Dictionary] = {
        "profile_visibility": visibilities, "profile_docker_option": docker_option_values
    }
    for section: String in sections:
        if not config.has_section(section):
            continue
        var into: Dictionary[String, Dictionary] = sections[section]
        for key: String in config.get_section_keys(section):
            if not key.begins_with(category + "_"):
                continue
            var element := key.substr(category.length() + 1)
            var filed := _under(into, category)
            if not filed.has(element):
                filed[element] = config.get_value(section, key)


## The autoload outlives a test run, so a test that registers must be able to
## take it back. A module being unloaded uses it for the same reason.
func unregister_layout_category(category_id: String) -> void:
    _runtime_orders.erase(category_id)
    _runtime_titles.erase(category_id)
    _runtime_holders.erase(category_id)


## Gives *element* a place in *category*'s list and a title in Preferences.
## An element the defaults already list only takes the title.
##
## *hidden* is whether a fresh profile hides it, and *after* is the element it
## follows in an order that does not name it yet. The first registration of an
## element decides both, the way the first tool to declare an option key
## builds its control.
func register_layout_element(category: String, element: String, title: String, hidden := false, after := "") -> void:
    if category.is_empty() or element.is_empty():
        return
    _under(_element_titles, category)[element] = title
    var shipped: Array = DEFAULT_ORDERS.get(category, [])
    if shipped.has(element):
        return
    if not _runtime_elements.has(category):
        _runtime_elements[category] = []
    if _runtime_elements[category].has(element):
        return
    _runtime_elements[category].append(element)
    if hidden:
        _under(_fresh_hidden, category)[element] = true
    if not after.is_empty():
        _under(_anchors, category)[element] = after


func unregister_layout_element(category: String, element: String) -> void:
    if _element_titles.has(category):
        _element_titles[category].erase(element)
    if _runtime_elements.has(category):
        _runtime_elements[category].erase(element)
    if _fresh_hidden.has(category):
        _fresh_hidden[category].erase(element)
    if _anchors.has(category):
        _anchors[category].erase(element)


## Every element of *category* a fresh profile hides: the skeleton's own from
## `DEFAULT_HIDDEN` and the ones a module registered hidden.
func fresh_hidden(category: String) -> Array:
    var out: Array = _shipped_hidden(category)
    for element: String in _fresh_hidden.get(category, {}):
        out.append(element)
    return out


## The skeleton's own elements of *category* a fresh profile hides on this
## platform: `DEFAULT_HIDDEN` and this platform's row of `PLATFORM_HIDDEN`.
func _shipped_hidden(category: String) -> Array:
    var shipped: Array = DEFAULT_HIDDEN.get(category, [])
    var out: Array = shipped.duplicate()
    var platform: Dictionary = PLATFORM_HIDDEN.get(_platform, {})
    var hidden_here: Array = platform.get(category, [])
    out.append_array(hidden_here)
    return out


## The row label Preferences shows for *element*: a registered title, else
## the stored name itself.
func element_title(category: String, element: String) -> String:
    var titles: Dictionary = _element_titles.get(category, {})
    var shipped: Dictionary = ELEMENT_TITLES.get(category, {})
    return titles.get(element, shipped.get(element, element))


## Every reorderable category, in declaration order, as (id, title) pairs.
func reorderable_categories() -> Array[Dictionary]:
    _take_back_orphans()
    var out: Array[Dictionary] = []
    for category_id: String in DEFAULT_ORDERS:
        out.append({"id": category_id, "title": CATEGORY_TITLES.get(category_id, category_id)})
    for category_id: String in _runtime_orders:
        out.append({"id": category_id, "title": _runtime_titles.get(category_id, category_id)})
    return out


## Always a copy. The two fallback branches already duplicated, but the stored
## branch handed back the live array, so a caller appending to what it got
## rewrote the saved order in memory with nothing written to disk to match. The
## divergence then lasts the whole session and the next save writes it out.
##
## No caller mutates the result today. The point is that one doing so should not
## be able to corrupt settings from the outside.
func get_layout_order(category: String) -> Array:
    if orders.has(category):
        var stored: Array = orders[category].duplicate()
        # A stored order that won outright over the defaults and merged nothing
        # in would never show an element added to DEFAULT_ORDERS after the
        # profile was written. Append what it
        # lacks, which puts a new control after the sentinel and a missing
        # sentinel at the end. A menu is the exception, `_seat_the_menus`.
        #
        # **In the order a fresh bar holds those elements, which is one
        # sequence**, rather than the defaults first and every registered
        # element after them, which would make the tail's order depend on which
        # side of the door an element came in by: a module's blend mode, erase,
        # Size and Opacity would land at the far end of the second row, where a
        # fresh bar has them first. What a profile already names keeps its
        # stored place either way, so only what it lacks moves.
        var fresh := _fresh_order(category)
        _seat_the_menus(category, stored, fresh)
        for element: Variant in fresh:
            if not stored.has(element):
                stored.append(element)
        return stored
    return _fresh_order(category)


## Puts every menu *stored* lacks, or holds after the sentinel, among the
## menus: after the nearest menu before it in *fresh* that *stored* has, and at
## the head when it has none. The menus are what the shipped order lists before
## the sentinel, and a category with no sentinel has none.
##
## A menu after the sentinel is one an older build's append put at the end of a
## painter's profile. The drag list
## cannot carry a menu past the sentinel, so no painter put it there. Walked in
## the fresh order, so a menu whose neighbour was itself moved goes after it.
func _seat_the_menus(category: String, stored: Array, fresh: Array) -> void:
    var sentinel_at := fresh.find(ROW_SENTINEL)
    if not DEFAULT_ORDERS.has(category) or sentinel_at < 0:
        return
    var menus: Array = fresh.slice(0, sentinel_at)
    for i: int in menus.size():
        var menu: Variant = menus[i]
        var held := stored.find(menu)
        var past := stored.find(ROW_SENTINEL)
        if held >= 0 and (past < 0 or held < past):
            continue
        if held >= 0:
            stored.remove_at(held)
        var at := 0
        for before: int in range(i - 1, -1, -1):
            var found := stored.find(menus[before])
            if found >= 0:
                at = found + 1
                break
        stored.insert(at, menu)


## The order a bar with no stored profile reads: the skeleton's defaults, every
## registered element after the element it anchors on, or the list a module
## registered for a category of its own with what was registered into it after.
##
## The yardstick for what a stored order lacks, because it is the order the
## painter sees on a first launch and after a reset. A module's category once
## read its list alone here, so an element registered into it showed only once
## an order was stored, and Reset to shipped would have taken it off the page.
func _fresh_order(category: String) -> Array:
    if not DEFAULT_ORDERS.has(category):
        var registered: Array = _runtime_orders.get(category, [])
        var runtime := registered.duplicate()
        _append_runtime_elements(category, runtime, false)
        return runtime
    var shipped: Array = DEFAULT_ORDERS[category]
    var fresh: Array = shipped.duplicate()
    _append_runtime_elements(category, fresh, true)
    return fresh


## Puts every runtime element *order* does not hold yet at its end, or, in a
## fresh order and when *anchored*, after the element it names as its
## anchor. At the end when it names none or the order lacks it.
##
## A stored order is never anchored. It is the painter's, and what it lacks goes
## after it, onto the second row, by the rule for an element the stored order
## predates. A first launch and a reset store no order, so a fresh bar reaches
## the anchored branch rather than a copy of the defaults.
##
## A pass per round rather than one walk, because an anchor can be another
## runtime element: the stamp brush's Size follows its erase toggle, which
## follows Keep Blend Mode. Two elements anchored on one element keep their
## registration order, each after the last one placed there.
func _append_runtime_elements(category: String, order: Array, anchored: bool) -> void:
    var pending: Array = []
    for element: Variant in _runtime_elements.get(category, []):
        if not order.has(element):
            pending.append(element)
    var anchors: Dictionary[String, Variant] = {}
    if anchored and _anchors.has(category):
        anchors = _anchors[category]
    var last_after: Dictionary[String, String] = {}
    var placed := true
    while placed and not pending.is_empty():
        placed = false
        for element: Variant in pending.duplicate():
            var anchor: String = anchors.get(element, "")
            if anchor.is_empty() or not order.has(anchor):
                continue
            var behind: String = last_after.get(anchor, anchor)
            order.insert(order.find(behind) + 1, element)
            last_after[anchor] = element
            pending.erase(element)
            placed = true
    order.append_array(pending)


func _init(file: SaSettingsFile, values: SaSettingsValues, platform := OS.get_name()) -> void:
    _platform = platform
    _file = file
    _values = values
    _file.read.connect(_read)
    _file.cleared.connect(_clear)


## The three sections, which are dictionaries rather than preferences and so are
## not in `SaSettingsKeys.KEYS`, read out of the profile the file just loaded.
func _read() -> void:
    var config := _file.config
    orders.clear()
    if config.has_section("profile_order"):
        for key in config.get_section_keys("profile_order"):
            # The profile is text a hand may have edited, and an order that is
            # not a list has nothing to order by, so only a list is kept.
            var stored: Variant = config.get_value("profile_order", key)
            if stored is Array:
                orders[key] = stored

    # The per-docker options, the same shape as the visibilities below: one
    # flat section keyed `category_option`.
    docker_option_values.clear()
    if config.has_section("profile_docker_option"):
        for key in config.get_section_keys("profile_docker_option"):
            var split := key.find("_")
            if split == -1:
                continue
            var owner := key.left(split)
            _under(docker_option_values, owner)[key.substr(split + 1)] = config.get_value("profile_docker_option", key)

    visibilities.clear()
    if config.has_section("profile_visibility"):
        for key in config.get_section_keys("profile_visibility"):
            var value: bool = config.get_value("profile_visibility", key)
            # key is category_element
            var idx := key.find("_")
            if idx != -1:
                var category := key.left(idx)
                var element := key.substr(idx + 1)
                _under(visibilities, category)[element] = value
    for category: String in _runtime_orders.keys() + _docker_options.keys():
        _refile(category)


## A first launch or a reset. What a docker was told to lay itself out as goes
## with the order, because the orientation and the line cap are as much of the
## layout as the order is.
func _clear() -> void:
    orders.clear()
    visibilities.clear()
    docker_option_values.clear()
    for section: String in SECTIONS:
        if _file.config.has_section(section):
            _file.config.erase_section(section)


## Writes one key of *section*, saves, and tells everything that reads the
## layout.
func _store(section: String, key: String, value: Variant) -> void:
    _store_all([[section, key, value]])


## Writes every `[section, key, value]` of *writes*, a null value erasing its
## key as `ConfigFile.set_value` does, then saves once and tells everything
## that reads the layout once. It is the one place the layout writes its file.
func _store_all(writes: Array) -> void:
    var config := _file.config
    for write: Array in writes:
        var section: String = write[0]
        var key: String = write[1]
        config.set_value(section, key, write[2])
    _file.save()
    profile_changed.emit()


func set_layout_order(category: String, order: Array) -> void:
    orders[category] = order
    _store("profile_order", category, order)


func get_element_visible(category: String, element: String) -> bool:
    if category == "TopMenuBar" and element == "Edit":
        return true
    if visibilities.has(category) and visibilities[category].has(element):
        return visibilities[category][element]
    if _shipped_hidden(category).has(element):
        return false
    var registered_hidden: Dictionary = _fresh_hidden.get(category, {})
    if registered_hidden.has(element):
        return false
    return true  # Default is visible


func set_element_visible(category: String, element: String, visible: bool) -> void:
    if category == "TopMenuBar" and element == "Edit":
        return  # Safety catch
    _under(visibilities, category)[element] = visible
    _store("profile_visibility", category + "_" + element, visible)


## Writes every order of *new_orders*, category to its order, and every
## `[category, element, visible]` of *shown*, as one save and one
## `profile_changed`, for a layout preset loaded whole.
##
## A preset names some ninety of them, and the one call a key at a time was
## ninety saves and ninety rounds of every docker laying itself out again, 2.5
## seconds in one frame of a press in Quick settings. The values written
## are the ones the calls a key at a time write, so the layout ends the same.
func set_many(new_orders: Dictionary, shown: Array) -> void:
    var writes: Array = []
    for category: String in new_orders:
        orders[category] = new_orders[category]
        writes.append(["profile_order", category, new_orders[category]])
    for entry: Array in shown:
        var category: String = entry[0]
        var element: String = entry[1]
        if category == "TopMenuBar" and element == "Edit":
            continue
        var visible: bool = true if entry[2] else false
        _under(visibilities, category)[element] = visible
        writes.append(["profile_visibility", category + "_" + element, visible])
    if not writes.is_empty():
        _store_all(writes)


## Whether *category* has an arrangement to go back to, the skeleton's own or
## one a module registered. A composed docker has neither.
func ships(category: String) -> bool:
    return DEFAULT_ORDERS.has(category) or _runtime_orders.has(category)


## Puts *category*'s order and hidden elements back as a fresh profile has them,
## and leaves every other category and every per-docker option alone. Forgetting
## what is stored is the whole of it, since a category with nothing stored reads
## its fresh order and its fresh hidden elements, so an element shipped later
## still finds its place. The keys erased are the ones filed under the whole id,
## which `_refile` makes right for an id with an underscore. A null value
## erases its key, so the reset is one save and one `profile_changed`.
func reset_category(category: String) -> void:
    var writes: Array = [["profile_order", category, null]]
    var switched: Dictionary = visibilities.get(category, {})
    for element: String in switched:
        writes.append(["profile_visibility", category + "_" + element, null])
    orders.erase(category)
    visibilities.erase(category)
    _store_all(writes)


# --- Per-docker options --------------------------------------------------
#
# A setting that belongs to one docker's Preferences page and is **not** a row
# in its element list. An element row answers whether a part of the docker is
# drawn and where in the order it sits, and these answer how the docker lays
# itself out, which is a different question and cannot be asked with a switch.
#
# Registered rather than declared in a const above, for the reason
# `register_layout_category` is registered: the toolbox is a built-in and gives
# itself its two exactly the way a module's docker would, which is rule 6.


## Gives *category* a per-docker option under *key*, and answers whether it took.
##
## *spec* carries `title` and `hint` for the row, `kind`, `default`, and then
## per kind: `values` and `labels` for `OPTION_CHOICE`, `min` and `max` for
## `OPTION_COUNT`. A key already registered is refused rather than replaced, so
## a docker rebuilt twice does not draw its rows twice.
func register_docker_option(category: String, key: String, spec: Dictionary) -> bool:
    if category.is_empty() or key.is_empty() or spec.is_empty():
        return false
    if not _docker_options.has(category):
        _under(_docker_options, category)
        _docker_option_keys[category] = []
        _refile(category)
    if _docker_options[category].has(key):
        return false
    # The spec is what a module built and arrives untyped, so it is typed here,
    # where it enters.
    var stored := SaTyped.strings(spec.duplicate(true))
    stored["key"] = key
    _docker_options[category][key] = stored
    _docker_option_keys[category].append(key)
    return true


## Takes one back, for a test or an unloading module.
func unregister_docker_option(category: String, key: String) -> void:
    if _docker_options.has(category):
        _docker_options[category].erase(key)
    if _docker_option_keys.has(category):
        _docker_option_keys[category].erase(key)


## Every option *category* registered, in registration order, each spec carrying
## its own `key`. Always copies, so a page cannot edit the registry by holding a
## row it was handed.
func docker_options(category: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for key: String in _docker_option_keys.get(category, []):
        var option: Dictionary = _docker_options[category][key]
        out.append(option.duplicate(true))
    return out


## What *key* is set to, or its declared default, or null when nothing declared
## it. Null rather than a guess, because a caller asking for an option nobody
## registered has a spelling mistake and a zero would hide it.
##
## **A spec carrying `setting` reads that `SaSettings` property instead**. The
## picker's shape is the case: `color_picker_shape` was already the setting
## behind the docker's own dropdown, four committed scenarios write it through
## `{"prefs": {...}}`, and a second copy of the answer in
## `profile_docker_option` would be a second authority on which shape the picker
## is. The row moves to Preferences and the setting stays where it was.
func get_docker_option(category: String, key: String) -> Variant:
    var spec := _spec(category, key)
    var setting := str(spec.get("setting", ""))
    if not setting.is_empty():
        return _values.get(setting)
    if docker_option_values.has(category) and docker_option_values[category].has(key):
        return docker_option_values[category][key]
    return spec.get("default", null)


## The spec *key* was registered with under *category*, and an empty one when
## nothing registered it.
func _spec(category: String, key: String) -> Dictionary[String, Variant]:
    if _docker_options.has(category) and _docker_options[category].has(key):
        return _docker_options[category][key]
    return {}


## The map *table* keeps under *category*, filed empty on its first use. Typed by
## its key and not by its value, because the tables it serves keep titles, flags,
## anchors, option values and specs.
static func _under(table: Dictionary[String, Dictionary], category: String) -> Dictionary[String, Variant]:
    if not table.has(category):
        var fresh: Dictionary[String, Variant] = {}
        table[category] = fresh
    return table[category]


## Writes *value*, saves, and tells everything that reads the profile.
##
## `profile_changed` rather than a signal of its own, because a docker already
## rebuilds its layout on that signal and a second one would be a second thing
## to remember to connect.
func set_docker_option(category: String, key: String, value: Variant) -> void:
    # A setting-backed option writes the setting, whose own setter saves the
    # profile and emits `profile_changed`, so the two paths end the same way and
    # nothing has to know which kind of option it was handed.
    var setting := str(_spec(category, key).get("setting", ""))
    if not setting.is_empty():
        _values.set(setting, value)
        return
    _under(docker_option_values, category)[key] = value
    _store("profile_docker_option", category + "_" + key, value)


## Option specs per category, and the order each was registered in. Two
## dictionaries rather than one, because a `Dictionary` keeps insertion order in
## Godot and a caller relying on that is relying on an implementation detail.
var _docker_options: Dictionary[String, Dictionary] = {}
var _docker_option_keys: Dictionary[String, Array] = {}
