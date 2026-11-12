## Preferences > Display: the highlight roll-off, the gamut mapping, the display
## exposure, where a new document's relief light starts, the two gamuts, the two
## proofs, the grid, whether it shows and its spacing, and what Ctrl+0 shows. All
## of it but the gamut mapping is a view: it changes what the canvas shows and
## never what it stores. The mapping is the one row here that an export reads
## too, and it is beside the roll-off because it is that operator's tail rather
## than an export option.
##
## **Declared rather than built, all six sections of it**. The three sections
## with nothing live in them went first and the three that have something
## followed: the roll-off's own dimming is `dims` on the switch now, the two
## sliders and the Stops slider hang their side effects on `page.row_changed`,
## and the page's own `DIMMED_ALPHA` is gone, so the rows the switch governs
## fade to `SaPage.DIMMED_ALPHA` like every other dimmed row in the application
## and give the keyboard up while they are faint.
class_name SaDisplayPage
extends SaSettingsPage

## The registry's name for no mode at all, which is what the first row of the
## View transform dropdown carries.
const NO_MODE := SaViewTransformRegistry.NORMAL

## The roll-off toggle's registry id. Named here because the Highlight roll-off
## switch is that toggle rather than a mode, so its name comes from the toggle's
## descriptor and not from a mode's. `ui/menus/view_menu.gd` names the same id
## for the same reason.
const ROLLOFF_ID := &"highlight_rolloff"

## The rows of the View transform dropdown that are not modes, which is the
## ordinary view alone. The roll-off is not a row here but the switch further
## down, as it is a toggle of its own in the View menu, so the page sets one
## setting once and this list says only which mode the canvas is in.
const PLAIN_ROWS: Array[StringName] = [SaViewTransformRegistry.NORMAL]

## The monitor's profile row, by the key Help > Display Settings... opens the
## page on, because the profile row is below the fold of a page opened at its
## top. Tablet Settings... names no row, its page starting with what it is for.
const PROFILE_ROW := &"display_profile"

## The Stops slider's row, by the key View > Exposure Stops... opens the page
## on. Declared rather than left to the label it was derived from, so a row
## retitled "Exposure stops" keeps the door, and `stops` because a Display
## scenario already drives the row by that key.
const STOPS_ROW := &"stops"

## What each Wider display entry does, by the id the setting stores.
const FILL_SENTENCES := {
    SaDisplayFill.CORRECT:
    "Converts the picture into the display profile, so every colour is shown as it is stored and exported.",
    SaDisplayFill.NATIVE:
    (
        "Sends the picture's numbers to the display unconverted, so its red, green and blue are the panel's own, "
        + "more saturated than the picture looks anywhere else."
    ),
    SaDisplayFill.EVEN:
    (
        "Stretches red, green and blue outward by one ratio, the largest none of them clips at, so the picture is "
        + "more saturated and no primary is stretched more than another."
    ),
}

## Redrawn by both roll-off sliders, so the picture follows the drag.
var _curve: SaCurvePlot = null
var _gamut: SaGamutPreview = null

## The Display exposure switch, held so the Stops slider can put it on. A slider
## that silently does nothing until a switch above it is found is a slider that
## reads as broken.
var _exposure_check: CheckButton = null

## The Stops slider itself, held so a scenario can move it the way a hand does.
## The View menu's three nudges are one row that opens this page now, so this
## control is the only way a painter changes the exposure and a run has to be
## able to reach it.
var _exposure_slider: HSlider = null

## The rows of the Highlight roll-off section under its switch, so they can say
## whether the operator they describe is running. Read off the first governed
## row rather than kept from a section builder, because the section is declared
## now and the container is the builder's.
var _rolloff_rows: VBoxContainer = null

## The Highlight roll-off switch, held for the same reason one row further up.
## It is the one control on the page that writes the roll-off, and the View
## menu's toggle writes the same setting, so the dump reads the two back side by
## side.
var _rolloff_check: CheckButton = null

## The View transform dropdown, and what each of its items means. The ids are
## the registry's own, with the ordinary-view row carrying no mode.
var _view_option: SaChoiceButton = null
var _view_items: Array[StringName] = []

## The View transform row, whose value is the mode the canvas is in. It has no
## binding, being a custom row, so `_sync_view_transform` writes the mode into it
## and the Shape check rows' rule reads it from there.
var _view_row: SaPageRow = null

## The Shape check section's rows, a class of their own beside this page, held
## so a test and the dump can read whether they are live.
var _shape_rows := SaShapeCheckRows.new()

## The Display profile row and the monitor profile file under it.
var _monitor_rows := SaMonitorProfileRows.new()

## The Proof gamut row and the proof's profile file under it.
var _proof_rows := SaProofProfileRows.new()

## The picked row's own sentence, under the list rather than in a tooltip.
##
## The sentence that says, for False Colour, that grey is normal and coloured
## maps are HDR helps only where it is read, and a tooltip nobody hovers is not
## read. A tooltip is an answer to a question a painter has to know to ask, and
## this is a page somebody opens because they do not know.
var _view_sentence: Label = null

## The second copy of the gamut picture, with no material on it, so the first
## one's operator is read against something rather than in the abstract.
var _gamut_plain: SaGamutPreview = null

## The five declared rows whose built control or line this page reads back, kept
## from [method build] because a control exists only once the base has realized
## the declaration. A row rather than a key: `SaPage.adopt_row` files a row
## under the key its label gave it, so a key written down here would have to be
## kept in step with a label by hand.
var _rolloff_row: SaPageRow = null
var _curve_row: SaPageRow = null
var _sentence_row: SaPageRow = null
var _exposure_row: SaPageRow = null
var _stops_row: SaPageRow = null

## The keys the two roll-off sliders announce themselves under, for the redraw
## that hangs on `page.row_changed`.
##
## Read off the declared rows rather than written down, for the reason
## `ui/settings/arrange/workspace_page.gd` carries: `SaPage` binds a row's key to
## `row_changed` when it adopts the row, which is before a `named()` chained
## after it could move it. Neither slider names itself, so the key its label
## gave it is the key it announces.
var _redraw_on: Array[StringName] = []

## Whether the gamut pair shows the stand-in `SaGamutPictureBake` gives it.
var _awaiting_picture := false


## The base declares and realizes in its own `_init`, so every control exists by
## the time `super()` returns and this is where the page reads them back.
func _init() -> void:
    super()
    _rolloff_check = _rolloff_row.control as CheckButton
    _rolloff_rows = _curve_row.line.get_parent() as VBoxContainer
    _view_sentence = _sentence_row.line as Label
    _exposure_check = _exposure_row.control as CheckButton
    _exposure_slider = _stops_row.control as HSlider
    _sync_view_transform()
    _describe_fills(page.row(&"display_fill").control as SaChoiceButton)


## The nine sections. The first four carry something live, which is why they
## were the last ones built by hand.
func build(ui: SaPage) -> void:
    _redraw_on.clear()
    _declare_view_transform(ui)
    _declare_rolloff(ui)
    _declare_gamut_mapping(ui)
    _declare_exposure(ui)
    _declare_relief(ui)
    _declare_plain_rows(ui)
    _declare_zoom(ui)
    ui.row_changed.connect(_on_page_row_changed)


## What Ctrl+0 shows, and so how a new or opened document opens: the fit, the
## fit zoomed in or out by a value the painter chooses, or actual pixels. The
## whole picture at a Size of 100 is the fit, a Size under it zooms out and one
## over it in, and actual pixels is the Pixels figure's 100%. The Size is dimmed
## while the row shows actual pixels, which it has nothing to say about. The
## labels are translated here, as `SaShapeCheckRows._method_choices` says why.
func _declare_zoom(ui: SaPage) -> void:
    var zoom := ui.section("Zoom")
    var shows: Array = [
        {"id": SaView.RESET_WHOLE, "label": tr("The whole picture")},
        {"id": SaView.RESET_PIXELS, "label": tr("Actual pixels")},
    ]
    (
        zoom
        . choice("Reset zoom to", shows, SaSettings, ^"reset_zoom")
        . explain(
            tr(
                (
                    "What Reset Zoom (Ctrl+0) shows, centred, and how a new or opened picture opens. "
                    + "Ctrl+1 always shows actual pixels."
                )
            )
        )
        . named(&"reset_zoom")
        . node("ResetZoomOption")
        . dims(&"reset_zoom_size", [SaView.RESET_WHOLE])
    )
    (
        zoom
        . number("Size", SaView.RESET_SIZE_MIN, SaView.RESET_SIZE_MAX, SaSettings, ^"reset_zoom_size")
        . explain(
            tr(
                (
                    "The Zoom figure the whole picture is shown at. 100 fits it between the bars and the dockers, less "
                    + "leaves a margin round it and more lets it overflow a little."
                )
            )
        )
        . with_suffix("%")
        . named(&"reset_zoom_size")
        . node("ResetZoomSizeSpin")
    )
    (
        zoom
        . toggle("Whole steps", SaSettings, ^"integer_zoom")
        . explain(
            tr(
                (
                    "Zoom in and out land on 100%, 200%, 300%, 400%, 800% and 1600% of actual pixels, "
                    + "so a pixel is never drawn a fraction wider than its neighbour. For pixel art."
                )
            )
        )
        . named(&"integer_zoom")
    )


## The gamut mapping row, a section of its own under the roll-off.
##
## Here rather than on Colour Spaces, although an export to an integer file
## reads it too and it is therefore also a fact about colour leaving Sara,
## because a painter looks for it where it acts: the mapping is what happens to
## the tail the roll-off leaves, after the display matrix and outside the
## rolloff's branch, so it belongs under the operator it finishes.
##
## View > Gamut Mapping is the same setting as a toggle, on for Oklab and off
## for clip, and Oklab is the default. The row is bound to the
## setting and the page refreshes on every view key, so the toggle moves it.
##
## A section of its own rather than a row under the roll-off's switch, because
## the roll-off dims and disables the rows it governs and this one applies
## whether the roll-off is running or not. The entry's id is the key the setting
## stores, so the row needs no handler.
func _declare_gamut_mapping(ui: SaPage) -> void:
    var section := ui.section(tr("Gamut mapping"))
    var modes: Array = [
        {"id": SaGamutMapping.CLIP, "label": tr("Clip")},
        {"id": SaGamutMapping.OKLAB, "label": tr("Oklab, hue held")},
    ]
    var row := section.choice(tr("Gamut mapping"), modes, SaSettings, ^"gamut_mapping")
    row.named(&"gamut_mapping").node("GamutMappingOpt").explain(
        tr(
            (
                "What happens to a colour the screen or an 8 or 16-bit file cannot hold, a negative channel above all. "
                + "Clip cuts each channel on its own, which is what other programs write and can turn the hue. "
                + "Oklab keeps the lightness and the hue and gives up chroma until the colour fits, and is the default. "
                + "View > Gamut Mapping switches between the two. Stored pixels, EXR and 32-bit TIFF are never touched."
            )
        )
    )


## The one row that says what the canvas is showing. Blender's View Transform,
## over Sara's own list: the ordinary view, then every registered mode, so False
## Colour and Display encoding off are entries here and a module's mode is one
## without a line being added.
##
## It writes nothing of its own. Every row is the view transform registry's
## mode, which is what the View menu writes too, so the two doors cannot
## disagree. The roll-off is not a row, being a toggle that runs under the
## ordinary view rather than a view of its own, and the switch in the section
## below is its one door on this page. A custom row rather than a bound
## one, because the registry is found at build time and is no settings object.
func _declare_view_transform(ui: SaPage) -> void:
    var rows := ui.section("View transform")
    # Sara's own choice button rather than the engine's dropdown. The rows are
    # keyed on their position, which the dump and the scenarios already read.
    _view_option = SaMake.choice(null, "ViewTransformOpt")
    _view_items = [NO_MODE]
    var view_choices: Array = []
    var registry := _view_transforms()
    # The plain row is named by the registry rather than here, so one view has
    # one name on the page and on the View menu, the two surfaces that set it.
    view_choices.append({"id": 0, "label": tr(_plain_row_name(0))})
    if registry != null:
        for descriptor in registry.list_modes():
            _view_items.append(descriptor.id)
            view_choices.append({"id": _view_items.size() - 1, "label": tr(descriptor.display_name)})
        if not registry.changed.is_connected(_sync_view_transform):
            registry.changed.connect(_sync_view_transform)
    _view_option.set_choices(view_choices)
    _describe_view_items()
    if not EventBus.tonemap_changed.is_connected(_on_tonemap_changed):
        EventBus.tonemap_changed.connect(_on_tonemap_changed)
    _view_option.choice_picked.connect(func(row: Variant) -> void: _select_view_transform(int(row)))
    _view_row = (
        rows
        . custom("View transform", _view_option)
        . explain(tr("How the canvas displays colour. Each option is explained when you select it."))
        . node("ViewTransformOpt")
    )
    # Under the list, so the sentence for whatever is picked is on screen
    # without a hover. It is the registry's own sentence, the same one the row
    # and the View menu carry, so there is still one wording per mode. A note
    # row carries no label, so it is named rather than left to be filed under a
    # key its empty label made.
    _sentence_row = rows.note("").named(&"view_sentence")
    # The shape check's options, a section under the list rather than a sixth
    # mode, so the check is one tool and not a menu of checks.
    _shape_rows.declare(ui, _view_row)


## The label for a row `PLAIN_ROWS` names, a row that is not a mode and so has
## no `list_modes` descriptor to be named by. The ordinary view's is the
## registry constant, because it is the absence of a mode and nothing registers
## it.
func _plain_row_name(index: int) -> String:
    if index < 0 or index >= PLAIN_ROWS.size():
        return ""
    return SaViewTransformRegistry.NORMAL_NAME


## The Highlight roll-off switch's label, which is its own descriptor's name, so
## the switch and the View menu's toggle carry one name.
##
## A page built with no registries falls back to the raw id rather than to a
## second copy of the name, which would drift from the descriptor's. Only the suite
## builds such a page, and a painter never sees an id because the application
## always has its registries by the time Preferences opens.
func _rolloff_name() -> String:
    var registry := _view_transforms()
    var descriptor := registry.get_descriptor(ROLLOFF_ID) if registry != null else null
    return descriptor.display_name if descriptor != null else String(ROLLOFF_ID)


## Puts a sentence on every row of the dropdown, and it is the registry's own
## sentence: the View menu lists the same modes and shows the same text, so the
## two surfaces cannot drift.
##
## The registry's sentence rather than a paraphrase in the description beside
## the control, which goes stale the moment a mode is registered and says
## nothing about a module's mode.
func _describe_view_items() -> void:
    var registry := _view_transforms()
    if registry == null or _view_option == null:
        return
    # On the row's own button, because a row is a Control now and the sentence
    # belongs to the thing a pointer rests on.
    for i in _view_items.size():
        var label := _view_option.popup.label_button(SaChoiceButton.row_id_of(i))
        if label != null:
            label.tooltip_text = _sentence_for_row(i)


## The sentence for row *index*. The first row is not a mode, so it takes the id
## `PLAIN_ROWS` puts beside it: the ordinary view, which has no descriptor and
## whose sentence the registry keeps as a constant for exactly this reason.
## Translated here, so each sentence is a constant or a descriptor's field the
## template reads, which a `tr` round the registry's `tooltip_for` was not.
func _sentence_for_row(index: int) -> String:
    var registry := _view_transforms()
    if registry == null or index < 0 or index >= _view_items.size():
        return ""
    var described: StringName = PLAIN_ROWS[index] if index < PLAIN_ROWS.size() else _view_items[index]
    if described == SaViewTransformRegistry.NORMAL:
        return tr(SaViewTransformRegistry.NORMAL_TOOLTIP)
    var descriptor := registry.get_descriptor(described)
    if descriptor == null:
        return ""
    return tr(descriptor.tooltip)


## The View transform dropdown as the state dump sees it: every row with the
## label it shows and the sentence it carries, plus which row is picked and what
## the collapsed control says.
##
## A tooltip is not in a screenshot, so this is the only proof of it. A static
## function that finds the page itself, the way `SaDockerWindowCapture.capture_hide` and
## `GraphDocker.capture_mode` do, so `sa_state_report.gd` needs one line and no
## knowledge of what a row is.
##
## The page is found by method rather than by cast, because a cast to a
## `class_name` inside a static function of that same class leaks the script.
static func capture_state(root: Window) -> Dictionary:
    for node in root.find_children("*", "VBoxContainer", true, false):
        if node.has_method("view_transform_report"):
            return node.call("view_transform_report")
    return {}


## This page's own half of [method capture_state], so the dump holds no second
## copy of what a row is.
func view_transform_report() -> Dictionary:
    if _view_option == null or not is_instance_valid(_view_option):
        return {}
    var rows: Array = []
    var labels := _view_option.choice_labels()
    for i in labels.size():
        var button := _view_option.popup.label_button(SaChoiceButton.row_id_of(i))
        rows.append({"label": labels[i], "tooltip": button.tooltip_text if button != null else ""})
    return {
        "selected": int(_view_option.selected_value() if _view_option.selected_value() != null else -1),
        "control_tooltip": _view_option.tooltip_text,
        "rows": rows,
        # This is a claim about two controls agreeing, and a screenshot of a
        # switch is a shape rather than a state. The setting is here beside the
        # switch, because the bug was the two disagreeing rather than either
        # being wrong on its own.
        "rolloff_setting": SaSettings.tonemap_highlights,
        "rolloff_switch": _rolloff_check.button_pressed if _rolloff_check != null else false,
        # The Shape check rows under the view they belong to: the mode the
        # list is on and whether the rows answer a painter, read from one dump.
        "view_mode": String(_view_row.value) if _view_row != null else "",
        "shape_check_live": _shape_rows.live(),
        # The section below the switch un-dims, so the dump
        # carries what it is drawn at rather than leaving it to a screenshot.
        "rolloff_rows_alpha": _rolloff_rows_alpha(),
        # And whether they answer a painter. One entry per row under the switch,
        # beside the alpha, so the pair is read from one dump.
        "rolloff_rows_editable": _rolloff_rows_editable(),
        # The switch itself, which is live in both states because it is the
        # control that changes them.
        "rolloff_switch_editable":
        # The graph, sampled rather than photographed. Whether a line bends where
        # the Knee slider says it does is a claim about numbers, and counting
        # pixels in a screenshot of a graph is the least reliable way
        not _rolloff_check.disabled if _rolloff_check != null and is_instance_valid(_rolloff_check) else false,
        # to read one.
        "rolloff_curve": _curve.curve_report() if _curve != null and is_instance_valid(_curve) else {},
        # The exposure, under the two names the settings file stores it by. The
        # View menu writes neither, so what is read is that the slider does and
        # that neither key moved.
        "display_exposure_stops": SaSettings.display_exposure_stops,
        "display_exposure_on": SaSettings.display_exposure_enabled,
        # The sentence under the list, which a screenshot of a dimmed paragraph
        # is a poor reading of.
        "view_sentence": _view_sentence.text if _view_sentence != null and is_instance_valid(_view_sentence) else "",
        # And the pair of gamut pictures: the same texture in both, an operator
        # on one of them and none on the other.
        "gamut_pair": _gamut_pair_report(),
    }


## The two copies of the gamut picture, for the dump.
##
## What has to be read is that they are the same picture and that only one of
## them is being operated on, and neither is visible in a shot of two coloured
## strips: the material is the operator and a screenshot has no material in it.
##
## Both halves carry a material, so `plain_operated` is the roll-off flag rather
## than the presence of one, and every uniform either half sets is listed beside
## it. A shot of the pair says whether they read as one picture, and only these
## say why.
func _gamut_pair_report() -> Dictionary:
    var live: bool = _gamut != null and is_instance_valid(_gamut) and _gamut_plain != null and is_instance_valid(_gamut_plain)
    if not live:
        return {"count": 0, "operated": false, "plain_operated": false, "same_texture": false}
    var operated := _gamut.shader_report()
    var plain := _gamut_plain.shader_report()
    var same_texture: bool = _gamut.texture == _gamut_plain.texture
    return {
        "count": 2 if same_texture else 0,
        "operated": bool(operated["uniforms"].get("tonemap_enabled", false)),
        "plain_operated": bool(plain["uniforms"].get("tonemap_enabled", false)),
        "same_texture": same_texture,
        "same_shader": operated["shader"] == plain["shader"] and operated["shader"] != "",
        "operated_uniforms": operated["uniforms"],
        "plain_uniforms": plain["uniforms"],
        "plain_mirrored": _gamut_plain.flip_h,
        "gap": _gamut_plain.get_global_rect().position.x - _gamut.get_global_rect().end.x,
        "rects": [_gamut.get_global_rect(), _gamut_plain.get_global_rect()],
    }


## Moves the Stops slider: `{"exposure_stops": 1.5}`.
##
## A step of its own because the View menu's Exposure Up and Exposure Down are
## gone: the slider is the whole of what a painter has now, and a run that
## cannot move it cannot show the exposure working at all. The settings window
## is a `Window`, so an injected click lands no better here than on the View
## transform dropdown one function up.
static func set_exposure_stops(root: Window, stops: float) -> String:
    for node in root.find_children("*", "VBoxContainer", true, false):
        if not node.has_method("drag_exposure_stops"):
            continue
        return node.call("drag_exposure_stops", stops)
    return "SaCapture: no open Display page to move the Stops slider on"


## This page's own half of [method set_exposure_stops]. Assigning `value` is
## what a drag does, `Range` announcing the change itself, and the announcement
## is what writes the row's binding and runs the rule that puts the exposure on.
func drag_exposure_stops(stops: float) -> String:
    if _exposure_slider == null or not is_instance_valid(_exposure_slider):
        return "SaCapture: the Display page has no Stops slider"
    _exposure_slider.value = stops
    return "SaCapture: Stops %.2f, exposure %s" % [_exposure_slider.value, SaSettings.display_exposure_enabled]


## What the rows under the roll-off switch are drawn at, one entry each, for a
## dump. Empty before the section is built.
func _rolloff_rows_alpha() -> Array:
    var out: Array = []
    if _rolloff_rows == null or not is_instance_valid(_rolloff_rows):
        return out
    for i in range(1, _rolloff_rows.get_child_count()):
        var row := _rolloff_rows.get_child(i) as Control
        if row != null:
            out.append(snappedf(row.modulate.a, 0.01))
    return out


## Whether each row under the switch answers a painter, one entry each, in the
## same order as [method _rolloff_rows_alpha] so a dump reads them as pairs.
##
## A row with no control of its own, the curve and the gamut strip, answers on
## its own `mouse_filter`, which is what turns "faint" into "not yours yet".
func _rolloff_rows_editable() -> Array:
    var out: Array = []
    if _rolloff_rows == null or not is_instance_valid(_rolloff_rows):
        return out
    for i in range(1, _rolloff_rows.get_child_count()):
        var row := _rolloff_rows.get_child(i) as Control
        if row == null:
            continue
        var live := row.mouse_filter != Control.MOUSE_FILTER_IGNORE
        for node in row.find_children("*", "Range", true, false):
            live = live and bool(node.get("editable"))
        for node in row.find_children("*", "BaseButton", true, false):
            live = live and not (node as BaseButton).disabled
        out.append(live)
    return out


## Reads the dropdown back out of the state, so the View menu, Ctrl+Y and this
## page always say the same thing while Preferences is open.
func _sync_view_transform() -> void:
    if _view_option == null or not is_instance_valid(_view_option):
        return
    var registry := _view_transforms()
    var mode: StringName = registry.mode if registry != null else NO_MODE
    var wanted := maxi(_view_items.find(mode), 0)
    _view_option.select_value(wanted)
    # The row's value is the mode, which is what the Shape check rows' rule
    # reads. Written before the refresh below, which is what applies the rule.
    if _view_row != null:
        _view_row.value = mode
    # The collapsed control says what the view is currently doing, so the
    # sentence is readable without opening the list. A dropdown's own tooltip is
    # the one a person meets first.
    var sentence := _sentence_for_row(wanted)
    _view_option.tooltip_text = sentence
    if _view_sentence != null and is_instance_valid(_view_sentence):
        _view_sentence.text = sentence
    # The roll-off switch follows the View menu's toggle rather than reading the
    # setting once, the Shape check rows follow the mode, and the rows the switch
    # governs follow the switch. One refresh does all three: every binding is
    # re-read into its control and every rule re-evaluated, and neither writes a
    # setting back, because a refresh pushes through the silent setters and the
    # page's own guard turns a control that answers its setter into nothing.
    page.refresh()


func _on_tonemap_changed(_enabled: bool) -> void:
    _sync_view_transform()
    # And the two pictures under the sliders, because the signal carries every
    # one of `SaSettingsApply.VIEW_KEYS`, the knee and the desaturation among
    # them, rather than from the slider callbacks alone, which leave a stale
    # curve and a stale pair when a setting moves from anywhere else, a scenario
    # writing preferences the plainest case of it. `_redraw_curve` writes no
    # setting, so there is no loop.
    _redraw_curve()


## Picking a row sets the mode and nothing else. The roll-off is the switch's
## alone: the list once wrote it from its first two rows, so one setting
## had two doors on one page, and the modes that ignore it ignore it in the
## shader.
##
## The page is synced by hand as well as by the registry's `changed`, because a
## page built with no registries has nothing to announce the pick, and the row's
## value is what the Shape check rows' rule reads.
func _select_view_transform(index: int) -> void:
    if index < 0 or index >= _view_items.size():
        return
    var registry := _view_transforms()
    if registry != null:
        registry.set_mode(_view_items[index])
    _sync_view_transform()


## The Highlight roll-off section: the switch, the curve, the pair of gamut
## pictures and the two sliders, with the switch dimming the four rows under it.
##
## **Dimmed and disabled, rather than dimmed and left live,** because picking
## the row un-dims the section, switches the operator on and makes the rows
## editable as one action, and rows editable before it would make the last of
## the three say nothing. Dimmed rather than hidden, because the curve and the
## two sliders describe an operator that is not running, which is worth saying,
## and setting one up before switching it on is a reasonable thing to want to
## do.
func _declare_rolloff(ui: SaPage) -> void:
    var rows := ui.section("Highlight roll-off")

    # The page's one door onto this setting, the View menu's toggle
    # being the other. It reads the descriptor, so the switch and the menu carry
    # one name. Named, because the label is the registry's and a key made from it
    # would change with the registry.
    _rolloff_row = rows.toggle(_rolloff_name(), SaSettings, ^"tonemap_highlights").named(&"tonemap_highlights")
    _rolloff_row.explain(
        tr(
            (
                "Values above 1.0 clip to white channel by channel, which shifts their hue: a hot "
                + "orange arrives pale yellow. The roll-off holds the ratios and lets the colour go "
                + "white instead. White stays white, and nothing here changes a single stored pixel. "
                + "The Tonemap filter runs this same operator, as its Paper method, so a Tonemap over "
                + "the whole picture does it too and the view steps aside."
            )
        )
    )

    _curve = SaCurvePlot.new()
    _curve.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)
    # Handed over at the row shape's own default width. `SaCurvePlot` asks for
    # `SIZE_EXPAND_FILL` in its constructor, and `SaPage` gives a custom control
    # back the width it was handed over with, so handing it over at `SIZE_FILL`
    # is what keeps the plot the size the page draws it at.
    _curve.size_flags_horizontal = Control.SIZE_FILL
    _curve_row = rows.custom("The curve", _curve)
    _curve_row.explain(
        tr(
            (
                "Two lines over stored value along the bottom. The bright one is how much of a colour's "
                + "chroma survives: flat up to the knee, then falling, slowly at first and faster the further "
                + "Desaturation is pushed, and drawn in what a red highlight of that value comes out as. At "
                + "the default knee of 1.0 it stays flat over every colour the screen can show and falls only "
                + "past white. The dim one is the magnitude, a ramp to white and flat after it at every knee, "
                + "because white stays white. The dashed mark is the knee, and under a knee above 1.0 a thin "
                + "line rises from white to the knee with how much of a colour's ratios are held rather than "
                + "clipped as the screen would clip them."
            )
        )
    )

    # Two copies of one picture: the operator on the left and the same texels
    # untouched on the right, for comparison, which is the only way to read a
    # roll-off at a glance: on its own the strip is a picture of colours, and a
    # painter has no way to know which of them the operator moved.
    #
    # The plain one runs the same shader with the operator off rather than no
    # material at all. Cleared, it drew the texels raw, and they are baked three
    # stops above white, so the display clipped them channel by channel and the
    # right half came up pale and flat beside a left half whose first act is to
    # bring that peak back to white. `SaGamutPreview`'s header has the whole of
    # it. Off, with the exposure that undoes the bake, the two halves are one
    # picture at Desaturation zero and every drag of it is the answer.
    _gamut = SaGamutPreview.new(true)
    _gamut.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)
    _gamut_plain = SaGamutPreview.new(false)
    # Both take the sliders, so the two materials agree about everything the
    # reference does not read. What differs is what the dump and the test read.
    _gamut_plain.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)
    # No width asked for here either, for the reason the curve above carries.
    var pair := SaGamutPreview.pair(_gamut, _gamut_plain)
    var pair_row := rows.custom("Every colour", pair)
    pair_row.explain(
        tr(
            (
                "The same operator run over every hue a screen can show, each falling from white at the "
                + "top to its own most saturated colour at the bottom, on the left, and the same picture "
                + "with nothing done to it on the right, mirrored so each hue meets itself. The curve above "
                + "says what happens to a value. This says what happens to a colour, which is the half the "
                + "Desaturation slider moves, and the pair is what makes the difference readable."
            )
        )
    )

    var knee := rows.slider("Knee", 0.05, SaSettingsValues.TONEMAP_KNEE_TOP, SaSettings, ^"tonemap_knee")
    knee.explain(
        tr(
            (
                "Where the roll-off starts. At 1.0, the default, only a colour brighter than the screen can "
                + "show changes. A lower knee starts the fading earlier, on colours the screen could show as "
                + "they are. A higher one leaves a colour just past white nearly as the screen shows it with the "
                + "roll-off off and holds the ratios more the nearer the knee it stands, all of them from the "
                + "knee on. No grey and no white moves."
            )
        )
    )
    var desaturation := rows.slider("Desaturation", 0.0, 1.0, SaSettings, ^"tonemap_desaturation")
    desaturation.explain(tr("How fast a highlight past the knee loses Oklab chroma. 0 keeps the colour, higher goes white."))
    _redraw_on.append(knee.key)
    _redraw_on.append(desaturation.key)

    # The switch's own row is not among them, because it is the control that
    # changes the state rather than something governed by it.
    _rolloff_row.dims(_curve_row).dims(pair_row).dims(knee).dims(desaturation)


## The display exposure. The viewer's, never the brush's: the slider on the bar
## multiplies paint, this one scales what is shown.
func _declare_exposure(ui: SaPage) -> void:
    var rows := ui.section("Display exposure")
    _exposure_row = rows.toggle("Display exposure", SaSettings, ^"display_exposure_enabled")
    _exposure_row.explain(tr("Scale the view by the stops below, before the roll-off. Never touches a pixel."))
    _stops_row = rows.slider(
        "Stops", -SaSettings.MAX_EXPOSURE_STOPS, SaSettings.MAX_EXPOSURE_STOPS, SaSettings, ^"display_exposure_stops"
    )
    _stops_row.explain(
        tr("How far to open or close the view. Each stop doubles or halves the light, and moving this puts the exposure on.")
    )
    _stops_row.step(0.25).named(STOPS_ROW)


## Where a new document's relief light starts. The light is each document's
## own, `SaReliefLight`, saved in its `.sad` and moved from View > Relief
## Light..., so these two bind to the setting and nothing on the canvas follows
## them: a new document, an opened picture and a `.sad` saved before the light
## was the document's start from them.
func _declare_relief(ui: SaPage) -> void:
    var rows := ui.section("Relief")
    (
        rows
        . slider("Light direction", 0.0, 360.0, SaSettings, ^"relief_light_angle")
        . explain(
            tr(
                (
                    "Where a new document's light on the paint's height comes from, in degrees clockwise from the top of the"
                    + " canvas. The open document keeps its own, set in View > Relief Light."
                )
            )
        )
        . step(15.0)
        . with_suffix("°")
        . named(&"relief_light_angle")
    )
    (
        rows
        . slider("Relief strength", 0.0, SaSettings.MAX_RELIEF_STRENGTH, SaSettings, ^"relief_strength")
        . explain(
            tr(
                (
                    "How steep a new document draws the paint's height. The height itself stays as painted. The open"
                    + " document keeps its own, set in View > Relief Light."
                )
            )
        )
        . step(0.25)
        . named(&"relief_strength")
    )
    var gloss := rows.slider("Gloss", 0.0, SaSettings.MAX_RELIEF_GLOSS, SaSettings, ^"relief_gloss")
    gloss.explain(tr("How strongly a ridge facing the light shines, in the view and in an export. 0 is no shine."))
    gloss.step(0.005).named(&"relief_gloss")


## A row wrote its binding. The two roll-off sliders redraw what they describe,
## and the Stops slider runs the rule below.
func _on_page_row_changed(key: StringName, value: Variant) -> void:
    if _redraw_on.has(key):
        _redraw_curve()
    elif _stops_row != null and key == _stops_row.key:
        _stops_moved(float(value))


## The Stops slider. Asking for stops is asking to see them, so this switches
## the exposure on the way View > Exposure Up does, and back off at zero, and
## refreshes the page so the switch above it still says what the canvas is
## doing.
##
## Without it the slider is dead on a fresh profile: the exposure is off by
## default, so a drag wrote a number nothing read. The number itself is the
## row's binding and is already written by the time this runs.
func _stops_moved(val: float) -> void:
    var wanted := not is_zero_approx(val)
    if SaSettings.display_exposure_enabled != wanted:
        SaSettings.display_exposure_enabled = wanted
    page.refresh()


func _redraw_curve() -> void:
    if _curve != null and is_instance_valid(_curve):
        _curve.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)
    if _gamut != null and is_instance_valid(_gamut):
        _gamut.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)
    # The reference half too, and it moves for none of it, which is the point:
    # the two differ by `tonemap_enabled` and the exposure, and by nothing a
    # slider touches.
    if _gamut_plain != null and is_instance_valid(_gamut_plain):
        _gamut_plain.configure(SaSettings.tonemap_knee, SaSettings.tonemap_desaturation)


## Gamuts, Proofs and Grid, on the same page as the three sections above.
func _declare_plain_rows(ui: SaPage) -> void:
    _monitor_rows.declare(ui, PROFILE_ROW)
    var gamuts := ui.sections[-1]
    # Under the display profile because it is a question about the same panel,
    # and not a proof, because it is how the canvas is shown all the time.
    (
        gamuts
        . choice("Wider display", _fill_option(), SaSettings, ^"display_fill")
        . explain(
            tr(
                (
                    "How the canvas fills a display wider than the document. Converted shows every colour as it is stored."
                    + " Unconverted sends the document's numbers as they are, stretching every colour to the panel's primaries."
                    + " Even stretch stretches red, green and blue by one Oklab ratio, the largest none of them clips at."
                    + " The window title shows the last two."
                )
            )
        )
        . named(&"display_fill")
        . node("DisplayFillOption")
    )
    _proof_rows.declare(ui)

    var proofs := ui.section("Proofs")
    (
        proofs
        . choice("Canvas proof", _mode_option(SaSettings.canvas_proof_mode), SaSettings, ^"canvas_proof_mode")
        . explain(tr("What Ctrl+Y shows on the canvas. A proof already on screen follows this at once."))
        . named(&"canvas_proof_mode")
    )
    (
        proofs
        . choice("Minimap proof", _mode_option(SaSettings.minimap_proof_mode), SaSettings, ^"minimap_proof_mode")
        . explain(tr("What Ctrl+Shift+Y shows in the Minimap docker, whatever the canvas is showing."))
        . named(&"minimap_proof_mode")
    )

    var grid := ui.section("Grid")
    # The switch beside the size it draws at, where a painter who found the size
    # looked for it. Bound to the setting View > Toggle Grid writes, so a press
    # there shows here while the page is open.
    (
        grid
        . toggle("Show the grid", SaSettings, ^"show_grid")
        . explain(
            tr(
                (
                    "A hairline grid over the document, drawn on the screen and never painted on. "
                    + "View > Toggle Grid is this same switch."
                )
            )
        )
        . named(&"show_grid")
    )
    (
        grid
        . number("Grid size", SaSettings.MIN_GRID_SIZE, SaSettings.MAX_GRID_SIZE, SaSettings, ^"grid_size")
        . explain(
            tr(
                (
                    "How far apart the grid's lines are, in document pixels. 1 draws a line on every pixel, "
                    + "which is what a pixel painter wants. Zoomed too far out for the size asked for, the grid "
                    + "doubles it until the lines are eight screen pixels apart rather than becoming a grey field."
                )
            )
        )
        . named(&"grid_size")
        . node("GridSizeSpin")
    )


## The Wider display dropdown's entries. The label is translated here rather
## than by the builder, because a choice row's entries are its own list and not
## the row's title.
func _fill_option() -> Array:
    var choices: Array = []
    for fill_id: String in SaSettings.DISPLAY_FILLS:
        choices.append({"id": fill_id, "label": tr(SaDisplayFill.display_name(fill_id))})
    return choices


## What each Wider display entry does, on its own row of the dropdown. The three
## names are the window title's as well, and Correct, Native and Even say
## nothing to a painter who has not read the hint under the row, so each says
## what it does. On the row's button, the way the View transform rows carry
## theirs.
func _describe_fills(option: SaChoiceButton) -> void:
    if option == null:
        return
    for fill_id: String in SaSettings.DISPLAY_FILLS:
        var label := option.popup.label_button(SaChoiceButton.row_id_of(fill_id))
        if label != null:
            label.tooltip_text = tr(String(FILL_SENTENCES.get(fill_id, "")))


## Every registered view transform of kind MODE, for the two proof dropdowns.
## Falls back to *current* alone when there is no main scene to ask, so the
## page still builds in a test.
func _mode_option(current: String) -> Array:
    var choices: Array = []
    var registry := _view_transforms()
    if registry != null:
        for descriptor in registry.list_modes():
            choices.append({"id": String(descriptor.id), "label": tr(descriptor.display_name)})
    if choices.is_empty():
        # A test's page with no registry, whose mode is an id no catalogue holds.
        choices.append({"id": current, "label": current.capitalize()})
    return choices


## The application's view transforms, when a main scene holds them. The same
## lookup `sa_generated_layer.gd` uses, for the same reason: a settings page is
## built by the Preferences window and is handed no registries.
static func _view_transforms() -> SaViewTransformRegistry:
    var tree := Engine.get_main_loop() as SceneTree
    var main_node: Node = tree.current_scene if tree != null else null
    if main_node == null or not ("registries" in main_node):
        return null
    var registries: SaRegistries = main_node.registries
    return registries.view_transforms if registries != null else null


## The gamut pair's picture is baked off the main thread as the page enters the
## tree, with a blank stand-in until it lands. A page the search builds
## off the tree never enters it and never asks.
func _enter_tree() -> void:
    _awaiting_picture = not SaGamutPictureBake.dress([_gamut, _gamut_plain])


func _process(_delta: float) -> void:
    if _awaiting_picture:
        _awaiting_picture = not SaGamutPictureBake.dress([_gamut, _gamut_plain])
    else:
        set_process(false)


## A page closed while the bake runs claims it, because a task nobody waits for
## is an engine error at exit.
func _exit_tree() -> void:
    if _awaiting_picture:
        SaGamutPictureBake.finish()
        _awaiting_picture = false
