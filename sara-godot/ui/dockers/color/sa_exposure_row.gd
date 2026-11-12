## The paint exposure in stops, a row of the colour docker under the shape.
##
## What you pick is what you paint: a pick moves the slider and the slider
## moves the colour. The foreground is `SaColors`'s
## colour part times two to the power of these stops, so this row and the
## bar's Exposure are two views of one number, [member
## SaColorStore.exposure_stops]. The picker's wheel and sliders edit the colour
## part and leave this alone, and this leaves the colour part alone.
##
## A sibling of `sa_color_picker.gd` the way [SaPickerSliders] is, because it is
## a row with a meaning of its own, and it owns no number: it shows what it is
## given and says what the hand moved, and `ColorDocker` writes the store.
class_name SaExposureRow
extends HBoxContainer

## The layout key the row is called by in the element list and in Preferences.
const ELEMENT := "Paint Exposure"
## What the slider says on hover, the bar's Exposure's own sentence.
const HINT := "The paint exposure in stops: the colour picked, times two to this. A pick brighter than white sets it."

## The hand moved the slider, by drag, step or typed number.
signal stops_changed(stops: float)

var slider: FactorSlider


static func make() -> SaExposureRow:
    var row := SaExposureRow.new()
    row.name = "PaintExposure"
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.slider = SaMake.slider(row, "PaintExposureSlider", 0.0, SaPaintExposure.MAX, 0.01, 0.0)
    # The bar's Exposure reaches as far by drag and as far typed, so the two
    # views of one number move over the same travel.
    row.slider.soft_max_value = SaPaintExposure.REACH
    row.slider.prefix = "%s: " % TranslationServer.translate("Exposure")
    row.slider.suffix = " EV"
    row.slider.decimal_places = 2
    row.slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.slider.tooltip_text = TranslationServer.translate(HINT)
    row.slider.value_changed.connect(row.stops_changed.emit)
    return row


## Puts *value* stops on the slider without announcing them, so the store can
## move the row without the row writing the store back.
func show_stops(value: float) -> void:
    slider.set_value_no_signal(value)


## The stops the slider shows.
func stops() -> float:
    return slider.value


## *base* at the stops shown, the colour a brush paints from it.
func painted(base: Color) -> Color:
    return SaColorStore.exposed(base, slider.value)
