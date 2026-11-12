## The widget `SaDialog.slider` answers, and the type a student writes on a
## member.
##
## A box blur filter declares `var radius: SaSlider` and reads `radius.value`
## in `run`, so the name is the contract and this file exists to carry it. What
## it adds to [SaPageRow] is the soft and hard range a filter's options
## dictionary describes: the drag and the fill stop at the soft ends, and a
## typed number goes on to the hard ones, which is Krita's rule and the one
## `SaOptionSpec.soft_max` already spells for a tool's options.
##
## It draws a `FactorSlider` rather than the page layer's slider row, and that
## is the whole reason the row's kind is `CUSTOM`. The page layer draws an
## `HSlider` with a readout beside it, because that is what a Preferences page
## draws today and a converted page has to keep looking the same. A filter's
## slider needs the soft ceiling and a number a painter can type past it, which
## is `FactorSlider`, the control the options bar and the brush editor already
## use. `CUSTOM` is the escape hatch the declarative filter format put there for exactly
## this, and the row keeps its label column, its explanation, its dimming and,
## because this class wires the control itself, its value and its `changed`
## signal as well.
class_name SaSlider
extends SaPageRow

## What a slider shows when nothing said otherwise and the numbers it was given
## are whole. A radius of 3 reads `3`, not `3.0`.
const WHOLE_STEP: float = 1.0
const FINE_STEP: float = 0.01
const FINE_DECIMALS: int = 2

## Where the drag and the fill stop, when that is below [member max_value].
var soft_max: float = 0.0
## Where the drag and the fill start, when that is above [member min_value].
var soft_min: float = 0.0


## The widget for `slider(label, soft_min, soft_max, default, options)`.
##
## *options* carries `hard_min`, `hard_max`, `step`, `decimals` and `suffix`,
## which are the hard range, the step and the
## decimals, with the suffix added because a radius in pixels wants one and
## `FactorSlider` already draws it.
##
## **The three numbers are untyped because the way they are written is the
## declaration**. `ui.slider("Radius", 1, 20, 3)` is a count and steps by one,
## `ui.slider("Strength", 0.0, 1.0, 1.0)` is a fraction and steps by a
## hundredth, and the only thing telling them apart is that one call site wrote
## integers and the other wrote decimals. A typed `float` parameter throws that
## away at the door: both arrive as floats, `1.0` and `20.0` and `3.0` look
## exactly like `0.0` and `1.0` and `1.0`, and a strength between nought and one
## would draw a control with two positions on it, which is a checkbox somebody
## spelled as a slider. `Variant` keeps what the call site wrote long enough to
## read it.
static func make(text: String, soft_floor: Variant, soft_ceiling: Variant, default: Variant, options: Dictionary) -> SaSlider:
    var row := SaSlider.new()
    row.kind = SaPageRow.Kind.CUSTOM
    row.label = text
    var ceiling := float(soft_ceiling)
    row.min_value = float(options.get("hard_min", soft_floor))
    row.max_value = float(options.get("hard_max", soft_ceiling))
    # Zero means the two are one, which is `FactorSlider`'s own spelling.
    row.soft_max = ceiling if ceiling < row.max_value else 0.0
    row.soft_min = float(soft_floor) if float(soft_floor) > row.min_value else 0.0
    var whole := _written_whole(soft_floor) and _written_whole(soft_ceiling) and _written_whole(default)
    row.step_value = float(options.get("step", WHOLE_STEP if whole else FINE_STEP))
    row.decimal_places = int(options.get("decimals", 0 if whole else FINE_DECIMALS))
    row.suffix = String(options.get("suffix", ""))
    row.value = clampf(float(default), row.min_value, row.max_value)
    row.custom_control = row._build_control()
    return row


## What the row says about itself, plus the five numbers a slider has that no
## other row does. `widget` rather than `kind`, because the kind is the row the
## page layer draws and the widget is the name the student wrote.
func describe() -> Dictionary:
    var out := super()
    out["widget"] = "slider"
    out["soft_max"] = soft_max
    out["soft_min"] = soft_min
    out["hard"] = [min_value, max_value]
    out["step"] = step_value
    out["decimals"] = decimal_places
    return out


## Whether *number* was **written** as an integer, which is not the same
## question as whether it happens to have no fraction.
##
## `1` is, `1.0` is not, and GDScript keeps the difference in the `Variant` for
## exactly as long as nobody declares a `float` parameter. A value that is
## neither an int nor a float, which nothing in the tree passes and a student
## might, is read as not whole: a slider that steps by a hundredth is wrong
## about the step and a slider that steps by one is wrong about the range.
static func _written_whole(number: Variant) -> bool:
    return typeof(number) == TYPE_INT


## The control, wired here rather than by the builder, because a `CUSTOM` row is
## one the page hands a control to and the page cannot know what a
## `FactorSlider` calls its signal.
func _build_control() -> Control:
    var slider := FactorSlider.new()
    # Named for its caption, so a scenario's `slider_edit` finds this one and not
    # the first slider the options bar built.
    slider.name = label
    slider.min_value = min_value
    slider.max_value = max_value
    slider.soft_max_value = soft_max
    slider.soft_min_value = soft_min
    slider.step = step_value
    slider.decimal_places = decimal_places
    slider.suffix = suffix
    # The caption lives inside the box, the way the options bar's sliders read
    # `Size: 5 px`, and the row's own label column stays empty for it.
    slider.prefix = "%s: " % SaPage.translated(label)
    slider.value = float(value)
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(_slider_moved)
    return slider


func _slider_moved(moved: float) -> void:
    if is_equal_approx(moved, float(value)):
        return
    write(moved)
