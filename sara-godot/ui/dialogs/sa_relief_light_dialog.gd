## View > Relief Light...: the open document's light on its impasto, where it
## stands and how strong the relief looks, in a small window of two sliders.
##
## The light is the document's, `SaReliefLight`, saved in its `.sad`, so a
## painting opens lit the way it was left. Preferences > Canvas and colour keeps
## the two values a new document starts from, and this is where the open one's
## are moved.
##
## **The sliders move the light as they travel**, so the canvas relights under
## the hand, and the window's close records the whole move as one Relief Light
## step, however often either slider moved. A drag recorded tick by tick folds
## only while the ticks come less than 800 ms apart, which is `UndoRedo`'s own
## window, so a slow drag would leave several steps to undo.
@tool
class_name SaReliefLightDialog
extends SaDialogWindow

var angle_slider: FactorSlider = null
var strength_slider: FactorSlider = null

## The document the sliders move, from `configure` until the close records the
## move, and null otherwise.
var _document: SaDocument = null
## Where its light stood when the window was pointed at it.
var _was_angle: float = 0.0
var _was_strength: float = 0.0


func _init() -> void:
    _init_dialog("ReliefLightDialog", tr("Relief Light"), Vector2i(360, 170), Vector2i(280, 150))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    angle_slider = SaMake.slider(column, "LightAngleSlider", 0.0, 360.0, 1.0, 315.0)
    angle_slider.prefix = tr("Light direction") + ": "
    angle_slider.suffix = "°"
    angle_slider.decimal_places = 0
    angle_slider.tooltip_text = tr(
        "Where the light on the paint's height comes from, in degrees clockwise from the top of the canvas."
    )
    angle_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    angle_slider.value_changed.connect(_on_angle_moved)
    strength_slider = SaMake.slider(column, "ReliefStrengthSlider", 0.0, SaSettings.MAX_RELIEF_STRENGTH, 0.25, 2.0)
    strength_slider.prefix = tr("Relief strength") + ": "
    strength_slider.decimal_places = 2
    strength_slider.tooltip_text = tr("How steep the paint's height is drawn. The height itself stays as painted.")
    strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    strength_slider.value_changed.connect(_on_strength_moved)
    var note := SaMake.label(column, "NoteLabel", tr("Saved with this document. Preferences sets where a new one starts."))
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(note, "text_muted")

    var buttons := pinned_buttons(column)
    var close := SaMake.button(buttons, "CloseButton", tr("Close"))
    close.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    close.pressed.connect(hide)
    default_button = close
    visibility_changed.connect(_record_on_close)


## Points the sliders at *document*'s light as it stands. A move the window
## held for another document, or for this one before a second open, is recorded
## first, so no move goes unrecorded.
func configure(document: SaDocument) -> void:
    _record()
    _document = document
    _was_angle = document.relief_light.angle
    _was_strength = document.relief_light.strength
    angle_slider.set_value_no_signal(_was_angle)
    strength_slider.set_value_no_signal(_was_strength)


func _on_angle_moved(value: float) -> void:
    if _document != null and is_instance_valid(_document):
        _document.relief_light.angle = value


func _on_strength_moved(value: float) -> void:
    if _document != null and is_instance_valid(_document):
        _document.relief_light.strength = value


## Any close, the button, the ×, Escape or a hide from outside, records the move.
func _record_on_close() -> void:
    if not visible:
        _record()


## The move since `configure` as one Relief Light step, and the window lets go
## of the document.
func _record() -> void:
    if _document != null and is_instance_valid(_document):
        SaReliefLight.record(_document, _was_angle, _was_strength)
    _document = null
