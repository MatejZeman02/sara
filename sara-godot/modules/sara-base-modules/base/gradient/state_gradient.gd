## The gradient tool: drag on the canvas and the layer fills with a ramp from
## the foreground colour at the press to the background colour at the
## release, inside the selection when there is one.
##
## The ramp itself is `sa_gradient.gd` beside this file, one chunk at a time on
## the GPU. This holds the options, the drag, and the live preview: every motion
## repaints the stroke buffer, which the compositor already shows over the
## active layer, so the painter sees the ramp before committing to it and the
## layer is not touched until the pen lifts.
##
## The colours are an `SaColorRamp` of any number of stops rather than the
## foreground and the background, and the tool's fourth option is the ramp
## itself. It opens holding the two picked colours, one at each end, and it
## stops following the picker the moment a painter edits it: a ramp that reset
## itself whenever the foreground changed would throw away the edit that
## changing the foreground was for.
##
## **An edit is not for the tool's life.** Were it, a stop edited or a gradient
## loaded in one document would leave every later drag on colours long since
## changed, with nothing on screen saying so. Choosing one of the library's
## stock gradients puts the ramp back on following, through
## [method follow_stock], and the ramp row says which of the two the ramp is.
##
## **The ends stay after the release.** The release lays the ramp as one
## history step, and two round handles stay on its ends: a
## press on one drags that end with the preview following, and its release lays
## the ramp again under the same step. A changed option or stop lays it again
## too. Enter, a press away from both, a tool switch, another layer, a save or
## any other step let the ends go and leave the ramp as it is, and Escape takes
## it back off. Laid at once rather than held in the preview until Enter,
## because a held ramp is a picture the document does not have: a save would
## write the file without it and a filter would run on the layer under it, and
## both of those run through doors no tool is asked at.
extends ToolState

## The ramp started or stopped following the picked pair, *following* being
## which. The ramp row's option names this signal rather than the ramp, so its
## binder is handed the tool the signal belongs to: the row says whether the ramp
## follows and calls [method follow_stock], and a ramp alone knows neither. The
## same door the stamp brush's tip preview finds its tool through.
signal following_changed(following: bool)

## By path rather than by `class_name`, because the pass sits beside this file
## and a module's own files are reached the way its tests reach them.
const SaGradientScript = preload("res://modules/sara-base-modules/base/gradient/sa_gradient.gd")

## How near an end a press has to land to take it, in screen pixels. The
## transform's reach, because a grab is a gesture of the hand and not of the
## picture.
const HANDLE_REACH: float = 10.0

## How far the hand has to go from the end it moves before the end follows, in
## screen pixels. Within it a reading leaves the end where it stands, and past
## it the end goes to the hand exactly, so a moving hand is followed with no
## lag.
##
## **A hand held still still moves the pointer.** A pen streams its place every
## few milliseconds while it is in range, each a little off the last, and a
## driver that rounds the pen to whole pixels flips between two neighbours,
## straight or diagonal, which one and a half pixels takes in. Moving the end
## on every reading would dispatch a preview for each, dozens of them under a
## hand that has not moved, with the end going back and forth between two
## places and the release laying the ramp at whichever the last reading said.
## That is the gradient drifting under a still hand. A mouse sends nothing
## while it is still, so only a pen reaches this.
const STILL_REACH: float = 1.5

## Which end of a laid ramp a press took: neither, the press end or the release
## end.
enum End { NONE, FROM, TO }

## Linear or radial, an `SaGradientScript.Shape`. The `gradient_shape` option.
var shape: int = SaGradientScript.Shape.LINEAR
## What happens past the release point, an `SaGradientScript.Repeat`. The
## `gradient_repeat` option.
var repeat: int = SaGradientScript.Repeat.NONE
## How many bands `Repeat.STEPS` cuts the ramp into. The `gradient_steps`
## option, and it means nothing under the other three repeats.
var steps: int = 5
## Which wobble pushes the ramp off its axis, an `SaGradientScript.Wobble`. The
## `gradient_wobble` option.
var wobble: int = SaGradientScript.Wobble.NONE
## How far that wobble pushes, in ramp units. The `gradient_wobble_amount`
## option, and it means nothing while the wobble is off.
var wobble_amount: float = 0.3
## Whether the ramp replaces what is under it, alpha and all, rather than
## compositing over it. The `gradient_replace` option.
var replace: bool = false

## The rule for the ramp's two ends and the alphas they remember. The
## module's one object, which the tool machine hands every surface's instance
## as the descriptor's `shared_settings`: a gradient on the scratchpad
## remembers into the same preferences as one on the canvas. A bare one until
## then, which opens opaque and remembers nothing, for a state a test builds.
var settings: SaGradientEnds = SaGradientEnds.new()

## The colours the drag lays down, which the `gradient_ramp` row edits. Built on
## first use rather than in a constructor, because a tool state is made before
## `SaColors` has necessarily settled and because the two picked colours are the
## default rather than a snapshot: see [method ramp].
var _ramp_colors: SaColorRamp = null

## A motion has moved the far end since the last preview was dispatched.
var _preview_pending: bool = false

## Whether the ramp follows the picked pair or has been edited. While it follows
## it is re-seeded from the picker on every read, so a painter who picks a colour
## and then drags gets the colour they picked. An edit ends it and a stock
## gradient chosen in the library starts it again.
var ramp_is_default: bool = true

## The button is down on a new ramp, which previews and is not laid yet.
var _dragging: bool = false
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
## The layer the drag under way or the held ramp is on, and its document.
var _layer: SaLayer = null
var _ramp_in: SaDocument = null
## A laid ramp whose ends can still be moved. Its step is the last one of
## [member _ramp_in], whose history stood at [member _held_at] once it was
## written.
var _held: bool = false
var _held_at: int = 0
## The end the button is down on, while one is.
var _grabbed: End = End.NONE
## The options and stops the held ramp was last laid with, so a change to any
## of them lays it again.
var _laid_key: Array = []
## The same for the preview, so a change during a drag previews again without
## waiting for the pointer to move.
var _previewed_key: Array = []
## The skeleton's gradient pass, which is what actually dispatches the kernel.
## Named for what it is rather than "the ramp", because the ramp is the colours
## and this is the machinery.
var _pass: SaGradientScript = null
## The document `_pass` was built for, so a new document gets a new pass rather
## than one holding the old one's compositor.
var _pass_document: SaDocument = null

## The ramp this tool draws. Seeded from the foreground and the background, and
## re-seeded from them on every read until something edits it, which is what
## makes "the default when opened is the two selected colors on each end" true
## whenever the painter opens the tool rather than only the first time.
var ramp: SaColorRamp:
    get:
        if _ramp_colors == null:
            _ramp_colors = settings.fresh_ramp(SaInHand.Pair.foreground(), SaInHand.Pair.background())
            _ramp_colors.changed.connect(_on_ramp_changed)
        elif ramp_is_default:
            _refresh_default_ramp()
        return _ramp_colors
    set(value):
        if value == null:
            return
        if _ramp_colors != null and _ramp_colors.changed.is_connected(_on_ramp_changed):
            _ramp_colors.changed.disconnect(_on_ramp_changed)
        _ramp_colors = value
        _ramp_colors.changed.connect(_on_ramp_changed)
        _stop_following()


func _init() -> void:
    if not EventBus.document_color_space_changed.is_connected(warm_at):
        EventBus.document_color_space_changed.connect(warm_at)
    # Sara's first document sets its space before the machine builds any tool,
    # so the bus has spoken by the time this listens. One idle later the machine
    # has handed the tool its surface and its roles, and the pass is warmed then.
    warm.call_deferred()


## Builds the gradient's kernel at the depth of the document this tool paints,
## through the pass the drag will use, so the first move waits for neither the
## compile nor the pipeline. A tool with no document yet, as a suite builds
## one, has nothing to build for.
func warm() -> void:
    var doc: SaDocument = document()
    if doc == null or GlobalShaderCompiler.get_rd() == null:
        return
    _pass_for(doc).warm()


## Builds the gradient's kernel at the depth *changed* declares when it is
## this tool's own document, which has just opened or changed its depth, the
## way the brush's `warm_at` does. A document behind another tab builds
## nothing. The build goes through an object of its own rather than this
## tool's pass, which [method warm] keeps.
func warm_at(changed: SaDocument) -> void:
    if changed != null and surface != null and changed == surface.get_document():
        SaGradientScript.warm_at(changed.color_space.texel_format())


## An edit stops the ramp following the picker, until a stock gradient is
## chosen.
func _on_ramp_changed() -> void:
    _stop_following()


func _stop_following() -> void:
    if not ramp_is_default:
        return
    ramp_is_default = false
    following_changed.emit(false)


## Puts the ramp back on following the picked pair as the library's stock
## gradient *stock* lays it, an `SaGradientEnds` stock id, and answers whether
## *stock* named one. What the ramp row's stock rows call: the ramp is reshaped
## in place, so the row and a drag already under way keep the object they hold.
##
## Following again even when the ramp already follows, because choosing
## Foreground to Transparent on a ramp following Foreground to Background is a
## change of its far end.
func follow_stock(stock: StringName) -> bool:
    if not settings.restock(ramp, stock, SaInHand.Pair.foreground(), SaInHand.Pair.background()):
        return false
    ramp_is_default = true
    following_changed.emit(true)
    return true


## Puts the current pair back on the untouched ramp, without going through the
## setter and without announcing an edit.
##
## Through `SaGradientEnds` rather than by writing the stops: the ends also carry the
## remembered alphas, and doing the colours here and the alphas there is how the
## second half ends up forgotten.
func _refresh_default_ramp() -> void:
    settings.reseed(_ramp_colors, SaInHand.Pair.foreground(), SaInHand.Pair.background())


## Leaving the tool lays a drag under way and lets the ends go, the ramp
## staying as it is. A document rebuilt under the tool takes nothing: what it
## held went with the old one.
func reset() -> void:
    _let_go_if_edited()
    finish()


## Enter lets the ends go and Escape takes the ramp back off, a press on an end
## drags it, a press anywhere else starts the next ramp, and a release lays
## whatever the drag was moving.
func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    _let_go_if_edited()
    var key := event as InputEventKey
    if key != null:
        if key.pressed and not key.echo:
            if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
                finish()
            elif key.keycode == KEY_ESCAPE:
                cancel()
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            _press(get_document_mouse_position())
        else:
            _release(get_document_mouse_position())
        return
    if event is InputEventMouseMotion and (_dragging or _grabbed != End.NONE):
        move_to(get_document_mouse_position())


## Moves the end under the hand, the release end of a new drag. The preview
## follows on the next tick rather than here, because a tablet sends a motion
## event every few milliseconds and the preview is the ramp over every chunk of
## the canvas: dispatched per event it lagged the whole computer. One a frame
## is all a painter can see anyway.
##
## A place within [constant STILL_REACH] of the end is the hand held still, and
## moves nothing and previews nothing.
func move_to(at: Vector2) -> void:
    if _held_still(at, _from if _grabbed == End.FROM else _to):
        return
    if _grabbed == End.FROM:
        _from = at
    else:
        _to = at
    _preview_pending = true


## Whether *at* is within [constant STILL_REACH] screen pixels of *end*.
func _held_still(at: Vector2, end: Vector2) -> bool:
    var view: SaView = surface.view if surface != null else null
    return at.distance_to(end) < STILL_REACH / maxf(view.get_zoom() if view != null else 1.0, 0.01)


## The frame's one dispatch: the preview when a motion or an option asked for
## one since the last, or the held ramp laid again when an option or a stop has
## changed under it.
func tick(_delta: float) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    _let_go_if_edited()
    if _held and _grabbed == End.NONE:
        if _key() != _laid_key:
            _relay()
        return
    if not (_dragging or _grabbed != End.NONE):
        return
    var key := _key()
    if not _preview_pending and key == _previewed_key:
        return
    _preview_pending = false
    _previewed_key = key
    _pass_for(doc).preview(_from, _to, ramp, shape, repeat, _wobble())


## Lays a ramp from *from* to *to* in one call, with no pointer. What a test
## and a capture step reach for, the way the wand offers `flood`.
func draw_between(from: Vector2, to: Vector2) -> bool:
    finish()
    _from = from
    return draw_to(to)


## Ends the drag at *to*: the preview comes off and the ramp goes down as one
## history step, on the layer the drag began on, or the active one when no
## drag did.
func draw_to(to: Vector2) -> bool:
    var doc: SaDocument = document()
    _to = to
    _preview_pending = false
    if doc == null:
        return false
    var gradient_pass := _pass_for(doc)
    gradient_pass.clear_preview()
    var layer := _layer if _layer != null else doc.active_layer
    return gradient_pass.apply(layer, _from, _to, ramp, shape, repeat, replace, _wobble())


## Ends the ramp where it stands: a drag under way is laid, a held end is laid
## where it was let go, and the ends are let go. What Enter, a tool switch and
## a press away from both ends come to. True when a step was written, which a
## held ramp's already was at its release.
func finish() -> bool:
    var wrote := false
    if _dragging:
        _dragging = false
        wrote = draw_to(_to)
    elif _grabbed != End.NONE:
        _grabbed = End.NONE
        _relay()
    _let_go()
    return wrote


## An undo or a redo finishes the ramp first, the way it closes a transform,
## so the undo takes the ramp back whole rather than the step under it.
func close_session() -> bool:
    return finish()


## Takes the ramp back off: a drag under way is dropped with nothing laid, and
## a held ramp's step is undone, so the layer is what it was before the drag.
## The undone step waits on the redo list, where Ctrl+Shift+Z finds it.
func cancel() -> void:
    var doc: SaDocument = document()
    if _dragging:
        _dragging = false
        _pass_for(doc).clear_preview()
    elif _held:
        if _grabbed != End.NONE:
            # Laid first, so the redo the undo leaves is the ramp on screen and
            # not the layer the grab had taken it off.
            _grabbed = End.NONE
            _relay()
        _let_go()
        doc.undo()
    _layer = null
    _ramp_in = null


## The two ends and the line between them, while a drag is under way or a laid
## ramp's ends can still be moved, in the selection overlay's `rings`. Empty
## otherwise, which is also what tells the shortcut router that an Escape is
## not this tool's.
func preview_shape() -> Dictionary:
    if not (_dragging or _held):
        return {}
    return {"rings": PackedVector2Array([_from, _to]), "joined": true}


## Which end of the held ramp *at* is on, within [constant HANDLE_REACH]
## screen pixels: the nearer one, and the release end when the two sit together,
## since that is the end a drag most often moves next.
func end_under(at: Vector2) -> End:
    var view: SaView = surface.view if surface != null else null
    if not _held:
        return End.NONE
    var reach := HANDLE_REACH / maxf(view.get_zoom() if view != null else 1.0, 0.01)
    var to_far := at.distance_to(_to)
    var from_far := at.distance_to(_from)
    if to_far <= reach and to_far <= from_far:
        return End.TO
    if from_far <= reach:
        return End.FROM
    return End.NONE


## The three numbers the kernel wants that are not the ramp or the shape, in
## the one dictionary the pass takes them in.
func _wobble() -> Dictionary:
    return {"steps": steps, "kind": wobble, "amount": wobble_amount}


## Everything a lay reads besides the two ends, so a change to any of it is
## seen. The ramp's stops are read through [member ramp], which re-seeds a
## following ramp from the picker, so a colour picked while the ends are held
## lays the ramp again in it.
func _key() -> Array:
    return [shape, repeat, steps, wobble, wobble_amount, replace, ramp.to_array()]


func _press(at: Vector2) -> void:
    var doc: SaDocument = document()
    if _held:
        var end := end_under(at)
        if end != End.NONE:
            _grab(end)
            return
        finish()
    var layer := doc.active_layer
    if layer == null or SaContext.refuse_stroke(layer, tr("gradient")):
        return
    _dragging = true
    _layer = layer
    _ramp_in = doc
    _from = at
    _to = at
    # A press alone previews nothing, as it never did: a ramp from a point to
    # itself is the far colour over the whole canvas, a flash and not a ramp.
    _previewed_key = _key()
    # The stroke buffer is the preview's canvas, so the drag opens a stroke the
    # way a brush does. Nothing ever commits it: the ramp lands on the layer
    # itself and the buffer is dropped on release.
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)


## The button is up: a new drag is laid as its step and its ends are held, and
## a dragged end is laid again under the step it already has. A release within
## [constant STILL_REACH] of the end lays the ramp where the end stands, since
## a pen slides a little as it lifts.
func _release(at: Vector2) -> void:
    if _grabbed != End.NONE:
        move_to(at)
        _grabbed = End.NONE
        _relay()
    elif _dragging:
        _dragging = false
        if draw_to(_to if _held_still(at, _to) else at):
            _held = true
            _held_at = _position()
            _laid_key = _key()
        else:
            _layer = null


## Takes *end* of the held ramp: the ramp comes back off the layer and the
## preview shows it instead while the end moves, so a motion dispatches the
## preview and nothing else. A layer locked since the release lets the ends go.
func _grab(end: End) -> void:
    var doc: SaDocument = document()
    if SaContext.refuse_stroke(_layer, tr("gradient")):
        _let_go()
        return
    _grabbed = end
    _pass_for(doc).take_back(_layer)
    doc.begin_stroke(1.0, SaLayer.BLEND_MODE.NORMAL)
    # The layer has just given the ramp back, so the preview has to show it
    # this frame, motion or none.
    _previewed_key = _key()
    _preview_pending = true


## The held ramp laid again with the ends and the options as they are now.
func _relay() -> void:
    var doc: SaDocument = document()
    _laid_key = _key()
    var gradient_pass := _pass_for(doc)
    gradient_pass.clear_preview()
    gradient_pass.relay(_layer, _from, _to, ramp, shape, repeat, replace, _wobble())


## Lets the ends go when the document moved on under them by any door but this
## tool's: another step or an undo the tool was not asked to close for, a save,
## another layer made active, or another document. The ramp stays as laid,
## which is the picture those found. A drag on an end is laid first where the
## step it belongs to is still the one the document stands on.
func _let_go_if_edited() -> void:
    var doc: SaDocument = document()
    if not (_held or _dragging):
        return
    if doc != _ramp_in or not is_instance_valid(_layer):
        # Another document: what the tool held went with the old one, preview
        # and all.
        _dragging = false
        _let_go()
        return
    if not _held:
        return
    var same_step := _position() == _held_at
    if same_step and doc.active_layer == _layer and doc.modified:
        return
    if same_step and _grabbed != End.NONE:
        _grabbed = End.NONE
        _relay()
    _let_go()


func _let_go() -> void:
    _held = false
    _grabbed = End.NONE
    _layer = null
    _ramp_in = null
    _laid_key = []


## Where the history stands, as `SaHistory.position` says: a serial that
## differs whenever the document has moved on by any step, undone or redone.
func _position() -> int:
    var doc: SaDocument = document()
    return doc.history.position() if doc != null and doc.history != null else 0


## What a capture's state dump says about the ramp, which a shot cannot: whether
## its ends are held, which one the button is on, and where both are.
func capture_report(tool_name: StringName, active: bool) -> Dictionary:
    if not active:
        return {}
    return {
        "gradient":
        {
            "tool": String(tool_name),
            "dragging": _dragging,
            "held": _held,
            "grabbed": ["none", "from", "to"][_grabbed],
            "from": [_from.x, _from.y],
            "to": [_to.x, _to.y],
            "previews": _pass.previews if _pass != null else 0,
        }
    }


## The gradient engine under the `gradient` role when the machine handed
## this tool the registries, and the module's own class when nothing did.
func _pass_for(for_document: SaDocument) -> SaGradientScript:
    if _pass == null or _pass_document != for_document:
        _pass = (roles.script_for(&"gradient") if roles != null else SaGradientScript).new(for_document)
        _pass_document = for_document
    return _pass
