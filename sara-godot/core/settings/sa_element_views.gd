## Which layout elements can be placed in a docker other than their own, and
## how a second view of one is built.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## What can be placed is exactly the registered layout elements, and a module
## adds one through the same door. A name, a title and a switch on a Preferences
## page say nothing of how to build an element's control a second time, so the door,
## `SaSettings.register_layout_element`, takes a callable that builds a fresh
## control showing and driving that element's state, and it is kept here. An
## element is placeable when it has one. A view is built fresh rather than
## borrowed because a placed element is a second view of the same state as
## at home, so the home control stays where it is and the callable makes
## another that reads and writes what it does.
##
## Its own class rather than a fifth table in `SaSettingsLayout`, because that
## registry answers where an element sits and whether it is drawn, and this
## answers whether it can be drawn somewhere else and how. It reads the layout
## for the categories, the order and the titles, and the layout knows nothing of
## it.
##
## `@tool` because the autoload that holds it is.
@tool
class_name SaElementViews
extends RefCounted

## An element gained a view after something may already have asked for it: a
## module loaded late, or a docker built after the Preferences page that lists
## what can be placed. A composed docker that holds the element with no view to
## build yet builds it on this.
signal view_registered(category: String, element: String)

## The elements that are where things go rather than things: a docker's drag
## bar and its grip, and the top bar's Second Row, the sentinel that says
## which row of the bar a control sits on. A composed docker carries its own
## bar and grip, so none of them is ever placed, whatever was registered for it.
const PLACES: Array[String] = ["Drag Handle", "Resizer", SaSettingsLayout.ROW_SENTINEL]

## The registry the categories, their order and the titles are read from.
var _layout: SaSettingsLayout

## The callable that builds a view, category -> {element: Callable}. Each inner
## map is typed, as `_views_of` files it.
var _builders: Dictionary[String, Dictionary] = {}


func _init(layout: SaSettingsLayout) -> void:
    _layout = layout


## Keeps *builder* as the way to build a view of *element* in *category*, and
## answers whether it took. An invalid callable or a place is refused. A second
## registration replaces the first, because a docker built twice registers
## twice, and only an element's first view is announced.
func register(category: String, element: String, builder: Callable) -> bool:
    if category.is_empty() or element.is_empty() or not builder.is_valid():
        return false
    if PLACES.has(element):
        return false
    var views := _views_of(category)
    var first := not views.has(element)
    views[element] = builder
    _builders[category] = views
    if first:
        view_registered.emit(category, element)
    return true


## Takes *element*'s view back, for a test or an unloading module, with the
## element itself.
func unregister(category: String, element: String) -> void:
    if _builders.has(category):
        _builders[category].erase(element)


## Whether *element* of *category* can be placed: it has a view, and it is not
## one of the [constant PLACES].
func placeable(category: String, element: String) -> bool:
    if PLACES.has(element):
        return false
    var views := _views_of(category)
    if not views.has(element):
        return false
    var builder: Callable = views[element]
    return builder.is_valid()


## The views *category* holds, as the typed map filed under it, or a fresh empty
## one that only [method register] files.
func _views_of(category: String) -> Dictionary[String, Callable]:
    if _builders.has(category):
        return _builders[category]
    var fresh: Dictionary[String, Callable] = {}
    return fresh


## Every placeable element, by category, as `{id, title, elements}` with each
## element `{id, title}`. The categories run in the order Preferences lists
## them and the elements in their category's order, so a list built from this
## reads as the Elements… pages do. A category with nothing placeable is left
## out, and one that has views but no page of its own comes last, under its id.
func placeable_elements() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var seen: Dictionary[String, bool] = {}
    for category: Dictionary in _layout.reorderable_categories():
        var id: String = category["id"]
        var title: String = category["title"]
        seen[id] = true
        _append_category(out, id, title)
    for id: String in _builders:
        if not seen.has(id):
            _append_category(out, id, id)
    return out


## Appends *category*'s placeable elements to *out* under *title*, when it has
## any. The category's order first, then a viewed element that order does not
## list, in the order its view was registered.
func _append_category(out: Array[Dictionary], category: String, title: String) -> void:
    var elements: Array[Dictionary] = []
    var order := _layout.get_layout_order(category)
    for element: String in _views_of(category):
        if not order.has(element):
            order.append(element)
    for element: String in order:
        if placeable(category, element):
            elements.append({"id": element, "title": _layout.element_title(category, element)})
    if not elements.is_empty():
        out.append({"id": category, "title": title, "elements": elements})


## A fresh view of *element*, or null when it is not placeable or its callable
## built something that is not a control. Every call builds another, so two
## dockers holding one element hold two controls over the same state.
func build(category: String, element: String) -> Control:
    if not placeable(category, element):
        return null
    var builder: Callable = _views_of(category)[element]
    var built: Variant = builder.call()
    if built is Control:
        return built
    if built is Node:
        var stray: Node = built
        stray.free()
    push_warning("SaElementViews: the view of '%s' in '%s' did not build a Control." % [element, category])
    return null
