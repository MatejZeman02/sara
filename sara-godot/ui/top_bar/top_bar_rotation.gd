## The top bar's rotation slider and its reset button.
##
## The two controls are row elements like every other, so a profile can reorder
## them, move them to the second row or hide them from Preferences > Top Menu
## Bar, and the bar's rows place them. This owns what they mean: the angle the
## view is at, the drag that turns it, and the button that puts it back. It
## takes no bar: the tree it asks for the view is the one its slider is in.
##
## The slider and the view drive each other, so both directions are guarded. A
## drag writes the view through `rotate_at`, which is the same call the View
## menu's Rotate Left makes, and the view's own `transform_changed` writes the
## slider with `set_value_no_signal`, so a turn made with the chords, the menu or
## a two-finger drag moves the slider without the slider then turning the canvas
## a second time.
##
## The connection is made as soon as there is a view, at `EventBus.boot_finished`
## and again at every `EventBus.document_loaded`, so a turn made before anyone
## touched the slider is on it too. Once the view was found only by a drag
## or the reset, and a fresh start read 0 degrees under a canvas at 60.
## The view is the front document's, found again at every
## `EventBus.active_document_changed`, so with a second document in front the
## slider reads and turns that one.
class_name SaTopBarRotation
extends RefCounted

## The layout keys, which are what `SaSettingsLayout.DEFAULT_ORDERS` lists and
## what a stored profile holds. English there, like every other key, and
## translated on the control.
const ELEMENT_SLIDER := "Rotation"
const ELEMENT_RESET := "Reset Rotation"

## The name the slider carries for the value drive, the canvas view's angle.
const VALUE_NAME := &"view/rotation"

## The bar's group the pair sits in, `SaOptionSpec.bar_group`'s word for it,
## since the two turn the view and not the brush or the line. Declared here,
## where the pair is listed, the way the tool options bar's own elements declare
## theirs on its element table.
const GROUP := SaOptionSpec.BAR_GROUP_VIEW

## Half a degree. Below this the slider and the view are saying the same thing,
## and rewriting the slider would only fight a drag in progress.
const SAME_ANGLE: float = 0.5

## Logical pixels the slider asks for when its text needs fewer. The text is
## "Rotate: " and the widest angle, which asks for more at the bar's font,
## so this is a floor for a translation shorter than that.
## The row sends
## the pair to the overflow among its first controls now, by
## `SaTopBarRows.LEAVE_FIRST`, rather than narrowing it.
##
## Written through `preferred_width` and not `custom_minimum_size`.
## `FactorSlider._update_display` rewrites the minimum from `preferred_width` on
## every value change, so a width set the other way survives exactly until the
## first drag.
const SLIDER_WIDTH: int = 96

var slider: FactorSlider
var reset_button: Button

## The view the slider is following. Kept so the connection is made once and
## dropped when the canvas is replaced, which File > Open does.
var _view: SaView = null

## The surface `_view` shows, so a turn redraws the document it turned alone.
var _surface: SaSurface = null

## The view a suite hands the bar, which `view()` prefers to the one it would find
## in the tree. Null on the running bar, which asks the scene.
var _given_view: SaView = null


## *given_view* is for a suite that wants one view whatever is in front. The bar
## made by `SaTopMenuBar` passes nothing and asks the front document.
func _init(given_view: SaView = null) -> void:
    _given_view = given_view
    EventBus.boot_finished.connect(follow)
    EventBus.document_loaded.connect(follow)
    EventBus.active_document_changed.connect(follow.unbind(1))


## Builds both controls and parents them under *host*, which is the tool options
## bar. Built here rather than in `_init` because a control with no parent is a
## `Node` nothing frees, and a bar made without tool options is exactly what
## several suites build: two orphans per bar was a leak the run reported and no
## assertion did.
##
## A stored profile written before the rotation pair existed has no entry for
## either key, and `apply_layout_settings` moves only what the order names, so
## this is also where such a profile leaves them: at the end of the tool options
## bar, the way "Brush Presets" landed there for the same reason.
func attach(host: Node) -> void:
    if host == null:
        return
    if slider != null:
        _reparent(host)
        return

    slider = FactorSlider.new()
    slider.name = "RotationSlider"
    slider.set_meta(SaMake.KIND_META, SaMake.Kind.SLIDER)
    # Before the setters below, because each of them calls `_update_display`,
    # which is what writes the minimum width from this.
    slider.preferred_width = DockerUtils.px(SLIDER_WIDTH)
    slider.min_value = -180.0
    slider.max_value = 180.0
    # A typed 360 is a whole turn and lands on 0, where a clamp put it at 180.
    slider.wraps = true
    slider.step = 1.0
    slider.decimal_places = 0
    # The word ahead of the angle, because a slider that read "0 °" alone was
    # taken for a progress bar. The room it costs comes out of a row that sends
    # this slider to the overflow among its first controls. "Rotate" and not
    # "Rotation" or an icon, because the shipped icon set has no rotate icon,
    # and of the two words the shorter is 18 pixels narrower on the
    # bar at 1920 by 1080, which pays for two of the eight-pixel breaks between
    # the bar's groups.
    # Written again at each change of language, since the bar is built before
    # a language module's catalogue arrives.
    SaOnLanguage.watch(slider, func() -> void: slider.prefix = TranslationServer.translate("Rotate") + ": ")
    slider.suffix = "°"
    slider.value = 0.0
    # Named so Map to MIDI can bind a knob to it, as it does the brush's size.
    slider.value_name = VALUE_NAME
    slider.tooltip_text = TranslationServer.translate("Turn the canvas. Ctrl+[ and Ctrl+] turn it in steps of 15°.")
    slider.value_changed.connect(_on_slider_changed)

    # The Colour Picker's reset icon rather than the arrow U+21BA in the text,
    # which Atkinson Hyperlegible and Source Sans 3 drew as a box.
    reset_button = SaMake.button(null, "ResetRotationBtn", "", TranslationServer.translate("Reset rotation"))
    reset_button.focus_mode = Control.FOCUS_NONE
    # The bar's one size for an icon button, shared with the mirrors and the
    # erase toggle.
    SaBarIconButton.shape(reset_button, "reset")
    reset_button.pressed.connect(_on_reset_pressed)

    _reparent(host)


## Element key -> control, for the bar to merge into the map a profile orders.
## Empty until `attach`, so a bar with no tool options offers no rows and the
## profile pass skips both keys.
func elements() -> Dictionary:
    if slider == null:
        return {}
    return {ELEMENT_SLIDER: slider, ELEMENT_RESET: reset_button}


## Element key -> group, beside `elements` and empty while it is.
func groups() -> Dictionary:
    if slider == null:
        return {}
    return {ELEMENT_SLIDER: GROUP, ELEMENT_RESET: GROUP}


func _reparent(host: Node) -> void:
    for control: Control in [slider, reset_button]:
        if control.get_parent() == host:
            continue
        if control.get_parent() != null:
            control.get_parent().remove_child(control)
        host.add_child(control)
    sync()


## The view the two controls act on, connecting to it the first time it is seen.
## Null on a detached bar, which is what a test builds.
func view() -> SaView:
    var tree := slider.get_tree() if slider != null and slider.is_inside_tree() else null
    _surface = SaDocuments.front_in(tree.current_scene) if _given_view == null and tree != null else null
    var found: SaView = _given_view if _given_view != null else (_surface.view if _surface != null else null)
    if found == _view:
        return found
    if _view != null and _view.transform_changed.is_connected(sync):
        _view.transform_changed.disconnect(sync)
    _view = found
    if _view != null and not _view.transform_changed.is_connected(sync):
        _view.transform_changed.connect(sync)
    return _view


## Finds the view and puts its angle on the slider, which is what boot and every
## opened document call, so the slider follows before it is touched. The
## document `document_loaded` carries is not read, the view is what is asked.
func follow(_document: SaDocument = null) -> void:
    view()
    sync()


## Puts the view's own angle on the slider. Public because it is what
## `transform_changed` is connected to, and what a test reads to ask whether the
## bar agrees with the view.
func sync() -> void:
    if slider == null or _view == null:
        return
    var degrees := rad_to_deg(_view.get_rotation())
    if absf(degrees - slider.value) < SAME_ANGLE:
        return
    # -180 and 180 are the same angle and `rotate_at` wraps onto the first of
    # them, so without this a slider dragged to its right end would jump to its
    # left end the moment the view answered.
    if absf(absf(degrees) - 180.0) < SAME_ANGLE and absf(absf(slider.value) - 180.0) < SAME_ANGLE:
        return
    slider.set_value_no_signal(degrees)


func _on_slider_changed(degrees: float) -> void:
    _turn_to(deg_to_rad(degrees))


func _on_reset_pressed() -> void:
    _turn_to(0.0)
    sync()


## Turns the view about the middle of the viewport, which is what Rotate Left,
## Rotate Right and Reset Rotation in the View menu all do, so the slider and
## the menu cannot disagree about the pivot.
func _turn_to(radians: float) -> void:
    var canvas_view := view()
    if canvas_view == null:
        return
    canvas_view.rotate_at(radians, canvas_view.get_viewport_size() * 0.5)
    # Turning reveals chunks outside the region the compositor last covered, the
    # same reason the View menu invalidates after every zoom.
    var document := _surface.get_document() if _surface != null else null
    if document != null:
        document.reveal_all_allocated_chunks()


## What the two controls are and where they are, for a capture. The slider's own
## value against the view's angle is the only way to say the two agree, and the
## rectangle is what a scenario presses to turn the canvas. Empty until
## `attach`. The bar adds what the pair costs its row.
func report() -> Dictionary:
    if slider == null:
        return {}
    return {
        "slider_degrees": slider.value,
        # The view's own angle beside it, so a capture can say the canvas turned
        # where the slider says and not only that the slider moved.
        "view_degrees": (rad_to_deg(_view.get_rotation()) as Variant) if _view != null else null,
        "slider_rect": _rect_of(slider),
        "reset_rect": _rect_of(reset_button),
        "shown": slider.visible,
        # What this pair costs the row it is on, so `row_spent` minus this is
        # what the row spent without the pair and its cost is a number rather
        # than a guess.
        "pair_cost": _cost_of(slider) + _cost_of(reset_button),
        "slider_min": slider.get_combined_minimum_size().x,
        "reset_min": reset_button.get_combined_minimum_size().x,
    }


## A control's minimum width plus the separation that follows it, which is how
## `SaTopBarRows.row_spent` counts one.
static func _cost_of(control: Control) -> float:
    if control == null or not control.visible:
        return 0.0
    var parent := control.get_parent() as Container
    var separation := float(parent.get_theme_constant("separation")) if parent != null else 0.0
    return control.get_combined_minimum_size().x + separation


static func _rect_of(control: Control) -> Dictionary:
    var r := control.get_global_rect()
    return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}
