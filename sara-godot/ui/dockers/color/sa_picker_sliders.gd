## A row of numeric sliders in the colour picker docker: red, green and blue, or
## hue, saturation and value in OKHSV.
##
## A sibling of `sa_color_picker.gd` rather than lines in it, because that file
## holds the rows and this holds what a row of numbers means. Two instances,
## one per model, built from the same class: the models differ only in what
## three channels a colour is taken apart into and put back together from, and
## writing that twice is how the two would come to disagree.
##
## **A value above 1.0 survives.** `FactorSlider` clamps to its range, so a
## fixed 0 to 1 red slider would destroy an HDR colour the eyedropper picked
## the moment the picker refreshed, without anybody touching it. Two rules stop
## that. The RGB row widens its range to hold whatever it is shown, so a colour
## at 3.0 gets a slider that reaches 3.0 and reads it back exactly. And a drag
## writes only the channel that moved, taking the other two from the colour the
## row was last shown rather than from the sliders beside it, so a channel out
## of range is never round-tripped through a control that cannot hold it.
##
## The OKHSV row needs a third rule, though it looks as if it needs none: its
## three are angles and fractions with real ends, but a colour above 1.0 comes
## back through `okhsv_to_srgb`, which has no answer above 1.0, so the round
## trip alone would be the clamp. What the model cannot hold is one number, the
## peak channel, so the row carries it beside the three and shows OKHSV of the
## colour divided by it. A move of any of the three rebuilds a colour inside the
## cube and multiplies the peak back on, which is why a saturation drag on a
## colour at 3.0 leaves it at 3.0.
##
## **The OKHSV row holds a hue a grey has not got.** A grey has no hue and black
## has neither hue nor saturation, and `srgb_to_okhsv` answers nought for what a
## colour lacks. Taken at its word, a saturation dragged to nought and back
## would bring the colour back red, and a value dragged to nought and back would
## bring it back grey. So the row keeps its own three numbers, written by its
## drags and by a colour from outside, and a colour from outside that lacks a
## hue or a saturation leaves the one held, as the HSV square keeps its hue.
class_name SaPickerSliders
extends VBoxContainer

## Which three numbers a colour is taken apart into.
enum Model { RGB, OKHSV }

## Emitted while a slider is being dragged, the way the shape emits it.
signal color_changed(color: Color)
## Emitted when the drag ends or a typed value lands, so the recent colours get
## one entry per colour chosen rather than one per pixel of travel.
signal color_committed(color: Color)

## Channel labels and the layout key each model's row is called by.
const RGB_LABELS: Array[String] = ["R", "G", "B"]
const OKHSV_LABELS: Array[String] = ["H", "S", "V"]
const ELEMENT_RGB := "RGB Sliders"
const ELEMENT_OKHSV := "OK-HSV Sliders"

## What each channel's slider says on hover, in the labels' order: the channel
## by name and the unit its number reads in, which a single letter says neither
## of. An RGB channel switches its unit past the cube, so its sentence names both.
const RGB_HINTS: Array[String] = [
    "Red, from 0 to 255, and as a multiple of full red once any channel passes 255",
    "Green, from 0 to 255, and as a multiple of full green once any channel passes 255",
    "Blue, from 0 to 255, and as a multiple of full blue once any channel passes 255",
]
const OKHSV_HINTS: Array[String] = [
    "Hue, in degrees round the wheel",
    "Saturation, in per cent from the grey at 0 to the full colour at 100",
    "Value, in per cent from black at 0 to the colour at its brightest at 100",
]

## What an RGB slider's top end is for an ordinary colour, and the step it
## widens by. A colour at 1.4 gets a slider to 2.0 rather than to 1.4, so the
## end of the bar is a round number and dragging near it does not keep moving
## the range under the hand.
const SDR_MAX: float = 1.0
const HEADROOM_STEP: float = 1.0

## What a painter reads a channel in, as the number its slider multiplies by
## when it prints and divides by when a number is typed. The value underneath
## stays a fraction of one, so the colour, the dump and every scenario that
## reads [method report] keep their numbers and only the label changes: a hue
## of 0.114 is 41 degrees, a saturation of 0.77 is 77 per cent, and a channel
## of 0.784 is 200 of 255.
const HUE_DEGREES: float = 360.0
const PER_CENT: float = 100.0
const BYTE_MAX: float = 255.0
## The places an HDR channel prints, because 255 is the top of a colour inside the
## cube and a channel past it is not on that scale.
const HDR_PLACES: int = 3

## How many stops a channel's track is sampled at. An RGB ramp is a straight
## line in the encoding the track is drawn in and needs two, but OKHSV's are
## curves there, and the hue ring passes six primaries on its way round.
const TRACK_STOPS: int = 25

## The floor under one slider's own width, in logical units, and narrower than
## the tool options bar's because a docker column is narrower than the top bar.
##
## It is a floor and not a width. `FactorSlider._update_display` writes
## `custom_minimum_size.x = maxf(preferred_width, text_width() + TEXT_PADDING)`
## on every value change, so a channel reading `R: 12.345` widens past this and
## a channel reading `R: 0.910` does not.
##
## **It is one slider's number and not the row's.** This class is a
## `VBoxContainer`, so its three sliders stack rather than sitting side by side,
## and the row's own minimum width is one of them: a run reports `wants_width`
## 96 for the RGB row and 96 for the OKHSV row, not three times it. The
## sentence that stood here multiplied this number by three, as though the
## sliders were in a line, and measured the result against a docker default that
## had already moved to 279. It is not quoted here, so a grep for the stale width finds no live claim of it.
##
## **This row is not what the picker column's minimum is measured against.**
## `SaColorPicker.rows_fit` names the widest row, and it is `PickerTypeRow` at
## 305 logical units against this row's 96, so the column wants 305 and
## `DockerWindow.enforce_column_minimum` holds the docker at 321. Both numbers
## move, so read them off a run rather than off this comment
## (`scenarios/picker-slider-width-reason.json`) and change the width here
## for what a slider needs to read, not for what a docker is.
const SLIDER_WIDTH: int = 96

## The line over the OKHSV row that says whose H, S and V these are. The
## letters alone read as the HSV of every other program, which they are not,
## and the hover hints only reach a painter who hovers. A child of the row, so
## it shows and hides with it.
const OKHSV_CAPTION := "OKHSV, hue, saturation and value as Oklab sees them"

var model: Model = Model.RGB
var sliders: Array[FactorSlider] = []
## [constant OKHSV_CAPTION] in muted type over the OKHSV row, and null on the
## RGB row, whose letters mean what they mean everywhere.
var caption: Label = null

## The colour the row was last shown, which is what an untouched channel is
## taken from. Never re-derived from the sliders: a channel the sliders cannot
## hold would come back clamped.
var _color: Color = Color.BLACK
## The magnitude the OKHSV model cannot hold: the peak channel of the colour
## this row was last shown from outside, never below 1.0. The three sliders show
## OKHSV of the colour divided by this, and a colour they build is multiplied by
## it again. Unused by the RGB row, which widens a slider instead.
var _headroom: float = 1.0
## The OKHSV row's three numbers, hue, saturation and value of the colour over
## [member _headroom]. The colour alone cannot say them at a grey or at black,
## so the row holds them rather than re-deriving them from [member _color].
## Unused by the RGB row, whose three are the colour's own channels.
var _okhsv: Vector3 = Vector3.ZERO
## True between a press and a release on any of the three, so a drag emits
## changes and one commit rather than a commit per motion.
var _dragging: bool = false
## True while the row is hidden and has been shown a colour it has not drawn.
## Painting the three tracks is some 25 colour conversions a channel, and every
## picker refreshes every hidden row with every colour, a drag in the square
## once a frame, so a hidden row keeps the colour and draws
## it when it is shown.
var _stale: bool = false


static func make(which: Model) -> SaPickerSliders:
    var row := SaPickerSliders.new()
    row.model = which
    row.name = "RgbSliders" if which == Model.RGB else "OkhsvSliders"
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_theme_constant_override("separation", DockerUtils.px(2))
    if which == Model.OKHSV:
        row.caption = SaMake.label(row, "OkhsvCaption", TranslationServer.translate(OKHSV_CAPTION))
        # One line in the smaller face a page's help is drawn in, ending in an
        # ellipsis where the column is narrower than the sentence, so it never
        # widens the docker. The hover holds the whole of it.
        row.caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        row.caption.clip_text = true
        row.caption.tooltip_text = row.caption.text
        row.caption.mouse_filter = Control.MOUSE_FILTER_PASS
        # The theme pass's own scale rather than an override of the size, which
        # the docker's theme pass writes over.
        row.caption.set_meta(SaUI.FONT_SCALE_META, SaSettingsRows.HINT_SCALE)
        SaTheme.bind_font(row.caption, "text_muted")
    var labels: Array[String] = RGB_LABELS if which == Model.RGB else OKHSV_LABELS
    var hints: Array[String] = RGB_HINTS if which == Model.RGB else OKHSV_HINTS
    for i in labels.size():
        var slider := SaMake.slider(row, "%s%s" % [row.name, labels[i]], 0.0, SDR_MAX if which == Model.RGB else 1.0, 0.001, 0.0)
        slider.prefix = "%s: " % labels[i]
        slider.tooltip_text = TranslationServer.translate(hints[i])
        slider.preferred_width = DockerUtils.px(SLIDER_WIDTH)
        slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slider.value_changed.connect(row._on_slider_changed.bind(i))
        slider.gui_input.connect(row._on_slider_gui_input)
        # Each channel draws the colours it reaches rather than one orange fill
        # for all six, so R shows red and a fill does not read as on.
        slider.track_gradient = Gradient.new()
        row.sliders.append(slider)
        row._print_channel(i, true)
    row._paint_tracks()
    return row


## The element key this row is called by in the layout list and in Preferences.
func element_key() -> String:
    return ELEMENT_RGB if model == Model.RGB else ELEMENT_OKHSV


## Puts *color* on the three sliders without announcing anything, so the shape,
## the hex box and a chip can all drive this row without it driving them back.
func show_color(color: Color) -> void:
    # Only a colour from outside sets the headroom. The picker echoes every
    # change straight back here, so re-deriving it from the peak each time would
    # drag the value slider back to 1.0 under the hand the moment it moved.
    if color != _color:
        _headroom = peak_of(color)
        _okhsv = _okhsv_keeping(color)
    _color = color
    if not visible:
        _stale = true
        return
    _draw_color()


func _notification(what: int) -> void:
    if what == NOTIFICATION_VISIBILITY_CHANGED and visible and _stale:
        _draw_color()


## The sliders and their tracks put on the colour the row was last shown.
func _draw_color() -> void:
    _stale = false
    var color := _color
    var values := _channels()
    var within_cube := headroom_for(color) <= SDR_MAX
    for i in sliders.size():
        if model == Model.RGB:
            sliders[i].max_value = headroom_for(color)
            _print_channel(i, within_cube)
        sliders[i].set_value_no_signal(values[i])
    _paint_tracks()


## The top end an RGB slider needs to hold *color* exactly: 1.0 for a colour
## inside the cube, and the next whole number up for one outside it. Static so
## a test can ask without building a row.
static func headroom_for(color: Color) -> float:
    var highest := maxf(maxf(color.r, color.g), color.b)
    if highest <= SDR_MAX:
        return SDR_MAX
    return ceilf(highest / HEADROOM_STEP) * HEADROOM_STEP


## The peak the OKHSV row divides by, which is the colour's own and never the
## round number [method headroom_for] widens an RGB slider to. Exactness is the
## whole mechanism: dividing by the peak puts the colour on the sRGB gamut
## surface, where `max(r, g, b)` is 1.0 by construction and OKHSV's value is
## therefore 1.0, and a hue or saturation move along that surface comes back with
## a peak of 1.0 again. Round the divisor up to 4.0 for a colour at 3.5 and the
## base sits inside the cube instead, where nothing holds the peak still.
##
## A colour already inside the cube divides by 1.0, so an SDR picker behaves
## exactly as one with no HDR would.
static func peak_of(color: Color) -> float:
    return maxf(SDR_MAX, maxf(maxf(color.r, color.g), color.b))


## What the three sliders are showing, for a capture and for a test. The values
## are the sliders' own rather than the colour's, which is the point: a row
## that had clamped an HDR colour would say so here.
func report() -> Dictionary:
    var out := {
        "model": "rgb" if model == Model.RGB else "okhsv",
        "visible": visible,
        "headroom": _headroom,
        # What this row costs the column, which is the number `SLIDER_WIDTH`'s
        # docstring is about and the only one that can settle whether the row is
        # what a docker's minimum width is measured against. The column's own
        # `rows_fit` names its widest row and not the rest, so a row that is not
        # the widest reports nothing there.
        "wants_width": get_combined_minimum_size().x,
        "slider_width": DockerUtils.px(SLIDER_WIDTH),
        "caption": caption.text if caption != null else "",
        "caption_shown": caption != null and caption.is_visible_in_tree(),
    }
    var labels: Array[String] = RGB_LABELS if model == Model.RGB else OKHSV_LABELS
    for i in sliders.size():
        out[labels[i]] = sliders[i].value
        out["%s_max" % labels[i]] = sliders[i].max_value
        # In the docker's own window, which is what `origin` in the dump is
        # added to, so a scenario can press a channel rather than call into it.
        var rect := sliders[i].get_global_rect()
        out["%s_rect" % labels[i]] = {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
    return out


## Sets what channel *index* prints and what a number typed into it means.
##
## The OKHSV row always reads in degrees and per cent. The RGB row reads 0 to 255
## while *within_cube* and as a plain float once the colour is past 1.0: the
## display range is no ceiling (colours are never clamped), and 300 of 255 would claim a scale
## the colour has left. The three channels of a row switch together, so a row
## never reads one channel in bytes beside a neighbour in fractions.
func _print_channel(index: int, within_cube: bool) -> void:
    var slider := sliders[index]
    if model == Model.RGB:
        var wanted := BYTE_MAX if within_cube else 1.0
        # Every refresh of the picker comes through here, and each write to the
        # slider relays its text out, so a channel already reading this way is
        # left alone.
        if slider.display_value_multiplier != wanted:
            slider.display_value_multiplier = wanted
            slider.decimal_places = 0 if within_cube else HDR_PLACES
        return
    slider.decimal_places = 0
    if index == 0:
        slider.display_value_multiplier = HUE_DEGREES
        # The degree sign sits against the number and the per cent sign does not,
        # which is how each is written, so the hue carries it in the format and
        # the other two in the suffix the slider sets off with a space.
        slider.value_format = "%.0f°"
    else:
        slider.display_value_multiplier = PER_CENT
        slider.suffix = "%"


## Writes each channel's track: the colours the row would make with that channel
## alone moved across its range, the other two where the colour holds them. So R
## runs from no red to full red at this green and blue, S from the grey to the
## colour, and V from black to it. H is the ring the wheel draws, at full
## saturation and value, because a hue ramp at a grey's own would be one grey and
## say nothing about where the hues are.
func _paint_tracks() -> void:
    var held := _channels()
    for i in sliders.size():
        var slider := sliders[i]
        var offsets := PackedFloat32Array()
        var colors := PackedColorArray()
        for stop in TRACK_STOPS:
            var t := float(stop) / float(TRACK_STOPS - 1)
            var at := slider.value_at_ratio(t, slider.drag_max())
            var color: Color
            if model == Model.OKHSV and i == 0:
                color = OkhsvConversions.okhsv_to_srgb(at, 1.0, 1.0)
            else:
                var values := held.duplicate()
                values[i] = at
                color = _color_from(values)
            # Opaque, or a translucent colour's track would show the ground.
            color.a = 1.0
            offsets.append(t)
            colors.append(color)
        slider.track_gradient.offsets = offsets
        slider.track_gradient.colors = colors


## The colour *values* name under this row's model.
func _color_from(values: Array) -> Color:
    if model == Model.RGB:
        return Color(float(values[0]), float(values[1]), float(values[2]), _color.a)
    var out := OkhsvConversions.okhsv_to_srgb(float(values[0]), float(values[1]), float(values[2]))
    # Channel by channel rather than `out * _headroom`, which would scale the
    # alpha with them.
    return Color(out.r * _headroom, out.g * _headroom, out.b * _headroom, _color.a)


## The colour this row was last shown as its three channels.
func _channels() -> Array:
    if model == Model.RGB:
        return [_color.r, _color.g, _color.b]
    return [_okhsv.x, _okhsv.y, _okhsv.z]


## *color* in OKHSV over the current headroom, with the hue the row holds where
## *color* is a grey, and the hue and saturation it holds where *color* is
## black, since `srgb_to_okhsv` answers nought for both and nought is red.
func _okhsv_keeping(color: Color) -> Vector3:
    var base := Color(color.r / _headroom, color.g / _headroom, color.b / _headroom, color.a)
    var hsv := OkhsvConversions.srgb_to_okhsv(base)
    if OkhsvConversions.is_achromatic(base):
        hsv.x = _okhsv.x
    if hsv.z <= 0.0:
        hsv.y = _okhsv.y
    return hsv


## One channel moved. The other two come from what this row holds, not from
## the sliders: a channel above a slider's top end lives in
## `_color` and nowhere else, and reading it back off a control would clamp it.
func _on_slider_changed(new_value: float, index: int) -> void:
    var values := _channels()
    values[index] = new_value
    if model == Model.OKHSV:
        _okhsv = Vector3(values[0], values[1], values[2])
    _color = _color_from(values)
    color_changed.emit(_color)
    # A value that arrives with no drag under way was typed into the slider's
    # own box, which is a colour chosen rather than a colour being swept.
    if not _dragging:
        color_committed.emit(_color)


func _on_slider_gui_input(event: InputEvent) -> void:
    var press := event as InputEventMouseButton
    if press == null or press.button_index != MOUSE_BUTTON_LEFT:
        return
    if press.pressed:
        _dragging = true
        return
    if _dragging:
        _dragging = false
        color_committed.emit(_color)
