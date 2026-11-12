## The Info docker's frame rate: a number that follows every frame and a graph
## of the last minute, one point every two seconds.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## Both are counted here from
## `Engine.get_frames_drawn()`, which is the frames the renderer actually drew.
## `Engine.get_frames_per_second()` is not used, because it counts main loop
## iterations, and in low processor mode the loop keeps iterating while the
## renderer draws nothing, so an idle Sara would read as a busy one.
##
## **A rest reads as rest.** `SaFramePacer` turns low processor mode off while
## the hand moves and back on after, so a Sara left alone draws a frame only
## when something asks for one. A count of those is how often something asked,
## not how fast Sara draws, and drawn as a line it falls to the floor, which
## even under a faint band reads as a graph dropping to zero when nothing is
## happening. So a point spent mostly at rest
## is left out of the line, which stops where the rest
## begins, and the band carries the word where it is wide enough. A busy point
## is the frames drawn while the hand moved over the time it moved, so the line
## does not dip into a rest either: a point half spent at rest was drawn at half
## the rate the hand had. A slow stretch while the hand moves still draws low,
## because that one is real. A resting point keeps what the engine drew, for a
## dump to read.
##
## **The height carries its values.** The top the line is scaled to, half of it
## and the floor are written up the left, so a point at half height reads as 30
## or as 60 frames a second on the graph itself rather than on a top nobody sees.
##
## **At rest the number reads the word.** The frames of the last second at
## rest are 0 or 1, a count near zero that reads as a fault. The word never
## changes while Sara rests, so the row is written
## once when a rest begins and not again until the hand moves, and a text that
## does not change asks for no frame. The graph asks for one frame when a point
## lands, so the band follows the rest across the strip, which is the one frame
## in two seconds a visible Info docker costs at rest. A hidden docker costs
## nothing, because the docker stops ticking it.
##
## Drawn on the CPU with `draw_polyline` from counts the engine already keeps,
## so it adds no dispatch and no readback.
class_name SaInfoFpsGraph
extends Control

## Microseconds a point of the graph spans.
const SAMPLE_USEC: int = 2_000_000

## Points the graph holds, so the width is a minute.
const SAMPLES: int = 30

## The graph's height in logical pixels, tall enough that the values written
## up the side leave the line room to read.
const HEIGHT: int = 64

## The rate the top of the graph stands for until a sample goes above it, and
## the step the top grows in when one does. Sixty is a common refresh, and a
## graph scaled to its own peak would draw a flat minute of rest as a cliff.
## A point within `TOP_SLACK` of a step stays under it, because a display at
## sixty measures 60.1 as often as 59.9 and the graph should not halve for it.
const TOP_STEP: float = 60.0

## The fraction of a step a point may pass the top by and still sit under it.
const TOP_SLACK: float = 0.02

## Logical pixels between a value and the line it names.
const AXIS_GAP: float = 4.0

## Logical pixels a band keeps clear either side of the word it carries.
const REST_WORD_PAD: float = 4.0

## Frames per second of each point, oldest first.
var samples: PackedFloat32Array = PackedFloat32Array()

## Whether each point was spent mostly in low processor mode, beside `samples`.
var idle: Array[bool] = []

## Frames drawn in the last second, as of the latest tick.
var fps_now: int = 0

## Whether the latest tick was spent at rest, which is what the number reads.
var resting: bool = false

## The values the last draw wrote up the side, top first, so a dump reads the
## axis a shot shows.
var axis_drawn: PackedStringArray = PackedStringArray()

## How many bands the last draw wrote the word in.
var rest_words_drawn: int = 0

## When the drawn frames of the last second were counted, a time per frame.
var _frame_times: PackedInt64Array = PackedInt64Array()

## The previous tick's time and drawn-frame count, -1 before the first.
var _last_tick: int = -1
var _last_drawn: int = 0

## Where the current sample began, and the drawn-frame count then.
var _sample_start: int = 0
var _sample_frames: int = 0

## Microseconds of the current sample spent at rest.
var _sample_idle_usec: int = 0

## Frames of the current sample drawn while the hand moved.
var _sample_busy_frames: int = 0


func _init() -> void:
    name = "FpsGraph"
    custom_minimum_size = Vector2(0.0, SaUI.pxf(HEIGHT))
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    # The values are written at the rows' size, through the meta the theme pass
    # reads, so a Font size preference moves both.
    set_meta(SaUI.FONT_SCALE_META, SaInfoSection.ROW_FONT_SCALE)


## One frame of the main loop: the time, the engine's drawn-frame count and
## whether the engine is resting. Answers whether what the number reads changed,
## which at rest is only the tick the rest began.
##
## Every argument is passed in rather than read here, so a suite feeds a known
## series and the docker feeds the engine.
func tick(now_usec: int, frames_drawn: int, at_rest: bool) -> bool:
    var was_resting := resting
    resting = at_rest
    if _last_tick < 0:
        _last_tick = now_usec
        _last_drawn = frames_drawn
        _sample_start = now_usec
        _sample_frames = frames_drawn
        return resting != was_resting
    var drawn := maxi(frames_drawn - _last_drawn, 0)
    if at_rest:
        _sample_idle_usec += now_usec - _last_tick
    else:
        _sample_busy_frames += drawn
    _last_tick = now_usec
    for _frame in range(drawn):
        _frame_times.append(now_usec)
    _last_drawn = frames_drawn
    var keep := 0
    while keep < _frame_times.size() and _frame_times[keep] <= now_usec - 1_000_000:
        keep += 1
    if keep > 0:
        _frame_times = _frame_times.slice(keep)
    var before := fps_now
    fps_now = _frame_times.size()

    var spent := now_usec - _sample_start
    if spent >= SAMPLE_USEC:
        # Mostly at rest, what the engine drew over the whole span. Mostly
        # moving, what it drew while the hand moved over that time, which is at
        # least half the span and so never a division by nothing.
        var was_idle := _sample_idle_usec * 2 >= spent
        var frames := frames_drawn - _sample_frames if was_idle else _sample_busy_frames
        var usec := spent if was_idle else spent - _sample_idle_usec
        push_sample(float(frames) * 1_000_000.0 / float(usec), was_idle)
        _sample_start = now_usec
        _sample_frames = frames_drawn
        _sample_idle_usec = 0
        _sample_busy_frames = 0
    return resting != was_resting or (not resting and fps_now != before)


## Adds one point, dropping the oldest past a minute, and asks for a frame.
func push_sample(fps: float, was_idle: bool) -> void:
    samples.append(fps)
    idle.append(was_idle)
    if samples.size() > SAMPLES:
        samples = samples.slice(samples.size() - SAMPLES)
        idle = idle.slice(idle.size() - SAMPLES)
    queue_redraw()


## What the number reads: the frames of the last second while the hand moves,
## and the word at rest.
func fps_text() -> String:
    return rest_word() if resting else str(fps_now)


## The word the number and a band read at rest, lower case like the docker's
## other words.
func rest_word() -> String:
    return tr("resting")


## The rate the top edge stands for: `TOP_STEP`, or the peak of the points the
## line draws rounded up to a step when one is above it.
func top() -> float:
    var peak := TOP_STEP
    for i in range(samples.size()):
        if not idle[i]:
            peak = maxf(peak, samples[i])
    return maxf(ceilf(peak / TOP_STEP - TOP_SLACK), 1.0) * TOP_STEP


## Where the newest point sits and how far apart two are, in *area*: the newest
## at the right edge, a minute across the width.
static func slot_width(area: Vector2) -> float:
    return area.x / float(SAMPLES - 1)


## The part of *area* the line is drawn in, for values *label* wide and tall:
## right of the values, and in from the top and the bottom by half a value's
## height, so the top's value and the floor's are centred on the heights they
## name rather than cut by the edge.
static func plot_rect(area: Vector2, label: Vector2) -> Rect2:
    var gutter := label.x + SaUI.pxf(AXIS_GAP)
    var inset := label.y * 0.5
    return Rect2(gutter, inset, maxf(area.x - gutter, 0.0), maxf(area.y - 2.0 * inset, 0.0))


## Where a rate of *fps* stands in *plot* on a graph whose top is *ceiling*.
static func height_of(fps: float, ceiling: float, plot: Rect2) -> float:
    return plot.end.y - clampf(fps / ceiling, 0.0, 1.0) * plot.size.y


## The values written up the side of *plot*, top first, each as its text and the
## height it names: the top, half of it and the floor. The half is left out
## when *label_height* leaves it no room between the other two.
func axis_marks(plot: Rect2, label_height: float) -> Array:
    var ceiling := top()
    var fractions := [1.0, 0.5, 0.0] if plot.size.y * 0.5 >= label_height else [1.0, 0.0]
    var out := []
    for fraction: float in fractions:
        out.append([str(roundi(ceiling * fraction)), height_of(ceiling * fraction, ceiling, plot)])
    return out


## The line through the points spent moving, newest at the right of *plot*, as
## one polyline per run of them. A point spent at rest is left out, so the line
## stops where a rest begins rather than falling to the floor through it.
func lines(plot: Rect2) -> Array[PackedVector2Array]:
    var out: Array[PackedVector2Array] = []
    var step := slot_width(plot.size)
    var ceiling := top()
    var count := samples.size()
    var run := PackedVector2Array()
    for i in range(count):
        if idle[i]:
            if not run.is_empty():
                out.append(run)
                run = PackedVector2Array()
            continue
        var x := plot.end.x - float(count - 1 - i) * step
        run.append(Vector2(x, height_of(samples[i], ceiling, plot)))
    if not run.is_empty():
        out.append(run)
    return out


## The stretches spent at rest in *plot*, one rectangle per run of idle points,
## each point covering the two seconds up to it.
func idle_rects(plot: Rect2) -> Array[Rect2]:
    var out: Array[Rect2] = []
    var step := slot_width(plot.size)
    var count := idle.size()
    var run_from := -1
    for i in range(count + 1):
        var at_rest := i < count and idle[i]
        if at_rest and run_from < 0:
            run_from = i
        elif not at_rest and run_from >= 0:
            var left := maxf(plot.end.x - float(count - run_from) * step, plot.position.x)
            var right := plot.end.x - float(count - i) * step
            out.append(Rect2(left, plot.position.y, right - left, plot.size.y))
            run_from = -1
    return out


## Where the word goes in each band of *plot* wide and tall enough to carry a
## word of *word* size, centred.
func rest_labels(plot: Rect2, word: Vector2) -> Array[Rect2]:
    var out: Array[Rect2] = []
    var pad := SaUI.pxf(REST_WORD_PAD)
    for band in idle_rects(plot):
        if band.size.x >= word.x + 2.0 * pad and band.size.y >= word.y:
            out.append(Rect2(band.get_center() - word * 0.5, word))
    return out


func _draw() -> void:
    var font := get_theme_default_font()
    var font_size := get_theme_font_size(&"font_size")
    var ascent := font.get_ascent(font_size)
    var label_height := font.get_height(font_size)
    var widest := font.get_string_size(str(roundi(top())), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    var plot := plot_rect(size, Vector2(widest, label_height))
    var palette := SaTheme.palette

    # The floor as the solid line it was, and the top and the half faint, so
    # the line reads against the values without a grid over it.
    var faint := palette.border_secondary
    faint.a = 0.5
    var bands := idle_rects(plot)
    axis_drawn = PackedStringArray()
    for mark: Array in axis_marks(plot, label_height):
        var text: String = mark[0]
        var y: float = mark[1]
        if is_equal_approx(y, plot.end.y):
            draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), palette.border_secondary, SaUI.pxf(1.0))
        else:
            _draw_grid_line(plot, y, bands, faint)
        var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        var at := Vector2(plot.position.x - SaUI.pxf(AXIS_GAP) - width, y - label_height * 0.5 + ascent)
        draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, palette.text_muted)
        axis_drawn.append(text)

    var band := palette.text_muted
    band.a = 0.18
    for rect in bands:
        draw_rect(rect, band)
    var word := rest_word()
    var word_size := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    var words := rest_labels(plot, word_size)
    for spot in words:
        var baseline := Vector2(spot.position.x, spot.position.y + ascent)
        draw_string(font, baseline, word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, palette.text_muted)
    rest_words_drawn = words.size()

    for run in lines(plot):
        if run.size() >= 2:
            draw_polyline(run, palette.accent_stroke, SaUI.pxf(1.5), true)
        else:
            draw_circle(run[0], SaUI.pxf(1.5), palette.accent_stroke)


## A faint line across *plot* at *y*, broken where a band of *bands* stands,
## because a rest has no line to read against it and the half would cross the
## band's word.
func _draw_grid_line(plot: Rect2, y: float, bands: Array[Rect2], tint: Color) -> void:
    var from := plot.position.x
    for band in bands:
        if band.position.x > from:
            draw_line(Vector2(from, y), Vector2(band.position.x, y), tint, SaUI.pxf(1.0))
        from = maxf(from, band.end.x)
    if plot.end.x > from:
        draw_line(Vector2(from, y), Vector2(plot.end.x, y), tint, SaUI.pxf(1.0))


## The graph as numbers, for a dump: the points, which of them rested, the top
## the line is scaled to, the values and words the last draw wrote, and the
## number as it reads.
func report() -> Dictionary:
    return {
        "samples": Array(samples),
        "idle": idle.duplicate(),
        "top": top(),
        "axis": Array(axis_drawn),
        "rest_words": rest_words_drawn,
        "resting": resting,
        "fps_now": fps_now,
        "fps_text": fps_text(),
    }
