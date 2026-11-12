## The Exposure docker: the view's exposure, the paint's and the values', all
## in stops.
##
## Each row is a second hand on a number another place already owns, so the
## docker keeps none of its own and writes only through the doors those places
## write through.
##
## **View** is the switch and the stops the Display page writes,
## `SaInHand.Settings.read(&"display_exposure_enabled")` and `display_exposure_stops`, under the
## page's rule that moving the stops off nought puts the exposure on and back to
## nought takes it off. A change from the page, the View menu or a profile
## arrives through `SaSettings.changed` and moves this row without a write.
##
## **Paint** is the paint exposure, [member SaColorStore.exposure_stops],
## which the bar's Exposure and the colour docker's row show too. The store announces a
## move on `foreground_changed`, so the three follow one another.
##
## **Layer** is the Exposure filter on the active layer or group, with the
## dialog's Affect all and way toggle, in `exposure_layer_row.gd`. A drag previews
## through the compositor's point preview as the filter dialog's does, and
## Apply commits as one undo step.
##
## Registered by `module.gd` beside it through `SaContext.register_docker`, the
## call every module's docker makes (hard rule 6). No script of the skeleton
## names this file, and the shipped layouts and a painter's saved one find the
## docker by the id below.
@tool
extends DockerWindow

const LayerRow := preload("exposure_layer_row.gd")

## The docker's id, the section `docker_layout.cfg` files its window under. A
## stored layout names its window by this id, so it stays the one the shipped
## layouts were written with and an older profile's layout opens the docker.
const DOCKER_ID := &"ExposureDocker"

## What the docker opens at: three rows of one slider each, and the way row
## and Apply under the last. The way row is the widest thing in it, three
## words read whole over their stops, so the column floors near 226 at scale 1
## and the docker opens at 230.
const DEFAULT_SIZE := Vector2i(230, 340)

## The narrowest the docker is dragged to. Declared rather than left to the
## column's own floor, because the Layer row's controls show only once the
## filter is found, after the docker measured its column, and a floor taken
## without them lets a drag cut the way row's Layer stop off.
const MIN_SIZE := Vector2i(226, 260)

## How far a drag of the Layer slider reaches either way, the Exposure
## filter's own reach. A typed number goes past it to the filter's hard range,
## which the row reads once it finds the filter, and to
## [constant SaPaintExposure.FLOAT_STOPS] until then.
const LAYER_REACH := 8.0

## The View row's switch and stops.
var view_switch: CheckButton = null
var view_slider: FactorSlider = null

## The Paint row's stops, the foreground's.
var paint_slider: FactorSlider = null
## Under the Paint row, why a typed number was refused, hidden until one is.
var paint_refusal: Label = null

## The Layer row, the filter's slider, Affect all, the way toggle and Apply.
var layer_row: LayerRow = null

## The surface the Layer row previews and applies on, the front one when null.
## A suite hands its own.
var target_surface: SaSurface = null

## The filters the Layer row looks the Exposure filter up in, and the layer
## types its Layer way makes an adjustment layer from. The module hands its
## context's two, the registries every module registers into, and a suite its
## own. The row says no module registers the filter while they are null.
var filter_registry: SaFilterRegistry = null
var layer_types: SaLayerTypeRegistry = null


func _init() -> void:
    _init_docker(DOCKER_ID, tr("Exposure"), DEFAULT_SIZE, MIN_SIZE)
    # Where a first tick in the Window menu opens it under a layout with no
    # section for it: the Default layout's place, between the Undo History and
    # the Layers docker.
    position = Vector2i(1368, 556)

    var column := SaMake.column(_control_node, "VBoxContainer")
    column.set_anchors_preset(Control.PRESET_FULL_RECT)
    drag_handle = DockerUtils.make_drag_bar(tr("Exposure"))
    column.add_child(drag_handle)
    var margin := SaMake.margin(column, "MarginContainer", SaUI.BASE_MARGIN)
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var scroll := SaMake.scroll(margin, "Scroll")
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    var rows := SaMake.column(scroll, "Rows")
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var view := _heading(rows, "ViewRow", tr("View"))
    view_switch = SaMake.switch(view, "ExposureViewSwitch", "", bool(SaInHand.Settings.read(&"display_exposure_enabled")))
    view_switch.tooltip_text = tr("Scale the view by the stops below, before the roll-off. Never touches a pixel.")
    view_switch.toggled.connect(_on_view_switched)
    # A drag reaches the Display page's four stops either way, and a typed
    # number goes on to what the setting holds, a float's stops.
    view_slider = _stops_slider(rows, "ExposureViewSlider", -SaPaintExposure.FLOAT_STOPS, SaPaintExposure.FLOAT_STOPS)
    view_slider.soft_min_value = -SaInHand.Settings.MAX_EXPOSURE_STOPS
    view_slider.soft_max_value = SaInHand.Settings.MAX_EXPOSURE_STOPS
    view_slider.step = 0.25
    view_slider.set_value_no_signal(SaInHand.Settings.read(&"display_exposure_stops"))
    view_slider.tooltip_text = tr(
        "How far to open or close the view. Each stop doubles or halves the light, and moving this puts the exposure on."
    )
    view_slider.value_changed.connect(_on_view_moved)

    _heading(rows, "PaintRow", tr("Paint"))
    paint_slider = _stops_slider(rows, "ExposurePaintSlider", 0.0, SaPaintExposure.MAX)
    # The bar's Exposure and the colour docker's row reach as far by drag.
    paint_slider.soft_max_value = SaPaintExposure.REACH
    paint_slider.set_value_no_signal(SaInHand.Pair.exposure_stops())
    paint_slider.tooltip_text = tr(
        "The paint exposure in stops: the colour picked, times two to this. A pick brighter than white sets it."
    )
    paint_slider.value_changed.connect(_on_paint_moved)
    paint_refusal = SaMake.label(rows, "ExposurePaintRefusal", "")
    paint_refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    paint_refusal.visible = false
    SaTheme.bind_font(paint_refusal, "text_muted")

    _heading(rows, "LayerRow", tr("Layer"))
    # The filter's own reach until the row finds the filter and reads its range.
    var layer_slider := _stops_slider(null, "ExposureLayerSlider", -SaPaintExposure.FLOAT_STOPS, SaPaintExposure.FLOAT_STOPS)
    layer_slider.soft_min_value = -LAYER_REACH
    layer_slider.soft_max_value = LAYER_REACH
    layer_row = LayerRow.new(layer_slider)
    rows.add_child(layer_row)

    SaInHand.Settings.changed().connect(_on_setting_changed)
    SaInHand.Pair.foreground_changed().connect(_on_foreground_changed)
    visibility_changed.connect(_on_visibility_changed)


func _ready() -> void:
    _setup_docker_ready()
    if not SaInHand.Settings.profile_changed().is_connected(apply_layout_settings):
        SaInHand.Settings.profile_changed().connect(apply_layout_settings)
    apply_layout_settings()
    follow()


func _exit_tree() -> void:
    layer_row.cancel()


func apply_layout_settings() -> void:
    apply_docker_base_layout(DOCKER_ID)


func _process(_delta: float) -> void:
    # A docker is a Window, so `visible` is the whole question.
    if visible and is_inside_tree():
        follow()


## Points the Layer row at the canvas and the registries as they stand, which
## takes a preview off a document or a layer the painter has left and dims the
## ways again for the layer now active. Every frame the docker is shown.
func follow() -> void:
    layer_row.follow(_surface(), filter_registry, layer_types)


## One heading over a row, in the muted font the docker's section words use,
## in a line of its own that a control can join on the right.
func _heading(parent: Node, node_name: String, words: String) -> HBoxContainer:
    var line := SaMake.row(parent, node_name)
    var label := SaMake.label(line, "Heading", words)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    SaTheme.bind_font(label, "text_muted")
    return line


## A slider in stops filling its line, read to two places.
static func _stops_slider(parent: Node, node_name: String, low: float, high: float) -> FactorSlider:
    var slider := SaMake.slider(parent, node_name, low, high, 0.01, 0.0)
    slider.suffix = " EV"
    slider.decimal_places = 2
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return slider


## The page's rule: the stops a hand moved are written, and the exposure is on
## exactly while they are off nought, or the drag would show nothing.
func _on_view_moved(stops: float) -> void:
    SaInHand.Settings.write(&"display_exposure_stops", stops)
    var wanted := not is_zero_approx(stops)
    if SaInHand.Settings.read(&"display_exposure_enabled") != wanted:
        SaInHand.Settings.write(&"display_exposure_enabled", wanted)


func _on_view_switched(on: bool) -> void:
    SaInHand.Settings.write(&"display_exposure_enabled", on)


## A number the document cannot hold is refused rather than cut: the field
## goes back to the stops the pair has, and the line under it says what was
## typed and the most the document holds.
func _on_paint_moved(stops: float) -> void:
    var document := _surface().get_document() if _surface() != null else null
    var held := SaPaintExposure.held_by(document.color_space if document != null else null)
    if stops > held:
        paint_slider.set_value_no_signal(SaInHand.Pair.exposure_stops())
        # Two places cut down, so the most said is a number the field takes.
        held = floorf(held * 100.0) / 100.0
        paint_refusal.text = (
            tr("%.2f EV refused: a half precision document holds at most %.2f EV, a peak of 65504.") % [stops, held]
        )
        paint_refusal.visible = true
        return
    paint_refusal.visible = false
    SaInHand.Pair.expose(stops)


## The View row follows a write from anywhere, the Display page above all,
## without writing back.
func _on_setting_changed(key: StringName) -> void:
    if key == &"display_exposure_stops":
        view_slider.set_value_no_signal(SaInHand.Settings.read(&"display_exposure_stops"))
    elif key == &"display_exposure_enabled":
        view_switch.set_pressed_no_signal(SaInHand.Settings.read(&"display_exposure_enabled"))
    elif key == &"filter_way" or key == &"filter_affect_all":
        layer_row.follow_settings()


## The Paint row follows the store, the bar's and the colour docker's moves and
## a pick's.
func _on_foreground_changed() -> void:
    if not is_equal_approx(paint_slider.value, SaInHand.Pair.exposure_stops()):
        paint_slider.set_value_no_signal(SaInHand.Pair.exposure_stops())


## A hidden docker shows no preview, so a drag left standing is taken off the
## canvas as the dialog's Cancel takes it, and a shown one reads the rows again.
func _on_visibility_changed() -> void:
    if visible:
        view_slider.set_value_no_signal(SaInHand.Settings.read(&"display_exposure_stops"))
        view_switch.set_pressed_no_signal(SaInHand.Settings.read(&"display_exposure_enabled"))
        paint_slider.set_value_no_signal(SaInHand.Pair.exposure_stops())
        follow()
    else:
        layer_row.cancel()


## The surface of the document the painter is working on, the painting rather
## than the Info docker's scratchpad, which the front surface says.
func _surface() -> SaSurface:
    if target_surface != null:
        return target_surface
    return SaInHand.Canvas.front() if is_inside_tree() else null
