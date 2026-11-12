## Which list the Layers docker's one popup draws, the More button's or the
## whole Layer menu the right click opens at the pointer, and the rows
## only the second holds.
##
## **At the pointer the whole Layer menu**, Delete Layer, Duplicate Layer,
## Merge Down and the rest in the menu bar's order, because nothing stands
## beside a menu at the pointer to do what the docker's buttons do. A painter
## from Photoshop looked there for Duplicate Layer, Delete Layer and Merge
## Down and found them on buttons a right click never shows. The More button
## keeps its list, which leaves out what plus, the arrow, minus and the
## standing operation buttons do.
##
## **The rows the More list never held are run here**: New Layer, a kind and a
## ground through `SaLayerOps` and `SaLayerMenuRows.run`, as plus and the
## arrow's rows run them, and the rest through their command, as the Layer
## menu runs it. Delete Layer is the docker's minus, so the docker runs it.
class_name SaLayerPointerMenu
extends RefCounted

## Whether the popup was last opened at the pointer, until it closes.
var at_pointer: bool = false


## Opens *menu* at *at* under *anchor*, a point in the space `SaPopupRect`
## measures in, built by *build* first, since the list is sized by the rows it
## holds.
func open_at(menu: SaChoicePopup, anchor: Control, at: Vector2, build: Callable) -> void:
    at_pointer = true
    build.call()
    menu.open_under(anchor, at)


## The list is the More button's again, once the popup has closed.
func forget() -> void:
    at_pointer = false


## The rows to draw for *document*: every row of the Layer menu at the pointer,
## and otherwise the More list, less the operation buttons standing on
## *buttons*. *kinds* are the kinds a row adds.
func rows(document: SaDocument, buttons: SaLayerOpButtons, kinds: SaLayerTypeRegistry) -> Array:
    var list := SaLayerMenuRows.new(document, buttons.commands, kinds)
    if at_pointer:
        return list.rows(false, [], true)
    var standing: Array[StringName] = []
    for entry: Array in SaLayerOpButtons.ENTRIES:
        if buttons.on_row(entry[0]) != null:
            standing.append(entry[0])
    return list.rows(true, standing, true)


## Runs the row *id* of *document*, one the More list never held: New Layer and
## a kind added with *kinds*, the filter browser under *host*'s scene, and a
## command row through *commands*.
func press(id: StringName, document: SaDocument, kinds: SaLayerTypeRegistry, commands: SaCommandRegistry, host: Node) -> void:
    if document == null:
        return
    if id == &"layer_new_paint":
        SaLayerOps.new(document).add(SaLayerTypeDescriptor.PLAIN if kinds != null else &"", kinds)
    elif commands != null and commands.has(id):
        commands.execute(id)
    else:
        _run(id, document, kinds, host)


## Opens the Ground row's list, or Duplicate To's list of the other open
## documents, beside *menu*'s row when *id* is one of them, and answers whether
## it was.
func branch(id: StringName, menu: SaChoicePopup, document: SaDocument, kinds: SaLayerTypeRegistry) -> bool:
    var list := SaLayerMenuRows.new(document, null, kinds)
    if id == SaLayerMenuRows.DUPLICATE_TO:
        list.open_duplicate_to(menu, id)
        return true
    if id != SaLayerMenuRows.GROUND:
        return false
    list.open_grounds(menu, _run.bind(document, kinds, menu), SaLayerMenuRows.GROUND)
    return true


## A kind or a ground added as the arrow's row adds it.
func _run(id: StringName, document: SaDocument, kinds: SaLayerTypeRegistry, host: Node) -> void:
    var scene: Node = host.get_tree().current_scene if host.is_inside_tree() else host
    SaLayerMenuRows.new(document, null, kinds).run(id, scene)
