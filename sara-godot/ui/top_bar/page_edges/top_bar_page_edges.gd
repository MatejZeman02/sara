## The top bar's Page Edges, one icon that chooses what the page's edges do,
## and every view of it a custom docker holds, all showing and driving the
## document in front: Fixed, Grows, Wraps Sides or Wraps All Edges, which is
## `SaInfiniteCanvas.on` and `SaProjection.wrapping` read as one choice.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **One button, because the two switches it replaced contradicted each
## other.** A growing page cannot wrap, since a wrap needs a page that keeps its
## size, so a separate Infinite Canvas toggle beside the Wrap icon turned the
## other off and the corner had to say so. One button cannot contradict itself,
## so a change of mode is one undo step that writes both and says nothing.
##
## The icon is the grid of nine, `wrap` in `assets/icons/`, and where a press
## lands on it says what it does. The left and right columns, between the top
## and bottom rows, choose Wraps Sides. The top and bottom rows, corners
## included, choose Wraps All Edges. A press on either while its mode is on
## goes back to Fixed. The middle cell steps Fixed, Grows, Wraps Sides, Wraps
## All Edges and Fixed again. The cells a wrap fills are drawn over the grid,
## and Grows fills the middle cell with an arrow pointing out at each edge. A
## hover draws what the press under the pointer would leave, in a fainter tone,
## and the tooltip says it, so every mode is one press away and nothing is
## remembered.
##
## Registered as a `TopMenuBar` element with a view through
## `SaSettings.register_layout_element`, the door a module's element takes,
## anchored after Environment View and hidden on a fresh bar, for the
## photographed width of a fresh second row: View > Page Edges is where a
## painter finds it. A layout or a custom docker that placed one of the two
## retired elements shows this one in its place, [constant RETIRED]. On a
## panorama the icon is greyed, since the projection sets how it wraps.
class_name SaTopBarPageEdges
extends RefCounted

## The layout key, English like every other key and translated on the button.
const ELEMENT := "Page Edges"
const CATEGORY := "TopMenuBar"
## The element a fresh bar puts it after.
const AFTER := "Environment View"
## The elements this one took the place of, each read as this one where a
## saved layout or a custom docker still names it. The settings keep the list,
## since their version-29 step maps a stored bar and core never names this
## class.
const RETIRED: Array[String] = SaSettings.PAGE_EDGES_RETIRED
## The node name of the icon's button, which is the element.
const NODE_NAME := "PageEdgesToggle"
## The grid of nine the fills are drawn over, from `assets/icons/`.
const ICON := "wrap"
## The undo step a change of mode leaves.
const ACTION_NAME := "Page Edges"

## What the page's edges do.
enum Mode { FIXED, GROWS, WRAPS_SIDES, WRAPS_ALL }

## Each mode's command, by the mode, which View > Page Edges lists as its rows.
## Registered by `SaTopBarPageEdgesCommand`.
const MODE_COMMANDS := {
    Mode.FIXED: &"view_page_edges_fixed",
    Mode.GROWS: &"view_page_edges_grows",
    Mode.WRAPS_SIDES: &"view_page_edges_wraps_sides",
    Mode.WRAPS_ALL: &"view_page_edges_wraps_all",
}

## Where on the icon a press lands, which is what it does.
enum Region { SIDES, EDGES, MIDDLE }

## Each mode named and said, English and translated where it is shown.
const DESCRIPTIONS := {
    Mode.FIXED: "Page Edges, Fixed: every edge is an edge and the page keeps its size.",
    Mode.GROWS: "Page Edges, Grows: the page grows by whole chunks as a stroke nears an edge, so nothing painted falls past it.",
    Mode.WRAPS_SIDES: "Page Edges, Wraps Sides: a stroke across the left or right edge goes on at the other.",
    Mode.WRAPS_ALL: "Page Edges, Wraps All Edges: a stroke across any edge goes on at the opposite one.",
}


## Registers the element and its view, through the door a module uses.
## *documents* answers the `SaDocument` the views show and drive, the one in
## front when empty, which is every caller but a suite with a document of its
## own. A second call replaces the first, so a suite puts the shipped one back by
## calling this without one.
static func register(documents: Callable = Callable()) -> void:
    var builder := func() -> Control: return make(null, documents)
    SaSettings.register_layout_element(CATEGORY, ELEMENT, ELEMENT, true, AFTER, builder)


## Registers the commands that choose each mode and View > Wrap Around Mode
## against *ctx*, which `SaTopBarPageEdgesCommand` holds.
static func register_command(ctx: SaContext) -> void:
    SaTopBarPageEdgesCommand.register(ctx)


## The bar's own button under *host*, built the first time and found there
## after, as the element map the bar's rows order. *documents* as for
## [method register].
static func home(host: Node, documents: Callable = Callable()) -> Dictionary:
    if host == null:
        return {}
    register(documents)
    var button := host.get_node_or_null(NODE_NAME) as Control
    if button == null:
        button = make(host, documents)
    return {ELEMENT: button}


## Element key -> group, beside [method home]: it changes what the canvas is,
## and sits with the view's group beside Environment View.
static func groups() -> Dictionary:
    return {ELEMENT: SaOptionSpec.BAR_GROUP_VIEW}


## The icon's button that shows and drives the mode, under *parent* or loose,
## shaped by `SaBarIconButton` as Double Resolution is, so the grid has the
## bar's icon size and each region is wide enough to aim at.
static func make(parent: Node, documents: Callable = Callable()) -> Button:
    var button := SaMake.button(parent, NODE_NAME, TranslationServer.translate("Page Edges"))
    SaBarIconButton.shape(button, ICON, button.text)
    button.toggle_mode = true
    button.focus_mode = Control.FOCUS_NONE
    var follower := Follower.new(button, documents if documents.is_valid() else front)
    button.add_child(follower)
    button.gui_input.connect(follower.heard)
    button.mouse_exited.connect(follower.left)
    button.pressed.connect(follower.press)
    button.draw.connect(follower.draw_cells)
    return button


## The document in front, or null with no scene.
static func front() -> SaDocument:
    var canvas := SaCanvasView.front_canvas()
    return canvas.document if canvas != null else null


## The follower under *button*, which a suite asks to read the mode at once.
static func follower_of(button: Control) -> Follower:
    return button.get_node_or_null(Follower.NODE_NAME) as Follower if button != null else null


## Why *document*'s edges cannot be chosen here, or empty when they can.
static func refusal(document: SaDocument) -> String:
    if document == null:
        return String(TranslationServer.translate("There is no document whose edges to choose."))
    if document.projection.kind.id != SaProjection.FLAT:
        return String(TranslationServer.translate("The projection sets how a panorama wraps, under Image > Projection..."))
    return ""


## What *document*'s edges do now, Fixed with no document. A panorama reads as
## the wrap its projection sets.
static func mode_of(document: SaDocument) -> Mode:
    if document == null:
        return Mode.FIXED
    match document.projection.wrapping:
        SaProjection.Wrap.X:
            return Mode.WRAPS_SIDES
        SaProjection.Wrap.XY:
            return Mode.WRAPS_ALL
    if document.infinite_canvas != null and document.infinite_canvas.on:
        return Mode.GROWS
    return Mode.FIXED


## Gives *document*'s edges *mode*, as one undo step that writes both the
## growth and the wrap. False, and no step, where [method refusal] refuses or
## the mode is already in force.
static func choose(document: SaDocument, mode: Mode) -> bool:
    if not refusal(document).is_empty() or mode_of(document) == mode:
        return false
    var put := func(grows: bool, wrapping: SaProjection.Wrap) -> void:
        if document.infinite_canvas != null:
            document.infinite_canvas.on = grows
        if document.projection.wrapping != wrapping:
            document.projection = SaProjection.new(document.projection.kind, document.projection.orientation, wrapping)
        document.modified = true
    var was_grows := document.infinite_canvas != null and document.infinite_canvas.on
    var was_edges := document.projection.wrapping
    var edges := wrap_of(mode)
    if document.history != null:
        document.history.commit_pair(ACTION_NAME, put.bind(mode == Mode.GROWS, edges), put.bind(was_grows, was_edges))
    put.call(mode == Mode.GROWS, edges)
    return true


## The wrap *mode* asks of the projection.
static func wrap_of(mode: Mode) -> SaProjection.Wrap:
    match mode:
        Mode.WRAPS_SIDES:
            return SaProjection.Wrap.X
        Mode.WRAPS_ALL:
            return SaProjection.Wrap.XY
    return SaProjection.Wrap.NONE


## The region of the grid of nine at *point*, inside *grid*. A point beyond
## the grid counts as the cell nearest it, so the button's margin is no dead
## ground.
static func region_at(point: Vector2, grid: Rect2) -> Region:
    var cell := Vector2i(_third(point.x - grid.position.x, grid.size.x), _third(point.y - grid.position.y, grid.size.y))
    if cell.y != 1:
        return Region.EDGES
    return Region.MIDDLE if cell.x == 1 else Region.SIDES


## What a press on *region* turns a mode of *now* into.
static func outcome(now: Mode, region: Region) -> Mode:
    match region:
        Region.SIDES:
            return Mode.FIXED if now == Mode.WRAPS_SIDES else Mode.WRAPS_SIDES
        Region.EDGES:
            return Mode.FIXED if now == Mode.WRAPS_ALL else Mode.WRAPS_ALL
    return ((int(now) + 1) % Mode.size()) as Mode


## The cells of the grid a wrap of *mode* fills, each as its column and row.
## Grows fills none of them and is drawn as arrows instead.
static func cells_of(mode: Mode) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if mode != Mode.WRAPS_SIDES and mode != Mode.WRAPS_ALL:
        return out
    for row in range(3):
        for column in range(3):
            var side := column != 1
            var edge := side or row != 1
            if (side and mode == Mode.WRAPS_SIDES) or (edge and mode == Mode.WRAPS_ALL):
                out.append(Vector2i(column, row))
    return out


## What a press on *region* does to a mode of *now*, in the painter's words.
## The middle adds the round it steps through, since its next press differs.
static func tooltip_for(now: Mode, region: Region) -> String:
    var words := describe(outcome(now, region))
    if region == Region.MIDDLE:
        words += "\n" + String(TranslationServer.translate("The middle steps Fixed, Grows, Wraps Sides and Wraps All Edges."))
    return words


## One sentence that names *mode* and says what it does, which opens the
## button's tooltip.
static func describe(mode: Mode) -> String:
    return String(TranslationServer.translate(DESCRIPTIONS[mode]))


static func _third(offset: float, length: float) -> int:
    if length <= 0.0:
        return 1
    return clampi(int(floor(offset / length * 3.0)), 0, 2)


## Reads the mode off the document every frame, draws it over the grid, and
## hands a press to it. A child of the button and not a subclass of one, so the
## button is the made `Button` the harness and the theme read like any other.
class Follower:
    extends Node

    const NODE_NAME := "Follower"
    ## How much of the mode's own tone a hover's preview is drawn in.
    const PREVIEW_ALPHA := 0.4
    ## The tone of the drawn icon, which the theme's icon colour tints.
    const INK := Color("e0e0e0")
    ## The four arrowheads Grows draws, in the sixteenths of the grid the icon
    ## is drawn on: one over each edge cell beside the middle, pointing out, so
    ## the page reads as pushing past its edges. A wrap fills whole cells, so
    ## the two never look alike.
    const ARROWS := [
        [Vector2(8.0, 0.5), Vector2(5.0, 5.0), Vector2(11.0, 5.0)],
        [Vector2(8.0, 15.5), Vector2(5.0, 11.0), Vector2(11.0, 11.0)],
        [Vector2(0.5, 8.0), Vector2(5.0, 5.0), Vector2(5.0, 11.0)],
        [Vector2(15.5, 8.0), Vector2(11.0, 5.0), Vector2(11.0, 11.0)],
    ]

    var _button: Button
    ## Answers the `SaDocument` to show and drive, or null.
    var _documents: Callable
    ## The region under the pointer, or -1 with the pointer away, which a suite
    ## reads.
    var _hovered: int = -1
    ## The region the last press went down on, -1 before one.
    var _pressed_on: int = -1
    ## The mode the icon was last drawn for, so a frame that keeps it draws
    ## nothing.
    var _drawn: int = -1

    func _init(button: Button = null, documents: Callable = Callable()) -> void:
        _button = button
        _documents = documents
        name = NODE_NAME

    func _ready() -> void:
        sync()

    func _process(_delta: float) -> void:
        sync()

    func document() -> SaDocument:
        return _documents.call() if _documents.is_valid() else null

    ## The mode in front, Fixed with no document.
    func mode() -> Mode:
        return SaTopBarPageEdges.mode_of(document())

    func sync() -> void:
        var now := mode()
        var on := now != Mode.FIXED
        if _button.button_pressed != on:
            _button.set_pressed_no_signal(on)
        var reason := SaTopBarPageEdges.refusal(document())
        var lock := not reason.is_empty()
        if _button.disabled != lock:
            _button.disabled = lock
        var tip := reason
        if not lock:
            var region := _hovered if _hovered >= 0 else Region.MIDDLE
            tip = SaTopBarPageEdges.tooltip_for(now, region as Region)
        if _button.tooltip_text != tip:
            _button.tooltip_text = tip
        if _drawn != int(now):
            _drawn = int(now)
            _button.queue_redraw()

    ## The square the grid of nine is drawn in, in the button's space: the
    ## content box past the style's margins, as wide as the icon may be.
    func grid_rect() -> Rect2:
        var style := _button.get_theme_stylebox(&"normal")
        var inner := Rect2(Vector2.ZERO, _button.size)
        if style != null:
            inner = Rect2(
                Vector2(style.get_margin(SIDE_LEFT), style.get_margin(SIDE_TOP)), _button.size - style.get_minimum_size()
            )
        var side := minf(inner.size.x, inner.size.y)
        var widest := _button.get_theme_constant(&"icon_max_width")
        if widest > 0:
            side = minf(side, float(widest))
        return Rect2(inner.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))

    ## Keeps the region under the pointer and the one a press goes down on.
    func heard(event: InputEvent) -> void:
        var mouse := event as InputEventMouse
        if mouse == null:
            return
        var region := int(SaTopBarPageEdges.region_at(mouse.position, grid_rect()))
        var button := event as InputEventMouseButton
        if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
            _pressed_on = region
        if region != _hovered:
            _hovered = region
            sync()
            _button.queue_redraw()

    ## The pointer went away, and the preview with it.
    func left() -> void:
        if _hovered < 0:
            return
        _hovered = -1
        sync()
        _button.queue_redraw()

    ## Gives the document the mode the region the press went down on says.
    func press() -> void:
        var doc := document()
        if doc != null:
            var region := _pressed_on if _pressed_on >= 0 else Region.MIDDLE
            SaTopBarPageEdges.choose(doc, SaTopBarPageEdges.outcome(mode(), region as Region))
        _pressed_on = -1
        sync()

    ## The cells a wrap fills or the arrows of Grows, or under a hover what the
    ## press would leave in the fainter tone, drawn over the grid the icon is.
    func draw_cells() -> void:
        if _button.icon == null:
            return
        var key := &"icon_disabled_color" if _button.disabled else &"icon_normal_color"
        var ink := INK * _button.get_theme_color(key)
        var shown := mode()
        if _hovered >= 0 and not _button.disabled:
            shown = SaTopBarPageEdges.outcome(shown, _hovered as Region)
            ink.a *= PREVIEW_ALPHA
        var grid := grid_rect()
        var unit := grid.size.x / 16.0
        for cell in SaTopBarPageEdges.cells_of(shown):
            var at := grid.position + Vector2(1.0 + 5.0 * cell.x, 1.0 + 5.0 * cell.y) * unit
            _button.draw_rect(Rect2(at, Vector2(4.0, 4.0) * unit), ink)
        if shown != Mode.GROWS:
            return
        _button.draw_rect(Rect2(grid.position + Vector2(6.0, 6.0) * unit, Vector2(4.0, 4.0) * unit), ink)
        for arrow: Array in ARROWS:
            var points := PackedVector2Array()
            for point: Vector2 in arrow:
                points.append(grid.position + point * unit)
            _button.draw_colored_polygon(points, ink)
