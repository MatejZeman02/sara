## The open documents: every surface a painter can work on, in order, and the
## one in front.
##
## One answer to "which document is the painter working on", and a signal when
## that answer changes, which several documents open at once need first.
## Only surfaces that hold a document are held here. The Info docker's
## scratchpad is a swatch, so `SaContext.list_surfaces()` still lists it and
## this list does not.
##
## Both members are written by this class alone and read from outside.
class_name SaDocuments
extends RefCounted

## The open surfaces, in the order their tabs will stand in.
var surfaces: Array[SaSurface] = []

## The surface the painter is working on, or null while none is open.
var front: SaSurface = null

## What Cut and Copy hold, `core/api/selection/sa_clipboard.gd`, one for every
## open document, so a Copy in one painting pastes into another. Held here
## rather than as a static, because the owner is let go of while the rendering
## device is still alive and a static holding textures would be freed at
## shutdown against a device already gone. A copy is chunks of its own, so it
## outlives the document it came from being closed.
var clipboard := SaClipboard.new()


## Holds a surface. The first one held comes to the front, and the bus hears it.
## Answers false for a null surface or one already held.
func add(surface: SaSurface) -> bool:
    if surface == null or surfaces.has(surface):
        return false
    surfaces.append(surface)
    if front == null:
        _make_front(surface)
    return true


## Lets a surface go. When it was in front, its neighbour comes forward, the
## one after it or else the one before, and the bus hears that too.
func remove(surface: SaSurface) -> bool:
    var at := surfaces.find(surface)
    if at < 0:
        return false
    if surface != front:
        surfaces.remove_at(at)
        return true
    _close_session_of(surface)
    surfaces.remove_at(at)
    _make_front(surfaces[mini(at, surfaces.size() - 1)] if not surfaces.is_empty() else null)
    return true


## Brings a held surface to the front. The outgoing surface's tool session
## closes first, so a transform box open on it is committed to its own
## document before anything reads the new front one. Answers false, and sends
## nothing, for a surface not held or already in front.
func bring_to_front(surface: SaSurface) -> bool:
    if surface == null or surface == front or not surfaces.has(surface):
        return false
    _close_session_of(front)
    _make_front(surface)
    return true


## The front surface's easel, or null. What `SaContext.get_easel()` answers.
func front_easel() -> SaEasel:
    return front.easel if front != null else null


## The surface holding *document*, or null for a document no open surface
## holds. What a flow about one named document asks when it needs the view or
## the tools over it: the quit's Save All saves a document that is not in
## front, and the session a tool holds over it is on its own surface.
func surface_of(document: SaDocument) -> SaSurface:
    for surface in surfaces:
        if surface.get_document() == document:
            return surface
    return null


## What a dump says of the open documents: how many, their ids in order, and
## which is in front.
func state() -> Dictionary:
    return {
        "count": surfaces.size(),
        "ids": surfaces.map(func(surface: SaSurface) -> String: return String(surface.id)),
        "front": String(front.id) if front != null else "",
    }


## The block of [method state] for the host that holds the documents, main in
## the app, and empty for a host that holds none.
static func state_in(host: Node) -> Dictionary:
    var held: Object = host.get("documents") if host != null else null
    return (held as SaDocuments).state() if held is SaDocuments else {}


## The front surface of the owner *host* holds, null for a host that holds
## none. Beside [method state_in] and read by name for the same reason: a
## lookup for "the document the painter is working on" that holds no context
## reaches the one owner through the node that keeps it, so `core/api` names
## no scene of the interface's and one file knows where the owner sits.
static func front_in(host: Node) -> SaSurface:
    var held: Object = host.get("documents") if host != null else null
    return (held as SaDocuments).front if held is SaDocuments else null


## The clipboard of the owner *host* holds, null for a host that holds none.
## Read by name for the reason [method front_in] gives.
static func clipboard_in(host: Node) -> SaClipboard:
    var held: Object = host.get("documents") if host != null else null
    return (held as SaDocuments).clipboard if held is SaDocuments else null


## The tool machine is untyped on the surface, because `tools/` sits above
## `core/api`, so it is reached by duck typing the way the surface documents.
func _close_session_of(surface: SaSurface) -> void:
    if surface == null or surface.tool_machine == null:
        return
    var machine: Object = surface.tool_machine
    if machine.has_method("close_session"):
        machine.call("close_session")


func _make_front(surface: SaSurface) -> void:
    front = surface
    EventBus.active_document_changed.emit(surface)
