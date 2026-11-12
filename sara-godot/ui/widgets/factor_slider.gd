## Factor Slider (`[ Size: 5.xyz px ]`).
##
## Merges label, numeric value, and interactive progress bar into a single sleek rounded box.
##
## The text is drawn in the interface font's Bold face at the theme font's
## size, so the Font size preference reaches it, and the slider asks for the
## width and the height that text needs, so no default label elides. The top
## bar may widen a slider on a row with room, never narrow it below its text.
##
## A drag with Shift held moves at a tenth of the rate, and Left and Right
## step the value by one displayed unit while the pointer is over the slider,
## ten with Shift. A painter found one pixel of drag worth three per cent of
## the brush's radius, and no way to land between two pixels of hand. A right
## press or Escape during a drag puts the value back, as in Blender.
@tool  # tmp tool to see changes in editor
extends Control

class_name FactorSlider

## A prefix or suffix longer than this is cut. A limit of ten would cut
## "Smoothing: " to "Smoothin.." on the bar, which reads as a broken label.
const MAX_LENGTH: int = 40

## Room above and below the text inside the box, both together, logical.
## None, since a font's height already holds its ascent and descent, and every
## pixel here is taken off the Colour Picker's wheel, whose docker keeps its
## height while its sliders grow.
const TEXT_V_PADDING: int = 0

## Room for the text inside the box, both sides together, logical. Six
## rather than more, because the first row's default assignment has to fit
## at 1920 and every slider on it pays this.
const TEXT_PADDING: int = 6

## How many displayed units Left or Right moves with Shift held.
const COARSE_KEY_UNITS: float = 10.0

## How far a new value has to be from the one held before a drag, a key, a
## reset or a typed number commits it, in the value's own units rather than
## the display's.
const COMMIT_TOLERANCE: float = 1e-6

## The most places after the point the number box opens on. A double carries
## about fifteen significant digits, so a sixteenth place names nothing.
const EDIT_PLACES_MAX: int = 15

## The share of the range under which the fill is not drawn and the zero tick
## is, since a fill a hair wide reads as a smudge rather than a value.
const FILL_RATIO_MIN: float = 0.005

## The tick a slider at the bottom of its range draws at the start of its
## track, logical: its width, and how far it stands in from the box's edges. An
## empty track read as a slider switched off, Hardness at 0 above all, and the
## fill's own floor of four pixels would read as a small value rather than
## none.
const ZERO_TICK_WIDTH: int = 3
const ZERO_TICK_INSET: int = 3

## The width of the marker a slider with a track gradient draws at its value in
## place of the fill, logical.
const MARKER_WIDTH: int = 6

## The dark edge round the label's text, logical, rather than a shadow one pixel
## off at 0.7 alpha, which the orange fill swallows: white on `#DE8055` is 2.87
## to 1.
const LABEL_OUTLINE: int = 4

## How many texels a track gradient is baked into, and how many segments each
## rounded corner of the polygon it is drawn on takes.
const TRACK_TEXELS: int = 256
const CORNER_SEGMENTS: int = 4

signal value_changed(new_value: float)

@export var min_value: float = 0.0:
    set(val):
        min_value = val
        _update_display()

@export var max_value: float = 100.0:
    set(val):
        max_value = val
        _update_display()

## Where a drag stops and where the fill reads full, when it is lower than
## `max_value`: Krita's soft limit. A typed value is clamped to `max_value`
## alone, the hard one, and a value past the soft ceiling draws as full. Zero
## means there is no soft ceiling.
@export var soft_max_value: float = 0.0:
    set(val):
        soft_max_value = val
        _update_display()

## The soft ceiling turned round: where a drag starts and the fill reads empty.
@export var soft_min_value: float = 0.0:
    set(val):
        soft_min_value = val
        _update_display()

@export var step: float = 0.1:
    set(val):
        step = val
        _update_display()

## The drag is geometric rather than linear, so a box that spans a tenth of a
## pixel to the whole document gives every octave of size the same room and the
## sizes a painter works at are not crushed into the last few pixels.
##
## Off by default. A slider that turns it on must have `min_value` above zero,
## because the mapping is a ratio of two distances from the minimum and a
## minimum of zero has no ratio to divide by: `_drag_ratio` answers zero for
## such a range and the drag stays linear.
@export var logarithmic: bool = false:
    set(val):
        logarithmic = val
        _update_display()

## A typed value past either end comes back round into the range rather than
## stopping at the end, for a row whose two ends are one place, an angle from
## -180 to 180. Off by default, so every other row still clamps. A value inside
## the range is kept as typed, so 180 stays 180 rather than turning into -180.
@export var wraps: bool = false

@export var value: float = 0.0:
    set(val):
        if value != val:
            value = val
            _update_display()

@export var prefix: String = "":
    set(val):
        prefix = val
        if prefix.length() > MAX_LENGTH:
            prefix = prefix.left(MAX_LENGTH - 2) + ".."
        _update_display()

@export var suffix: String = "":
    set(val):
        suffix = val
        if suffix.length() > MAX_LENGTH:
            suffix = suffix.left(MAX_LENGTH - 2) + ".."
        _update_display()

## Words the label shows after the prefix in place of the number, empty for the
## number. Paint and Smudge says "off" here while its Colour Rate is switched
## off, where its number would read "0 %" and say nothing about why.
var words: String = "":
    set(val):
        words = val
        _update_display()

## If true, internal value e.g. 0.023 is displayed/edited in range [min_value, max_value] (e.g. 2.3 %)
@export var normalized_display: bool = false:
    set(val):
        normalized_display = val
        _update_display()

@export var normalized_scale: float = 100.0

@export var display_value_multiplier: float = 1.0:
    set(val):
        display_value_multiplier = val
        _update_display()

@export var decimal_places: int = 1:
    set(val):
        decimal_places = maxi(0, val)
        value_format = "%%.%df" % decimal_places
        _update_display()

@export var value_format: String = "%.1f":
    set(val):
        value_format = val
        _update_display()

## Whether the label drops a trailing run of noughts after the point.
## Off unless a row asks for it, because a row's two decimals are either a
## scale or the number itself: the Size row spans three orders of magnitude
## and wants "25 px", and the export quality's two decimals are the precision
## a painter reads and must keep "1.00".
@export var trim_trailing_zeros: bool = false:
    set(val):
        trim_trailing_zeros = val
        _update_display()

## A gradient drawn across the track in place of the plain ground, left to right
## over the box as the drag maps it, for a slider whose values are colours. The
## value is then a thin marker rather than a fill, because a fill would cover
## the colours the track is there to show. Null on every slider but the Colour
## Picker's channels. A gradient changed in place redraws the slider as well.
## Whether Left and Right step by a whole displayed unit whatever the
## decimals. The Radius row asks for it: it shows two decimals always, so its
## text keeps one width, and a press still moves it a pixel and not a hundredth.
@export var steps_by_whole_units: bool = false

@export var track_gradient: Gradient = null:
    set(val):
        if track_gradient != null and track_gradient.changed.is_connected(queue_redraw):
            track_gradient.changed.disconnect(queue_redraw)
        track_gradient = val
        if val != null:
            _make_track()
            val.changed.connect(queue_redraw)
        if _track_texture != null:
            _track_texture.gradient = val
        queue_redraw()

## The left-button drag, and the value it began at, which a cancel puts back.
var _drag := SaSliderDrag.new()

var _label: Label
var _line_edit: LineEdit
## The text the number box opened on, so a box closed as it opened is a cancel
## and not a number to commit. Empty while the box is shut.
var _opened_text: String = ""
var _style_bg: StyleBoxFlat
var _style_fill: StyleBoxFlat
## The marker's light bar and the dark edge round it, and the track gradient
## baked into a texture the draw can stretch over the track. All three are made
## by `_make_track` and stay null on a slider that never had a track.
var _style_marker: StyleBoxFlat
var _style_marker_edge: StyleBoxFlat
var _track_texture: GradientTexture1D

## The value this slider was built with, what Backspace restores while nobody
## has given it a `default_value`. Read once in `_ready()`, because a dialog
## or a settings page sets `value` before `add_child()`, so the exported setter
## has already run by the time `_ready()` does and there is nothing to race.
var _built_value: float = 0.0

## What Backspace puts back, when a caller knows better than the slider what
## the value is meant to be. NaN until one says, and the slider then answers
## with `_built_value`.
##
## A brush slider on the Tool Options bar is built with a range and no value,
## and the loaded preset's value arrives after it is in the tree, so what it
## holds at `_ready()` is its range's floor, and Backspace would put Flow at
## nought.
## `ToolOptionControls` writes the preset's value here, again with each preset.
var default_value: float = NAN

## Whether the pointer sits over the slider, so Backspace answers a hover the
## same as a focus. Godot only routes a key event to a control's own
## `_gui_input` when that control holds keyboard focus, and this one asks for
## none, so the reset is caught in `_unhandled_key_input` instead and gated on
## this flag rather than on focus alone.
var _hovered: bool = false

## The width the slider asks for when its text does not need more. The constant
## by default, and the top bar raises it on a row with room to spare, so this is
## what the refresh below keeps rather than a number the bar set once and the
## next value change threw away.
var preferred_width: int = DockerUtils.px(DockerUtils.BASE_FACTOR_SLIDER_W)

## Whether the slider asks for its text's width. The Tool Options docker turns
## it off, because a slider there is a whole row and its widest text asked the
## docker 343 wide at a default of 300. Off, it asks for `preferred_width`
## and cuts its text with the ellipsis it already carries.
var fits_its_text: bool = true

## The value this slider moves, so a MIDI binding finds it again once the slider
## is gone: `tool/<tool>/<key>`, `filter/<filter>/<key>`, `layer/opacity`, and a
## Preferences row's `settings/<property>` under `SaPage.VALUE_NAME_META`. Empty
## when it moves nothing nameable.
var value_name: StringName = &""


func _init() -> void:
    name = "FactorSlider"
    custom_minimum_size = Vector2(
        DockerUtils.px(DockerUtils.BASE_FACTOR_SLIDER_W),
        DockerUtils.px(DockerUtils.BASE_FACTOR_SLIDER_H),
    )
    mouse_filter = MOUSE_FILTER_STOP

    _style_bg = StyleBoxFlat.new()
    # The slider family's own fields, so the box takes the slider track's colour
    # and the primary border as every slider of the family does.
    SaTheme.bind(_style_bg, {"bg_color": "slider_track", "border_color": "border_primary"})
    _style_bg.set_border_width_all(1)
    _style_bg.set_corner_radius_all(DockerUtils.px(4))

    _style_fill = StyleBoxFlat.new()
    SaTheme.bind(_style_fill, {"bg_color": "slider_handle"})
    _style_fill.corner_radius_top_left = DockerUtils.px(4)
    _style_fill.corner_radius_bottom_left = DockerUtils.px(4)
    _style_fill.corner_radius_top_right = DockerUtils.px(2)
    _style_fill.corner_radius_bottom_right = DockerUtils.px(2)

    _label = SaMake.label(self, "Label")
    _label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _label.set_anchors_preset(Control.PRESET_FULL_RECT)
    var offset_y := -DockerUtils.px(1)
    _label.offset_top = offset_y
    _label.offset_bottom = offset_y
    _label.mouse_filter = MOUSE_FILTER_IGNORE
    # A LabelSettings rather than theme overrides, because the theme pass and
    # the bar's compact pass rewrite every control's font size, and the text
    # would be measured at one size and drawn at another. Settings win over
    # both, so the size here is the size on screen.
    _label.label_settings = LabelSettings.new()
    _label.label_settings.font = SaFonts.bold()
    _label.label_settings.font_size = _resolved_text_size()
    _label.label_settings.font_color = SaTheme.palette.text_primary
    # An edge rather than a shadow, so the text holds on the fill, on the empty
    # track and on the brightest end of a colour ramp alike.
    _label.label_settings.outline_size = DockerUtils.px(LABEL_OUTLINE)
    _label.label_settings.outline_color = SaTheme.palette.text_shadow
    _label.text_overrun_behavior = SaTheme.TEXT_CUT

    _line_edit = SaMake.line_edit(self, "LineEdit")
    _line_edit.set_anchors_preset(Control.PRESET_FULL_RECT)
    var le_offset_y := -DockerUtils.px(1)
    _line_edit.offset_top = le_offset_y
    _line_edit.offset_bottom = le_offset_y
    _line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _line_edit.visible = false
    _line_edit.text_submitted.connect(_on_line_edit_submitted)
    _line_edit.focus_exited.connect(_on_line_edit_focus_exited)
    # Escape out of the field is a cancel and not a close.
    _line_edit.gui_input.connect(_on_line_edit_gui_input)
    _line_edit.add_theme_font_size_override("font_size", _resolved_text_size())
    _line_edit.add_theme_font_override("font", SaFonts.bold())
    var le_style := StyleBoxFlat.new()
    SaTheme.bind(le_style, {"bg_color": "bg_input", "border_color": "border_primary"})
    le_style.set_border_width_all(1)
    _line_edit.add_theme_stylebox_override("normal", le_style)
    _line_edit.add_theme_stylebox_override("focus", le_style)


func _ready() -> void:
    # The styles are drawn by hand in _draw, so a recoloured stylebox shows
    # only on the next draw, which a theme switch has to ask for.
    if not EventBus.theme_changed.is_connected(_on_theme_changed):
        EventBus.theme_changed.connect(_on_theme_changed)
    if not EventBus.ui_font_changed.is_connected(_on_font_changed):
        EventBus.ui_font_changed.connect(_on_font_changed)
    # A dialog never runs the theme pass, so the preference itself is what
    # moves a slider there. A docker's pass arrives after this as a theme
    # change, which refits it again at the size the pass wrote.
    if not EventBus.ui_font_scale_changed.is_connected(_on_font_scale_changed):
        EventBus.ui_font_scale_changed.connect(_on_font_scale_changed)
    if not mouse_entered.is_connected(_on_mouse_entered):
        mouse_entered.connect(_on_mouse_entered)
    if not mouse_exited.is_connected(_on_mouse_exited):
        mouse_exited.connect(_on_mouse_exited)
    _built_value = value
    _update_display()


## The width the widest text this slider can show needs at its size, plus
## the padding. What the box can never be narrower than, whatever a caller
## writes to custom_minimum_size. The widest rather than the current, so a
## drag from 9 to 100 does not shift everything to the right of it.
func _get_minimum_size() -> Vector2:
    if _label == null:
        return Vector2.ZERO
    var width := text_width() + float(DockerUtils.px(TEXT_PADDING)) if fits_its_text else 0.0
    return Vector2(width, text_height())


## The height the text needs at its size, plus the padding, so a larger Font
## size makes the box taller rather than letting the text spill over its edge.
func text_height() -> float:
    var font := _label.label_settings.font
    if font == null:
        return 0.0
    return ceilf(font.get_height(_label.label_settings.font_size)) + float(DockerUtils.px(TEXT_V_PADDING))


## The size the text is drawn at, logical: the theme font's size here, which
## is the theme pass's override when a pass reached this slider and the Font
## size preference's own size when none did.
func text_size() -> int:
    return _label.label_settings.font_size


func _resolved_text_size() -> int:
    if has_theme_font_size_override("font_size"):
        return get_theme_font_size("font_size")
    return SaUI.get_font_size()


## Reads the size again and remeasures, when it has moved.
func _refit_text() -> void:
    if _label != null and _sync_text_size():
        _update_display()


## Writes the resolved size onto the text and the field, and says whether it
## moved.
func _sync_text_size() -> bool:
    var wanted := _resolved_text_size()
    if wanted == _label.label_settings.font_size:
        return false
    _label.label_settings.font_size = wanted
    _line_edit.add_theme_font_size_override("font_size", wanted)
    return true


func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_THEME_CHANGED:
        _refit_text()


func _on_font_scale_changed(_font_scale: float) -> void:
    _refit_text()


## The widest text the drag can show, measured in the face and size the label
## draws at: either end of the range written with every decimal the row
## declares and every digit the font's widest, and the text it shows now.
##
## **The width holds for the whole range, so a drag never moves the bar.** A
## trimmed end is shorter than the values between, and a proportional face
## draws "111" narrower than "888".
func text_width() -> float:
    # Here as well as on entering the tree, because the top bar's sliders are
    # built and measured on a bar that is not in the tree yet, and a theme pass
    # may have set their size since they were built.
    _sync_text_size()
    var font := _label.label_settings.font
    if font == null:
        return 0.0
    var font_size := _label.label_settings.font_size
    var digit := _widest_digit(font, font_size)
    var widest := 0.0
    # Measured against the drag's ends rather than the typed ones, so a hard
    # limit ten times the soft one does not widen every row for a value nobody
    # drags to. A typed value past them is the painter's own choice.
    var texts: Array[String] = [_label.text]
    for end: float in [drag_min(), drag_max()]:
        texts.append(_display_text(end))
        texts.append(_with_digit(_display_text(end, false), digit))
    for text: String in texts:
        widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
    return widest


## The digit *font* draws widest at *font_size*.
static func _widest_digit(font: Font, font_size: int) -> String:
    var widest := "0"
    var width := -1.0
    for d in range(10):
        var w := font.get_string_size(str(d), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
        if w > width:
            width = w
            widest = str(d)
    return widest


## *text* with every digit in it written as *digit*.
static func _with_digit(text: String, digit: String) -> String:
    return RegEx.create_from_string("[0-9]").sub(text, digit, true)


## What the label shows for *raw*: prefix, the number as displayed, suffix.
##
## **One space stands between the number and the unit, whoever hands it**, so a
## module's " px" and its "px" both read "10.00 px".
func _display_text(raw: float, trimmed: bool = trim_trailing_zeros) -> String:
    var disp_val: float = raw * normalized_scale if normalized_display else raw
    disp_val *= display_value_multiplier
    var formatted_val := value_format % disp_val
    if trimmed:
        formatted_val = _trim_trailing_zeros(formatted_val)
    var unit := suffix.strip_edges(true, false)
    return "%s%s %s" % [prefix, formatted_val, unit] if unit != "" else "%s%s" % [prefix, formatted_val]


## *text* with a trailing run of noughts after the point removed, and the point
## with them when nothing follows it: "25.00" becomes "25" and "0.50" becomes
## "0.5".
##
## **Only a slider with `trim_trailing_zeros` set calls this**.
## The Size row is that slider: it reaches below one pixel, so it needs a second
## decimal to show 0.5 at all, and without this its two decimals would turn
## every whole size into "25.00 px". A row whose decimals are the number rather
## than a scale keeps them, which the export quality's "1.00" is.
static func _trim_trailing_zeros(text: String) -> String:
    if not text.contains("."):
        return text
    var trimmed := text.rstrip("0")
    if trimmed.ends_with("."):
        trimmed = trimmed.left(trimmed.length() - 1)
    return trimmed


func _on_font_changed(_font_id: String) -> void:
    _label.label_settings.font = SaFonts.bold()
    _line_edit.add_theme_font_override("font", SaFonts.bold())
    _update_display()


## Makes the track's texture and the marker's rims, the first time a track
## gradient is set rather than for every slider, since only the Colour Picker's
## channels draw one.
func _make_track() -> void:
    if _track_texture != null:
        return
    _track_texture = GradientTexture1D.new()
    _track_texture.width = TRACK_TEXELS
    # Float texels, so a channel past 1.0 is held rather than clamped on its way
    # to the screen.
    _track_texture.use_hdr = true
    # The label's own pair, a light bar in a dark edge, so the marker reads at
    # the darkest end of a ramp and at the lightest, and on Paper White turns
    # round with the text.
    _style_marker = StyleBoxFlat.new()
    SaTheme.bind(_style_marker, {"bg_color": "text_primary"})
    _style_marker.set_corner_radius_all(DockerUtils.px(1))
    _style_marker_edge = StyleBoxFlat.new()
    SaTheme.bind(_style_marker_edge, {"border_color": "text_shadow"})
    _style_marker_edge.draw_center = false
    _style_marker_edge.set_border_width_all(1)
    _style_marker_edge.set_corner_radius_all(DockerUtils.px(2))


func _draw() -> void:
    draw_style_box(_style_bg, Rect2(Vector2.ZERO, size))
    if track_gradient != null:
        _draw_track()
        return

    # The fill reads the same curve the drag does, so the bar is full where the
    # hand reaches the end and the middle of the box is the middle size.
    var top := drag_max()
    var ratio := ratio_of_value(value, top)

    if ratio <= FILL_RATIO_MIN:
        draw_rect(zero_tick(), _style_fill.bg_color)
        return
    var fill_width: float = clampf(size.x * ratio, DockerUtils.px(4), size.x)
    var fill_rect := Rect2(0, 0, fill_width, size.y)
    # If filling 100%, round right corners cleanly
    var right_corner := DockerUtils.px(4 if ratio >= 0.99 else 1)
    _style_fill.corner_radius_top_right = right_corner
    _style_fill.corner_radius_bottom_right = right_corner
    draw_style_box(_style_fill, fill_rect)


## Where the tick of a slider at the bottom of its range stands, at the start of
## the track and drawn in the fill's colour, or an empty rectangle while the
## fill says the value or a track gradient's marker does.
func zero_tick() -> Rect2:
    if track_gradient != null or ratio_of_value(value, drag_max()) > FILL_RATIO_MIN:
        return Rect2()
    var inset := float(DockerUtils.px(ZERO_TICK_INSET))
    return Rect2(inset, inset, float(DockerUtils.px(ZERO_TICK_WIDTH)), maxf(size.y - 2.0 * inset, 0.0))


## Where the marker of a slider with a track gradient stands: centred on the
## value, the box's full height, and held inside the box at either end.
func marker_rect() -> Rect2:
    var width := float(DockerUtils.px(MARKER_WIDTH))
    var center := size.x * ratio_of_value(value, drag_max())
    return Rect2(clampf(center - width * 0.5, 0.0, maxf(size.x - width, 0.0)), 0.0, width, size.y)


## The gradient inside the box's border, rounded the way the box is, and the
## marker over it. The texture's left edge is the box's left edge, so a colour
## sits at the same share of the box as the value that makes it.
func _draw_track() -> void:
    var border := float(_style_bg.border_width_left)
    var inner := Rect2(Vector2.ZERO, size).grow(-border)
    if inner.size.x < 1.0 or inner.size.y < 1.0:
        return
    var points := _rounded_points(inner, maxf(float(_style_bg.corner_radius_top_left) - border, 0.0))
    var uvs := PackedVector2Array()
    for point: Vector2 in points:
        uvs.append(Vector2(point.x / size.x, 0.5))
    draw_colored_polygon(points, Color.WHITE, uvs, _track_texture)
    var marker := marker_rect()
    draw_style_box(_style_marker_edge, marker)
    draw_style_box(_style_marker, marker.grow(-1.0))


## The outline of *rect* with its corners rounded by *radius*, clockwise from the
## top right, so a track's colours stay inside the box's own rounded edge.
static func _rounded_points(rect: Rect2, radius: float) -> PackedVector2Array:
    var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
    if r < 0.5:
        return PackedVector2Array(
            [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
        )
    var centers: Array[Vector2] = [
        Vector2(rect.end.x - r, rect.position.y + r),
        rect.end - Vector2(r, r),
        Vector2(rect.position.x + r, rect.end.y - r),
        rect.position + Vector2(r, r),
    ]
    var points := PackedVector2Array()
    for corner in centers.size():
        var start := PI * 0.5 * (corner - 1)
        for segment in CORNER_SEGMENTS + 1:
            var angle := start + PI * 0.5 * segment / CORNER_SEGMENTS
            points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * r)
    return points


func _gui_input(ev: InputEvent) -> void:
    var button := ev as InputEventMouseButton
    if button != null and button.button_index == MOUSE_BUTTON_LEFT:
        if button.pressed and button.double_click:
            start_editing()
        elif button.pressed:
            _begin_drag(button.position.x, button.shift_pressed)
        elif _drag.held:
            _drag.end()
        else:
            return
        accept_event()
    elif button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _drag.held:
        cancel_drag()
        accept_event()
    elif ev is InputEventMouseMotion and _drag.held and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
        _drag_to(ev.position.x, ev.shift_pressed)
        accept_event()


func _begin_drag(mx: float, fine: bool) -> void:
    _drag.begin(self, mx, fine)
    if not fine:
        _set_from_drag(_drag.ratio)


func _drag_to(mx: float, fine: bool) -> void:
    _set_from_drag(_drag.move(mx, fine))


## Ends the held drag with the value back at the press, a right press's and
## Escape's cancel. The release after it does nothing.
func cancel_drag() -> void:
    _commit(_drag.end())


func _on_mouse_entered() -> void:
    _hovered = true


func _on_mouse_exited() -> void:
    _hovered = false


## Backspace resets to the slider's default, and Left and
## Right step it, over a hovered slider or a focused one, neither of which a
## mouse-button or motion event reaches `_gui_input` for. Left alone while the
## text field is open, where both keys already mean what they always mean in a
## `LineEdit`.
##
## An arrow repeats while it is held, so a painter can run the value along,
## and one with Ctrl, Alt or Meta is left for a shortcut. The wheel is not
## taken, because over the Tool Options docker it scrolls the rows.
func _unhandled_key_input(event: InputEvent) -> void:
    if _line_edit.visible or not (_hovered or has_focus()):
        return
    var key := event as InputEventKey
    if key == null or not key.is_pressed():
        return
    if key.keycode == KEY_BACKSPACE and not key.is_echo():
        _commit(_built_value if is_nan(default_value) else default_value)
    elif (key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT) and not _is_chord(key):
        var units := COARSE_KEY_UNITS if key.shift_pressed else 1.0
        step_by_units(units if key.keycode == KEY_RIGHT else -units)
    else:
        return
    var viewport := get_viewport()
    if viewport != null:
        viewport.set_input_as_handled()


static func _is_chord(key: InputEventKey) -> bool:
    return key.ctrl_pressed or key.alt_pressed or key.meta_pressed


## Moves the value by *units* of what the label shows, a whole pixel on the
## Radius row and a per cent on Opacity, and says so when it moved.
##
## Held to the hard ends the way a typed number is, rather than to the drag's
## soft ceiling, because an arrow is as deliberate as typing and the brackets
## already reach past the soft ceiling on the Radius row. A row that `wraps`
## comes round, so Right at 180 degrees is -179.
func step_by_units(units: float) -> void:
    _commit(in_range(quantized(value + units * display_unit())))


## One displayed unit in the value's own terms: the last digit the label
## draws, turned back through the display's scale.
##
## **A row that trims its trailing noughts or asks for whole steps steps by a
## whole unit.** Its decimals are a scale rather than a precision, so the
## Radius row, two decimals to reach under a pixel, steps by a pixel and not by
## a hundredth of one. **A linear row never steps finer than its own
## step**, or the rounding in `quantized` would put every press back where it
## started. A geometric row is not rounded, so its step does not bound this.
func display_unit() -> float:
    var places := 0 if trim_trailing_zeros or steps_by_whole_units else decimal_places
    var shown := pow(10.0, -places)
    var display_scale := (normalized_scale if normalized_display else 1.0) * display_value_multiplier
    var unit := shown / display_scale if display_scale != 0.0 else shown
    if not logarithmic and step > 0.0:
        unit = maxf(unit, step)
    return unit


## Opens the number field on the value, as a double click on the row does.
func start_editing() -> void:
    _opened_text = editing_text()
    _line_edit.text = _opened_text
    # Again here, because the theme pass writes the field's size with every
    # other child's, and the field has to match the label it stands in for.
    _line_edit.add_theme_font_size_override("font_size", _label.label_settings.font_size)
    _line_edit.visible = true
    _line_edit.grab_focus()
    _line_edit.select_all()


## The text the number box opens on: the number the label shows, to the fewest
## places after the point that still name `value` within `COMMIT_TOLERANCE`.
##
## Rather than `str()` of the product, because a picker channel is a float32 and
## its noise times the multiplier would open R at 200 of 255 on
## `200.000003278255` and H at 81 degrees on `81.3417702913284`. Rounded to the
## tolerance they open on `200` and `81.342`: the three places H keeps are
## what 1e-6 of a turn is in degrees, and a painter nudging the hue by hand
## starts from them.
##
## **A slider with a multiplier of one keeps the text `str()` writes wherever
## rounding would drop no digit of it**, so a slider at 0.8 opens on `0.8` and
## one at 25 on `25.0`. Only a text carrying digits below the
## tolerance is cut there, which is float32 noise that is in the value rather
## than in a multiplier: the HDR channel at 1.2 would open on
## `1.20000004768372`.
##
## Measured against the tolerance before `quantized`, not after, because a
## picker channel steps by a thousandth and 200 of 255 is not on that grid, so
## no text at all would land within it. `_stop_editing` reads a box closed as
## it opened as a cancel for the same reason.
func editing_text() -> String:
    var disp_val: float = value * normalized_scale if normalized_display else value
    disp_val *= display_value_multiplier
    var today := str(disp_val)
    for places in EDIT_PLACES_MAX + 1:
        var text := String.num(disp_val, places)
        # `String.num` writes a small negative that rounds to nothing as "-0".
        if text.to_float() == 0.0:
            text = text.trim_prefix("-")
        if absf(value_from_shown(text.to_float()) - value) > COMMIT_TOLERANCE:
            continue
        if display_value_multiplier == 1.0 and str(text.to_float()) == today:
            return today
        return text
    return today


## The value a number *shown* in the display's units stands for, before it is
## rounded to the step or held in range. The one inverse of the label's
## scaling, which `_stop_editing` reads a typed number through and
## `editing_text` measures its rounding with.
func value_from_shown(shown: float) -> float:
    var raw := shown
    if display_value_multiplier != 0.0:
        raw /= display_value_multiplier
    if normalized_display and normalized_scale != 0.0:
        raw /= normalized_scale
    return raw


## The number *text* spells, or null when it spells none.
##
## **The app's one number-entry rule, and this file is where it lives.** Every
## slider a painter can type into commits through `_stop_editing` below:
## `SaSlider` builds a `FactorSlider`, and the options bar, the brush editor and
## the filter dialogs build one directly, so there is no second field to keep
## in step.
##
## `to_float()` answers zero for a word and for "1,5", and the clamp after it
## would write that zero out as the field's minimum, so a word typed into a
## brush's size would leave a 0.3 px brush.
##
## Whitespace is stripped first, because `is_valid_float()` answers false for
## " 42 " while `to_float()` reads it as 42, so a pasted number would be refused
## as if it were a word. `12`, `-3`, `1e2`, `1.` and `.5` all pass, and so does anything the
## display itself wrote.
static func number_from_text(text: String) -> Variant:
    var trimmed := text.strip_edges()
    if trimmed.is_empty() or not trimmed.is_valid_float():
        return null
    return trimmed.to_float()


## Commits what the field holds, or refuses it and says so.
##
## A refusal is the same rule as a cancel in every way that matters to a
## painter: the value is untouched and the label shows the number that was
## there before. The difference is that a refusal is announced, because Enter
## that silently does nothing reads as a broken field.
func _stop_editing() -> void:
    if not _line_edit.visible:
        return
    _line_edit.visible = false
    # A box closed as it opened commits nothing, so an Enter on a picker
    # channel leaves the colour where it was rather than on the step's grid.
    var left_alone := not _opened_text.is_empty() and _line_edit.text.strip_edges() == _opened_text
    _opened_text = ""
    if left_alone:
        _update_display()
        return
    var typed: Variant = number_from_text(_line_edit.text)
    if typed == null:
        var said := _line_edit.text.strip_edges()
        SaMessage.notice(
            (
                tr("Nothing was typed, so the value is unchanged.")
                if said.is_empty()
                else tr("'%s' is not a number, so the value is unchanged.") % said
            )
        )
        _update_display()
        return
    _commit(in_range(quantized(value_from_shown(float(typed)))))


## Where a typed *at_value* lands: clamped to the hard ends, or on a row that
## `wraps`, taken modulo the span into it, so 360 on an angle row is 0 and -270
## is 90. A drag never needs this, because the box it is read from is the range.
func in_range(at_value: float) -> float:
    var span := max_value - min_value
    if not wraps or span <= 0.0 or (at_value >= min_value and at_value <= max_value):
        return clampf(at_value, min_value, max_value)
    return fposmod(at_value - min_value, span) + min_value


func _on_line_edit_submitted(_text: String) -> void:
    _stop_editing()


func _on_line_edit_focus_exited() -> void:
    _stop_editing()


## Escape cancels the edit, leaves the value alone, and stops there.
##
## Without it the field has no Escape and the window around it does, so a
## mistyped number in the brush editor would cost the editor.
##
## `accept_event` is what makes the first Escape the field's and the second the
## window's, the shape `dockers/layer_rename.gd` has as well.
func _on_line_edit_gui_input(event: InputEvent) -> void:
    if not SaShortcutKeys.is_escape(event):
        return
    var key := event as InputEventKey
    if key == null or not key.is_pressed() or key.is_echo():
        return
    _cancel_editing()
    _line_edit.accept_event()


## Closes the text field without reading it, so the value is the one that was
## there before the typing.
##
## **Hidden before the focus is released**, and that order is the whole of it:
## `release_focus` emits `focus_exited`, which is wired to `_stop_editing`, which
## parses the field and commits it. `_stop_editing` returns at once for an
## invisible field, so hiding first is what turns the commit into a cancel
## without a second flag to keep in step.
func _cancel_editing() -> void:
    if not _line_edit.visible:
        return
    _line_edit.visible = false
    _opened_text = ""
    _line_edit.release_focus()
    _update_display()


func _update_from_mouse_x(mx: float) -> void:
    _set_from_drag(SaSliderDrag.share_of(mx, size.x))


## Puts the value at *ratio* of the box, rounded to the step and held between
## the drag's floor and its ceiling, and says so when it moved.
func _set_from_drag(ratio: float) -> void:
    var top := drag_max()
    _commit(clampf(quantized(value_at_ratio(ratio, top)), drag_min(), top))


## Makes *target* the value and says so, when it moved by more than `COMMIT_TOLERANCE`.
func _commit(target: float) -> void:
    if absf(target - value) > COMMIT_TOLERANCE:
        value = target
        _update_display()
        value_changed.emit(value)


## *at_value* rounded to the slider's step.
##
## **A geometric row is not quantized at all, and that is the point rather than
## an omission**. The absolute step would destroy the values the row was made to
## reach: a typed half pixel on a 1080-tall document is the canvas fraction
## nought point nought nought nought six, which a step of nought point nought
## nought one rounds to none and the floor then puts back at a whole pixel. A ratio quantum is no better: at a thousandth
## it is finer than the two decimals the row shows, so it is a rule that does
## nothing while reading as though it did. On a geometric row the discrete steps
## are the bracket keys' tenth and the drag is continuous, which is what a scale
## with a constant relative step means.
##
## **The grid starts at `min_value` when the floor is off it**, the way Godot's
## own `Range` steps, so the eyedropper's Sample, 1 to 25 in steps of two, lands
## on the odd sides it is made of rather than on the even ones between them. A
## floor on the grid, nought or a whole step, rounds as a plain grid does.
## A geometric row with no decimals lands on whole numbers, not 39.374103.
func quantized(at_value: float) -> float:
    if logarithmic and step > 0.0 and decimal_places == 0:
        return roundf(at_value)
    if step <= 0.0 or logarithmic:
        return at_value
    var origin := fposmod(min_value, step)
    if is_zero_approx(origin) or is_equal_approx(origin, step):
        origin = 0.0
    return roundf((at_value - origin) / step) * step + origin


## Where a drag to *ratio* of the box lands between `drag_min()` and *top*.
##
## Linear by default: a fraction of a range. Geometric when `logarithmic`, in
## which case equal steps of the box are equal *ratios* of size, and ratio 0.5
## sits at the geometric mean of the two ends rather than their average. The
## geomean is what makes the box's own middle a size a painter can name: on the
## Size row it is a brush the square root of the document's size rather than
## half of it.
##
## **A minimum of zero falls back to linear rather than answering zero.** The
## ratio's denominator is the distance from the minimum, so a range starting at
## zero has no scale to divide by. A spec asking for the curve on such a range is
## a declaration mistake, and the honest answer is the drag it always had rather
## than a slider that cannot move.
func value_at_ratio(ratio: float, top: float) -> float:
    var bottom := drag_min()
    if logarithmic and bottom > 0.0 and top > bottom:
        return bottom * pow(top / bottom, ratio)
    return bottom + ratio * (top - bottom)


## The ratio of the box *value* sits at, the inverse of [method value_at_ratio],
## so a dump or a test can name where a size is on the slider.
func ratio_of_value(at_value: float, top: float) -> float:
    var bottom := drag_min()
    if logarithmic and bottom > 0.0 and top > bottom:
        return clampf(log(at_value / bottom) / log(top / bottom), 0.0, 1.0)
    return clampf((at_value - bottom) / (top - bottom), 0.0, 1.0) if top > bottom else 0.0


## Not gated on being ready: the bar measures a slider before it is in a
## tree, and a slider that answered with no text would be measured at no width.
func _update_display() -> void:
    if _label == null:
        return
    _label.text = prefix + words if not words.is_empty() else _display_text(value)

    var text := text_width() + float(DockerUtils.px(TEXT_PADDING)) if fits_its_text else 0.0
    custom_minimum_size.x = maxf(float(preferred_width), text)
    update_minimum_size()
    queue_redraw()


## The ceiling a drag reaches: the soft one when there is one below the hard
## one, the hard one otherwise.
##
## **Zero is tested as zero, not as "not above the minimum".** The field's own
## comment says zero means there is no soft ceiling, and on a slider that starts
## at zero `soft_max_value > min_value` alone says the same thing by accident.
## On Brightness, minus a hundred to a hundred, an unset zero is above the
## minimum and below the maximum, so that test alone would read a soft ceiling
## at nought: a click at the middle would land at minus fifty and no drag could
## pass zero.
func drag_max() -> float:
    if soft_max_value != 0.0 and soft_max_value > min_value and soft_max_value < max_value:
        return soft_max_value
    return max_value


## The floor a drag reaches, `drag_max` turned round, zero read the same way.
func drag_min() -> float:
    if soft_min_value != 0.0 and soft_min_value > min_value and soft_min_value < drag_max():
        return soft_min_value
    return min_value


func set_value_no_signal(new_val: float) -> void:
    value = new_val
    _update_display()


func _on_theme_changed(_theme_id: String) -> void:
    _label.label_settings.font_color = SaTheme.palette.text_primary
    _label.label_settings.outline_color = SaTheme.palette.text_shadow
    queue_redraw()
