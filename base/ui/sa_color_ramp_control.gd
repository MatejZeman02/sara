## The colour ramp editor in the Tool Options docker.
##
## A colour ramp of the shape Blender's is, alpha for each stop included so a
## one-sided gradient can be made, and all of it inside the Tool Options
## docker.
##
## A bar showing the ramp over a checkerboard, a triangular handle per stop, and
## a row underneath for the selected stop: its colour, taken from the picker, and
## its alpha. A subclass of nothing in particular and a sibling of
## `sa_gradient_slider.gd`, which is the other control in Sara that draws a ramp
## and which is a read-only picture rather than an editor.
##
## A row under it is the library: a name field, Save, and a dropdown of the
## two stock gradients and the saved ones, which loads or deletes one. The store is
## `SaPresetStore.for_gradients()`, which is the brush preset store pointed at
## another directory rather than a second store, because it lives in the
## skeleton so that anything with a settings resource can use it.
##
## **One idea of a colour, and it is Sara's own picker**. The swatch is the
## stop's colour and opens `SaPickerShape`, the same control the Colour Picker
## docker draws, in a popup under the row, writing the stop as the colour
## moves, so every colour on the ramp is edited here rather than only by
## setting the foreground. No colour picker of its own: Godot's
## `ColorPickerButton` would put a second colour picker in the app with its own
## idea of a colour space, in a program whose whole point is that colour goes
## through one door. Sara's own control in a popup is that same door, opened
## nearer to hand.
##
## **The base module's**, because the gradient tool is the only thing that uses
## it. The gradient's Ramp row is a `Kind.CUSTOM` spec carrying a factory, the
## module builds this control through it, and nothing in the skeleton names the
## class: the options bar builds it through the spec and the capture step
## reaches it through `capture_option_edit` below.
##
## **Whether the ramp follows the colours is said under the bar**, in a muted
## line, and the library's two stock rows are how it follows them again. The
## row is bound to the tool rather than to its ramp for that, by
## [method follow_tool]: the ramp is a type of the door and knows nothing of who
## follows what.
@tool
class_name SaColorRampControl
extends VBoxContainer

const SaPickerShapeScript = preload("res://ui/widgets/picker/sa_picker_shape.gd")
const StateGradientScript = preload("res://modules/sara-base-modules/base/gradient/state_gradient.gd")

## What a stock row's id starts with in the library list. A saved gradient's name
## is a file name, which never holds a colon, so the two cannot collide.
const STOCK_ROW_PREFIX := "stock:"

## Emitted when the ramp's stops have changed, so a live preview can repaint.
signal ramp_changed

## The bar's height in logical units. Tall enough to read a colour and to put a
## handle under the pointer, short enough for a docker row.
const BAR_HEIGHT: int = 26

## The handle's half-width in logical units, which is also how near the pointer
## has to be to grab one.
const HANDLE_HALF: float = 5.0

## The picker popup's side in logical units. Square, because the shape is, and
## wide enough for the ring and whatever is inside it to be aimed at.
const POPUP_SIDE: int = 200

## The checkerboard behind the ramp, so a stop at alpha zero reads as
## transparent rather than as black.
const CHECKER_CELL: float = 6.0
const CHECKER_LIGHT := Color(0.45, 0.45, 0.45, 1.0)
const CHECKER_DARK := Color(0.32, 0.32, 0.32, 1.0)

var ramp: SaColorRamp = null
## Which stop the row below the bar is editing, for a test and for a capture.
var selected: int = 0
var _dragging: bool = false

var _bar: Control = null
var _swatch: Button = null
## The picker popup under the swatch and the picker in it, built on first press
## and kept.
var _popup: PopupPanel = null
var _picker: SaPickerShape = null
var _alpha: FactorSlider = null
var _remove_button: Button = null
var _name_edit: LineEdit = null
var _save_button: Button = null
var _library_button: Button = null
## The saved gradients as the app's own list, under the button.
var _library_list: SaChoicePopup = null
## The saved gradients, built on first use so a control in a test that never
## opens the library touches no directory.
var _store: SaPresetStore = null

## The gradient's end rule, which an alpha edit on an endpoint is remembered
## through. The module's own object, handed in by the row's builder, and a
## bare one for a control a test builds, which remembers nothing.
var _ends: SaGradientEnds = null

## The gradient tool whose ramp this row edits, which says whether the ramp
## follows the colours and takes the stock rows. Null for a control bound to a
## bare ramp, which shows no follow line and whose stock rows do nothing.
var _tool: StateGradientScript = null
## The muted line under the bar saying whether the ramp follows the colours.
var _follow_line: Label = null


## *library_store* is where the library reads and writes, and null is the
## gradients directory every painter has. A test hands a scratch one. *ends* is
## the module's end rule, and null is one that remembers nothing.
func _init(library_store: SaPresetStore = null, ends: SaGradientEnds = null) -> void:
    _store = library_store
    _ends = ends if ends != null else SaGradientEnds.new()
    name = "ColorRamp"
    add_theme_constant_override("separation", SaUI.px(4))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _bar = Control.new()
    _bar.name = "Bar"
    _bar.custom_minimum_size = Vector2(SaUI.px(120), SaUI.px(BAR_HEIGHT))
    _bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _bar.mouse_filter = Control.MOUSE_FILTER_STOP
    # A press takes the focus, so Delete reaches the ramp before the key that
    # clears the layer does.
    _bar.focus_mode = Control.FOCUS_CLICK
    # Said to the shortcut router, which a docker's window lets see a key before
    # the bar does: Delete is the ramp's while the bar, or the row under it, has
    # the focus.
    _bar.set_meta(&"keeps_delete", true)
    _bar.tooltip_text = tr("Click to add a stop, drag one to move it, right-click one or press Delete to remove it.")
    _bar.draw.connect(_draw_bar)
    _bar.gui_input.connect(_on_bar_input)
    add_child(_bar)

    _follow_line = Label.new()
    _follow_line.name = "FollowLine"
    _follow_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _follow_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _follow_line.visible = false
    # The theme pass writes font_size onto every Control it walks, so the meta is
    # what survives it.
    _follow_line.set_meta(SaUI.FONT_SCALE_META, 0.85)
    SaTheme.bind_font(_follow_line, "text_muted")
    add_child(_follow_line)

    var row := HBoxContainer.new()
    row.name = "StopRow"
    row.add_theme_constant_override("separation", SaUI.px(4))
    add_child(row)

    _swatch = Button.new()
    _swatch.name = "StopColor"
    _swatch.tooltip_text = tr("The selected stop's colour. Press to pick another.")
    _swatch.custom_minimum_size = Vector2(SaUI.px(44), SaUI.px(SaUI.BASE_ICON_SIZE + 2))
    _swatch.pressed.connect(open_swatch)
    _swatch.gui_input.connect(_on_stop_row_key)
    _swatch.set_meta(&"keeps_delete", true)
    row.add_child(_swatch)

    _remove_button = Button.new()
    _remove_button.name = "RemoveStop"
    # A word rather than a bare minus sign, which a painter looking for the way
    # to take a stop away did not find.
    _remove_button.text = tr("Remove")
    _remove_button.tooltip_text = tr("Remove the selected stop. Right-click a stop or press Delete does the same.")
    _remove_button.custom_minimum_size = Vector2(SaUI.px(64), SaUI.px(SaUI.BASE_ICON_SIZE + 2))
    _remove_button.pressed.connect(_remove_selected)
    _remove_button.gui_input.connect(_on_stop_row_key)
    _remove_button.set_meta(&"keeps_delete", true)
    row.add_child(_remove_button)

    # A `FactorSlider` and not an `HSlider`. A bare `HSlider` is a groove with a
    # knob on it: no name, no number, nothing that says it is the alpha. Every
    # other number a painter drags in Sara is one of these.
    _alpha = FactorSlider.new()
    _alpha.name = "StopAlpha"
    _alpha.min_value = 0.0
    _alpha.max_value = 1.0
    _alpha.prefix = tr("Alpha") + ": "
    _alpha.suffix = " %"
    _alpha.display_value_multiplier = 100.0
    _alpha.decimal_places = 0
    _alpha.tooltip_text = tr("The selected stop's alpha. Zero at one end is a gradient that fades out.")
    _alpha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _alpha.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _alpha.value_changed.connect(_on_alpha_changed)
    row.add_child(_alpha)

    _build_library_row()

    # A following ramp is re-seeded when the tool reads it, and nothing reads it
    # while the painter only changes colours, so the bar asks again whenever the
    # pair moves. In `_init` for the reason `ColorPair` gives: a control a test
    # builds detached never enters a tree.
    if not EventBus.color_picked.is_connected(_on_colours_changed):
        EventBus.color_picked.connect(_on_colours_changed)
    if not EventBus.background_color_changed.is_connected(_on_colours_changed):
        EventBus.background_color_changed.connect(_on_colours_changed)


## The name field, Save, and the dropdown that loads or deletes one.
##
## A button opening a list rather than a choice button, because the list is a set
## of commands rather than a value the control holds: picking a row loads a
## gradient and leaves the button reading "Library", where a choice button would
## keep showing the last name as though it were the state of the ramp, which it
## stops being the moment a stop moves.
##
## **The list is the app's own `SaChoicePopup`, not a `MenuButton`'s**, which
## draws an engine popup in the engine's look rather than the app's and gives a
## scenario step no row to point at.
func _build_library_row() -> void:
    var row := HBoxContainer.new()
    row.name = "LibraryRow"
    row.add_theme_constant_override("separation", SaUI.px(4))
    add_child(row)

    _name_edit = LineEdit.new()
    _name_edit.name = "RampName"
    _name_edit.placeholder_text = tr("Gradient name")
    _name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _name_edit.text_submitted.connect(func(_text: String) -> void: save_ramp(_name_edit.text))
    row.add_child(_name_edit)

    _save_button = Button.new()
    _save_button.name = "SaveRamp"
    _save_button.text = tr("Save")
    _save_button.tooltip_text = tr("Save this gradient under the name beside it.")
    _save_button.pressed.connect(func() -> void: save_ramp(_name_edit.text))
    row.add_child(_save_button)

    _library_button = Button.new()
    _library_button.name = "RampLibrary"
    _library_button.text = tr("Library")
    _library_button.tooltip_text = tr(
        "Choose a stock gradient, which follows the colours, or load a saved one. Shift+click a saved one to delete it."
    )
    _library_button.pressed.connect(open_library)
    SaTheme.make_dropdown(_library_button)
    row.add_child(_library_button)

    _library_list = SaChoicePopup.new()
    _library_list.name = "RampLibraryList"
    _library_button.add_child(_library_list)
    _library_list.chosen.connect(_on_library_chosen)


## The store, built on first use. A control that never opens the library never
## looks at a directory, which is what keeps a headless test off the disk.
func store() -> SaPresetStore:
    if _store == null:
        _store = SaPresetStore.for_gradients()
    return _store


## Fills the list and opens it under the button, which is what a press on the
## button does. Public, so a scenario and a test reach the same door.
func open_library() -> void:
    fill_library()
    _library_list.open_under(_library_button)


## Fills the list from the directory each time it opens rather than once, so a
## gradient saved from a second surface is in the list without a restart.
##
## A row's id is the gradient's own name, so a press answers the name it was drawn
## for, and one deleted since the list was filled loads nothing.
##
## The two stock gradients head the list on every profile, so the list is never
## empty and needs no row saying that nothing is saved.
## They are live rather than files: choosing one makes the ramp follow the
## colours, where a saved gradient is a fixed set of stops.
func fill_library() -> void:
    _library_list.clear()
    for stock: Dictionary in SaGradientEnds.STOCK:
        _library_list.add_row(StringName(STOCK_ROW_PREFIX + String(stock["id"])), tr(String(stock["label"])))
    var names := store().list_names()
    if not names.is_empty():
        _library_list.add_gap()
    for saved: String in names:
        _library_list.add_row(StringName(saved), saved)


## A plain click loads, a shift-click deletes. One row rather than a row and a
## delete button beside it: the list is already as wide as the docker, and a
## painter who wants a gradient gone is not looking for it in a second control.
##
## A stock row is chosen whether or not Shift is down, because there is no file
## behind it to delete.
func _on_library_chosen(id: StringName) -> void:
    var wanted := String(id)
    if wanted.begins_with(STOCK_ROW_PREFIX):
        choose_stock(StringName(wanted.trim_prefix(STOCK_ROW_PREFIX)))
        return
    if not store().list_names().has(wanted):
        return
    if Input.is_key_pressed(KEY_SHIFT):
        delete_ramp(wanted)
        return
    load_ramp(wanted)


## Writes the ramp under *wanted*, and answers the name it was stored under,
## which sanitizing can change. Empty when nothing was written.
func save_ramp(wanted: String) -> String:
    if ramp == null:
        return ""
    var stored := store().save_preset(wanted, SaGradientPreset.from_ramp(ramp))
    if not stored.is_empty():
        _name_edit.text = stored
    return stored


## Puts a saved gradient's stops on the live ramp, in place. True when one
## loaded.
##
## In place rather than by swapping the object, for the reason `apply_preset`
## gives for brush settings: the tool holds this ramp and a control that
## replaced it would leave the tool drawing the old one. It goes through the
## ramp's own edit path so the tool learns the ramp is no longer its default.
func load_ramp(wanted: String) -> bool:
    if ramp == null:
        return false
    var preset := store().load_preset(wanted) as SaGradientPreset
    if preset == null:
        return false
    var loaded := preset.to_ramp(ramp)
    ramp.stops.clear()
    for stop: Dictionary in loaded.stops:
        ramp.stops.append({"position": float(stop["position"]), "color": Color(stop["color"])})
    selected = 0
    _name_edit.text = wanted
    ramp.changed.emit()
    return true


func delete_ramp(wanted: String) -> bool:
    return store().delete_preset(wanted)


## Makes the ramp follow the colours as the stock gradient *stock* lays them, an
## `SaGradientEnds` stock id, and answers whether it did. Through the tool's own
## [method StateGradientScript.follow_stock], which owns whether its ramp
## follows, so a row bound to a bare ramp has nothing to make follow and answers
## false.
##
## The name field is emptied, since the ramp is no longer a saved gradient.
func choose_stock(stock: StringName) -> bool:
    if _tool == null or not _tool.follow_stock(stock):
        return false
    selected = 0
    _name_edit.text = ""
    ramp_changed.emit()
    return true


## The library as the state dump reads it: the stock rows, what is saved and what
## the name field holds. The open list is in the dump's `choice_lists` under
## `RampLibrary` as well, and this says what is listed whether or not it is open.
func library_report() -> Dictionary:
    var stock: Array = []
    for entry: Dictionary in SaGradientEnds.STOCK:
        stock.append(String(entry["label"]))
    return {"stock": stock, "saved": Array(store().list_names()), "name": _name_edit.text if _name_edit != null else ""}


## Points the row at the gradient tool behind *following*, that tool's
## `following_changed`, which is what the row's option names. The row binds the
## tool's ramp, says under the bar whether it follows the colours, and hears when
## that changes. Called on every sync of the docker, so it reads the ramp again
## each time, which is what re-seeds a ramp that follows.
func follow_tool(following: Variant) -> void:
    var tool: StateGradientScript = null
    if following is Signal:
        tool = (following as Signal).get_object() as StateGradientScript
    if tool != _tool:
        if _tool != null and _tool.following_changed.is_connected(_on_following_changed):
            _tool.following_changed.disconnect(_on_following_changed)
        _tool = tool
        if _tool != null:
            _tool.following_changed.connect(_on_following_changed)
    _refresh_from_tool()


## Reads the tool's ramp again, which re-seeds it while it follows, and shows it
## and the follow line. Nothing to read for a row bound to a bare ramp.
func _refresh_from_tool() -> void:
    if _tool != null:
        bind_ramp(_tool.ramp)
        _sync_row()
        _bar.queue_redraw()
    _show_follow_line()


func _on_following_changed(_following: bool) -> void:
    _refresh_from_tool()


## The pair moved. Only a following ramp changes with it, so an edited one is not
## read again.
func _on_colours_changed(_color: Color) -> void:
    if _tool != null and _tool.ramp_is_default:
        _refresh_from_tool()


## "Follows the colours" while the ramp follows the pair and what to do about it
## once an edit has stopped it, so a ramp frozen on colours long since changed
## says so. Hidden for a row with no tool behind it.
func _show_follow_line() -> void:
    _follow_line.visible = _tool != null
    if _tool == null:
        _follow_line.text = ""
        return
    if _tool.ramp_is_default:
        _follow_line.text = tr("Follows the colours")
    else:
        _follow_line.text = tr("Edited, choose a stock gradient to follow the colours again")


## Points the control at *ramp*. Rebinding the same one is a no-op, so a docker
## that refreshes often does not reset the selection under the painter's hand.
func bind_ramp(colors: SaColorRamp) -> void:
    if colors == ramp:
        return
    if ramp != null and ramp.changed.is_connected(_on_ramp_changed):
        ramp.changed.disconnect(_on_ramp_changed)
    ramp = colors
    if ramp != null:
        ramp.changed.connect(_on_ramp_changed)
    selected = 0
    _sync_row()
    _bar.queue_redraw()


## *control*'s rectangle as x, y, width, height, in the window it stands in.
func _rect_in_window(control: Control) -> Array:
    var rect := control.get_global_rect()
    return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## The stops as plain data, for the state dump. The control reports itself, the
## way the minimap and the Colour Themes page do, so `sa_state_report.gd` holds
## no second copy of what a stop is.
func stop_report() -> Dictionary:
    if ramp == null:
        return {}
    # Null for a row with no tool behind it, which neither follows nor not.
    var following: Variant = null
    if _tool != null:
        following = _tool.ramp_is_default
    return {
        "selected": selected,
        "stops": ramp.to_array(),
        # What the row is showing, which is the half the stop array cannot say:
        # the swatch's colour, the alpha slider's name and value, and whether
        # the picker popup is open.
        "swatch": ramp.color_of(selected).to_html(false),
        "alpha_row": {"label": _alpha.prefix.strip_edges(), "shown": snappedf(_alpha.value, 0.0001)},
        "swatch_popup_open": _popup != null and _popup.visible,
        # The remove control's word, whether it is dimmed and disabled, and where
        # it stands in the control's own window, so a scenario can measure a shot.
        "remove_control":
        {
            "text": _remove_button.text,
            "disabled": _remove_button.disabled,
            "rect": _rect_in_window(_remove_button),
        },
        # The two remembered alphas, beside the stops they were taken from, so
        # one dump says both what the ramp holds and what a fresh launch would
        # rebuild it with.
        "remembered_alpha": [_ends.start_alpha(), _ends.end_alpha()],
        # Whether the ramp follows the colours and the line that says so, null
        # and empty for a row with no tool behind it.
        "following": following,
        "follow_line": _follow_line.text,
        "library": library_report(),
    }


func _on_ramp_changed() -> void:
    _sync_row()
    _bar.queue_redraw()
    ramp_changed.emit()


func _sync_row() -> void:
    var has_ramp := ramp != null and ramp.size() > 0
    _swatch.disabled = not has_ramp
    _remove_button.disabled = not has_ramp or ramp.size() <= SaColorRamp.MIN_STOPS
    if not has_ramp:
        return
    selected = clampi(selected, 0, ramp.size() - 1)
    var held := ramp.color_of(selected)
    _alpha.set_value_no_signal(held.a)
    _show_swatch(held)
    if _picker != null and _picker.visible:
        _picker.set_from_color(held)


## Paints the swatch button in the stop's colour, over the same checkerboard the
## bar uses so a stop at alpha zero reads as transparent rather than as black.
##
## A stylebox rather than an icon, because the button is a rectangle of one
## colour and an icon would be a texture to build and free on every selection.
func _show_swatch(held: Color) -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = Color(held.r, held.g, held.b, 1.0)
    box.set_border_width_all(1)
    box.border_color = SaTheme.palette.border_primary
    box.set_corner_radius_all(2)
    for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
        _swatch.add_theme_stylebox_override(state, box)


## Shows Sara's own picker in a popup under the swatch, and answers whether it
## opened.
##
## Built on first use and kept, the way the flyouts and the curve option host
## are: a picker is a shader material and two frames, and building one per press
## would be paid for by every stop a painter tries.
##
## The shape follows `color_picker_shape`, so the painter picks in whatever
## picker they chose for the docker rather than in a second one that disagrees
## with it.
func open_swatch() -> bool:
    if ramp == null or ramp.size() == 0:
        return false
    if _popup == null:
        _build_popup()
    _picker.set_kind(SaPickerShapeScript.kind_of(String(SaInHand.Settings.read(&"color_picker_shape"))))
    _picker.set_from_color(ramp.color_of(selected))
    # `get_screen_position` and not `get_global_rect`, which is measured from the
    # corner of the embedded docker the swatch lives in, so a popup placed with
    # it opens where nobody can find it while the dump says it is open. That is
    # the same trap `SaDockerWindowCapture.capture_hide` records.
    var at := _swatch.get_screen_position()
    _popup.popup(Rect2i(Vector2i(int(at.x), int(at.y + _swatch.size.y) + 2), _popup.size))
    return true


## Moves the picker in the open popup to *wanted*, which writes the stop the way
## a hand on the ring does, and answers whether there was a picker to move.
##
## Through the picker rather than through `set_selected_color`, because what the
## swatch promises is a picker that edits the stop, and writing the stop behind
## the popup would pass on a popup that never opened.
func pick_in_swatch(wanted: Color) -> bool:
    if _popup == null or not _popup.visible or _picker == null:
        return false
    _picker.set_from_color(wanted)
    _on_picked(_picker.color())
    return true


## Shuts the popup, and answers whether one was up.
func close_swatch() -> bool:
    if _popup == null or not _popup.visible:
        return false
    _popup.hide()
    return true


func _build_popup() -> void:
    _popup = PopupPanel.new()
    _popup.name = "StopColorPopup"
    # The engine opens a popup as a transparent window, and nothing behind it
    # may read through. The ground is the shared theme's `PopupPanel` box.
    _popup.transparent = false
    _popup.transparent_bg = false
    _popup.size = Vector2i(SaUI.px(POPUP_SIDE), SaUI.px(POPUP_SIDE))
    _picker = SaPickerShapeScript.new()
    _picker.name = "StopPicker"
    _picker.custom_minimum_size = Vector2(SaUI.px(POPUP_SIDE - 16), SaUI.px(POPUP_SIDE - 16))
    # As the colour moves, not when the popup shuts, which is what the answer to
    # decision 10 asks for: the ramp under the popup repaints while the hand is
    # still on the ring.
    _picker.color_changed.connect(_on_picked)
    _picker.color_committed.connect(_on_picked)
    _popup.add_child(_picker)
    add_child(_popup)


## The picker moved. The stop keeps its own alpha, because the two are edited by
## two different controls and taking the picker's would undo whatever the slider
## beside the swatch was just set to.
func _on_picked(picked: Color) -> void:
    if ramp == null or ramp.size() == 0:
        return
    picked.a = ramp.color_of(selected).a
    ramp.set_stop_color(selected, picked)


func _remove_selected() -> void:
    if ramp == null:
        return
    if ramp.remove_stop(selected):
        selected = clampi(selected, 0, ramp.size() - 1)


func _on_alpha_changed(value: float) -> void:
    set_selected_alpha(value)


# --- The bar -------------------------------------------------------------------


## Where along the ramp *x* is, in the bar's own logical units.
func _position_at(x: float) -> float:
    var width := _bar.size.x
    return clampf(x / width, 0.0, 1.0) if width > 0.0 else 0.0


## The stop nearest *x*, or -1 when none is within a handle's width of it.
func _stop_near(x: float) -> int:
    if ramp == null:
        return -1
    var best := -1
    var best_distance := SaUI.pxf(HANDLE_HALF)
    for i in ramp.size():
        var at := ramp.position_of(i) * _bar.size.x
        var distance := absf(at - x)
        if distance <= best_distance:
            best_distance = distance
            best = i
    return best


## Delete on the bar or on the row under it removes the selected stop, and is
## accepted whether or not one goes, so it never reaches the key that clears
## the layer. The fewest stops are kept by `remove_stop` itself.
func _on_stop_row_key(event: InputEvent) -> void:
    var key := event as InputEventKey
    if key == null or key.keycode != KEY_DELETE or key.is_command_or_control_pressed():
        return
    if key.pressed and not key.echo:
        _remove_selected()
    _bar.accept_event()


func _on_bar_input(event: InputEvent) -> void:
    if ramp == null:
        return
    if event is InputEventKey:
        _on_stop_row_key(event)
        return
    var button := event as InputEventMouseButton
    if button != null and button.pressed:
        var hit := _stop_near(button.position.x)
        if button.button_index == MOUSE_BUTTON_RIGHT:
            # Right on a handle removes it, which is the one gesture Blender's
            # ramp spends a button on and the one a painter reaches for first.
            if hit != -1 and ramp.remove_stop(hit):
                selected = clampi(selected, 0, ramp.size() - 1)
                _sync_row()
            _bar.accept_event()
            return
        if button.button_index != MOUSE_BUTTON_LEFT:
            return
        if hit != -1:
            selected = hit
            _dragging = true
        else:
            # A new stop takes the colour the ramp already has where it lands,
            # so adding one changes nothing until it is dragged or recoloured.
            selected = ramp.add_stop(_position_at(button.position.x))
            _dragging = true
        _sync_row()
        _bar.queue_redraw()
        _bar.accept_event()
        return
    if button != null and not button.pressed:
        _dragging = false
        _bar.accept_event()
        return
    var motion := event as InputEventMouseMotion
    if motion != null and _dragging:
        selected = ramp.move_stop(selected, _position_at(motion.position.x))
        _bar.accept_event()


func _draw_bar() -> void:
    var rect := Rect2(Vector2.ZERO, _bar.size)
    if rect.size.x <= 0.0 or rect.size.y <= 0.0:
        return
    _draw_checker(rect)
    if ramp != null:
        # One column per pixel of the bar, which is the finest a screen can show
        # and cheap enough at a docker's width: a GradientTexture1D would need
        # rebuilding on every stop drag and would still be sampled per column.
        var columns := int(rect.size.x)
        for x in columns:
            var t := (float(x) + 0.5) / float(columns)
            _bar.draw_rect(Rect2(float(x), 0.0, 1.0, rect.size.y), ramp.display_at(t))
    _bar.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45), false, 1.0)
    if ramp != null:
        for i in ramp.size():
            _draw_handle(rect, i)


func _draw_checker(rect: Rect2) -> void:
    var cell := SaUI.pxf(CHECKER_CELL)
    var rows := int(ceilf(rect.size.y / cell))
    var columns := int(ceilf(rect.size.x / cell))
    for row in rows:
        for column in columns:
            var light := (row + column) % 2 == 0
            var cell_rect := Rect2(float(column) * cell, float(row) * cell, cell, cell)
            _bar.draw_rect(cell_rect.intersection(rect), CHECKER_LIGHT if light else CHECKER_DARK)


## A stop's handle: a triangle pointing up at its position, filled with the
## stop's own colour at full alpha so it is readable over any ramp, and outlined
## white when it is the selected one.
func _draw_handle(rect: Rect2, index: int) -> void:
    var x := rect.size.x * ramp.position_of(index)
    var half := SaUI.pxf(HANDLE_HALF)
    var top := rect.size.y - SaUI.pxf(8.0)
    var points := PackedVector2Array([Vector2(x, top), Vector2(x - half, rect.size.y), Vector2(x + half, rect.size.y)])
    var fill := ramp.color_of(index)
    fill.a = 1.0
    _bar.draw_colored_polygon(points, fill)
    var outline := Color(1.0, 1.0, 1.0, 1.0) if index == selected else Color(0.0, 0.0, 0.0, 0.7)
    _bar.draw_polyline(points + PackedVector2Array([points[0]]), outline, SaUI.pxf(1.0))


# --- The capture harness's door ------------------------------------------------
#
# The bar is driven with `gui_input`, and an injected motion never reaches one,
# so a scenario cannot drag a stop however well it aims. The same reason `probe`,
# `click` and `docker_resize` exist.


## `{"ramp": {"select": 1, "add": 0.5, "color": "#20c040", "alpha": 0.0,
## "move": 0.6, "remove": 2, "open": true, "pick": "#204080", "save": "Sunset",
## "load": "Sunset", "stock": "foreground_to_transparent", "delete": "Sunset"}}`,
## each key optional and applied in that order against the ramp the Tool Options
## docker is showing. Answers the stops it left, so a scenario reads the result
## without a second dump.
##
## **Stops are counted from 0**, the near end, as the stop array of the answer
## and its `selected` count them, so the far end of a ramp of two stops is stop
## 1. A `select` or a `remove` naming a stop the ramp does not have is refused
## with the count it does have, and so is a `remove` that would leave fewer
## than two stops and a `color` or a `pick` that is no colour. A refusal
## applies no key after it. Clamping stop 2 of a ramp of two to stop 1 and
## answering success instead would lay a ramp none of the answers had shown.
##
## **Every edit is read back** off the ramp the tool lays, the tool's own
## `ramp` read again rather than the one this row holds, so an edit the tool
## does not lay, a ramp that went back to following the colours under it, is
## answered as a failure naming the stop and the colour it holds. The row reads
## the tool's ramp before the first key for the same reason. A failure and a
## refusal are each pushed as an error as well, which is what a door's answer
## carries in its `errors`.
##
## The last four are the library's, and they exist for the reason the first
## six do: the Save button is reachable by a click and the library's rows are
## in a popup, which is a Window an injected click does not route into.
##
## **An instance method, and that is the door.** A static handed the tree would
## have the step table name this script's `class_name`, a module class named in
## the skeleton. Instead `harness/captures/ramp_capture.gd` finds the visible
## control in the Tool Options docker that answers `capture_option_edit` and
## `stop_report` and calls it here, so the harness knows two methods and not
## the widget. Both, because a dialog's value row answers the first as well and
## a walk asking for it alone reaches that row. Named for the door rather than for the
## verb, because `FactorSlider.capture_edit` exists and a walk looking for
## `capture_edit` stops at the first slider it meets.
func capture_option_edit(spec: Dictionary) -> String:
    _refresh_from_tool()
    if ramp == null:
        return _failed("SaCapture: ramp refused, the row has no ramp to edit")
    var said := _edit_stops(spec)
    if not said.is_empty():
        return _failed(said)
    # The library's three, after the edits, so one step can shape a ramp and
    # save it.
    if spec.has("save"):
        print("SaCapture: ramp saved as '%s'" % save_ramp(String(spec["save"])))
    if spec.has("load"):
        print("SaCapture: ramp load '%s' -> %s" % [String(spec["load"]), load_ramp(String(spec["load"]))])
    if spec.has("stock"):
        var stock := StringName(String(spec["stock"]))
        print("SaCapture: ramp stock '%s' -> %s" % [stock, choose_stock(stock)])
    if spec.has("delete"):
        print("SaCapture: ramp delete '%s' -> %s" % [String(spec["delete"]), delete_ramp(String(spec["delete"]))])
    return "SaCapture: ramp %s" % JSON.stringify(stop_report())


## The door's stop edits in the order its doc gives, each checked before it is
## made and read back after, answering the refusal or the failure that stopped
## them, or "" when every one landed.
func _edit_stops(spec: Dictionary) -> String:
    if spec.has("select"):
        var refused := _no_stop("select", spec["select"])
        if not refused.is_empty():
            return refused
        select_stop(int(spec["select"]))
    if spec.has("add"):
        var count := ramp.size()
        var at := clampf(float(spec["add"]), 0.0, 1.0)
        select_stop(add_stop_at(at))
        if _laid().size() != count + 1 or not is_equal_approx(_laid().position_of(selected), at):
            return _missed("add at %s" % spec["add"], selected)
    # The popup's two, before the colour, because a scenario has to go through
    # the popup rather than round it. `open` shows the picker under
    # the swatch and `pick` moves that picker, which is the path a hand takes and
    # the one an injected click cannot: a popup is a Window.
    if spec.has("open"):
        var opened: bool = open_swatch() if bool(spec["open"]) else close_swatch()
        print("SaCapture: ramp swatch %s -> %s" % ["opened" if bool(spec["open"]) else "closed", opened])
    if spec.has("pick"):
        var picked: Variant = _colour_of(spec["pick"])
        if picked is String:
            return picked
        var moved := pick_in_swatch(picked)
        print("SaCapture: ramp picked %s -> %s" % [spec["pick"], moved])
        if moved and not _laid().color_of(selected).is_equal_approx(Color(_picker.color(), ramp.color_of(selected).a)):
            return _missed("pick %s" % spec["pick"], selected)
    if spec.has("color"):
        var asked: Variant = _colour_of(spec["color"])
        if asked is String:
            return asked
        set_selected_color(asked)
        if not _laid().color_of(selected).is_equal_approx(Color(asked, ramp.color_of(selected).a)):
            return _missed("color %s" % spec["color"], selected)
    if spec.has("alpha"):
        set_selected_alpha(float(spec["alpha"]))
        if not is_equal_approx(_laid().color_of(selected).a, clampf(float(spec["alpha"]), 0.0, 1.0)):
            return _missed("alpha %s" % spec["alpha"], selected)
    if spec.has("move"):
        move_selected(float(spec["move"]))
        if not is_equal_approx(_laid().position_of(selected), clampf(float(spec["move"]), 0.0, 1.0)):
            return _missed("move to %s" % spec["move"], selected)
    if spec.has("remove"):
        var refused := _no_stop("remove", spec["remove"])
        if refused.is_empty() and ramp.size() <= SaColorRamp.MIN_STOPS:
            var floor_said := "SaCapture: ramp refused, remove %d, a ramp keeps at least %d stops"
            refused = floor_said % [int(spec["remove"]), SaColorRamp.MIN_STOPS]
        if not refused.is_empty():
            return refused
        var count := ramp.size()
        remove_stop_at(int(spec["remove"]))
        if _laid().size() != count - 1:
            return _missed("remove", int(spec["remove"]))
    return ""


## The ramp the tool lays, read through its own `ramp` again, which re-seeds a
## ramp that follows the colours. The row's own for a row bound to a bare ramp.
func _laid() -> SaColorRamp:
    return _tool.ramp if _tool != null else ramp


## Why *asked*, the stop a *key* names, is none of the ramp's, or "" when it is.
func _no_stop(key: String, asked: Variant) -> String:
    var last := ramp.size() - 1
    var whole := (asked is int or asked is float) and float(asked) == floorf(float(asked))
    if whole and int(asked) >= 0 and int(asked) <= last:
        return ""
    # A door's JSON reads every number as a float, and "stop 2.0" is no stop
    # a painter counts.
    var named := str(int(asked)) if whole else JSON.stringify(asked)
    return (
        "SaCapture: ramp refused, %s %s, there is no stop %s on a ramp of %d stops, counted from 0 to %d"
        % [key, named, named, ramp.size(), last]
    )


## The colour an html *asked* names, `#rrggbb`, or the refusal of one that names none.
func _colour_of(asked: Variant) -> Variant:
    if asked is String and Color.html_is_valid(asked):
        return Color.html(asked)
    return "SaCapture: ramp refused, %s is no colour, a stop's colour is written as html (#rrggbb)" % JSON.stringify(asked)


## The failure of an edit, *what*, that the ramp the tool lays does not hold:
## stop *index* as it holds it and the stops it has.
func _missed(what: String, index: int) -> String:
    var laid := _laid()
    var held := laid.color_of(index)
    return (
        "SaCapture: ramp edit did not land, %s, stop %d of the ramp the tool lays holds %s at alpha %.3f at %.3f, %s"
        % [what, index, held.to_html(false), held.a, laid.position_of(index), "the stops are " + JSON.stringify(laid.to_array())]
    )


## *said* pushed as an error, so a door's answer carries it in its `errors`,
## and answered for the step to print.
func _failed(said: String) -> String:
    push_error(said)
    return said


## The four edits the capture door and a test both need, each named for what a
## hand does rather than for which private field it moves.
func select_stop(index: int) -> void:
    if ramp == null:
        return
    selected = clampi(index, 0, maxi(ramp.size() - 1, 0))
    _sync_row()
    _bar.queue_redraw()


func add_stop_at(at: float) -> int:
    return ramp.add_stop(at) if ramp != null else 0


func set_selected_color(color: Color) -> void:
    if ramp == null:
        return
    color.a = ramp.color_of(selected).a
    ramp.set_stop_color(selected, color)


## The slider's own handler and the capture step both land here, which is what
## makes this the one place an endpoint alpha is remembered from.
func set_selected_alpha(alpha: float) -> void:
    if ramp == null:
        return
    ramp.set_stop_alpha(selected, alpha)
    _ends.remember_endpoint_alpha(ramp, selected)


func move_selected(to: float) -> void:
    if ramp != null:
        selected = ramp.move_stop(selected, to)


func remove_stop_at(index: int) -> void:
    if ramp != null and ramp.remove_stop(index):
        selected = clampi(selected, 0, ramp.size() - 1)
        _sync_row()
