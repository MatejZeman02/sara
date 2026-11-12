## The text over the Graph docker's picture, because a compute kernel has no
## font: the numbers beside the kernel's value lines on a waveform or a parade,
## and the hue letters beside the nodes of the vectorscope's gamut ring. Drawn
## over the picture rather than beside it because a panel this size has no
## column to spare.
##
## Its own file, cut from `graph_docker.gd` by responsibility: this is what is
## written over the picture and where, and the docker is the controls, the
## polling and the two plots.
##
## It is told what to draw: the four facts it needs are its own public members,
## and the docker sets them where it asks for a redraw, rather than holding the
## docker and reading four things of it in `_draw`, which would make it a
## piece of another object's class.
class_name SaGraphLabels
extends Control

## Where the value scale is written, as the fraction of the axis and the number
## that sits there. Nought, half and whole: the nine lines the kernel draws are
## the resolution, and numbering all nine on a panel this size is a wall of
## digits. The top one carries the unit, which says what the other two count.
const SCALE_MARKS: Array = [[1.0, "100 %"], [0.5, "50"], [0.0, "0"]]

## How far a number's backing stays above its line, and how far the backing
## reaches round the number, in logical pixels. The kernel's heaviest line
## fades out 1.7 texels from its middle, so two pixels is clear of all of it.
const LINE_CLEARANCE := 2.0
const BACKING_PAD := 2.0

## Where 1.0 sits on a waveform or a parade: eight ninths of the height, with
## darktable's headroom above it. The kernel's `VALUE_TOP`, and its nine lines
## are the same ninths.
const VALUE_TOP := 8.0 / 9.0

## The six hue labels round the vectorscope: the document's primaries and
## secondaries, each written beside the node the kernel draws for it on the
## gamut's hue ring.
const HUE_LABELS: Array = [
    [Color(1, 0, 0), "R"],
    [Color(1, 1, 0), "Y"],
    [Color(0, 1, 0), "G"],
    [Color(0, 1, 1), "C"],
    [Color(0, 0, 1), "B"],
    [Color(1, 0, 1), "M"],
]

## The kernel's `SCOPE_RANGE` and `SCOPE_LOG_BASE`, so a label lands where the
## node is: the half width of the a and b plane the vectorscope shows, and
## the base of darktable's log radius.
const SCOPE_RANGE := 0.4
const SCOPE_LOG_BASE := 30.0

## The graph shown, as one of `SaGraphPlot.MODES`' ids. Written by the docker.
var graph_mode: String = SaGraphPlot.DEFAULT_MODE

## Whether the graph shown puts value up the side, which is the only case a
## nought-to-a-hundred scale down the left says anything true about. Written
## by the docker, which owns the rule.
var has_value_axis: bool = false

## `log`, darktable's default, or `linear`, one of `SaGraphPlot.SCALES`.
## Written by the docker. Named `scale_mode` because `Control` already holds a
## `scale`, and a member that shadows it would not resolve.
var scale_mode: String = "log"

## The document whose colours the hue letters are placed for, or null when
## there is none. Written by the docker, which is what holds the canvas.
var color_space: SaColorSpace = null


func _init() -> void:
    name = "RangeScale"
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    resized.connect(queue_redraw)


func _draw() -> void:
    var font := get_theme_default_font()
    if font == null:
        return
    var font_size := maxi(8, int(round(float(SaUI.get_font_size()) * 0.6)))
    if has_value_axis:
        _draw_value_labels(font, font_size)
    elif graph_mode == "vectorscope":
        _draw_hue_labels(font, font_size)


## A label at *at*, an outline first, because the trace under a number is any
## colour and a grey label on a red waveform is unreadable half the time.
func _draw_label(font: Font, font_size: int, at: Vector2, text: String, tint: Color) -> void:
    draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.0, 0.0, 0.0, 0.7))
    draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


func _draw_value_labels(font: Font, font_size: int) -> void:
    var tint := SaTheme.palette.text_muted
    for mark: Dictionary in value_marks(font, font_size):
        draw_rect(mark["backing"] as Rect2, SaTheme.palette.bg_primary)
        draw_string(font, mark["at"] as Vector2, String(mark["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


## Where each number of the value scale goes at this size: its text, the line
## it names, the baseline it is written on, and the backing under it, in the
## panel's colour and clear above the line.
##
## Beside the line rather than on it, because a number written on its line
## reads as struck through. Public so the suite
## can hold every backing clear of its line without reading a picture.
func value_marks(font: Font, font_size: int) -> Array[Dictionary]:
    var height := size.y
    var ascent := font.get_ascent(font_size)
    var tall := ascent + font.get_descent(font_size)
    var pad := SaUI.pxf(BACKING_PAD)
    var at_x := SaUI.pxf(3.0)
    var out: Array[Dictionary] = []
    for mark: Array in SCALE_MARKS:
        var text := String(mark[1])
        var line_y := height - float(mark[0]) * VALUE_TOP * height
        var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        # The backing's foot clear of the line, and its head inside the
        # picture when the headroom is shorter than a number.
        var top := maxf(line_y - SaUI.pxf(LINE_CLEARANCE) - tall - pad * 2.0, 0.0)
        var backing := Rect2(at_x - pad, top, width + pad * 2.0, tall + pad * 2.0)
        out.append({"text": text, "line_y": line_y, "at": Vector2(at_x, top + pad + ascent), "backing": backing})
    return out


## Each letter just outside the node it names, along the line from the
## middle, and kept inside the picture at the rim.
func _draw_hue_labels(font: Font, font_size: int) -> void:
    var side := minf(size.x, size.y)
    var corner := (size - Vector2(side, side)) * 0.5
    var space := color_space
    var ascent := font.get_ascent(font_size)
    for entry: Array in HUE_LABELS:
        var unit := scope_unit(entry[0] as Color, space, scale_mode)
        var out := (unit - Vector2(0.5, 0.5)).normalized()
        var at := corner + (unit + out * 0.035) * side
        var width := font.get_string_size(String(entry[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        at = Vector2(clampf(at.x - width * 0.5, 0.0, size.x - width), clampf(at.y + ascent * 0.5, ascent, size.y))
        var tint := entry[0] as Color
        _draw_label(font, font_size, at, String(entry[1]), tint.lerp(Color.WHITE, 0.35))


## Where a colour of the document lands on the vectorscope's square, the
## kernel's `scope_unit` on the CPU: through the document's matrix to linear
## sRGB, to Oklab, a across and b up in the units of `SCOPE_RANGE`, and pulled
## outwards by darktable's log unless *on_scale* is `linear`. Worked out here
## rather than read back from the vertices the kernel wrote, because a label
## is drawn every frame and the graph never reads back. A primary is 0 or 1
## on every channel, which every transfer curve maps to itself, so the curve
## the kernel decodes through is not needed.
static func scope_unit(rgb: Color, space: SaColorSpace, on_scale: String) -> Vector2:
    var linear := Vector3(rgb.r, rgb.g, rgb.b)
    if space != null:
        linear = space.to_space_matrix(SaColorSpace.linear_srgb()) * linear
    var lab := SaOklab.from_linear_srgb(linear)
    var centred := Vector2(lab.y, -lab.z) / (2.0 * SCOPE_RANGE)
    var h := centred.length()
    if on_scale != "linear" and h > 1e-6:
        var warped := log(1.0 + (SCOPE_LOG_BASE - 1.0) * h / 0.5) / log(SCOPE_LOG_BASE) * 0.5
        centred *= warped / h
    return centred + Vector2(0.5, 0.5)
