## Points every docker that holds a `target_canvas` at the document in front,
## at start and again each time `EventBus.active_document_changed` brings
## another one forward, and has `SaColors` follow that document's mask target.
##
## The Info, minimap, graph and layers dockers were each handed the main
## canvas once at boot, which names one canvas only while one document is open.
## Each takes the new one through its own member, as the layers docker's
## keeper already did, so the docker needs no signal of its own. The Info
## docker reads the canvas beside its tool machine, so it takes the front
## surface's machine with it.
##
## A `Node`, for the reason `MainDockers` is one: its handler is connected to
## the bus, and a freed node's connection goes with it.
class_name MainFrontDocument
extends Node

## The dockers pointed at the front canvas, held weakly so a docker a suite has
## freed is passed over rather than kept alive.
var _dockers: Array[WeakRef] = []

## The canvas the dockers were last pointed at, so the bus repeating the one
## already shown rebuilds no layer rows.
var _shown: SaCanvas = null


func _init(dockers: Array) -> void:
    name = "FrontDocument"
    for docker: Object in dockers:
        if docker != null:
            _dockers.append(weakref(docker))


func _enter_tree() -> void:
    if not EventBus.active_document_changed.is_connected(point_at):
        EventBus.active_document_changed.connect(point_at)


func _exit_tree() -> void:
    if EventBus.active_document_changed.is_connected(point_at):
        EventBus.active_document_changed.disconnect(point_at)


## Hands *surface*'s canvas to every docker, null when no document is open.
func point_at(surface: SaSurface) -> void:
    show_canvas(SaCanvasView.canvas_of(surface))


## Hands *canvas* to every docker. Main calls it once at boot with the main
## canvas, whose surface is built only when the tools are bound, after the
## dockers are wired.
func show_canvas(canvas: SaCanvas) -> void:
    if canvas == _shown and canvas != null:
        return
    _shown = canvas
    for held: WeakRef in _dockers:
        var docker: Object = held.get_ref()
        if docker == null:
            continue
        docker.set(&"target_canvas", canvas)
        if &"target_tool_machine" in docker:
            docker.set(&"target_tool_machine", canvas.tool_machine() if canvas != null else null)
    # The main canvas has no document yet at boot, and the shortcut router
    # has `SaColors` follow its first one as it binds.
    if canvas == null or canvas.document != null:
        SaColors.follow(canvas.document if canvas != null else null)
