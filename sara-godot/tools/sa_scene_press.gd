## A press over an active scene layer, its drag and its release, handed to the
## layer's scene in place of the tool in hand, as the pointer or as a stroke.
##
## Input reaches the scene when its layer is active and the pan tool is not,
## through the same tool state machine, so a student can make the canvas a
## playable thing without touching Sara's input code. So the machine asks
## [method take] for every event it is about to hand its tool, the last stop on
## the machine's own route. Everything before it still runs first:
## the middle button and a turn move the view, the pen's barrel buttons pick
## their tool and a held Space makes the pan the tool in hand, so a painter
## who can pan over paint pans over a scene the same way.
##
## **What the scene is handed.** Its root may define
## `sara_pointer(phase: StringName, at: Vector2, pressure: float)`. *phase* is
## [constant PRESS], [constant DRAG] or [constant RELEASE], *at* is where the
## pointer is in the scene's own pixels, the viewport's: the document pixel as
## it is on a layer drawn where it was painted, and taken back through the
## layer's live transform on one drawn through a map, so a scene that draws
## where it is pressed draws under the pointer. *pressure* is the pen's from 0 to 1. A press carries the pressure
## of the motion that came with it, which a pen's driver sends just before the
## press, and 1 when none did, which is a mouse's. A motion of the drag carries
## its own, and the release the last the drag had. A drag that leaves the
## document goes on, with points outside it. A hover is never handed, since
## the tool reads it to tell a pen from a mouse.
##
## **A brush's stroke.** The spec again: "a scene may ask for the strokes as
## input and decide itself what a stroke means, particles that emit where the
## brush goes, walls in a physics scene, water that ripples under it." So the
## root may define `sara_stroke(phase: StringName, at: Vector2, pressure: float,
## radius: float, color: Color)` as well, and while a brush is in hand the same
## press, drag and release reach it there instead, in the same three phases
## with the same points and pressures, as they are painted. A brush is a
## painting tool that draws the brush ring, the stamp brush, its eraser and the
## noise brush, and not the fill or the gradient, which have no tip. *radius* is
## the brush's ring, the one the cursor draws, in the scene's pixels as *at* is, and *color* is the
## colour it paints, opaque, both fixed at the press as the brush fixes its own
## route there. An erasing stroke, the eraser, the brush's E toggle or the pen's
## eraser end, carries its colour at alpha 0, the colour an eraser leaves, which
## no colour a painter picks is, so the scene decides what taking away means.
## The points are the pen's, before the brush's stabiliser and its dabs,
## because nothing of the brush runs: the layer stays the scene's own pixels and
## Sara lays nothing on it. A root that defines both methods is handed a brush's
## press as a stroke and any other tool's as the pointer.
##
## **When.** The left press is the scene's while the document's active layer
## is a scene layer whose root defines the method the tool in hand calls for,
## and that tool is not a navigation tool, which is a descriptor of the
## `navigate` category, the pan and the zoom, rather than a list of ids, nor
## one of the `transform` category, which moves the layer itself. The
## drag and the release after it go to the same scene whatever changes
## meanwhile, and the tool hears none of the three, so a brush says nothing
## about a layer that refuses paint. A root with neither method is handed
## nothing, and the brush is refused on its layer. A root with only
## `sara_pointer` is handed a brush's press as the pointer.
##
## Private to the tools package, beside the machine as `SaShiftPress` is.
## **Static because there is one pointer** and a machine per surface, the
## reason the machine's pointer holder is static: a press one surface's scene
## took is let go by the release, wherever it lands.
class_name SaScenePress
extends RefCounted

## The method a scene's root defines to be handed the pointer.
const METHOD := &"sara_pointer"
## The method a scene's root defines to be handed a brush's strokes.
const STROKE_METHOD := &"sara_stroke"
## The three phases, as words a scene's script compares without naming a class
## of the skeleton's.
const PRESS := &"press"
const DRAG := &"drag"
const RELEASE := &"release"
## The category whose tools move the view and so never reach a scene.
const NAVIGATE := &"navigate"
## The category whose tools move the layer, the Transform tool's, which a
## scene layer takes as a paint layer does, and so never reach a scene.
const TRANSFORM := &"transform"

## The instance id of the scene stage that took the left press now down, and 0
## while none did.
static var _holder: int = 0
## The pressure of the last motion heard in the air, which the press takes.
static var _hovered: float = 0.0
## The pressure the press now held last reported.
static var _pressure: float = 1.0
## Whether the last motion heard in the air came from the pen's eraser end.
static var _inverted: bool = false
## Whether the press now held is a brush's stroke, handed to
## [constant STROKE_METHOD], and the brush's radius and colour it carries.
static var _stroke: bool = false
static var _radius: float = 0.0
static var _color: Color = Color.BLACK


## Takes *event* when it belongs to a press a scene layer's scene takes, hands
## it to the scene and answers true, so *machine* keeps it from the tool.
static func take(event: InputEvent, machine: ToolMachine) -> bool:
    var motion := event as InputEventMouseMotion
    if motion != null:
        var holding := _held()
        if holding == null:
            _hovered = motion.pressure
            _inverted = motion.pen_inverted
            return false
        if motion.pressure > 0.0:
            _pressure = motion.pressure
        _hand(holding, DRAG, machine)
        return true
    var button := event as InputEventMouseButton
    if button == null or button.button_index != MOUSE_BUTTON_LEFT:
        return false
    if not button.pressed:
        var holding := _held()
        _holder = 0
        _hovered = 0.0
        if holding == null:
            return false
        _hand(holding, RELEASE, machine)
        return true
    var stage := _listening(machine)
    _holder = stage.get_instance_id() if stage != null else 0
    if stage == null:
        return false
    _pressure = _hovered if _hovered > 0.0 else 1.0
    _hand(stage, PRESS, machine)
    return true


## Lets go of a held press without a word to its scene, for a suite that ends
## with one down.
static func drop() -> void:
    _holder = 0
    _hovered = 0.0
    _pressure = 1.0
    _inverted = false
    _stroke = false


## The stage whose root a left press over *machine*'s canvas goes to now, or
## null when the press is the tool's, and whether it goes as a stroke.
static func _listening(machine: ToolMachine) -> SaSceneLayer:
    var document: SaDocument = machine.surface.get_document() if machine.surface != null else null
    var layer: SaLayer = document.active_layer if document != null else null
    if layer == null or not layer.is_scene():
        return null
    var descriptor := machine.get_descriptor(machine.active_tool_name)
    if descriptor != null and descriptor.category in [NAVIGATE, TRANSFORM]:
        return null
    var stage := layer.get_node_or_null(SaSceneLayer.NODE_NAME) as SaSceneLayer
    if stage == null or not is_instance_valid(stage.root):
        return null
    var brush := descriptor != null and descriptor.is_painting and descriptor.wants_brush_cursor
    _stroke = brush and stage.root.has_method(STROKE_METHOD)
    if _stroke:
        _radius = _scene_radius(layer, _at(machine), machine.active_tool.get_cursor_radius())
        _color = _brush_color(machine.active_tool)
        return stage
    return stage if stage.root.has_method(METHOD) else null


## Hands *phase* of the press *stage* holds to its root, as the pointer or as
## the stroke the press began.
static func _hand(stage: SaSceneLayer, phase: StringName, machine: ToolMachine) -> void:
    var at := _scene_point(stage, _at(machine))
    if _stroke:
        stage.root.call(STROKE_METHOD, phase, at, _pressure, _radius, _color)
    else:
        stage.root.call(METHOD, phase, at, _pressure)


## The colour *tool* paints, opaque, or at alpha 0 while it erases. Read off its
## settings by name, as the machine hands them over, because the brush is a
## module's and the skeleton names none of its classes, and the foreground for
## a tool whose settings carry no colour.
static func _brush_color(tool: ToolState) -> Color:
    var settings := tool.get(&"settings") as Object
    var picked: Variant = settings.get(&"color") if settings != null else null
    var color: Color = picked if picked is Color else SaColors.foreground
    var mode: Variant = settings.get(&"blend_mode") if settings != null else null
    var erasing: bool = _inverted or tool.get(&"eraser_toggled") == true or mode == SaLayer.BLEND_MODE.ERASE
    return Color(color, 0.0 if erasing else 1.0)


## The stage that took the press now down, while it and its root still stand.
static func _held() -> SaSceneLayer:
    if _holder == 0:
        return null
    var stage := instance_from_id(_holder) as SaSceneLayer
    if stage == null or not is_instance_valid(stage.root):
        return null
    return stage


## Where the pointer is in document pixels, read the way a tool reads it.
static func _at(machine: ToolMachine) -> Vector2:
    var view: SaView = machine.surface.view if machine.surface != null else null
    return view.get_document_mouse_position() if view != null else Vector2.ZERO


## *point*, a document pixel, in the pixels of the scene *stage* draws: taken
## back through its layer's live transform when the layer has one, and as it is
## when it has none. A point the map puts outside the scene is answered all the
## same, so a drag that leaves the scene still ends with its release.
static func _scene_point(stage: SaSceneLayer, point: Vector2) -> Vector2:
    var live := SaLocalView.map_of(stage.get_parent() as SaLayer)
    return live.unmap_point(point) if live != null else point


## *radius*, in document pixels about *point*, in the scene's pixels of
## *layer*: the radius of the circle whose area the live transform takes the
## ring to at that point, which is the radius itself under a move or a turn and
## the radius over the scale under a scale. Unchanged with no live transform.
static func _scene_radius(layer: SaLayer, point: Vector2, radius: float) -> float:
    var live := SaLocalView.map_of(layer)
    if live == null or radius <= 0.0:
        return radius
    var centre := live.unmap_point(point)
    var across := live.unmap_point(point + Vector2(radius, 0.0)) - centre
    var down := live.unmap_point(point + Vector2(0.0, radius)) - centre
    return sqrt(absf(across.cross(down)))
