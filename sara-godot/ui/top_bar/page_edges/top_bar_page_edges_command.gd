## The commands beside the top bar's Page Edges: one a mode, which View > Page
## Edges lists as its rows, and View > Wrap Around Mode, which turns the wrap
## of all edges on or off.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Commands, so a chord, Quick Favourites and the search reach each mode, and
## the View menu's rows read their tick and their dimming off the command, as
## every command row does. Registered through the door a module's command
## takes.
##
## Wrap Around Mode keeps its id and Krita's Shift+W, `wrap_around_mode` in
## Krita's action files, while Sara's own map and the Photoshop one leave it
## unbound, since Shift+W is the Pop-up Palette there. On, it wraps all edges,
## the mode a press on the icon's top row chooses.
##
## Where the icon is greyed, a panorama or no document at all, a command does
## nothing to the document and says in the corner what the icon's tooltip
## says, `SaTopBarPageEdges.refusal`.
class_name SaTopBarPageEdgesCommand
extends RefCounted

const COMMAND := &"view_wrap"


## Registers the commands against *ctx*. They act on the document in front,
## the one the icon shows, and with no front canvas, which is a suite's, on the
## document of *ctx*'s easel.
static func register(ctx: SaContext) -> void:
    var reach := SaContext.new(ctx.easel_provider, ctx.surface_provider)
    var command := SaCommandDescriptor.create(COMMAND, "Wrap around mode", func() -> bool: return _flip(reach))
    command.label = "Wrap Around Mode"
    command.category = &"view"
    command.sentence = (
        "Turn the wrap on or off, so a stroke across an edge goes on at the opposite edge. On, it wraps all edges, and"
        + " View > Page Edges chooses the sides only."
    )
    command.checked = func() -> bool: return wraps(document_of(reach))
    ctx.register_command(command)
    var fixed := _mode_command(reach, SaTopBarPageEdges.Mode.FIXED, "Page edges: fixed")
    fixed.label = "Fixed"
    fixed.sentence = "Every edge is an edge and the page keeps its size."
    ctx.register_command(fixed)
    var grows := _mode_command(reach, SaTopBarPageEdges.Mode.GROWS, "Page edges: grows")
    grows.label = "Grows"
    grows.sentence = "The page grows by whole chunks as a stroke nears an edge, so nothing painted falls past it."
    ctx.register_command(grows)
    var sides := _mode_command(reach, SaTopBarPageEdges.Mode.WRAPS_SIDES, "Page edges: wraps sides")
    sides.label = "Wraps Sides"
    sides.sentence = "A stroke across the left or right edge goes on at the other."
    ctx.register_command(sides)
    var all := _mode_command(reach, SaTopBarPageEdges.Mode.WRAPS_ALL, "Page edges: wraps all edges")
    all.label = "Wraps All Edges"
    all.sentence = "A stroke across any edge goes on at the opposite one."
    ctx.register_command(all)


## The command that gives the document *mode*, named *title* on the Keyboard
## Shortcuts page, ticked while the mode is in force and dimmed where the icon
## is greyed. The caller writes its menu words and its sentence as literals, so
## the message template reads them.
static func _mode_command(reach: SaContext, mode: SaTopBarPageEdges.Mode, title: String) -> SaCommandDescriptor:
    var id: StringName = SaTopBarPageEdges.MODE_COMMANDS[mode]
    var command := SaCommandDescriptor.create(id, title, func() -> bool: return _choose(reach, mode))
    command.category = &"view"
    command.checked = func() -> bool: return SaTopBarPageEdges.mode_of(document_of(reach)) == mode
    command.enabled = func() -> bool: return SaTopBarPageEdges.refusal(document_of(reach)).is_empty()
    return command


## The document the commands turn, the front one, or *ctx*'s easel's.
static func document_of(ctx: SaContext) -> SaDocument:
    var front := SaTopBarPageEdges.front()
    if front != null:
        return front
    var easel := ctx.get_easel()
    return easel.document if easel != null else null


## Whether *document* wraps now.
static func wraps(document: SaDocument) -> bool:
    return document != null and document.projection.wrapping != SaProjection.Wrap.NONE


static func _flip(ctx: SaContext) -> bool:
    var document := document_of(ctx)
    var mode := SaTopBarPageEdges.Mode.FIXED if wraps(document) else SaTopBarPageEdges.Mode.WRAPS_ALL
    return _choose(ctx, mode)


static func _choose(ctx: SaContext, mode: SaTopBarPageEdges.Mode) -> bool:
    var document := document_of(ctx)
    var reason := SaTopBarPageEdges.refusal(document)
    if not reason.is_empty():
        SaMessage.notice(reason)
        return true
    SaTopBarPageEdges.choose(document, mode)
    return true
