## Select > Feather, Border, Grow and Shrink: one radius in pixels and an
## Apply, rather than a few fixed values in each submenu.
##
## `SaSelectMenu` builds one instance for each, under the window name it hands
## the constructor, and `configure()` retitles and loads the radius of the one
## it opens. All open centred, so a second is cascaded off the first by
## `SaDialogWindow`.
##
## The canvas right-click menu of a selection tool builds one more, under
## "FeatherOptionDialog", for the tool's own Feather, the one the next selection
## is drawn with, and sets the slider's word and ceiling for it.
##
## The slider carries its word inside the bar, "Feather: 5 px", and a muted line
## under it says which way the pixels run, because "5 px" alone is five pixels
## of nothing in particular and Border's could be inside or outside the edge.
@tool
class_name SaRadiusDialog
extends SaDialogWindow

## The painter pressed Enter or Apply. `SaSelectMenu` runs the filter and
## remembers the radius for next time.
signal radius_confirmed(radius: int)

## What each word's pixels mean, shown under the slider. A word with no line here
## shows none.
const HINTS := {
    "Feather": "The edge softens over this many pixels inside it and this many outside.",
    "Feather for the Next Selection":
    "The next selection you draw fades over this many pixels. The one there is now keeps its edge.",
    "Border": "A band drawn across the edge, this many pixels inside it and this many outside.",
    "Grow": "The edge moves out by this many pixels on every side.",
    "Shrink": "The edge moves in by this many pixels. Parts thinner than twice that disappear.",
}

var _slider: FactorSlider = null
var _hint: Label = null


## *window_name* is what the window answers to in the tree, one per kind, so a
## scenario step aimed at one finds that one.
func _init(window_name: String = "RadiusDialog") -> void:
    _init_dialog(window_name, tr("Radius"), Vector2i(300, 130), Vector2i(260, 110))

    var margin := SaMake.margin(content, "Margin", SaTheme.PAD)
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    var column := SaMake.column(margin, "Column", 10)
    _slider = SaMake.slider(column, "RadiusSlider", 1.0, float(SaSelectionFilters.MAX_RADIUS), 1.0, 1.0)
    _slider.decimal_places = 0
    _slider.suffix = "px"
    _slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hint = SaMake.label(column, "HintLabel")
    _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    SaTheme.bind_font(_hint, "text_muted")

    var buttons := SaMake.row(column, "Buttons", SaTheme.GAP)
    buttons.alignment = BoxContainer.ALIGNMENT_END
    var cancel_button := SaMake.button(buttons, "CancelButton", tr("Cancel"))
    cancel_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    cancel_button.pressed.connect(hide)
    var apply_button := SaMake.button(buttons, "ApplyButton", tr("Apply"))
    apply_button.custom_minimum_size = Vector2(float(SaUI.px(90)), 0.0)
    apply_button.pressed.connect(_apply)
    default_button = apply_button


## Retitles for *label*, a key of [constant HINTS], names the slider for it and
## opens at *starting_radius*. *slider_word*, translated by the caller, names the
## slider instead, for a title too long to sit inside the bar, and *ceiling* above 0 is the most the
## slider reaches, where a filter's own largest radius is not the limit.
func configure(label: String, starting_radius: int, slider_word: String = "", ceiling: float = 0.0) -> void:
    var words := tr(label)
    retitle(words)
    _slider.prefix = (slider_word if not slider_word.is_empty() else words) + ": "
    _slider.max_value = ceiling if ceiling > 0.0 else float(SaSelectionFilters.MAX_RADIUS)
    _hint.text = tr(String(HINTS.get(label, "")))
    _hint.visible = _hint.text != ""
    # Feather alone reaches 0, the hard edge a run of Feathers goes back to.
    # The others have nothing to do at 0, so they keep a floor of 1.
    _slider.min_value = 0.0 if label.begins_with("Feather") else 1.0
    _slider.value = maxf(float(starting_radius), _slider.min_value)


func radius() -> int:
    return int(_slider.value)


## Apply, and Enter from the base class whenever the outline is on no other
## button, the radius typed into the field included. The dialog takes no Enter
## of its own, because one that took every Enter applied the feather with the
## outline on Cancel.
func _apply() -> void:
    radius_confirmed.emit(radius())
    hide()
