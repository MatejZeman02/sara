## What the White Point filter hands its page: the eyedropper that picks the
## colour which should be neutral, Auto, which finds it in the whole picture,
## and a swatch and a caption showing the one picked or found.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## One `ui.custom` row. The eyedropper is Levels' own, `SaLevelsSampler` armed
## as its white one: a press puts the Eyedropper in the painter's hand through
## the door's `SaPickHold`, and the next click on the canvas says where it
## landed. `SaWhitePointSquare` then reads what this White Point filters there,
## the active layer's paint in the Filter menu's dialog and the record's input
## for an attached one, averaged over the square the Eyedropper tool's Sample
## size names, as Resolve's white balance picker averages the box it is dragged
## over. That is one copy and read back a click, the read back hard rule 1
## allows a pick, and never a second one of this panel's own.
##
## The mean is light-linear sRGB, which is what the record keeps, so the swatch
## shows the colour as the canvas does and the caption names it the way a hex
## field would.
##
## Auto, beside the eyedropper, reads the same thing the eyedropper does, but
## all of it: `SaWhitePointEstimate` sums it on the GPU from its surfaces or
## from its edges, as the choice beside the button says, and the colour it
## finds is written exactly as a pick is. So the swatch, the Strength and a
## later pick work on it unchanged, and a saved document keeps the colour found
## rather than finding it again. The choice is the panel's and is not saved.
class_name SaWhitePointPanel
extends VBoxContainer

## A pick landed, and the filter should take [member picked] and run again.
signal changed

## Which of the sampler's eyedroppers this one is.
const KIND := "white"

const EYEDROPPER_HINT := (
    "Pick a colour on the canvas that should be neutral grey, averaged over the Eyedropper tool's Sample size."
    + " Click it again to put it away."
)
const SWATCH_HINT := "The colour picked or found, which the filter turns into a grey of its own luminance."
const AUTO_HINT := "Find the cast in the whole picture, the way the choice beside it says, and take it out."
const FROM_HINT := "How Auto finds the cast: from the surfaces, whose colours it takes to average to grey, or from the edges."

## What the corner says when Auto finds nothing it may count.
const NOTHING_FOUND := "Auto found nothing to read, every texel empty, too dark or clipped, so the colour stays as it was."

## What Auto's choice offers, in `SaWhitePointEstimate.From`'s order, and the
## caption that says what each found, whole sentences so a translation can
## order them as its language does.
const FROM_LABELS: Array[String] = ["From surfaces", "From edges"]
const FROM_CAPTIONS: Array[String] = [
    "Found %s from the surfaces. It becomes neutral grey at %.3f.",
    "Found %s from the edges. It becomes neutral grey at %.3f.",
]
## The names the `filter` step's door takes for the two ways.
const FROM_KEYS: Array[String] = ["surfaces", "edges"]

## How wide and how tall the swatch stands, in logical units.
const SWATCH_WIDTH := 48
const SWATCH_HEIGHT := 24

## The colour picked, light-linear sRGB, NAN in every channel for none.
var picked: Vector3 = Vector3(NAN, NAN, NAN)

## A context listing the surfaces, which says where the main canvas is. Null in
## a suite, where a pick is handed a place rather than clicked.
var _surfaces: SaContext = null
var _sampler := SaLevelsSampler.new()
var _square := SaWhitePointSquare.new()
var _eyedropper: Button = null
var _auto: Button = null
var _from: SaChoiceButton = null
var _swatch: ColorRect = null
var _caption: Label = null
## The armed eyedropper said there was nothing to read, once an arming.
var _told_nothing_there: bool = false


## The panel, with *surfaces* the context the filter was handed.
func _init(surfaces: SaContext = null) -> void:
    _surfaces = surfaces
    name = "WhitePointPanel"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(8))

    var line := HBoxContainer.new()
    line.name = "PickLine"
    line.add_theme_constant_override("separation", SaUI.px(8))
    add_child(line)
    var label := Label.new()
    label.name = "PickLabel"
    label.text = tr("Neutral colour")
    label.tooltip_text = tr(EYEDROPPER_HINT)
    label.mouse_filter = Control.MOUSE_FILTER_STOP
    line.add_child(label)

    _eyedropper = Button.new()
    _eyedropper.name = "WhitePointEyedropper"
    _eyedropper.icon = SaUI.get_icon("colorpick")
    _eyedropper.toggle_mode = true
    SaTheme.make_toggle(_eyedropper)
    _eyedropper.focus_mode = Control.FOCUS_NONE
    _eyedropper.tooltip_text = tr(EYEDROPPER_HINT)
    _eyedropper.pressed.connect(arm_eyedropper)
    line.add_child(_eyedropper)

    _auto = Button.new()
    _auto.name = "WhitePointAuto"
    _auto.text = tr("Auto")
    _auto.tooltip_text = tr(AUTO_HINT)
    _auto.focus_mode = Control.FOCUS_NONE
    _auto.pressed.connect(_on_auto_pressed)
    line.add_child(_auto)

    _from = SaChoiceButton.new()
    _from.name = "WhitePointAutoFrom"
    _from.tooltip_text = tr(FROM_HINT)
    # The words are the choice, so it takes the room the line has left rather
    # than shrinking to an arrow, as Levels' channel choice does.
    _from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var ways: Array = []
    for way in FROM_LABELS.size():
        ways.append({"id": way, "label": tr(FROM_LABELS[way])})
    _from.set_choices(ways)
    _from.select_value(SaWhitePointEstimate.From.SURFACES)
    line.add_child(_from)

    _swatch = ColorRect.new()
    _swatch.name = "PickedSwatch"
    _swatch.custom_minimum_size = Vector2(float(SaUI.px(SWATCH_WIDTH)), float(SaUI.px(SWATCH_HEIGHT)))
    _swatch.tooltip_text = tr(SWATCH_HINT)
    _swatch.draw.connect(_draw_frame)
    line.add_child(_swatch)

    _caption = Label.new()
    _caption.name = "PickedCaption"
    _caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_caption, "text_muted")
    add_child(_caption)

    _sampler.armed_changed.connect(_on_armed_changed)
    _sampler.sampled.connect(_on_sampled)
    show_picked(picked)


## Shows *colour*, light-linear sRGB, as the one picked, with nothing announced,
## since it is what the filter already holds. *found_from*, a way of
## `SaWhitePointEstimate.From`, says Auto found it that way, and -1 that it was
## picked or held.
func show_picked(colour: Vector3, found_from: int = -1) -> void:
    picked = colour if colour.is_finite() else Vector3(NAN, NAN, NAN)
    if not picked.is_finite():
        _swatch.color = Color(0.0, 0.0, 0.0, 0.0)
        _caption.text = tr("Nothing picked yet. Press the eyedropper and click a colour that should be grey.")
        return
    var shown := display_colour(picked)
    _swatch.color = shown
    if not SaWhitePointFilter.can_neutralise(picked):
        _caption.text = (
            tr("Picked %s, too dark to set a white point by, so the document's white is kept.") % ("#" + shown.to_html(false))
        )
        return
    var luminance := SaWhitePointFilter.luminance(picked)
    if found_from >= 0 and found_from < FROM_CAPTIONS.size():
        _caption.text = tr(FROM_CAPTIONS[found_from]) % ["#" + shown.to_html(false), luminance]
        return
    _caption.text = tr("Picked %s. It becomes neutral grey at %.3f.") % ["#" + shown.to_html(false), luminance]


## Light-linear sRGB *colour* as the screen shows it, on sRGB's curve. The
## swatch alone is clipped, by the display, and never the colour kept.
static func display_colour(colour: Vector3) -> Color:
    return Color(colour.x, colour.y, colour.z, 1.0).linear_to_srgb()


## Arms the eyedropper over the main canvas, or puts it away when it is armed,
## as its button's press does.
func arm_eyedropper() -> void:
    if not _sampler.kind.is_empty():
        _sampler.disarm()
        return
    var surface := main_surface()
    _sampler.arm(KIND, surface.tool_machine if surface != null else null, get_window() if is_inside_tree() else null)


## The pick at *at*, in document coordinates: the colour this White Point reads
## there, averaged over the Eyedropper tool's Sample size, taken as the one
## that should be neutral, as one change. False, and nothing moves, where
## nothing is painted.
func sample_at(at: Vector2) -> bool:
    var subject := _subject()
    if subject.is_empty():
        return false
    return take_pick(subject[0], subject[1], at)


## The pick at *at* of *node* of *document*, the node null for the document's
## root, which [method sample_at] hands its subject to, and a suite with no
## canvas calls itself.
func take_pick(document: SaDocument, node: SaLayer, at: Vector2) -> bool:
    var input := SaNodeInput.new(document, node)
    var colour := _square.read(input, at, document.canvas_size, document.color_space, SaWhitePointSquare.side())
    if not colour.is_finite():
        return false
    show_picked(colour)
    changed.emit()
    return true


## Auto's press: the colour the whole of what this White Point reads says
## should be neutral, found the way *from* names, a way of
## `SaWhitePointEstimate.From`, and taken as a pick is, as one change. False,
## with a word in the corner, and nothing moves, when nothing there can be
## counted.
func find_cast(from: Variant) -> bool:
    var way := int(from) if from is int else int(SaWhitePointEstimate.From.SURFACES)
    var subject := _subject()
    var found := SaWhitePointEstimate.neutral(subject[0], subject[1], way) if not subject.is_empty() else Vector3(NAN, NAN, NAN)
    if not found.is_finite():
        EventBus.corner_notice.emit(tr(NOTHING_FOUND))
        return false
    show_picked(found, way)
    changed.emit()
    return true


## The main canvas's surface, the one not inside a docker, or null.
func main_surface() -> SaSurface:
    if _surfaces == null:
        return null
    for surface: Variant in _surfaces.list_surfaces():
        if surface is SaSurface and not (surface as SaSurface).is_embedded:
            return surface
    return null


## What this White Point reads, as `[document, node]`: the input of the record
## it edits, the node null for the document's root, or in the Filter menu's
## dialog the main canvas's active layer when it holds paint. Empty when there
## is nothing to read.
func _subject() -> Array:
    var host := attached_host()
    if not host.is_empty():
        var found := SaNodeInput.node_of(host[0], host[1])
        if bool(found[0]):
            return [host[0], found[1]]
    var surface := main_surface()
    var document := SaSurface.document_of(surface)
    var layer := document.active_layer if document != null else null
    if layer == null or layer.is_group or layer.is_adjustment():
        return []
    return [document, layer]


## The document and the record this panel edits, as `[document, record]`,
## when it stands in the edit window of an attached record or in the tool
## options panel of one, and empty in the Filter menu's dialog. Asked of the
## nearest ancestor that holds a `record`, as Levels asks, read by name so the
## module names neither host.
func attached_host() -> Array:
    var node: Node = get_parent()
    while node != null:
        var record: Variant = node.get("record")
        if record is SaAttachedFilter:
            var document: Variant = node.get("_document")
            return [document, record] if document is SaDocument else []
        node = node.get_parent()
    return []


## The `filter` step's door, since the panel is a custom row: `{"arm": true}`
## presses the eyedropper, `{"sample": [x, y]}` takes its pick at a document
## place without the click, `{"picked": [r, g, b]}` sets the colour as
## light-linear sRGB, `{"from": "edges"}` moves Auto's choice and
## `{"auto": "surfaces"}` or `"edges"` presses Auto that way. Every branch
## answers what the panel shows.
func capture_option_edit(spec: Dictionary) -> String:
    if bool(spec.get("arm", false)):
        arm_eyedropper()
    if FROM_KEYS.has(String(spec.get("from", ""))):
        _from.select_value(FROM_KEYS.find(String(spec["from"])))
    if FROM_KEYS.has(String(spec.get("auto", ""))):
        _from.select_value(FROM_KEYS.find(String(spec["auto"])))
        find_cast(_from.selected_value())
    if spec.has("sample"):
        var at: Array = spec["sample"]
        sample_at(Vector2(float(at[0]), float(at[1])))
    if spec.has("picked"):
        show_picked(SaWhitePointFilter.picked_of({String(SaWhitePointFilter.PICKED_KEY): spec["picked"]}))
        changed.emit()
    var shown := {
        "picked": SaWhitePointFilter.as_list(picked),
        "swatch": "#" + _swatch.color.to_html(false) if picked.is_finite() else "",
        "caption": _caption.text,
        "armed": not _sampler.kind.is_empty(),
        "from": FROM_KEYS[int(_from.selected_value())],
    }
    return "SaCapture: white_point %s" % JSON.stringify(shown)


## The swatch's frame, so a light colour is not lost against the page.
func _draw_frame() -> void:
    _swatch.draw_rect(Rect2(Vector2.ZERO, _swatch.size), SaTheme.palette.text_muted, false, 1.0)


## An armed eyedropper goes when the panel is hidden or leaves, whichever way
## its window closed, so the tool and the foreground come back.
func _notification(what: int) -> void:
    if what == NOTIFICATION_EXIT_TREE or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
        _sampler.disarm()


## The button reads pressed while the eyedropper is armed.
func _on_armed_changed(kind: String) -> void:
    _told_nothing_there = false
    _eyedropper.set_pressed_no_signal(kind == KIND)


## Auto pressed, the way its choice shows.
func _on_auto_pressed() -> void:
    find_cast(_from.selected_value())


## A click on the canvas while the eyedropper is armed. Where nothing is
## painted the eyedropper stays armed and says so in the corner, once.
func _on_sampled(_kind: String, at: Vector2) -> void:
    if sample_at(at):
        _sampler.land()
    elif not _told_nothing_there:
        _told_nothing_there = true
        EventBus.corner_notice.emit(tr("Nothing painted there for White Point to read, so the colour stays as it was."))
