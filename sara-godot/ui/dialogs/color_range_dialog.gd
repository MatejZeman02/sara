## Select > Colour Range and the filter mask's "Mask from Colour Range", one
## dialog for both: a colour, a fuzziness, whether the picture is the merged
## one, and for the selection a mode.
##
## The rows are a declarative `SaDialog` page realized into this window, so a
## dump describes them the way it describes a filter's and a scenario drives
## them by name. The page is built afresh on every open, because a page is
## realized once and never rebuilt.
##
## **Pick from canvas.** While the box is ticked, every colour the eyedropper
## picks, `EventBus.color_picked`, lands in the swatch, so the painter clicks the
## canvas with the picker and watches the colour arrive. The window is not
## exclusive, which is what lets that click reach the canvas at all.
##
## **The hold.** A click on the canvas goes to the tool in the hand, so while the
## box is ticked the dialog puts the Eyedropper in the hand through the main
## canvas's tool machine, and keeps the painter's foreground, which the picks
## that chose the range would otherwise repaint. Closing the window by Apply,
## Cancel, Escape or the corner, and unticking the box, let go: the tool and the
## foreground are what they were. A dialog opened with no machine, a suite's,
## holds the foreground alone. The hold is the door's `SaPickHold`, which the
## Levels eyedroppers take as well.
##
## **The preview.** While the window is open the canvas shows what Apply would
## choose, as the quick mask's tint, so a fuzziness is tuned by eye rather than
## by Apply, look and undo. The dialog keeps a scratch `SaSelection`,
## [member preview], fills it with the engine's coverage at most once a frame
## after the colour, the fuzziness or Sample merged moved, and hands it to the
## canvas's selection overlay. Only the chunks the view shows are measured, and
## a pan that shows others measures again, so a slider's drag costs what is on
## screen and Apply alone covers the canvas. The picture is the one Select >
## Colour Range reads, the merged one or the active layer. For a filter's mask
## that is the picture with the filter on, which Apply reads with it off.
## Closing by any way clears it.
##
## **Enter applies**, from every row but Fuzziness's typed number. Left to the
## rows, Enter would leave a previewed range looking applied: on the swatch,
## where the window opens, it opens the colour's popup, and after a pick from
## the canvas the keyboard is the main window's, so the tint stays, the dialog
## with it, and an undo takes the step before. So the swatch and the two boxes
## answer Enter with Apply, a pick hands the keyboard back to the swatch once
## the pointer is up, and the typed number keeps the filter windows' rule, the
## number taken and the preview run on it. Apply and Cancel keep every dialog's
## rule, Enter presses the button the outline is on.
@tool
class_name SaColorRangeDialog
extends SaDialogWindow

## The painter pressed Apply or Enter. *mode* is a `SaSelection.Mode`, and the
## mask's destination ignores it.
signal range_confirmed(color: Color, fuzziness: float, sample_merged: bool, mode: int)

## Whether the page offers the mode row: the selection's destination does, a
## mask's does not.
var for_selection: bool = true

## The page the rows live on, built by [method open].
var page: SaDialog = null

var _rows: VBoxContainer = null
var _color_row: SaPageRow = null
var _pick_row: SaPageRow = null
var _fuzziness_row: SaSlider = null
var _merged_row: SaPageRow = null
var _mode_row: SaPageRow = null

## The main canvas's tool machine, handed to [method open], or null.
var _machine: ToolMachine = null
## The surface the machine drives and the canvas it is a child of, read off it
## by [method open]: the preview's picture and the overlay it is drawn on.
var _surface: SaSurface = null
var _canvas: Node = null

## The Eyedropper in the hand and the foreground kept, while the box is ticked.
var _hold := SaPickHold.new()

## What Apply would choose over the chunks the view shows, while the window is
## open, and null otherwise. Filled by [method refresh_preview].
var preview: SaSelection = null

## A row moved since the preview was last filled.
var _preview_stale: bool = false
## The document rectangle the preview was last measured over.
var _preview_window: Rect2i = Rect2i()
## The engine the preview measures with, kept so its pipeline is built once,
## and the document it was made for.
var _preview_engine: SaColorRange = null
var _preview_document: SaDocument = null
## A pick landed in the swatch, and the keyboard goes back to it once the
## pointer is up, see [method _take_the_keyboard_back].
var _keyboard_wanted: bool = false


func _init() -> void:
    _init_dialog("ColorRangeDialog", tr("Colour Range"), Vector2i(420, 330), Vector2i(340, 260))
    visible = false
    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    _rows = SaMake.column(margin, "ColorRangePage")
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Enter in Fuzziness's field takes the number and the preview runs on it,
    # the filter windows' rule, rather than applying a range not yet seen.
    number_field_answers = false
    visibility_changed.connect(_on_shown_or_hidden)


## Builds the page for *selection_mode*, true for Select > Colour Range and
## false for a filter's mask, starting on *color* and on the settings last
## applied, and pops it up. *machine* is the main canvas's tool machine, which
## the Eyedropper is made active on while the box is ticked.
func open(
    color: Color, fuzziness: float, sample_merged: bool, merge_mode: int, selection_mode: bool, machine: ToolMachine = null
) -> void:
    for_selection = selection_mode
    _let_go()
    _machine = machine
    _surface = machine.surface if machine != null else null
    # Always the canvas's own child, which `SaCanvas.tool_machine` reads by name.
    _canvas = machine.get_parent() if machine != null else null
    retitle(tr("Colour Range") if selection_mode else tr("Mask from Colour Range"))
    build_page(color, fuzziness, sample_merged, merge_mode)
    popup_centered()
    if bool(_pick_row.value):
        _take_hold()


## The page alone, without popping it up, which is what a suite drives.
func build_page(color: Color, fuzziness: float, sample_merged: bool, merge_mode: int) -> void:
    _drop_page()
    var made := SaDialog.new()
    _color_row = made.color("Colour", color)
    _pick_row = made.checkbox("Pick from canvas", true).node("PickFromCanvas")
    _pick_row.explain(
        tr(
            (
                "While on, a click on the canvas picks the colour to choose by. "
                + "Your foreground colour and your tool are put back when this closes."
            )
        )
    )
    _pick_row.changed.connect(_on_pick_toggled)
    _fuzziness_row = made.slider("Fuzziness", 0, int(SaColorRange.MAX_FUZZINESS), int(roundf(fuzziness)))
    _fuzziness_row.explain(tr("How far from the colour a pixel may be and still be chosen, fading out towards the edge."))
    _merged_row = made.checkbox("Sample merged", sample_merged)
    _merged_row.explain(tr("Read the whole picture as it is seen, rather than the layer alone."))
    _mode_row = null
    if for_selection:
        _mode_row = made.dropdown("Mode", ["Replace", "Add", "Subtract", "Intersect"], merge_mode)
    made.apply_cancel()
    made.realize(_rows)
    page = made
    for row: SaPageRow in [_color_row, _fuzziness_row, _merged_row]:
        row.changed.connect(_on_range_moved)
    _preview_stale = true
    made.applied.connect(apply_range)
    made.cancelled.connect(hide)
    default_button = made.apply_button
    if not EventBus.color_picked.is_connected(_on_color_picked):
        EventBus.color_picked.connect(_on_color_picked)


## The colour the swatch holds.
func picked_color() -> Color:
    return _color_row.value as Color if _color_row != null and _color_row.value is Color else Color.WHITE


func chosen_fuzziness() -> float:
    return float(_fuzziness_row.value) if _fuzziness_row != null else SaColorRange.DEFAULT_FUZZINESS


func chosen_merged() -> bool:
    return bool(_merged_row.value) if _merged_row != null else true


func chosen_mode() -> int:
    return int(_mode_row.value) if _mode_row != null else int(SaSelection.Mode.REPLACE)


## Fills [member preview] with what Apply would choose over the chunks the
## canvas shows, and hands it to the canvas's overlay. Nothing without a machine
## bound to an easel, because there is then no picture to measure. Public so a
## suite fills it without waiting for a frame.
func refresh_preview() -> void:
    _preview_stale = false
    var easel := _easel()
    var document: SaDocument = easel.document if easel != null else null
    if document == null or easel.output == null:
        return
    _preview_window = _shown_window(easel)
    if _preview_engine == null or _preview_document != document:
        _preview_engine = SaColorRange.new(document)
        _preview_document = document
    if preview == null:
        preview = SaSelection.new()
    # An empty window is a view off the canvas, which shows no chunk, and the
    # engine and the flush both read an empty rectangle as the whole canvas.
    var region: Dictionary[Vector2i, SaChunk] = {}
    if _preview_window.has_area():
        var layer := document.active_layer
        var merged: SaTexture = null
        if chosen_merged() or layer == null:
            easel.flush(_preview_window)
            merged = easel.output
        region = _preview_engine.coverage(picked_color(), chosen_fuzziness(), merged, layer, _preview_window)
    preview.chunks = region
    preview.active = true
    preview.changed.emit()
    var overlay := _overlay()
    if overlay != null:
        overlay.selection_preview = preview


## Apply, or Enter: says what was chosen and closes.
func apply_range() -> void:
    range_confirmed.emit(picked_color(), chosen_fuzziness(), chosen_merged(), chosen_mode())
    hide()


## Enter on the swatch or on either box applies, outline or none, where the base
## would have opened the colour's popup or flipped the box. Space still does
## those. The swatch's press has begun its click, and the release finds the
## window gone.
func _unhandled_key_input(event: InputEvent) -> void:
    var key := event as InputEventKey
    var enter := key != null and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
    if enter and key.pressed and not key.echo and visible and _a_row_holds_the_keyboard():
        apply_range()
        set_input_as_handled()
        return
    super(event)


## Whether the swatch or one of the two boxes has the focus.
func _a_row_holds_the_keyboard() -> bool:
    var focused := gui_get_focus_owner()
    if focused == null:
        return false
    for row: SaPageRow in [_color_row, _pick_row, _merged_row]:
        if row != null and row.control == focused:
            return true
    return false


## What a dump prints for this window: the page's own description, which
## destination it serves, and whether it holds the tool and the foreground.
func describe() -> Dictionary:
    var out := page.describe() if page != null else {}
    out["for_selection"] = for_selection
    out["visible"] = visible
    out["holding"] = _hold._holding
    out["preview_chunks"] = preview.chunks.size() if preview != null else -1
    return out


func _on_color_picked(color: Color) -> void:
    if _hold._restoring or not visible or _pick_row == null or not bool(_pick_row.value):
        return
    if _color_row != null:
        _color_row.value = color
        _color_row.drive(color.to_html(true))
        _keyboard_wanted = true


## Ticking Pick from canvas takes the hold, unticking it gives the hold back.
func _on_pick_toggled(ticked: Variant) -> void:
    if not visible:
        return
    if bool(ticked):
        _take_hold()
    else:
        _let_go()


## Every way out of the window ends the hold and the preview, and the Escape
## key, the corner and Cancel all arrive here as the window hiding.
func _on_shown_or_hidden() -> void:
    if not visible:
        _keyboard_wanted = false
        _let_go()
        _clear_preview()


func _on_range_moved(_value: Variant) -> void:
    _preview_stale = true


## Once a frame at most: the rows moved, or the view shows chunks the preview
## was not measured over.
func _process(_delta: float) -> void:
    if Engine.is_editor_hint() or not visible:
        return
    _take_the_keyboard_back()
    var easel := _easel()
    if easel == null:
        return
    if _preview_stale or _shown_window(easel) != _preview_window:
        refresh_preview()


## After a pick the keyboard is the main window's, whose canvas the click
## landed on, so Enter and Escape went to the Eyedropper and the dialog stayed
## up. The window takes it back with the outline off the swatch, which the pick
## filled, once the pointer is up, so nothing moves the keyboard while the
## Eyedropper's drag is still under way.
func _take_the_keyboard_back() -> void:
    if not _keyboard_wanted or Input.get_mouse_button_mask() != 0:
        return
    _keyboard_wanted = false
    var swatch := _color_row.control if _color_row != null else null
    if not is_focusable(swatch):
        return
    grab_focus()
    swatch.grab_focus(true)


## Takes the preview off the canvas and lets it go. The overlay is told to
## redraw now, so the frame after the window closes shows the selection and
## not the tint.
func _clear_preview() -> void:
    var dropped := preview
    preview = null
    _preview_stale = false
    _preview_window = Rect2i()
    _preview_engine = null
    _preview_document = null
    var overlay := _overlay()
    if overlay != null and overlay.selection_preview == dropped:
        overlay.selection_preview = null
    if dropped != null:
        dropped.changed.emit()


## The easel of the canvas the machine drives, or null without one.
func _easel() -> SaEasel:
    return _surface.easel if _surface != null else null


## The chunks the view shows, as the document rectangle they cover, cut to the
## canvas. The whole canvas when nothing says what is shown, which is a suite.
static func _shown_window(easel: SaEasel) -> Rect2i:
    var canvas := Rect2i(Vector2i.ZERO, easel.canvas_size)
    var shown := Rect2()
    if easel.shown_rect.is_valid():
        shown = easel.shown_rect.call()
    if not shown.has_area():
        return canvas
    var side := SaChunk.SIZE
    var first := Vector2i(floori(shown.position.x / side), floori(shown.position.y / side))
    var last := Vector2i(ceili(shown.end.x / side), ceili(shown.end.y / side))
    return Rect2i(first * side, (last - first) * side).intersection(canvas)


## The selection overlay of the canvas the machine is a child of, or null.
func _overlay() -> SaSelectionOverlay:
    if _canvas == null or not is_instance_valid(_canvas):
        return null
    return _canvas.get_node_or_null("SelectionOverlay") as SaSelectionOverlay


## Makes the Eyedropper the tool in the hand and keeps the foreground as it is,
## once, through the door's hold.
func _take_hold() -> void:
    _hold.take(_machine)


## Puts the foreground and the tool back.
func _let_go() -> void:
    _hold.let_go()


func _drop_page() -> void:
    if page != null:
        if page.applied.is_connected(apply_range):
            page.applied.disconnect(apply_range)
        if page.cancelled.is_connected(hide):
            page.cancelled.disconnect(hide)
    page = null


## Drives the Colour Range dialog: it opens the dialog, moves its rows as a hand
## would and answers it, `{"color_range": {"open": "mask", "color": "#3c78c8",
## "fuzziness": 20, "merged": true, "mode": 1, "answer": "apply"}}`, every key
## optional. `open` is `selection`, Select > Colour Range through the Select
## menu's own handler, or `mask`, the picked filter's row in the layers docker.
## A click cannot reach either, the menus and the docker being embedded
## subwindows, so this is the door they go through with the pointer left out.
static func capture(tree: SceneTree, spec: Dictionary) -> String:
    var which := String(spec.get("open", ""))
    var dialog: SaColorRangeDialog = null
    match which:
        "selection":
            var bar: TopMenuBar = null
            for node in tree.root.find_children("*", "PanelContainer", true, false):
                if node is TopMenuBar:
                    bar = node as TopMenuBar
            var menu := bar.menu("Select") as SaSelectMenu if bar != null else null
            dialog = menu.open_color_range_dialog() if menu != null else null
        "mask":
            # Asked by name rather than typed, because the actions are an inner
            # file of the layers docker's package and its facade is the docker.
            var docker := tree.root.find_child(SaDockerIds.LAYERS, true, false)
            var actions: Object = docker.get("actions") if docker != null else null
            if actions != null and actions.has_method("open_color_range_dialog"):
                dialog = actions.call("open_color_range_dialog") as SaColorRangeDialog
        "":
            # The one on screen, because the Select menu and the layers docker
            # each keep one and both are named for the class.
            for node in tree.root.find_children("*", "Window", true, false):
                if node is SaColorRangeDialog and (node as Window).visible:
                    dialog = node as SaColorRangeDialog
        _:
            return "SaCapture: no colour range called '%s'" % which
    if dialog == null or dialog.page == null:
        return "SaCapture: no colour range dialog to drive"
    if spec.has("color"):
        dialog._color_row.drive(String(spec["color"]))
    if spec.has("fuzziness"):
        var slider := dialog._fuzziness_row.control as FactorSlider
        slider.value = float(spec["fuzziness"])
        slider.value_changed.emit(slider.value)
    if spec.has("merged"):
        dialog._merged_row.drive(bool(spec["merged"]))
    if spec.has("mode") and dialog._mode_row != null:
        dialog._mode_row.drive(int(spec["mode"]))
    var said := (
        "SaCapture: colour range %s at %s, fuzziness %.0f, merged %s, mode %d"
        % [
            "for the selection" if dialog.for_selection else "for a mask",
            "#" + dialog.picked_color().to_html(false),
            dialog.chosen_fuzziness(),
            str(dialog.chosen_merged()),
            dialog.chosen_mode(),
        ]
    )
    match String(spec.get("answer", "")):
        "apply":
            dialog.apply_range()
            said += ", applied"
        "cancel":
            dialog.hide()
            said += ", cancelled"
    return said
