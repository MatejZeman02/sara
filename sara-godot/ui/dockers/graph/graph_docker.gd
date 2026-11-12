## The Graph docker: a live scope over what the painter is looking at.
##
## Five graphs from one binning pass in `graph.gmacs`, chosen from a dropdown:
## a waveform, a histogram, an RGB parade, an Oklab vectorscope and an Oklab
## points cloud. The GPU half is `SaGraphPlot`, which owns the buffer, the
## picture and the three dispatches. This is the window round it. The sixth,
## the spectrogram, is `SaGraphSpectrogram`'s, shown in place of the pictures.
##
## The question was whether a scope should read the document or the screen, and
## the answer was the screen: the pass reads what the view shows, a sample a
## pixel, which costs the same on a 512 canvas as on a 8K one. The
## samples lie on the document's own grid, over the box of what the view shows
## with what it leaves out skipped, so turning or mirroring the view leaves the
## graph alone and a waveform's column is a run of document x. Zooming out
## until the whole picture is in view is how a painter asks for a scope of all
## of it, and then the whole width is the document's.
##
## The picture is drawn at the size of the panel rather than at a fixed square
## scaled into it, so a docker dragged wide gets a wider waveform rather than a
## blurrier one. What is binned does not change with it: the bin grid is the
## kernel's own and a scope has to report the same numbers at every size.
##
## It runs when the picture changed, never on a timer: the easel counts its
## composites, and a tick where that number has not moved dispatches nothing.
##
## The two-graph mode: a source dropdown beside the graph's, canvas, reference
## or both, and with the reference in it a second `SaGraphPlot` over the
## selected reference of the Reference docker, the picture last clicked on the
## board, drawn beside the canvas's. The reference is uploaded once and binned
## when it changes, never per frame, in its own display space, which is the
## space the canvas's graph shows the composite in through the view, so the two
## histograms compare like with like.
@tool
extends DockerWindow

class_name GraphDocker


## A toggle between two named states, which shows the name of the one it is in
## and a tooltip for what a press changes it to. Both of the docker's toggles
## are made through this one helper.
class StateToggle:
    const WORDS_META := &"state_words"
    const TIPS_META := &"state_tips"

    ## Makes *button* a toggle. *words* and *tips* are the unpressed state's
    ## first and the pressed state's second.
    static func setup(button: Button, words: Array, tips: Array) -> void:
        button.toggle_mode = true
        SaTheme.make_toggle(button)
        button.set_meta(WORDS_META, words)
        button.set_meta(TIPS_META, tips)
        button.toggled.connect(func(pressed: bool) -> void: _name(button, pressed))
        _name(button, button.button_pressed)

    ## Puts *button* in a state without announcing it, and names it.
    static func show_state(button: Button, pressed: bool) -> void:
        button.set_pressed_no_signal(pressed)
        _name(button, pressed)

    static func _name(button: Button, pressed: bool) -> void:
        var index := 1 if pressed else 0
        button.text = String((button.get_meta(WORDS_META) as Array)[index])
        button.tooltip_text = String((button.get_meta(TIPS_META) as Array)[index])


## What the docker opens at. Wider than tall, because the waveform it opens on
## is a picture of the canvas across the panel.
const DEFAULT_SIZE := Vector2i(320, 300)

## The kernel's `SKIN_HUE`, the Oklab hue in radians the vectorscope's skin tone
## line points at, read from darktable's table of measured skin colours.
## Mirrored for the dump alone, so a scenario says where the line is without
## reading a picture, and `ui/dockers/graph/tests/test_skin_tone_line.gd` holds the mirror and
## the kernel to one number.
const SKIN_HUE := 0.896

## The three sources the second dropdown offers, as the id a scenario names and
## the label the painter reads.
const SOURCES: Array = [["canvas", "Canvas"], ["reference", "Reference"], ["both", "Both"]]

var target_canvas: SaCanvas

## The scope, for a test that wants the counts rather than the picture.
var plot: SaGraphPlot = SaGraphPlot.new()
var _picture: TextureRect
## The text over the canvas's picture, its own class.
var _scale: SaGraphLabels
var _mode_button: SaChoiceButton

## The RGBW toggle beside the dropdown, shown only while a waveform is.
var _white_toggle: Button = null

## The scale toggle beside it, shown for the two graphs with a scale: the
## histogram's count axis and the vectorscope's radius.
var _scale_toggle: Button = null

## `log`, darktable's default, or `linear`, one of `SaGraphPlot.SCALES`.
var scale: String = "log"

## The graph shown, as one of `SaGraphPlot.MODES`' ids.
var graph_mode: String = SaGraphPlot.DEFAULT_MODE

## What is graphed: `canvas`, `reference` or `both`.
var source: String = "canvas"
var _source_button: SaChoiceButton

## Puts the cloud's view back, beside the source and shown for the cloud alone.
var _reset_button: Button = null

## The second scope, over the selected reference, and its picture.
var reference_plot: SaGraphPlot = SaGraphPlot.new()
var _reference_picture: TextureRect
## The reference the second plot was last run over, and how many times it
## has run, which is the number that says it ran when the reference changed
## and not per frame.
var _seen_reference: SaReferenceBoard.Picture = null
var _seen_reference_mode: String = ""
var _seen_reference_plot: Vector2i = Vector2i.ZERO
var _reference_texture: SaTexture = null
var reference_passes: int = 0
## Whether Reference and Both are offered, which is whether a reference is
## selected. Written by `_offer_reference` alone.
var _offers_reference: bool = false
var _reference_docker: ReferenceDocker = null

## Whether a drag on the picture is turning the cloud or moving it.
var _turning: bool = false
var _panning: bool = false

## The pass as `SaReductions` runs it, registered while the docker is open and
## setting the per-frame pace there. The poll that decides when is the
## service's, and [method SaReductionService.Reduction.stale] asks for a pass.
var reduction: SaReductionService.Reduction = null
## The Spectrogram mode's view, which registers its own transform while shown.
var spectrogram: SaGraphSpectrogram = SaGraphSpectrogram.new()


func _init() -> void:
    reduction = SaReductionService.Reduction.new(true, _scheduled_pass, _scheduled_shape)
    _init_docker(SaDockerIds.GRAPH, "Graph", DEFAULT_SIZE, Vector2i(180, 200))
    # Where a fresh profile finds it: under the minimap, on the left, out of
    # the picture's way.
    position = Vector2i(2, 400)

    var vbox := SaMake.column(_control_node, "VBoxContainer")
    vbox.set_anchors_preset(Control.PRESET_FULL_RECT)

    drag_handle = DockerUtils.make_drag_bar("Graph")
    vbox.add_child(drag_handle)

    # The controls keep a margin and the picture does not, so the graph
    # stretches to the edges and takes all the space it can. Inside a
    # MarginContainer with the dropdown it would lose BASE_MARGIN on all four
    # sides. On a docker squeezed to its minimum that is
    # a tenth of the width, and the parade pays it three times over because each
    # of its panels is a third of what is left.
    var margin := SaMake.margin(vbox, "MarginContainer", SaUI.BASE_MARGIN)
    margin.add_theme_constant_override("margin_bottom", SaUI.px(SaTheme.GAP_TIGHT))

    var column := SaMake.column(margin, "Column", SaTheme.GAP_TIGHT)

    # A flow rather than a box, so a docker narrower than the row's words puts
    # what does not fit on a second line instead of clipping a label. Each
    # dropdown is as wide as its longest row, and in a box the expanding mode
    # button got what the source left, which at the docker's own 320 cut
    # "Waveform (W)" to "Waveform (...". At the shipped layouts' 380 the row is
    # one line in every graph. Its gaps are the theme's, because the theme pass
    # writes every flow's separations over whatever the flow was built with.
    var row := HFlowContainer.new()
    row.name = "ModeRow"
    column.add_child(row)

    # Sara's own choice button rather than the engine's dropdown, here and for
    # the source row below. Each row carries the id the docker already names its
    # modes and sources by, so the two handlers take that id and the index
    # arithmetic goes.
    var mode_rows: Array = []
    for entry: Array in SaGraphPlot.MODES:
        mode_rows.append({"id": String(entry[0]), "label": tr(String(entry[1]))})
    mode_rows.append({"id": SaGraphSpectrogram.MODE, "label": tr("Spectrogram")})
    _mode_button = SaMake.choice(row, "ModeButton", mode_rows)
    _mode_button.select_value(graph_mode)
    _mode_button.choice_picked.connect(func(id: Variant) -> void: show_mode(String(id)))
    _mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _mode_button.theme_changed.connect(_fit_choice.bind(_mode_button))

    # The white trace is reached two ways, the list's row and the White beside
    # it, so the two say the same thing about it, since a "W" alone says white
    # and not of what. The toggle spells the letter out, and the row keeps its
    # W because "Waveform (White)" breaks the row in two at 380.
    var white_tip := tr("One white trace of Oklab lightness in place of the red, green and blue ones")
    _mode_button.popup.label_button(SaChoiceButton.row_id_of("waveform_white")).tooltip_text = white_tip

    # The RGBW toggle, beside the dropdown rather
    # than buried in it: a painter flicks this while looking at the picture, and
    # two rows of a dropdown cost a click, a read and a second click to compare.
    # Shown only for a waveform, because there is no white trace of a
    # vectorscope. It names the state it is in, RGB at rest and White pressed,
    # and its tooltip says what a press changes it to.
    _white_toggle = SaMake.button(row, "WhiteToggle")
    var rgb_tip := tr("Red, green and blue traces. Click for one white trace of Oklab lightness.")
    var w_tip := tr("One white trace of Oklab lightness. Click for the red, green and blue traces.")
    StateToggle.setup(_white_toggle, [tr("RGB"), tr("White")], [rgb_tip, w_tip])
    _white_toggle.custom_minimum_size = Vector2(SaUI.px(40), 0)
    _white_toggle.toggled.connect(_on_white_toggled)

    # The scale toggle. Log is darktable's default and what a painting wants,
    # because its background is most of its samples, and Lin is the plain ratio
    # for a picture that is a few flat colours. Shown only for the histogram and
    # the vectorscope, which are the two graphs whose scale it is: a waveform's
    # height is a value and has no scale to change.
    # Like White it names the state it is in, Log at rest and Lin pressed.
    _scale_toggle = SaMake.button(row, "ScaleToggle")
    var log_tip := tr("Logarithmic scale. Click for linear.")
    var lin_tip := tr("Linear scale. Click for logarithmic.")
    StateToggle.setup(_scale_toggle, [tr("Log"), tr("Lin")], [log_tip, lin_tip])
    _scale_toggle.custom_minimum_size = Vector2(SaUI.px(34), 0)
    _scale_toggle.toggled.connect(func(pressed: bool) -> void: show_scale("linear" if pressed else "log"))
    _scale_toggle.visible = _has_scale()

    _source_button = SaMake.choice(row, "SourceButton")
    _offer_reference(false)
    _source_button.select_value(source)
    _source_button.tooltip_text = tr("What is graphed: the canvas, the selected reference, or both side by side.")
    _source_button.choice_picked.connect(func(id: Variant) -> void: show_source(String(id)))
    _source_button.theme_changed.connect(_fit_choice.bind(_source_button))

    # The way back for a cloud that was turned, panned and zoomed. Shown only
    # for the cloud, the one graph with a view to lose.
    _reset_button = SaMake.button(row, "ResetViewButton", tr("Reset"), tr("Reset the cloud's view."))
    _reset_button.pressed.connect(reset_view)
    _reset_button.visible = graph_mode == "cloud"

    # The two pictures side by side. The reference's is hidden until a source
    # asks for it, and the scale is drawn over the canvas's only.
    var pictures := SaMake.row(vbox, "Pictures", 2)
    pictures.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _picture = TextureRect.new()
    _picture.name = "Picture"
    _picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    # Scaled rather than aspect-fitted: the texture is made at the size of this
    # rect, so keeping an aspect would letterbox a picture that already fits.
    _picture.stretch_mode = TextureRect.STRETCH_SCALE
    _picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # The cloud is turned, panned and zoomed on the picture itself, so it takes
    # the pointer. Every other mode ignores what arrives, as an IGNORE would.
    _picture.mouse_filter = Control.MOUSE_FILTER_STOP
    _picture.gui_input.connect(_on_picture_input.bind(false))
    pictures.add_child(_picture)

    _reference_picture = TextureRect.new()
    _reference_picture.name = "ReferencePicture"
    _reference_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _reference_picture.stretch_mode = TextureRect.STRETCH_SCALE
    _reference_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _reference_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
    # The same handler and filter as the canvas's. With the source set to
    # reference only the canvas's picture is hidden, and a hidden control is fed
    # no `gui_input` at all, so the one panel on screen has to carry the gesture
    # or the docker answers nothing.
    _reference_picture.mouse_filter = Control.MOUSE_FILTER_STOP
    _reference_picture.gui_input.connect(_on_picture_input.bind(true))
    _reference_picture.visible = false
    pictures.add_child(_reference_picture)
    vbox.add_child(spectrogram)

    _scale = SaGraphLabels.new()
    _picture.add_child(_scale)
    _tell_labels()


func _ready() -> void:
    assert(drag_handle != null, "DragHandle node not found")
    _setup_docker_ready()
    if not SaSettings.profile_changed.is_connected(apply_layout_settings):
        SaSettings.profile_changed.connect(apply_layout_settings)
    apply_layout_settings()
    visibility_changed.connect(_follow_open)


func _enter_tree() -> void:
    _follow_open()


## Still inside the tree while this runs, so the pass is taken off outright.
func _exit_tree() -> void:
    var service := SaReductionService.shared()
    if service != null:
        service.leave(reduction)


## Registers the pass with `SaReductions` while the docker is open and takes it
## off when it closes, so a closed graph costs nothing.
func _follow_open() -> void:
    var service := SaReductionService.shared()
    if service == null:
        return
    if visible and is_inside_tree():
        service.add(reduction)
    else:
        service.leave(reduction)


func apply_layout_settings() -> void:
    apply_docker_base_layout(SaDockerIds.GRAPH)


## Rotate, pan and zoom on the cloud.
##
## Left drag turns, middle or shift drag moves, and the wheel zooms about the
## middle of the picture. The same three gestures the canvas itself answers to,
## and the left drag is the one `ui/color_space/color_space_browser.gd` already uses on its
## gamut solid, at the same 0.01 radians a pixel.
##
## Only the cloud. Every other mode is a flat picture with nothing to turn, and
## a wheel over a waveform that silently changed nothing would read as a broken
## docker rather than as a mode without the feature.
##
## Either picture drives, and both clouds take the result. The two panels are
## one view of the same three axes: a painter comparing a reference against the
## canvas is comparing two shapes, and two shapes seen from different angles
## compare nothing.
func _on_picture_input(event: InputEvent, on_reference: bool) -> void:
    if apply_gesture(event, on_reference):
        var panel := _reference_picture if on_reference else _picture
        if panel != null:
            panel.accept_event()


## Reads one gesture event onto both clouds and answers whether it was taken.
##
## Split from `_on_picture_input` so the capture harness and a test can drive
## the same gesture the pointer does, on either panel: an injected motion never
## reaches a `gui_input`, and `accept_event()` off an input pass is an error, so
## the part worth exercising is the part without it.
func apply_gesture(event: InputEvent, on_reference: bool) -> bool:
    if graph_mode != "cloud":
        return false
    # The wheel and a touchpad's scroll zoom by as much as they moved, up in.
    var moved := SaStep.notches(event).y
    if moved != 0.0:
        _zoom_by(pow(1.1, -moved))
        return true
    var button := event as InputEventMouseButton
    if button != null:
        if button.button_index == MOUSE_BUTTON_LEFT:
            _turning = button.pressed and not button.shift_pressed
            _panning = button.pressed and button.shift_pressed
            return true
        if button.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = button.pressed
            return true
        return false
    var motion := event as InputEventMouseMotion
    if motion == null:
        return false
    if _turning:
        turn_by(motion.relative * 0.01)
        return true
    if _panning:
        # In unit coordinates of the square the cloud is drawn in, so a drag
        # moves the picture by the distance the pointer went whatever the
        # docker's size.
        var panel := _reference_picture if on_reference else _picture
        var room := panel.size if panel != null else Vector2.ZERO
        var side := maxf(minf(room.x, room.y), 1.0)
        pan_by(motion.relative / side)
        return true
    return false


## A whole left drag of *relative* pixels on one of the two panels, `canvas` or
## `reference`, through the handler the pointer uses. Public because a capture
## cannot drag: an injected motion never reaches a `gui_input`, and the claim is
## about which panel the drag started on, which `turn_by` alone cannot say.
##
## Shift held is the pan, the same branch the pointer takes.
func drag_on(panel_id: String, relative: Vector2, shift: bool) -> void:
    var on_reference := panel_id == "reference"
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    press.shift_pressed = shift
    apply_gesture(press, on_reference)
    var motion := InputEventMouseMotion.new()
    motion.relative = relative
    apply_gesture(motion, on_reference)
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    release.shift_pressed = shift
    apply_gesture(release, on_reference)


## One wheel notch on one of the two panels, up when *up*. Public for the
## reason `drag_on` is.
func wheel_on(panel_id: String, up: bool) -> void:
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed = true
    apply_gesture(wheel, panel_id == "reference")


## Turns the cloud by *by* radians, yaw then pitch. Public because a capture
## cannot drag: an injected motion never reaches a `gui_input`.
##
## **The pitch is subtracted**, which is the same sign choice as for the solid. Every
## orbit control in the trade lowers the eye when the pointer goes down, so a drag
## down tips the top of the cloud towards the painter. Adding was the sign this
## shipped with, and it carried the far side downwards instead, which left the two
## 3D pictures in the app answering the same buttons and the same wheel and turning
## opposite ways in the vertical. `ui/color_space/gamut_solid.gd`'s `turn_by` is the
## same line for the same reason.
##
## **The yaw is subtracted too**, and not because the solid's is. The solid
## turns its point by `a cos(yaw) - b sin(yaw)` and adds the drag, and
## `graph.gmacs`'s `project_point` turns by `a cos(yaw) + b sin(yaw)`, which is
## the solid at minus the yaw. So adding here, the sign it shipped with, carried
## the cloud's near side with a drag right while the solid's went against it,
## and the cloud answered its two axes in opposite senses. Subtracting makes the
## same drag move the same point the same way on screen in both pictures, on
## both axes: against the pointer, which is the sense the solid already
## turns in. The kernel is left alone, so the picture at rest does not move.
func turn_by(by: Vector2) -> void:
    var pitch := clampf(plot.cloud_pitch - by.y, -SaGraphPlot.CLOUD_PITCH_LIMIT, SaGraphPlot.CLOUD_PITCH_LIMIT)
    # Clamped once and written to both, so a pitch at its limit stops in both at
    # once rather than one panel creeping past the other.
    _look_from(plot.cloud_yaw - by.x, pitch, plot.cloud_pan, plot.cloud_zoom)


## Moves the cloud by *by*, in unit coordinates of its own square.
func pan_by(by: Vector2) -> void:
    _look_from(plot.cloud_yaw, plot.cloud_pitch, plot.cloud_pan + by, plot.cloud_zoom)


## Zooms about the middle of the picture by *factor*.
func zoom_by(factor: float) -> void:
    _zoom_by(factor)


## Puts the viewpoint back where a fresh docker has it.
func reset_view() -> void:
    _look_from(SaGraphPlot.CLOUD_YAW, SaGraphPlot.CLOUD_PITCH, Vector2.ZERO, 1.0)


## Writes the one viewpoint onto both plots, the way `show_scale` already writes
## the one scale onto both. Every writer above goes through here, so there is no
## path that can move one cloud and leave the other behind.
func _look_from(yaw: float, pitch: float, pan: Vector2, zoom: float) -> void:
    for target: SaGraphPlot in [plot, reference_plot]:
        target.cloud_yaw = yaw
        target.cloud_pitch = pitch
        target.cloud_pan = pan
        target.cloud_zoom = zoom
    _redraw_cloud()


## Where the cloud is being looked at from, and which graph is showing, for a
## state dump and a test.
##
## The mode is part of this. Which graph the docker opens on is a claim about the
## running app like any other, and the only thing that could say it was the picture: a
## reader had to recognise a waveform by eye and trust the dropdown's label under it.
## It goes here rather than into a block of its own in
## `harness/report/sa_state_report.gd`, which follows the rule that a new number is
## reported by the node that owns it.
func view_report() -> Dictionary:
    return {
        "mode": graph_mode,
        "source": source,
        "offers_reference": _offers_reference,
        "scale": scale,
        "reference_passes": reference_passes,
        "reference_plot":
        reference_plot.plot_size if _reference_picture != null and _reference_picture.visible else Vector2i.ZERO,
        "yaw": plot.cloud_yaw,
        "pitch": plot.cloud_pitch,
        "pan": {"x": plot.cloud_pan.x, "y": plot.cloud_pan.y},
        "zoom": plot.cloud_zoom,
        # The second cloud's four, so a dump says the two views are one rather
        # than leaving a reader to compare two pictures by eye.
        "reference_yaw": reference_plot.cloud_yaw,
        "reference_pitch": reference_plot.cloud_pitch,
        "reference_pan": {"x": reference_plot.cloud_pan.x, "y": reference_plot.cloud_pan.y},
        "reference_zoom": reference_plot.cloud_zoom,
        # The cloud's cell count, from the plot rather than from here, because
        # the plot is what owns the cell grid.
        "cloud": plot.cloud_report(),
        # The picture's rect in real pixels against the plot drawn into it, so a
        # dump says whether a texel meets a pixel of the screen one to one.
        "picture_physical": _picture.size * SaUI.scale() if _picture != null else Vector2.ZERO,
        "plot": plot.plot_size,
        # The samples, the live grid and the fixed grid's digest, from the plot
        # that owns them. The digest is what stays the same across panel sizes.
        "bins": plot.bins_report(),
        # Where the vectorscope's skin tone line points, and where the number
        # came from.
        "skin_hue": {"radians": SKIN_HUE, "degrees": rad_to_deg(SKIN_HUE), "source": "darktable color_vocabulary.c"},
        # Whether the pass is registered and how often it ran, from the service
        # that decides when.
        "runs": reduction.runs,
        "service": _service_report(),
        "spectrogram": spectrogram.report(),
    }


## Whether `SaReductions` holds the pass now, beside what the service reports.
func _service_report() -> Dictionary:
    var service := SaReductionService.shared()
    if service == null:
        return {"holds": false}
    var report := service.report()
    report["holds"] = service.holds(reduction)
    return report


func _zoom_by(factor: float) -> void:
    var zoom := clampf(plot.cloud_zoom * factor, SaGraphPlot.CLOUD_ZOOM_MIN, SaGraphPlot.CLOUD_ZOOM_MAX)
    _look_from(plot.cloud_yaw, plot.cloud_pitch, plot.cloud_pan, zoom)


## The pass runs only when the picture changed, so a viewpoint that moved has to
## say the last one is stale or the docker turns nothing until the next stroke.
##
## The reference's own guard is cleared beside it. `_refresh_reference` returns
## early on an unchanged picture, mode and panel, and a viewpoint is none of the
## three, so the second cloud would hold the angle it was binned at however far
## the first one turned.
func _redraw_cloud() -> void:
    reduction.stale()
    _seen_reference_mode = ""


## Switches graph. Public because the capture harness and a test both change it
## without a click: the dropdown's popup is a real window a scenario cannot
## reach past.
func show_mode(mode_id: String) -> void:
    var spectral := mode_id == SaGraphSpectrogram.MODE
    graph_mode = mode_id if spectral else SaGraphPlot.mode_at(SaGraphPlot.index_of(mode_id))
    # The spectrum is of the canvas alone, so the source goes with the pictures.
    spectrogram.visible = spectral
    (_picture.get_parent() as Control).visible = not spectral
    _source_button.visible = not spectral
    if _mode_button != null:
        _mode_button.select_value(graph_mode)
    if _white_toggle != null:
        _white_toggle.visible = SaGraphPlot.is_waveform(graph_mode)
        StateToggle.show_state(_white_toggle, graph_mode == "waveform_white")
    if _scale_toggle != null:
        _scale_toggle.visible = _has_scale()
    if _reset_button != null:
        _reset_button.visible = graph_mode == "cloud"
    _tell_labels()
    # The counts are laid out per mode, so the ones on the GPU are the other
    # graph's and have to be taken again before anything is drawn.
    reduction.stale()


## Switches what is graphed: the canvas alone, the selected reference alone, or
## both side by side. Public for the capture and the tests, for the reason
## `show_mode` is.
func show_source(source_id: String) -> void:
    var known := false
    for entry: Array in SOURCES:
        if String(entry[0]) == source_id:
            known = true
    source = source_id if known else "canvas"
    if _source_button != null:
        _source_button.select_value(source)
    if _picture != null:
        _picture.visible = source != "reference"
    if _reference_picture != null:
        _reference_picture.visible = source != "canvas"
    reduction.stale()
    _seen_reference_mode = ""


## The reference the second plot graphs: the picture last clicked on the
## Reference docker's board, or null when there is none or the docker is not
## built. Looked up by name rather than injected, the way the docker's own
## capture step finds it.
func selected_reference() -> SaReferenceBoard.Picture:
    if not is_inside_tree():
        return null
    # Kept once found, because this is asked every frame now and a search of the
    # whole tree is not two integer comparisons.
    if _reference_docker == null or not is_instance_valid(_reference_docker):
        _reference_docker = get_tree().root.find_child(SaDockerIds.REFERENCE, true, false) as ReferenceDocker
    if _reference_docker == null:
        return null
    var picture := _reference_docker.board_view.selected()
    return picture if picture != null and not picture.is_missing() else null


## Dims or offers Reference and Both for *picture*, the reference selected now
## or null, when that changed since the last call. Public for the tests, which
## cannot put the two dockers in a tree, for the reason `show_source` is.
func follow_reference(picture: SaReferenceBoard.Picture) -> void:
    if (picture != null) != _offers_reference:
        _offer_reference(picture != null)


## Offers Reference and Both only while there is a reference to graph. Without
## one they are dimmed, take no press, and say why on hover. A painter already
## on one of them stays on it, dimmed, rather than being moved back to the
## canvas under their hand, and the graph shows nothing until a picture is
## selected.
func _offer_reference(offered: bool) -> void:
    _offers_reference = offered
    var rows: Array = []
    for entry: Array in SOURCES:
        rows.append({"id": String(entry[0]), "label": tr(String(entry[1])), "disabled": not offered and entry[0] != "canvas"})
    _source_button.set_choices(rows)
    # Rows built after the docker's own theme pass draw at the engine's default
    # size, which the first capture showed as a list whose words shrank the
    # moment a reference was selected. So they are given the pass here.
    if _source_button.is_inside_tree():
        SaUI.apply_ui_theme(_source_button)
    if offered:
        return
    for id: StringName in [&"reference", &"both"]:
        _source_button.popup.label_button(id).tooltip_text = tr("Select a picture on the Reference docker first.")


## Gives a dropdown of the row the width of its longest row beside its arrow,
## so the source reads "Canvas" rather than its arrow alone and the mode reads
## "Waveform (W)" whole. `SaChoiceButton` clips its words, which keeps them out
## of its minimum size, so the row gave the source what the expanding mode
## button left, and at the shipped width that was the arrow. The longest row
## rather than the shown one, so the row breaks at one width whatever is
## picked. Measured on every theme change, because the font follows the UI
## scale and the painter's font size.
func _fit_choice(button: SaChoiceButton) -> void:
    if button == null:
        return
    var font := button.get_theme_font(&"font")
    var font_size := button.get_theme_font_size(&"font_size")
    var widest := 0.0
    for label: String in button.choice_labels():
        # As the button draws it, through the catalogue, since the label was
        # written in the language Sara started in.
        widest = maxf(widest, font.get_string_size(button.atr(label), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    # The theme's arrow rather than the button's icon, because the button takes
    # the arrow in its own handler of the change this answers, which runs after.
    var glyph := button.icon
    if button.has_theme_icon(&"arrow", &"OptionButton"):
        glyph = button.get_theme_icon(&"arrow", &"OptionButton")
    var arrow := 0.0
    if glyph != null:
        arrow = float(glyph.get_width())
        var cap := button.get_theme_constant(&"icon_max_width")
        if cap > 0:
            arrow = minf(arrow, float(cap))
        arrow += float(button.get_theme_constant(&"h_separation"))
    var frame := button.get_theme_stylebox(&"normal").get_minimum_size().x
    button.custom_minimum_size.x = ceilf(widest + arrow + frame)


## A language picked after the docker was built widens the two choices to the
## new words, as a theme change does.
func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED:
        _fit_choice(_mode_button)
        _fit_choice(_source_button)


## The second plot, when the source asks for one and the reference, the mode
## or the panel changed since the last pass. The upload and the pass are
## paid for a change and never per frame, which `reference_passes` counts.
func _refresh_reference() -> void:
    if source == "canvas" or graph_mode == SaGraphSpectrogram.MODE:
        return
    var picture := selected_reference()
    var wanted := _wanted_plot_size(_reference_picture)
    if picture == _seen_reference and graph_mode == _seen_reference_mode and wanted == _seen_reference_plot:
        return
    if picture != _seen_reference:
        # A board's canvas element has no image to upload, and the canvas
        # already has its own plot on the other side of this docker, so the
        # element is read as no reference rather than a second copy.
        var uploadable := picture != null and not picture.live and picture.image != null
        _reference_texture = SaGraphPlot.upload_image(picture.image) if uploadable else null
        _seen_reference = picture
    _seen_reference_mode = graph_mode
    _seen_reference_plot = wanted
    if _reference_texture == null:
        _reference_picture.texture = null
        return
    if wanted != reference_plot.plot_size:
        _reference_picture.texture = null
        reference_plot.set_plot_size(wanted)
    # The picture's own space, which for a PNG is display sRGB and passes
    # through, and for an EXR is linear and is encoded: the same values the
    # canvas's graph shows for the composite through the view.
    var space := picture.source_space if picture.source_space != null else SaColorSpace.srgb()
    var ok := reference_plot.run_over_document(_reference_texture, _reference_texture.size, space, graph_mode)
    if ok:
        reference_passes += 1
        if _reference_picture.texture != reference_plot.shown:
            _reference_picture.texture = reference_plot.shown
        _reference_picture.queue_redraw()


## Switches the histogram's count axis and the vectorscope's radius between
## darktable's log and the plain linear. Public for the capture and the tests,
## for the reason `show_mode` is. Both plots take it, so the reference's graph
## reads on the same scale as the canvas's, and both are binned again because
## the picture is drawn from the counts in the same pass.
func show_scale(scale_id: String) -> void:
    scale = "linear" if scale_id == "linear" else "log"
    plot.scale = scale
    reference_plot.scale = scale
    if _scale_toggle != null:
        StateToggle.show_state(_scale_toggle, scale == "linear")
    _tell_labels()
    reduction.stale()
    _seen_reference_mode = ""


## Whether the graph shown has a scale to toggle.
func _has_scale() -> bool:
    return graph_mode == "histogram" or graph_mode == "vectorscope"


## Tells the labels the four facts they draw from, and asks them to draw them.
## They are the labels' own members now, so this is the one place that writes
## them.
##
## Called where the mode or the scale moves and from `refresh`, which is the
## pass that runs when the canvas's document changed under the docker - a
## Convert is a new composite, and the hue letters are placed for the
## document's colour space.
func _tell_labels() -> void:
    if _scale == null:
        return
    _scale.graph_mode = graph_mode
    _scale.has_value_axis = has_value_axis()
    _scale.scale_mode = scale
    _scale.color_space = _document_space()
    _scale.queue_redraw()


## The colour space the hue letters are placed for, or null when there is no
## canvas or no document in it yet.
func _document_space() -> SaColorSpace:
    if target_canvas == null or not is_instance_valid(target_canvas):
        return null
    var easel := target_canvas.easel
    if easel == null or easel.document == null:
        return null
    return easel.document.color_space


## The RGBW toggle. Two entries of `MODES` from the shader's side and one switch
## from the painter's, so the stored choice and a scenario still name a mode.
func _on_white_toggled(pressed: bool) -> void:
    show_mode("waveform_white" if pressed else "waveform")


## Whether the graph shown puts value up the side, which is the only case a
## nought-to-a-hundred scale down the left says anything true about. The
## histogram's vertical is a population and the two Oklab graphs have no single
## axis at all. The rule lives here and the answer is told to `SaGraphLabels`,
## which writes the numbers.
func has_value_axis() -> bool:
    return SaGraphPlot.is_waveform(graph_mode) or graph_mode == "parade"


## The pass as the service runs it, on the service's decision rather than a
## poll of the docker's own. The reference is followed here too, because the
## selected picture is part of what the decision watches.
func _scheduled_pass(_easel: SaEasel) -> void:
    follow_reference(selected_reference())
    _refresh_reference()
    if source != "reference":
        refresh()


## What of the docker's own the service's decision watches beside the paint and
## the view: the panel sizes, since a docker dragged wider changes the picture
## without changing anything the easel counts, and the selected reference.
func _scheduled_shape() -> Array:
    return [_wanted_plot_size(_picture), selected_reference(), _wanted_plot_size(_reference_picture)]


## Takes a pass now, whatever the poll thinks. The capture harness and the
## tests want the picture without waiting for a frame that changed.
func refresh() -> void:
    var easel := target_canvas.easel if target_canvas != null else null
    if easel == null or easel.output == null or easel.document == null or graph_mode == SaGraphSpectrogram.MODE:
        return
    # The plot reads every texel, so what the window left unshown goes in first.
    easel.flush()
    _tell_labels()
    _resize_plot()
    var mapping := SaReductionService.view_of(target_canvas, easel.document.canvas_size)
    var ok := plot.run(
        easel.output,
        easel.document.canvas_size,
        Vector2(mapping[0], mapping[1]),
        Vector2(mapping[2], mapping[3]),
        Vector2(mapping[4], mapping[5]),
        easel.document.color_space,
        graph_mode,
        _shown_pixels()
    )
    if ok and _picture.texture != plot.shown:
        _picture.texture = plot.shown
    # The pass rewrote the picture in place, and the rect above is only told
    # about a new object, so the frame that shows it is asked for here.
    if ok:
        _picture.queue_redraw()


## The picture *panel* has room for, in real pixels rather than logical ones,
## so a graph on a 4K display is drawn at the resolution it is shown at.
func _wanted_plot_size(panel: TextureRect) -> Vector2i:
    if panel == null:
        return SaGraphPlot.PLOT
    var rect := panel.size
    if rect.x <= 0.0 or rect.y <= 0.0:
        return SaGraphPlot.PLOT
    return SaGraphPlot.round_size(Vector2i((rect * SaUI.scale()).round()))


## Hands the panel's size to the plot, letting go of the old picture first. The
## `TextureRect` holds its own reference to the `Texture2DRD`, and that object
## holds the RID the `SaTexture` frees on the next line, so a rect still
## pointing at it would draw a freed texture.
func _resize_plot() -> void:
    var wanted := _wanted_plot_size(_picture)
    if wanted == plot.plot_size:
        return
    _picture.texture = null
    plot.set_plot_size(wanted)


## How many real pixels the canvas's view is, which is how many samples a pass
## takes. Zero without a view, which the plot reads as one a texel.
func _shown_pixels() -> Vector2i:
    var view := SaCanvasView.for_canvas(target_canvas) if target_canvas != null else null
    if view == null:
        return Vector2i.ZERO
    return SaUI.to_physical_v(Vector2i(view.get_viewport_size()))


## Switches the graph, `{"graph": "vectorscope"}`. Static because the harness
## has a tree and no docker.
##
## The node is used untyped on purpose. Writing `node as GraphDocker` here, a
## cast to this script's own class inside its own static function, leaves the
## script alive at exit and 545 objects with it, which the suite's leak check
## catches and nothing else does.
static func capture_mode(tree: SceneTree, raw: Variant) -> void:
    var spec: Dictionary = raw if raw is Dictionary else {"mode": String(raw)}
    for node in tree.root.find_children(SaDockerIds.GRAPH, "", true, false):
        if not node.has_method("show_mode"):
            continue
        if spec.has("mode"):
            node.show_mode(String(spec["mode"]))
        if spec.has("source"):
            node.show_source(String(spec["source"]))
        if spec.has("scale"):
            node.show_scale(String(spec["scale"]))
        # The cloud's viewpoint. A drag cannot be injected: an injected motion
        # never reaches a `gui_input`, so a scenario turns the cloud through the
        # same three methods the drag calls.
        if spec.get("reset", false):
            node.call("reset_view")
        if spec.has("turn"):
            var by := spec["turn"] as Array
            if by != null and by.size() >= 2:
                node.call("turn_by", Vector2(float(by[0]), float(by[1])))
        if spec.has("pan"):
            var by_pan := spec["pan"] as Array
            if by_pan != null and by_pan.size() >= 2:
                node.call("pan_by", Vector2(float(by_pan[0]), float(by_pan[1])))
        if spec.has("zoom"):
            node.call("zoom_by", float(spec["zoom"]))
        # The drag, which says *where* it started: both clouds have to answer a
        # gesture on either panel, so the panel is the thing under test.
        var panel_id: String = String(spec.get("from", "canvas"))
        if spec.has("drag"):
            var by_drag := spec["drag"] as Array
            if by_drag != null and by_drag.size() >= 2:
                var shift: bool = bool(spec.get("shift", false))
                node.call("drag_on", panel_id, Vector2(float(by_drag[0]), float(by_drag[1])), shift)
        if spec.has("wheel"):
            node.call("wheel_on", panel_id, float(spec["wheel"]) > 0.0)
        node.refresh()
        node.call("_refresh_reference")
        print(
            (
                "SaCapture: graph %s at %s, view %s"
                % [node.graph_mode, node.plot.plot_size, JSON.stringify(node.call("view_report"))]
            )
        )
        return
    push_warning("SaCapture: no Graph docker to switch")


## The cloud viewpoint, for the state dump. Empty when the docker is not built.
##
## Untyped on purpose: a cast to this file's own `class_name` inside a static
## function leaks the script.
static func capture_state(root: Window) -> Dictionary:
    var docker := root.find_child(SaDockerIds.GRAPH, true, false)
    if docker == null or not docker.has_method("view_report"):
        return {}
    return docker.call("view_report")
