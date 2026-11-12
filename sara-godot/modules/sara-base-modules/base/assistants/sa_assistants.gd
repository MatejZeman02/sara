## The drawing assistants: rulers, vanishing points, parallel rulers and
## ellipses a painter places on the canvas once and draws along many times, the
## feature's facade.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What it registers.** The Assistants tool, which places a ruler by two
## handles, a vanishing point by one, a parallel ruler by two and an ellipse by
## three, moves a handle or the whole assistant and deletes it, each one
## history step. The
## View menu's Show Assistants row. And the holder `SaStrokeHold` asks at every
## brush press, which holds the stroke to the assistant its first point and
## first motion choose while the tool's Snap switch is on, [Guides]. Every
## engine reads the held position where it reads the pointer, so no engine
## knows an assistant exists.
##
## **An ellipse and its concentric ones.** An ellipse holds a stroke that
## starts near it to its own curve. With its Concentric switch on it holds a
## stroke that starts anywhere to the ellipse of its shape and centre through
## the stroke's first point, so a concentric ellipse holds every stroke while
## it stands, as Krita's does, and a ruler or a vanishing point beside it is
## drawn along with Concentric off.
##
## **Where an assistant lives.** In the document's `module_data` under
## `SaStrokeHold.GUIDES_KEY`, a list of JSON entries, each a shape and its
## points, so a `.sad` keeps them in a section of its own
## (`SaSadAssistants`) and `SaDocument` holds no field for them. The shape is
## written so every assistant shares the list.
##
## **A hidden assistant holds nothing.** With Show Assistants off, a stroke is
## free whatever Snap says, because a stroke bent by a line the painter cannot
## see reads as a fault.
class_name SaAssistants
extends RefCounted

const StateAssistantsScript = preload("res://modules/sara-base-modules/base/assistants/state_assistants.gd")

## The module the holder is handed in under.
const MODULE := &"sara-base-modules"
## The tool's id and the View menu's command.
const TOOL := &"assistants"
const SHOW_COMMAND := &"view_assistants"
## The shapes of an entry, under `"shape"` rather than `"kind"`, which the
## message template reads as words to translate. A ruler holds a stroke to its
## own line, a vanishing point to the line from the stroke's press through the
## point, and a parallel ruler to the line through the press along its
## direction.
const RULER := &"ruler"
const VANISHING := &"vanishing"
const PARALLEL := &"parallel"
const SHAPES: Array[StringName] = [RULER, VANISHING, PARALLEL]
## An ellipse's shape, which [Ellipse] reads and [Guide] leaves alone, its
## curve held to by a projection no line shares.
const ELLIPSE := &"ellipse"
## The guides' colour, a violet that tells them from the symmetry axes'
## orange and the effect line's cyan.
const COLOR := Color(0.72, 0.45, 1.0, 0.95)
## The colours the Colour row offers, so the guides can be told from the paint
## under them whatever it is. The first is [constant COLOR].
const TINTS: Array[Color] = [
    COLOR,
    Color(1.0, 0.6, 0.15, 0.95),
    Color(0.2, 0.85, 0.45, 0.95),
    Color(0.15, 0.8, 0.95, 0.95),
    Color(1.0, 1.0, 1.0, 0.95),
    Color(0.0, 0.0, 0.0, 0.95),
]
## The names the Colour row shows, in the order of [constant TINTS].
const TINT_NAMES: Array[String] = ["Violet", "Orange", "Green", "Cyan", "White", "Black"]
## How strong the line past a ruler's ends is drawn, which a stroke is held to
## as well, against the ruler itself.
const REACH_ALPHA: float = 0.35
## A handle's radius in screen pixels at every zoom, as the axes' are, and how
## much larger a vanishing point's is, the one handle its guide has.
const HANDLE_RADIUS: float = 5.0
const VANISHING_SCALE: float = 1.4
## How many guide lines a vanishing point draws round itself, one every 22.5
## degrees, enough to read the perspective by and few enough to paint under.
const RAYS: int = 16
## A parallel ruler's dash in screen pixels, which tells it from a ruler.
const DASH: float = 6.0
## How near a ruler's line a press has to land, in document pixels, for the
## ruler to take the stroke over a vanishing point or a parallel ruler, whose
## lines run through every press.
const RULER_REACH: float = 12.0
## How far the pointer has to move from the press, in document pixels, before
## the stroke chooses among the vanishing points and parallel rulers. A shorter
## motion is mostly the hand's tremor and points nowhere yet.
const DECIDE: float = 4.0


## The Snap switch and the View menu's switch, one for every surface and
## document, shared by the tool, the holder and the command.
class Switches:
    extends Resource

    ## Whether a brush stroke is held to the nearest ruler.
    var snap: bool = true
    ## Whether the rulers are drawn, and so whether they hold anything.
    var shown: bool = true
    ## Which of [constant TINTS] the guides are drawn in.
    var tint: int = 0
    ## How strongly the guides are drawn, one for fully and less to dim them, so
    ## they stay on screen without covering the paint.
    var strength: float = 1.0


## One assistant in document pixels: a ruler or a parallel ruler, the line
## through two handles, or a vanishing point, one handle with `b` kept on `a`.
class Guide:
    extends RefCounted

    var shape: StringName = RULER
    var a: Vector2 = Vector2.ZERO
    var b: Vector2 = Vector2.ZERO

    func _init(from: Vector2 = Vector2.ZERO, to: Vector2 = Vector2.ZERO, kind_of: StringName = RULER) -> void:
        shape = kind_of
        a = from
        b = from if kind_of == VANISHING else to

    ## The guide an entry of the document's list describes, or null for an
    ## entry of a shape this module does not know or a damaged one.
    static func of(given: Variant) -> Guide:
        if not (given is Dictionary):
            return null
        var named := StringName(str((given as Dictionary).get("shape", "")))
        if not named in SHAPES:
            return null
        var points := SaTyped.list((given as Dictionary).get("points"))
        if points.size() != (2 if named == VANISHING else 4):
            return null
        for value: Variant in points:
            if not (value is float or value is int):
                return null
        var from := Vector2(float(points[0]), float(points[1]))
        if named == VANISHING:
            return Guide.new(from, from, named)
        return Guide.new(from, Vector2(float(points[2]), float(points[3])), named)

    ## This guide as an entry of the document's list.
    func entry() -> Dictionary:
        if shape == VANISHING:
            return {"shape": String(shape), "points": [a.x, a.y]}
        return {"shape": String(shape), "points": [a.x, a.y, b.x, b.y]}

    ## Whether a stroke pressed anywhere has a line of this guide through its
    ## press, which a vanishing point and a parallel ruler give and a ruler,
    ## whose one line is where it lies, does not.
    func everywhere() -> bool:
        return shape != RULER

    ## The direction this guide holds a stroke pressed at *from* to, or zero
    ## where it holds none, a press on the vanishing point itself.
    func direction(from: Vector2) -> Vector2:
        var along := (a - from) if shape == VANISHING else (b - a)
        return along if along.length_squared() > 1e-6 else Vector2.ZERO

    ## The point the line a stroke pressed at *from* is held to runs through:
    ## the ruler's own handle, or the press for every other shape.
    func origin(from: Vector2) -> Vector2:
        return a if shape == RULER else from

    ## *at* moved onto the line this guide holds a stroke pressed at *from* to.
    func project(at: Vector2, from: Vector2 = Vector2.ZERO) -> Vector2:
        var along := direction(from)
        var through := origin(from)
        if along == Vector2.ZERO:
            return through
        return through + (at - through).project(along)

    ## How far *at* lies from the line this guide holds a stroke pressed at
    ## *from* to.
    func distance(at: Vector2, from: Vector2 = Vector2.ZERO) -> float:
        return at.distance_to(project(at, from))

    ## How far *at* lies from the guide between its handles, which a press on
    ## the guide itself reaches, and from the one handle of a vanishing point.
    func segment_distance(at: Vector2) -> float:
        return at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b))


## One ellipse, by the two ends of one axis and the half length of the other,
## in document pixels. Its third handle stands at the end of that other axis.
class Ellipse:
    extends RefCounted

    ## How many points the overlay draws the curve with.
    const DRAWN := 128
    ## The rounds of the nearest point search, each closing the gap by orders
    ## of magnitude, so six leave far less than a hundredth of a pixel on any
    ## ellipse a canvas holds.
    const ROUNDS := 6

    var a: Vector2 = Vector2.ZERO
    var b: Vector2 = Vector2.ZERO
    var minor: float = 0.0
    var concentric: bool = false

    func _init(from: Vector2 = Vector2.ZERO, to: Vector2 = Vector2.ZERO, half: float = 0.0, rings: bool = false) -> void:
        a = from
        b = to
        minor = half
        concentric = rings

    ## The ellipse a drag from *from* to *to* places, its other axis half the
    ## length of the one dragged, which the third handle then sets.
    static func placed(from: Vector2, to: Vector2, rings: bool) -> Ellipse:
        return Ellipse.new(from, to, from.distance_to(to) * 0.25, rings)

    ## The ellipse an entry of the document's list describes, or null for an
    ## entry of another kind or a damaged one.
    static func of(given: Variant) -> Ellipse:
        if not (given is Dictionary) or StringName(str((given as Dictionary).get("shape", ""))) != ELLIPSE:
            return null
        var points := SaTyped.list((given as Dictionary).get("points"))
        if points.size() != 5:
            return null
        for value: Variant in points:
            if not (value is float or value is int):
                return null
        return Ellipse.new(
            Vector2(float(points[0]), float(points[1])),
            Vector2(float(points[2]), float(points[3])),
            float(points[4]),
            bool((given as Dictionary).get("concentric", false))
        )

    func entry() -> Dictionary:
        return {"shape": String(ELLIPSE), "points": [a.x, a.y, b.x, b.y, minor], "concentric": concentric}

    func centre() -> Vector2:
        return (a + b) * 0.5

    ## The unit direction of the axis through the first two handles.
    func axis() -> Vector2:
        return (b - a).normalized()

    ## The two half axes, along the first and across it.
    func halves() -> Vector2:
        return Vector2(a.distance_to(b) * 0.5, minor)

    func holds() -> bool:
        var half := halves()
        return half.x > 1e-3 and half.y > 1e-3

    ## *at* in the ellipse's own frame, its centre at the origin and the first
    ## axis along x.
    func local(at: Vector2) -> Vector2:
        var along := axis()
        var offset := at - centre()
        return Vector2(offset.dot(along), offset.dot(along.orthogonal()))

    func world(at: Vector2) -> Vector2:
        var along := axis()
        return centre() + along * at.x + along.orthogonal() * at.y

    ## The scale of the concentric ellipse through *at*, 1 on this one.
    func scale_through(at: Vector2) -> float:
        var spot := local(at)
        var half := halves()
        return Vector2(spot.x / half.x, spot.y / half.y).length()

    ## The point of the ellipse scaled by *scale* nearest *at*, by the
    ## iteration that walks a point along the curve to where its normal meets
    ## *at*, in the first quadrant and then mirrored back.
    func nearest(at: Vector2, scale: float = 1.0) -> Vector2:
        var spot := local(at)
        var half := halves() * scale
        var px := absf(spot.x)
        var py := absf(spot.y)
        var tx := 0.70710678
        var ty := 0.70710678
        for _step in ROUNDS:
            var x := half.x * tx
            var y := half.y * ty
            var ex := (half.x * half.x - half.y * half.y) * tx * tx * tx / half.x
            var ey := (half.y * half.y - half.x * half.x) * ty * ty * ty / half.y
            var r := Vector2(x - ex, y - ey).length()
            var q := Vector2(px - ex, py - ey).length()
            if q < 1e-9:
                break
            tx = clampf(((px - ex) * r / q + ex) / half.x, 0.0, 1.0)
            ty = clampf(((py - ey) * r / q + ey) / half.y, 0.0, 1.0)
            var length := Vector2(tx, ty).length()
            tx /= length
            ty /= length
        var sx := 1.0 if spot.x >= 0.0 else -1.0
        var sy := 1.0 if spot.y >= 0.0 else -1.0
        return world(Vector2(half.x * tx * sx, half.y * ty * sy))

    ## How far *at* lies from the ellipse's curve.
    func distance(at: Vector2) -> float:
        return at.distance_to(nearest(at))

    ## A concentric ellipse reaches every press, a plain one the presses near
    ## its curve.
    func reach(at: Vector2) -> float:
        return 0.0 if concentric else distance(at)

    ## The hold of a stroke pressed at *at*: onto this curve, or with
    ## Concentric on onto the ellipse of this shape through *at*. A press on
    ## the very centre has no such ellipse and is left free.
    func holding(at: Vector2) -> Callable:
        var scale := scale_through(at) if concentric else 1.0
        if scale < 1e-3:
            return Callable()
        return func(pointer: Vector2) -> Vector2: return nearest(pointer, scale)

    ## The two ends of the first axis and the end of the other.
    func handles() -> Array[Vector2]:
        return [a, b, centre() + axis().orthogonal() * minor]

    ## This ellipse with handle *index* at *at*. An end of the first axis
    ## keeps the other's length, and the third handle sets that length from
    ## how far it stands off the first axis.
    func with_handle(index: int, at: Vector2) -> Ellipse:
        match index:
            0:
                return Ellipse.new(at, b, minor, concentric)
            1:
                return Ellipse.new(a, at, minor, concentric)
        return Ellipse.new(a, b, maxf(absf(local(at).y), 1.0), concentric)

    func shifted(by: Vector2) -> Ellipse:
        return Ellipse.new(a + by, b + by, minor, concentric)

    func draw(overlay: Control, _span: float) -> void:
        var colour := SaAssistants.tint()
        if not holds():
            overlay.draw_line(a, b, colour, -1.0)
            return
        if concentric:
            for ring: float in [0.33, 0.66]:
                overlay.draw_polyline(_curve(ring), Color(colour, colour.a * REACH_ALPHA), -1.0)
        overlay.draw_line(a, b, Color(colour, colour.a * REACH_ALPHA), -1.0)
        overlay.draw_polyline(_curve(1.0), colour, -1.0)

    func _curve(scale: float) -> PackedVector2Array:
        var half := halves() * scale
        var points := PackedVector2Array()
        for index in DRAWN + 1:
            var turn := TAU * float(index) / DRAWN
            points.append(world(Vector2(cos(turn) * half.x, sin(turn) * half.y)))
        return points


## What `SaStrokeHold` asks at a brush press, while Snap and Show Assistants
## are both on. An ellipse that reaches the press nearer than every ruler holds
## the stroke when it reaches within [constant RULER_REACH] or nothing else is
## placed, and a concentric one reaches every press. A ruler whose line lies within [constant RULER_REACH] of the
## press holds the stroke at once, and so does the nearest ruler when nothing
## else is placed. Otherwise the stroke waits for its first motion
## [constant DECIDE] pixels from the press, and the vanishing point or parallel
## ruler whose line through the press runs nearest that motion holds it from
## there, the press point itself lying on every one of them.
class Guides:
    extends SaStrokeHold.Holder

    var _switches: Switches = null

    func _init(switches: Switches) -> void:
        _switches = switches

    func hold(document: SaDocument, at: Vector2) -> Callable:
        if not _holding():
            return Callable()
        var guides := SaAssistants.guides(document)
        var ruler := _nearest_ruler(guides, at)
        var others: Array[Guide] = []
        for guide: Guide in guides:
            if guide.everywhere() and guide.direction(at) != Vector2.ZERO:
                others.append(guide)
        var ellipse := _nearest_ellipse(document, at)
        if ellipse != null:
            var near := ellipse.reach(at)
            if near <= (ruler.distance(at) if ruler != null else INF) and (near <= RULER_REACH or others.is_empty()):
                return ellipse.holding(at)
        if ruler != null and (others.is_empty() or ruler.distance(at) <= RULER_REACH):
            var from := ruler.a
            var along := ruler.b - ruler.a
            return func(pointer: Vector2) -> Vector2: return from + (pointer - from).project(along)
        if others.is_empty():
            return Callable()
        # The choice the first motion makes, kept for the rest of the stroke
        # in an array the closure holds by reference.
        var chosen: Array[Vector2] = []
        return func(pointer: Vector2) -> Vector2: return SaAssistants.held(others, at, pointer, chosen)

    func reach(document: SaDocument, at: Vector2) -> float:
        if not _holding():
            return INF
        var ellipse := _nearest_ellipse(document, at)
        var most := ellipse.reach(at) if ellipse != null else INF
        for guide: Guide in SaAssistants.guides(document):
            if guide.everywhere():
                if guide.direction(at) != Vector2.ZERO:
                    return 0.0
            elif guide.direction(at) != Vector2.ZERO:
                most = minf(most, guide.distance(at))
        return most

    func draw(document: SaDocument, overlay: Control, per_pixel: float) -> void:
        if not _switches.shown:
            return
        var span := Vector2(document.canvas_size).length()
        var colour := SaAssistants.tint()
        var reach_tint := Color(colour, colour.a * REACH_ALPHA)
        for guide: Guide in SaAssistants.guides(document):
            match guide.shape:
                VANISHING:
                    for ray in RAYS:
                        var toward := Vector2.from_angle(TAU * ray / RAYS) * span * 2.0
                        overlay.draw_line(guide.a, guide.a + toward, reach_tint, -1.0)
                    _handle(overlay, guide.a, per_pixel * VANISHING_SCALE)
                PARALLEL:
                    overlay.draw_dashed_line(guide.a, guide.b, colour, -1.0, DASH * per_pixel)
                    _handle(overlay, guide.a, per_pixel)
                    _handle(overlay, guide.b, per_pixel)
                _:
                    var along := guide.b - guide.a
                    if along.length_squared() > 1e-6:
                        var past := along.normalized() * span
                        overlay.draw_line(guide.a - past, guide.b + past, reach_tint, -1.0)
                    overlay.draw_line(guide.a, guide.b, colour, -1.0)
                    _handle(overlay, guide.a, per_pixel)
                    _handle(overlay, guide.b, per_pixel)

        for ellipse: Ellipse in SaAssistants.ellipses(document):
            ellipse.draw(overlay, span)
            for handle: Vector2 in ellipse.handles():
                _handle(overlay, handle, per_pixel)

    func signature(document: SaDocument) -> Array:
        return [_switches.shown, _switches.tint, _switches.strength, SaAssistants.entries(document)]

    func _holding() -> bool:
        return _switches.snap and _switches.shown

    func _handle(overlay: Control, at: Vector2, per_pixel: float) -> void:
        var strength := clampf(_switches.strength, 0.0, 1.0)
        overlay.draw_circle(at, HANDLE_RADIUS * per_pixel, Color(0.0, 0.0, 0.0, 0.6 * strength), true, -1.0, true)
        overlay.draw_circle(at, (HANDLE_RADIUS - 1.5) * per_pixel, Color(SaAssistants.tint(), strength), true, -1.0, true)

    ## The ellipse that reaches *at* nearest, or null for none.
    func _nearest_ellipse(document: SaDocument, at: Vector2) -> Ellipse:
        var nearest: Ellipse = null
        for ellipse: Ellipse in SaAssistants.ellipses(document):
            if ellipse.holds() and (nearest == null or ellipse.reach(at) < nearest.reach(at)):
                nearest = ellipse
        return nearest

    ## The ruler whose line runs nearest *at*, or null for none.
    func _nearest_ruler(guides: Array[Guide], at: Vector2) -> Guide:
        var nearest: Guide = null
        for guide: Guide in guides:
            if guide.everywhere() or guide.direction(at) == Vector2.ZERO:
                continue
            if nearest == null or guide.distance(at) < nearest.distance(at):
                nearest = guide
        return nearest


## The switches every surface's tool and the holder share, made at register.
static var switches: Switches = null


## The colour the guides are drawn in, the Colour row's choice dimmed by the
## Dim row's strength.
static func tint() -> Color:
    if switches == null:
        return COLOR
    var picked := TINTS[clampi(switches.tint, 0, TINTS.size() - 1)]
    return Color(picked, picked.a * clampf(switches.strength, 0.0, 1.0))


## Registers the tool, the View menu's row and the holder.
static func register(ctx: SaContext) -> void:
    switches = Switches.new()
    var tool := SaToolDescriptor.create(TOOL, StateAssistantsScript)
    tool.display_name = "Assistants"
    tool.icon_name = "res://modules/sara-base-modules/base/assistants/ruler.svg"
    tool.category = &"paint"
    tool.cursor_shape = Control.CURSOR_CROSS
    tool.activate_action = &"tool_assistants"
    tool.shared_settings = switches
    tool.options = options()
    ctx.register_tool(tool)

    var shown := switches
    var command := SaCommandDescriptor.create(SHOW_COMMAND, "Show or hide the drawing assistants", _flip_shown.bind(shown))
    command.label = "Show Assistants"
    command.category = &"view"
    command.sentence = "Draw the assistants over the canvas. Hidden assistants hold no stroke."
    command.checked = func() -> bool: return shown.shown
    ctx.register_command(command)
    SaStrokeHold.put(MODULE, Guides.new(switches))


## Takes the holder away, for the module's `unregister`.
static func unregister() -> void:
    SaStrokeHold.take_away(MODULE)


## The tool's rows: the shape a press places, Snap, Concentric, and the two
## that delete.
## Every row but Delete All has a control on the bar that starts hidden, as
## every tool's but the brush's does, so a fresh bar shows the brush's controls
## whichever tool is in hand. The Tool Options docker shows all five.
static func options() -> Array[SaOptionSpec]:
    var shape := (
        SaOptionSpec
        . make(
            &"assistants_shape",
            "Assistant",
            SaOptionSpec.Kind.ENUM,
            {
                "choices":
                [
                    {"id": StateAssistantsScript.Shape.RULER, "label": "Ruler", "tooltip": "A line strokes are held to"},
                    {
                        "id": StateAssistantsScript.Shape.VANISHING,
                        "label": "Vanishing Point",
                        "tooltip": "A point every stroke runs towards, for drawing in perspective"
                    },
                    {
                        "id": StateAssistantsScript.Shape.PARALLEL,
                        "label": "Parallel Ruler",
                        "tooltip": "A direction every stroke runs along, for hatching"
                    },
                    {
                        "id": StateAssistantsScript.Shape.ELLIPSE,
                        "label": "Ellipse",
                        "tooltip": "An ellipse strokes run round, placed by one axis and then the other"
                    },
                ],
                "on_tool": true,
                "property": ^"shape",
                "bar": true,
                "bar_hidden": true,
                "tooltip": "What a press on empty canvas places"
            }
        )
    )
    var snap := SaOptionSpec.make(
        &"assistants_snap",
        "Snap",
        SaOptionSpec.Kind.BOOL,
        {
            "property": ^"snap",
            "bar": true,
            "bar_hidden": true,
            "tooltip":
            "Hold every brush stroke to the assistant nearest where it starts. Off, they stay on screen and hold nothing."
        }
    )
    var colours: Array[Dictionary] = []
    for index in TINT_NAMES.size():
        colours.append({"id": index, "label": TINT_NAMES[index]})
    var tint_row := SaOptionSpec.make(
        &"assistants_tint",
        "Colour",
        SaOptionSpec.Kind.ENUM,
        {
            "choices": colours,
            "property": ^"tint",
            "bar": true,
            "bar_hidden": true,
            "tooltip": "The colour the assistants are drawn in."
        }
    )
    var dim := SaOptionSpec.make(
        &"assistants_strength",
        "Strength",
        SaOptionSpec.Kind.FLOAT,
        {
            "property": ^"strength",
            "min_value": 0.1,
            "max_value": 1.0,
            "step": 0.05,
            "bar": true,
            "bar_hidden": true,
            "tooltip": "How strongly the assistants are drawn. Lower it to see the painting through them."
        }
    )
    var concentric := SaOptionSpec.make(
        &"assistants_concentric",
        "Concentric",
        SaOptionSpec.Kind.BOOL,
        {
            "on_tool": true,
            "property": ^"concentric",
            "bar": true,
            "bar_hidden": true,
            "tooltip": "Hold a stroke starting anywhere to the ellipse of the same shape and centre through its start."
        }
    )
    var delete := SaOptionSpec.make(
        &"assistants_delete",
        "Delete Assistant",
        SaOptionSpec.Kind.ACTION,
        {
            "on_tool": true,
            "property": ^"delete_picked",
            "bar": true,
            "bar_hidden": true,
            "tooltip": "Delete the assistant last placed or moved."
        }
    )
    var clear := SaOptionSpec.make(
        &"assistants_clear",
        "Delete All",
        SaOptionSpec.Kind.ACTION,
        {"on_tool": true, "property": ^"delete_all", "bar": false, "tooltip": "Delete every assistant of the painting."}
    )
    return [shape, snap, tint_row, dim, concentric, delete, clear]


static func _flip_shown(shown: Switches) -> bool:
    shown.shown = not shown.shown
    return true


## The entries of *document*'s list, as JSON keeps them.
static func entries(document: SaDocument) -> Array:
    if document == null:
        return []
    return SaTyped.list(document.module_data.get(SaStrokeHold.GUIDES_KEY))


## *document*'s assistants of every shape, in the order they were placed.
static func guides(document: SaDocument) -> Array[Guide]:
    var out: Array[Guide] = []
    for entry: Variant in entries(document):
        var guide := Guide.of(entry)
        if guide != null:
            out.append(guide)
    return out


## *document*'s ellipses, in the order they were placed.
static func ellipses(document: SaDocument) -> Array[Ellipse]:
    var out: Array[Ellipse] = []
    for entry: Variant in entries(document):
        var ellipse := Ellipse.of(entry)
        if ellipse != null:
            out.append(ellipse)
    return out


## *document*'s assistants of *shape* alone, in the order they were placed.
static func of_shape(document: SaDocument, shape: StringName) -> Array[Guide]:
    var out: Array[Guide] = []
    for guide: Guide in guides(document):
        if guide.shape == shape:
            out.append(guide)
    return out


## *pointer* held for a stroke pressed at *from* among *others*. Until the
## pointer is [constant DECIDE] pixels from the press it stays on the press,
## and then the guide whose line through the press runs nearest it is written
## into *chosen*, its origin and direction, and holds the rest of the stroke.
static func held(others: Array[Guide], from: Vector2, pointer: Vector2, chosen: Array[Vector2]) -> Vector2:
    if chosen.is_empty():
        if pointer.distance_to(from) < DECIDE:
            return from
        var nearest: Guide = others[0]
        for guide: Guide in others:
            if guide.distance(pointer, from) < nearest.distance(pointer, from):
                nearest = guide
        chosen.append(from)
        chosen.append(nearest.direction(from))
    return chosen[0] + (pointer - chosen[0]).project(chosen[1])


## Makes *list* the document's entries, none taking the key away, so a
## document with no ruler saves the header it always had.
static func keep(document: SaDocument, list: Array) -> void:
    if document == null:
        return
    if list.is_empty():
        document.module_data.erase(SaStrokeHold.GUIDES_KEY)
    else:
        document.module_data[SaStrokeHold.GUIDES_KEY] = list.duplicate(true)
    document.modified = true


## Writes *after* as one history step named *step_name*, whose undo puts
## *before* back. The tool has already shown *after*.
static func commit(document: SaDocument, step_name: String, before: Array, after: Array) -> void:
    keep(document, after)
    if document.history != null:
        document.history.commit_pair(
            step_name, keep.bind(document, after.duplicate(true)), keep.bind(document, before.duplicate(true))
        )
