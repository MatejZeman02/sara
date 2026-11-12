## Select > Transform Selection: the transform tool's box round the selection,
## moving, turning and scaling the marching ants alone while the pixels stay
## where they are.
##
## What it is for is a selection no selection tool can draw: a rectangle
## selected, put through this and turned by 45 degrees is a rotated square.
##
## **A pass that lifts nothing.** It stands in the tool's slot where
## [SaTransform] stands for a lift, so every handle, the six Tool Options rows,
## the modes and the flips drive it through the same map arithmetic, which it
## inherits rather than copies. What it leaves out is everything a lift does to
## pixels: no hole is cut, no preview is drawn into the stroke layer and the
## layer is never written. The overlay draws the outline through the map the
## tool hands it as `ants`, the way it draws a lift's, so the ants follow the
## hand and the picture under them does not move.
##
## **Enter is one step and Escape costs nothing.** Nothing is changed until
## Enter, which resamples the mask through the map in one
## [method SaSelection.change], with the carry `SaTransformSelection` already
## runs for a lift, so a feathered or turned outline lands as the same shape a
## lifted picture's selection would. Escape forgets the map, and the selection
## is the one it never stopped being.
##
## In the transform's `selection` folder beside [SaTransformSelection], whose
## carry it runs, and this file is the feature's facade: [method register]
## puts the command on the Select menu, and the tool state gains only the
## switch into this pass, `transform_selection`.
class_name SaTransformShape
extends SaTransform

## The command's id, which `ui/menus/select_menu.gd` lists.
const COMMAND_ID := &"select_transform"

## The step the Undo History docker lists.
const TITLE := "Transform Selection"

## The id of the tool this pass drives.
const TOOL_ID := &"transform"

## What the corner says when the box opens, since the box and its handles are
## the free transform's and only the words tell the two apart.
const OPEN_LINE := "Only the selection's outline moves. Enter keeps it, Escape puts it back."


## Opens a session over *box*, the selection's bounds. True when there is a
## selection to move. The layer is not read: the pixels stay where they are.
func lift(_untouched: SaLayer, box: Rect2i) -> bool:
    cancel()
    if _document == null or _document.selection == null or not _document.selection.active:
        return false
    if box.size.x <= 0 or box.size.y <= 0:
        return false
    bounds = box
    # The carry's three kernels are built now, while the hand only reaches for
    # a handle, so Enter finds them ready, as a lift's do.
    _mask_kernels.prepare()
    return true


## A session is open while it holds a box, which the parent's `cancel` empties,
## in place of the lifted chunks a pixel lift holds.
func is_lifted() -> bool:
    return bounds.size.x > 0 and bounds.size.y > 0


## Nothing to draw: the ants are the overlay's, through the tool's map.
func tick() -> void:
    return


## Lands the outline where the map put it, one undo step. True when it moved,
## and false for a session put down where it opened, which writes no step, for
## the reason [method SaTransform.commit] gives about a lift.
func commit() -> bool:
    if not is_lifted():
        return false
    var selection := _document.selection if _document != null else null
    var moved := has_moved()
    # A warp's outline follows its four corners, as a lift's selection does.
    var mask_map := _homography
    if is_warped():
        mask_map = SaHomography.corners_to_quad(bounds, SaTransformMesh.corners_of(_mesh))
    var carry := SaTransformSelection.carry.bind(selection, mask_map, matrix, bounds, landed_bounds(), filter, _mask_kernels)
    cancel()
    if not moved or selection == null or not selection.active:
        return false
    selection.change(TITLE, carry)
    _document.document_changed.emit()
    return true


## Puts Transform Selection on the Select menu. Bound to a context carrying the
## surfaces alone, as liquify binds its own command, since the module's holds
## the registry that holds this handler.
static func register(ctx: SaContext) -> void:
    var surfaces := SaContext.new(Callable(), ctx.surface_provider)
    var command := SaCommandDescriptor.create(COMMAND_ID, "Transform the selection", _run.bind(surfaces))
    command.label = "Transform Selection"
    command.category = &"select"
    command.sentence = "Move, turn and scale the selection's outline with the transform box, leaving the pixels where they are."
    command.enabled = _has_selection.bind(surfaces)
    ctx.register_command(command)


## The command's handler: the transform tool in the main canvas's hand, opened
## on the selection's outline. False when there is no selection or no machine
## holds the tool, so the chord a painter gives it falls through.
static func _run(surfaces: SaContext) -> bool:
    var machine: Variant = _machine_of(surfaces)
    if machine == null or not machine.registered_tools.has(TOOL_ID) or not _has_selection(surfaces):
        return false
    machine.set_active_tool(TOOL_ID)
    var tool: Variant = machine.get_tool(TOOL_ID)
    return tool != null and tool.has_method(&"transform_selection") and tool.transform_selection()


## Whether the main canvas's document has a selection, which dims the row.
static func _has_selection(surfaces: SaContext) -> bool:
    for candidate: SaSurface in surfaces.list_surfaces():
        if not candidate.is_embedded:
            var document := candidate.get_document()
            return document != null and document.selection != null and document.selection.active
    return false


## The main canvas's tool machine, or null.
static func _machine_of(surfaces: SaContext) -> Variant:
    for candidate: SaSurface in surfaces.list_surfaces():
        if not candidate.is_embedded:
            return candidate.tool_machine
    return null
