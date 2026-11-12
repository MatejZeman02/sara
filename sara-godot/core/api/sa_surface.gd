## One paintable thing: a document, the view showing it, and its tool instances.
##
## There are two surfaces today - the main canvas and the info docker's
## scratchpad - which is why "the canvas" was never a safe singular. A tool is
## instantiated once per surface so each keeps its own stroke state, while a
## module describes the tool only once.
class_name SaSurface
extends RefCounted

var id: StringName = &"main"

## Owns the document, compositor and output texture. No UI dependency.
var easel: SaEasel = null

var view: SaView = null

## Embedded surfaces (the scratchpad) offer only tools whose descriptor sets
## available_in_embedded.
var is_embedded: bool = false

## The ToolMachine driving this surface, set by `ToolMachine.bind()` once it
## exists. Untyped on purpose: `tools/` sits above `core/api`, so this file
## never names `ToolMachine` outright, and a module reads it by duck typing
## the way `SaContext.list_surfaces()` hands surfaces out untyped, so the
## active tool is reachable from outside the UI tree.
var tool_machine: Variant = null

## Published for the cursor overlay: ring radius in screen pixels, or negative
## when this surface wants the OS cursor instead.
var cursor_ring_radius: float = -1.0

## Published beside it: the shape the ring is drawn as, in units of that radius,
## or empty for the circle every tool but an image-tipped brush wants.
var cursor_outline: PackedVector2Array = PackedVector2Array()


static func create(surface_id: StringName, surface_easel: SaEasel, surface_view: SaView) -> SaSurface:
    var surface := SaSurface.new()
    surface.id = surface_id
    surface.easel = surface_easel
    surface.view = surface_view
    return surface


func get_document() -> SaDocument:
    return easel.document if easel != null else null


## The document *on* shows, or null when there is no surface: the one guard
## every reader that may hold no surface shares, a tool's through
## [method ToolState.document].
static func document_of(on: SaSurface) -> SaDocument:
    return on.get_document() if on != null else null


func get_canvas_size() -> Vector2i:
    var document := get_document()
    return document.canvas_size if document != null else Vector2i.ZERO


func is_ready() -> bool:
    return easel != null and easel.document != null and view != null
