## Image > Projection...: say what the document's pixels are a picture of, flat
## or a panorama of a registered kind, and where its angle nought faces.
##
## Assign relabels and moves no pixel, the projection's half of the split the
## colour space dialog keeps. It is the honest repair for a panorama that
## arrived without saying so. Convert is the other half: it moves the pixels so
## the picture stays where it is, which between flat and polar is what other
## programs sell as a Polar Coordinates filter. The kinds are the registry's, so
## a module's kind is listed beside the three built-in ones with nothing here
## naming any of them.
##
## The dialog holds no document. Main configures it with the document's
## descriptor, the registry and the sentence a convert is said in, and applies
## [signal assign_requested] and [signal convert_requested], so it is exercised
## without an easel.
@tool
class_name SaProjectionDialog
extends SaDialogWindow

const DEFAULT_SIZE: Vector2i = Vector2i(460, 300)
const FLOOR_SIZE: Vector2i = Vector2i(380, 260)
const SEPARATION: int = 10
## The note's wrap width at a scale of one.
const NOTE_WIDTH: int = 400

## The painter chose to read the pixels as *projection*.
signal assign_requested(projection: SaProjection)
## The painter chose to move the pixels into *projection*.
signal convert_requested(projection: SaProjection)

var _current_label: Label = null
var _kind_option: SaChoiceButton = null
var _orientation_option: SaChoiceButton = null
var _yaw_slider: FactorSlider = null
## The orientation and yaw rows, shown only for a kind with an angle to point.
var _turn_rows: VBoxContainer = null
var cancel_button: Button = null
var assign_button: Button = null
var convert_button: Button = null
## What a convert to the rows' choice would do, said by [member _say_convert].
var _convert_label: Label = null

## The kinds the list was filled from, so a picked id finds its kind.
var _kinds: SaProjection.Kinds = null
## The document's descriptor, which a kind no module registers comes back as.
var _current: SaProjection = SaProjection.new()
## The sentence a convert to a projection is said in, for the document Main
## holds. Empty where there is none, and the label keeps its plain words.
var _say_convert: Callable = Callable()


func _init() -> void:
    _init_dialog("ProjectionDialog", tr("Document Projection"), DEFAULT_SIZE, FLOOR_SIZE)

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", SEPARATION)
    _current_label = SaMake.label(column, "CurrentLabel")

    var kind_row := SaMake.row(column, "KindRow", SEPARATION)
    SaMake.label(kind_row, "KindLabel", tr("Type"))
    _kind_option = SaMake.choice(kind_row, "KindOption")
    _kind_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _kind_option.choice_picked.connect(func(_value: Variant) -> void: _follow_kind())
    _kind_option.choice_picked.connect(func(_value: Variant) -> void: _follow_choice())

    _turn_rows = SaMake.column(column, "TurnRows", SEPARATION)
    var orientation_row := SaMake.row(_turn_rows, "OrientationRow", SEPARATION)
    SaMake.label(orientation_row, "OrientationLabel", tr("Orientation"))
    var presets: Array = []
    for preset: StringName in SaProjection.Heading.presets():
        presets.append({"id": preset, "label": tr(SaProjection.Heading.LABELS[preset])})
    _orientation_option = SaMake.choice(orientation_row, "OrientationOption", presets)
    _orientation_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _orientation_option.choice_picked.connect(func(_value: Variant) -> void: _follow_choice())

    _yaw_slider = SaMake.slider(_turn_rows, "YawSlider", -180.0, 180.0, 1.0, 0.0)
    _yaw_slider.decimal_places = 0
    _yaw_slider.prefix = tr("Yaw") + ": "
    _yaw_slider.suffix = "°"
    _yaw_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _yaw_slider.value_changed.connect(func(_value: float) -> void: _follow_choice())

    var note := SaMake.label(
        column,
        "NoteLabel",
        tr("Assign changes how the image is interpreted, without moving pixels. The orientation is where a panorama faces.")
    )
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    # A width of its own, because the column is no wider than its widest row
    # while the orientation rows are hidden, and a wrapping label measured that
    # narrow asked for a window 2,721 pixels tall.
    note.custom_minimum_size = Vector2(float(SaUI.px(NOTE_WIDTH)), 0.0)
    note.set_meta(SaUI.FONT_SCALE_META, 0.8)
    SaTheme.bind_font(note, "text_muted")
    _convert_label = SaMake.label(column, "ConvertLabel")
    _convert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _convert_label.custom_minimum_size = Vector2(float(SaUI.px(NOTE_WIDTH)), 0.0)
    _convert_label.set_meta(SaUI.FONT_SCALE_META, 0.8)
    SaTheme.bind_font(_convert_label, "text_muted")

    var buttons := pinned_buttons(column)
    cancel_button = SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    assign_button = SaMake.button(
        buttons, "AssignButton", tr("Assign"), tr("Read the pixels as this projection. Nothing moves, and it is one undo step.")
    )
    assign_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    assign_button.pressed.connect(_on_assign)
    default_button = assign_button
    convert_button = SaMake.button(
        buttons,
        "ConvertButton",
        tr("Convert"),
        tr("Move the pixels into this projection, so the picture stays where it is. One undo step.")
    )
    convert_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    convert_button.pressed.connect(_on_convert)

    configure(null, null)


## Opens on *current*, the document's projection, null for flat, with the kinds
## of *kinds* listed. A kind the document names and *kinds* does not hold is
## listed as well, so the dialog shows what the file says. *say_convert* takes a
## projection and gives the sentence a convert to it is said in.
func configure(current: SaProjection, kinds: SaProjection.Kinds, say_convert: Callable = Callable()) -> void:
    _current = current if current != null else SaProjection.new()
    _kinds = kinds
    _say_convert = say_convert
    var rows: Array = []
    var ids: Array[StringName] = []
    if kinds != null:
        ids = kinds.ids()
    if not ids.has(_current.kind.id):
        ids.append(_current.kind.id)
    for kind_id: StringName in ids:
        var listed := _kind_of(kind_id)
        rows.append({"id": kind_id, "label": tr(listed.label)})
    _kind_option.set_choices(rows)
    _kind_option.select_value(_current.kind.id)
    _orientation_option.select_value(_current.orientation.preset)
    _yaw_slider.set_value_no_signal(_current.orientation.yaw)
    _current_label.text = tr("Current: %s") % _current.describe()
    _follow_kind()
    _follow_choice()


## The projection the rows say. A flat kind takes the default orientation
## whatever the hidden rows hold, so a flat document's header stays as it was.
func chosen() -> SaProjection:
    var picked := _kind_of(StringName(str(_kind_option.selected_value())))
    if picked.view == SaProjection.View.CANVAS:
        return SaProjection.new(picked)
    var preset := StringName(str(_orientation_option.selected_value()))
    return SaProjection.new(picked, SaProjection.Heading.new(preset, _yaw_slider.value))


## A flat kind has no angle to point, so its orientation rows step aside. Shown
## again they take room the window may not have, so it is fitted once the
## layout has run, as it is when it opens, and the buttons stay inside it.
func _follow_kind() -> void:
    var turns := _kind_of(StringName(str(_kind_option.selected_value()))).view != SaProjection.View.CANVAS
    if turns == _turn_rows.visible:
        return
    _turn_rows.visible = turns
    fit_opening_size.call_deferred()


## The convert sentence for the rows' choice, and Convert only where it moves
## something.
func _follow_choice() -> void:
    var picked := chosen()
    var words := str(_say_convert.call(picked)) if _say_convert.is_valid() else ""
    _convert_label.text = words if not words.is_empty() else tr("Convert moves the pixels, so the picture stays where it is.")
    convert_button.disabled = picked.matches(_current)


func _kind_of(kind_id: StringName) -> SaProjection.Kind:
    var found: SaProjection.Kind = _kinds.find(kind_id) if _kinds != null else null
    if found != null:
        return found
    return _current.kind if _current.kind.id == kind_id else SaProjection.new().kind


func _on_assign() -> void:
    assign_requested.emit(chosen())
    hide()


func _on_convert() -> void:
    convert_requested.emit(chosen())
    hide()
