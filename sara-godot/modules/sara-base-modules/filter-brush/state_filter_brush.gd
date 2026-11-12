## The filter brush: where it passes, the chosen filter's result is painted
## onto the layer.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Private to the filter brush's folder, registered by its `module.gd`.
##
## This file is the gesture: the press, the path and the lift, and the one
## thing the Tool Options ask of the tool, the sentence that refuses a filter.
## The originals, the coverage and the history step are `filter_brush_stroke.gd`'s. Samples are gathered and laid
## once a frame, in `tick`, the way the liquify tool dabs once a frame, so a pen
## sending two hundred samples a second costs one filter dispatch a chunk a
## frame. The lift lays what is left before the stroke is committed.
##
## **Each sample carries the pen's pressure**, which the settings turn into how
## much of the filter's result it lays. A press carries none, so its sample
## waits for the first motion's and takes it, and a tap with no motion lays at
## a full press. A pointer that never showed a pen, a mouse, paints at one.
extends ToolState

const FilterBrushSettingsScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_settings.gd")
const FilterBrushStrokeScript = preload("res://modules/sara-base-modules/filter-brush/filter_brush_stroke.gd")

## The smallest radius the ring is drawn at, in document pixels, so a brush
## sized to nothing still shows where it is.
const RING_MIN: float = 0.05

var settings: Resource = FilterBrushSettingsScript.new().made_now()
var is_drawing: bool = false

## Why the brush cannot paint the chosen filter, or "" when it can. Asked by
## the Tool Options' note row every time they are drawn, and answered from the
## last evaluation while the filter and its parameters are the ones it was
## made for, since an evaluation runs the filter's `run`.
var filter_note: String:
    get:
        return _note()

## The stroke under way, null between strokes.
var _stroke: FilterBrushStrokeScript = null
## Where the path's last laid sample was, and the samples since, in document
## pixels.
var _last: Vector2 = Vector2.ZERO
var _pending: PackedVector2Array = PackedVector2Array()
## The pressure at the last laid sample and at each pending one, where a
## negative is the press's, not known until the first motion comes, and the
## last laid one's is negative until the stroke's first frame is laid.
var _laid_pressure: float = 1.0
var _pending_pressures: PackedFloat32Array = PackedFloat32Array()
## Whether the pointer has shown a pen since the last lift, by a pressure
## between nought and one, a tilt or the eraser end, so a pen's motion at no
## pressure lays nothing while a mouse's lays at one.
var _pen_seen: bool = false
## The refusal last answered for the note, and what it was answered for.
var _noted: String = ""
var _noted_for: Array = []


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    var button := event as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed:
            begin_stroke(get_document_mouse_position())
        elif is_drawing:
            end_stroke()
        return
    var motion := event as InputEventMouseMotion
    if motion == null:
        return
    var pressure := _pressure_of(motion)
    last_pressure = motion.pressure
    if is_drawing:
        add_sample(get_document_mouse_position(), pressure)


## Lays the samples gathered since the last frame.
func tick(_delta: float) -> void:
    _flush()


## Opens a stroke at *at*, in document pixels, on the active layer, and lays a
## dab there. Refused with a sentence on a mask, on a layer that takes no paint
## and for a filter the brush cannot paint. Public, with [method add_sample]
## and [method end_stroke], so a suite paints the stroke a pen would.
## *pressure* is the press's, negative for a press that carries none and waits
## for the first motion's, which is what a pen's press is.
func begin_stroke(at: Vector2, pressure: float = -1.0) -> void:
    var doc: SaDocument = document()
    if doc == null:
        return
    if is_drawing:
        end_stroke()
    if doc.mask_target != null:
        EventBus.paint_refused.emit(
            tr("The Filter Brush filters a layer's colour, not a mask. Select the layer in the Layers docker.")
        )
        return
    var layer := doc.active_layer
    if layer == null or SaContext.refuse_stroke(layer, tr("stroke")):
        return
    # A brush nobody handed the registry, a preset's thumbnail, has no filter
    # to look up and nobody to tell.
    if settings.context == null:
        return
    var evaluation := FilterBrushStrokeScript.evaluate(
        settings.context, settings.filter_key, settings.filter_parameters, doc, layer
    )
    if not evaluation.refusal.is_empty():
        EventBus.paint_refused.emit(evaluation.refusal)
        return
    _stroke = FilterBrushStrokeScript.new(doc, layer, evaluation)
    is_drawing = true
    _last = at
    _pending = PackedVector2Array([at])
    _pending_pressures = PackedFloat32Array([pressure])
    _laid_pressure = -1.0


## Adds *at* to the path at *pressure*, laid on the next frame or at the lift.
func add_sample(at: Vector2, pressure: float = 1.0) -> void:
    if not is_drawing:
        return
    # The press waiting for a pressure takes the first one that comes.
    for index in _pending_pressures.size():
        if _pending_pressures[index] < 0.0:
            _pending_pressures[index] = pressure
    _pending.append(at)
    _pending_pressures.append(pressure)


## Lays what is left of the path and writes the stroke as one history step.
func end_stroke() -> void:
    if not is_drawing:
        return
    _flush(true)
    is_drawing = false
    _pen_seen = false
    var stroke := _stroke
    _stroke = null
    if stroke != null:
        stroke.commit()


func reset() -> void:
    end_stroke()


## An undo under a held stroke takes the stroke back whole, so it is written
## first.
func close_session() -> bool:
    if not is_drawing:
        return false
    end_stroke()
    return true


func holds_session() -> bool:
    return is_drawing


func get_cursor_radius() -> float:
    if surface == null:
        return -1.0
    return maxf(RING_MIN, _radius())


## The brush's radius in document pixels.
func _radius() -> float:
    var doc: SaDocument = document()
    return settings.radius * (doc.brush_side if doc != null else 1080.0)


## The pressure *motion* carries: its own once the pointer has shown a pen,
## nought included, and a full press for a pointer that never has.
func _pressure_of(motion: InputEventMouseMotion) -> float:
    var touch := motion.pressure > 0.0 and motion.pressure < 1.0
    if touch or motion.tilt != Vector2.ZERO or motion.pen_inverted:
        _pen_seen = true
    if motion.pressure > 0.0:
        return motion.pressure
    return 0.0 if _pen_seen else 1.0


## Lays the samples since the last laid one, from it. A press still waiting
## for its pressure waits another frame, unless this is the *lift*, where a tap
## with no motion lays at a full press.
func _flush(lift: bool = false) -> void:
    if _stroke == null or _pending.is_empty():
        return
    if _pending_pressures.has(-1.0):
        if not lift:
            return
        _pending_pressures[_pending_pressures.find(-1.0)] = 1.0
    # The press's own sample is where the path starts, a segment of no
    # length, which lays a dab.
    var path := PackedVector2Array([_last])
    path.append_array(_pending)
    # A stroke's first frame starts from its press, whose pressure is the
    # first pending one.
    if _laid_pressure < 0.0:
        _laid_pressure = _pending_pressures[0]
    var strengths := PackedFloat32Array([settings.strength_at(_laid_pressure)])
    for pressure: float in _pending_pressures:
        strengths.append(settings.strength_at(pressure))
    _stroke.lay(path, strengths, _radius(), settings.softness, settings.soft_tip())
    _last = _pending[_pending.size() - 1]
    _laid_pressure = _pending_pressures[_pending_pressures.size() - 1]
    _pending = PackedVector2Array()
    _pending_pressures = PackedFloat32Array()


func _note() -> String:
    if settings.context == null:
        return ""
    var record := [settings.filter_key, settings.filter_parameters]
    if record != _noted_for:
        _noted_for = record
        var doc: SaDocument = document()
        var layer := doc.active_layer if doc != null else null
        var evaluated := FilterBrushStrokeScript.evaluate(
            settings.context, settings.filter_key, settings.filter_parameters, doc, layer
        )
        _noted = evaluated.refusal
    return _noted
