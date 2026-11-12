## Scales the view: a click zooms in about the point clicked, a Shift+click
## zooms out, and a vertical drag zooms about the point that was pressed.
##
## Goes through SaView rather than reaching sideways for the tool machine to
## refresh the brush ring: the view emits transform_changed and whoever cares
## subscribes.
##
## The zoom helper is the view's own, `SaView.zoom_at`, shared with the wheel,
## the pinch and the chords, so the zoom pins the point under the pointer. The
## screen centre instead would zoom away from a corner pressed and dragged on.
##
## A click is a notch of the wheel, the way Krita and Photoshop have it, and
## the Tool Options docker says so in a sentence. Zooming on the drag alone
## would give a click a distance of zero, a factor of one and no effect, with
## nothing saying that only an upward drag did anything.
extends ToolState

## How far the pointer may wander between the press and the release and still be
## a click, in logical pixels, the reference docker's slop.
const CLICK_SLOP: float = 4.0

## The sentence the Tool Options docker shows, since the tool has no options.
const HINT: String = "Click zooms in, Shift+click zooms out, drag up and down zooms"

var is_zooming: bool = false
var zoom_start_y: float = 0.0
var zoom_start_scale: float = 1.0
## Where the press landed, in the view's own space. Stays put while dragging.
var zoom_anchor: Vector2 = Vector2.ZERO
var zoom_sensitivity: float = 4.0
## Where the press landed on the screen, and the farthest the pointer has been
## from it since, which is what tells a click from a drag at the release.
var _pressed_at: Vector2 = Vector2.ZERO
var _farthest: float = 0.0
## Shift as the press had it. Read off the event, as `StateTransform._press`
## does, because a press a scenario injects has no key down for `Input` to find.
var _zooms_out: bool = false


## The one row the tool declares: its hint, a sentence the docker shows and the
## bar leaves out.
static func options() -> Array[SaOptionSpec]:
    return [SaOptionSpec.make_custom(&"zoom_hint", "", _build_hint, Callable(), {"bar": false})]


## The sentence in a box of its own, because the docker's row takes a bare
## `Label` child for its label column and never placed it, so it wrapped at no
## width, a letter to a line, measured on the running app.
static func _build_hint(_spec: SaOptionSpec, _write: Callable) -> Control:
    var box := VBoxContainer.new()
    var label := Label.new()
    label.name = "Hint"
    label.text = TranslationServer.translate(HINT)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(label)
    return box


func reset() -> void:
    is_zooming = false


func handle_input(event: InputEvent) -> void:
    var doc: SaDocument = document()
    var view: SaView = surface.view if surface != null else null
    if view == null:
        return

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_zooming = true
            zoom_start_y = event.global_position.y
            zoom_start_scale = view.get_zoom()
            zoom_anchor = event.position
            _pressed_at = event.global_position
            _farthest = 0.0
            _zooms_out = event.shift_pressed
        elif is_zooming:
            _farthest = maxf(_farthest, (event.global_position - _pressed_at).length())
            if _farthest <= CLICK_SLOP:
                _click()
            reset()
        return

    if not (event is InputEventMouseMotion and is_zooming):
        return

    _farthest = maxf(_farthest, (event.global_position - _pressed_at).length())
    var viewport_size := view.get_viewport_size()
    if viewport_size.y <= 0.0:
        return

    # Normalising by screen height keeps the feel identical at any resolution,
    # and the exponential keeps it relative: the same drag doubles the zoom
    # whether starting from 10% or 400%.
    var drag_dist: float = zoom_start_y - event.global_position.y
    var zoom_factor: float = exp((drag_dist / viewport_size.y) * zoom_sensitivity)
    view.zoom_at(zoom_start_scale * zoom_factor, zoom_anchor)

    # Scaling reveals chunks that were outside the visible region.
    if doc != null:
        doc.invalidate_all_allocated_chunks()


## A notch about the press, from the zoom the press found rather than the one a
## jitter inside the slop may have dragged it to, so a click is exactly one step.
func _click() -> void:
    var doc: SaDocument = document()
    var view: SaView = surface.view if surface != null else null
    view.zoom_at(SaView.Steps.next_zoom(zoom_start_scale, view.actual_pixel_zoom(), not _zooms_out), zoom_anchor)
    if doc != null:
        doc.invalidate_all_allocated_chunks()
