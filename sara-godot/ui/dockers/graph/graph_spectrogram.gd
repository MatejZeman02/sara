## The Graph docker's Spectrogram mode: the composite's power spectrum drawn as
## an image, and its radial average drawn as a curve beneath it, how much of the
## picture's energy sits at which scale.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **What it reads.** [SaPowerSpectrum], the reduction that transforms the
## composite's Oklab lightness on the GPU once the painter has stopped and hands
## back the half spectrum and its rings. This view registers it on the service
## while the view is shown, which is while the docker is open in this mode, and
## takes it off otherwise, so no other mode and no closed docker pays for a
## transform. The docker's own pass stays registered beside it and sets the
## per-frame pace, under which the reduction asks for its one run a stop.
##
## **The image.** The half spectrum mirrored to the whole through
## `X(u, v) = X*(-u, -v)`, `side + 1` texels a side, so that both edges at the
## highest frequency are drawn and the zero frequency is the centre texel. The
## frequency across runs with the picture's x and the one down with its y, as
## NumPy's `fftshift` lays a spectrum out, so a streak in the spectrum stands
## square to the strokes that made it. Each texel is the power on a log scale,
## the brightest white and [constant DECADES] below it the graphs' background
## grey, so a flat picture is one white texel on that grey.
##
## **The curve.** The radial average from ring 1, the coarsest scale the square
## holds, to ring `side / 2`, the finest, across on a log axis named in
## document pixels by [method SaPowerSpectrum.period_of], and up on the image's
## log scale against the highest ring. Ring 0 is the zero frequency, whose
## period is INF, and it is the image's centre texel rather than a point here.
##
## Drawn on the CPU from the floats the reduction already read back, once an
## answer, and so never while the painter paints.
class_name SaGraphSpectrogram
extends VBoxContainer

## The mode's id beside `SaGraphPlot.MODES`, which are the graphs of the
## binning kernel, and this is not one.
const MODE := "spectrogram"

## How many decades of power the image and the curve span below their
## brightest. The scenario's two paintings, broad masses and the same with fine
## hatching over them, put their median coefficient 8.4 and 7.9 decades under
## the zero frequency, so about half of each image is lit and the rest is the
## floor.
const DECADES := 8.0

## How tall the curve's panel is beside the image's, which takes the rest.
const CURVE_SHARE := 0.5

## The reduction this draws, registered while the view is shown.
var spectrum: SaPowerSpectrum = null

## The image last drawn, `side + 1` texels a side in floats, null before the
## first answer.
var image: Image = null

## The curve last drawn, ring 1 first, across and down in fractions of its
## panel, so 0 is the left and the top.
var curve: PackedVector2Array = PackedVector2Array()

## Where the scale axis is named: each as its place across, a fraction, and the
## period in document pixels there.
var ticks: Array[Vector2] = []

## How many answers this has drawn.
var drawn: int = 0

var _picture: TextureRect
var _curve_panel: CurvePanel
var _waiting: Label


## *clock* is the idle clock the transform waits for, the app's own `SaIdle`
## when null, which a suite hands its own.
func _init(clock: SaIdleClock = null) -> void:
    spectrum = SaPowerSpectrum.new(clock)
    name = "Spectrogram"
    visible = false
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_theme_constant_override("separation", SaUI.px(SaTheme.GAP_TIGHT))

    _waiting = Label.new()
    _waiting.name = "Waiting"
    _waiting.text = tr("The spectrum is worked out once you stop painting.")
    _waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _waiting.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(_waiting)

    _picture = TextureRect.new()
    _picture.name = "SpectrumImage"
    _picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_picture)

    _curve_panel = CurvePanel.new()
    _curve_panel.size_flags_stretch_ratio = CURVE_SHARE
    add_child(_curve_panel)

    spectrum.arrived.connect(_on_arrived)
    _show_waiting()


## Follows the view's own visibility, which the docker's mode and the docker's
## window both decide: shown, the reduction is registered, and hidden or out of
## the tree it is taken off and gives its textures back.
func _notification(what: int) -> void:
    if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED:
        _follow_shown(is_visible_in_tree())
    elif what == NOTIFICATION_EXIT_TREE:
        _follow_shown(false)


func _follow_shown(shown: bool) -> void:
    var service := SaReductionService.shared()
    if service == null:
        return
    if shown:
        service.add(spectrum)
    else:
        service.leave(spectrum)


## What the view holds and has drawn, for the docker's part of the state dump:
## where the curve peaks and where its energy sits, as a ring and as a scale in
## document pixels, so a scenario reads the shift a shot shows.
func report() -> Dictionary:
    var service := SaReductionService.shared()
    var peak := peak_ring(spectrum)
    var centre := energy_centroid(spectrum)
    return {
        "shown": visible,
        "registered": service != null and service.holds(spectrum),
        "waiting": _waiting.visible,
        "side": spectrum.side,
        "transforms": spectrum.transforms,
        "drawn": drawn,
        "peak_ring": peak,
        "peak_period": spectrum.period_of(peak),
        "centroid_ring": centre,
        "centroid_period": spectrum.period_of(roundi(centre)) if centre > 0.0 else INF,
        "decades_below_peak": [decades_below(spectrum, 0.5), decades_below(spectrum, 0.9), decades_below(spectrum, 0.99)],
    }


## How many decades under the brightest coefficient of *held* the one at
## *share* of the way up the sorted half sits, INF where that one is nothing.
## The three the report gives say how much of the image [constant DECADES]
## leaves on the floor.
static func decades_below(held: SaPowerSpectrum, share: float) -> float:
    if held.power.is_empty():
        return INF
    var sorted := held.power.duplicate()
    sorted.sort()
    var at := sorted[clampi(int(share * float(sorted.size() - 1)), 0, sorted.size() - 1)]
    var top := sorted[sorted.size() - 1]
    return log(top / at) / log(10.0) if at > 0.0 and top > 0.0 else INF


## The ring from 1 up whose mean power is highest, 0 before an answer.
static func peak_ring(held: SaPowerSpectrum) -> int:
    var best := 0
    for ring in range(1, held.radial.size()):
        if best == 0 or held.radial[ring] > held.radial[best]:
            best = ring
    return best


## The ring the energy outside the zero frequency centres on: each ring's mean
## power times its share of the square's texels, about `2 pi r`, weighting its
## radius. Low for a picture of broad masses and high for fine texture, and 0
## before an answer or for a flat picture.
static func energy_centroid(held: SaPowerSpectrum) -> float:
    var weighted := 0.0
    var total := 0.0
    for ring in range(1, held.radial.size()):
        var energy := held.radial[ring] * float(ring)
        weighted += energy * float(ring)
        total += energy
    return weighted / total if total > 0.0 else 0.0


## How bright *power* is drawn against *top*, from 0 at [constant DECADES]
## below it or at nothing to 1 at it.
static func level_of(power: float, top: float) -> float:
    if power <= 0.0 or top <= 0.0:
        return 0.0
    return clampf(1.0 + log(power / top) / log(10.0) / DECADES, 0.0, 1.0)


## The whole spectrum of *held* as a grey picture, `side + 1` texels a side
## with the zero frequency at the centre. Each coefficient of the half is worked
## once into a grey, and each row of the picture is two runs of the half's
## rows: its own row read forwards for the frequencies from zero, and the row
## of the opposite frequency read backwards for the ones below. A grey's three
## channels are equal, so a run of them reversed is still the run of greys.
static func image_of(held: SaPowerSpectrum) -> Image:
    var n := held.side
    var half := n >> 1
    var columns := SaPowerSpectrum.columns_for(n)
    var top := 0.0
    for power in held.power:
        top = maxf(top, power)
    var greys := PackedFloat32Array()
    greys.resize(held.power.size() * 3)
    for at in held.power.size():
        var grey := lerpf(SaGraphPlot.BACKGROUND, 1.0, level_of(held.power[at], top))
        greys[3 * at] = grey
        greys[3 * at + 1] = grey
        greys[3 * at + 2] = grey
    var texels := PackedFloat32Array()
    for y in n + 1:
        var v := y - half
        var mirrored := posmod(-v, n) * columns
        var row := greys.slice(3 * (mirrored + 1), 3 * (mirrored + half + 1))
        row.reverse()
        var own := posmod(v, n) * columns
        row.append_array(greys.slice(3 * own, 3 * (own + half + 1)))
        texels.append_array(row)
    return Image.create_from_data(n + 1, n + 1, false, Image.FORMAT_RGBF, texels.to_byte_array())


## The radial average of *held* as points across and down its panel, ring 1
## first, across by the logarithm of the ring and down by [method level_of]
## against the highest ring.
static func curve_of(held: SaPowerSpectrum) -> PackedVector2Array:
    var points := PackedVector2Array()
    var last := held.radial.size() - 1
    if last < 2:
        return points
    var top := 0.0
    for ring in range(1, last + 1):
        top = maxf(top, held.radial[ring])
    for ring in range(1, last + 1):
        points.append(Vector2(log(float(ring)) / log(float(last)), 1.0 - level_of(held.radial[ring], top)))
    return points


## Where the scale axis of *held* is named: the rings at each power of two,
## each as its place across and its period in document pixels.
static func ticks_of(held: SaPowerSpectrum) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var last := held.radial.size() - 1
    var ring := 1
    while last >= 2 and ring <= last:
        out.append(Vector2(log(float(ring)) / log(float(last)), held.period_of(ring)))
        ring *= 2
    return out


## Works the picture and the curve out at once, and hands the picture to the
## card at the message queue's flush rather than here. The answer comes inside
## the device's own call as it draws a frame, and an update of the texture sent
## from there never reached the screen: the second answer's curve was drawn and
## its picture was still the first one's. Sent at the flush, it is.
func _on_arrived() -> void:
    image = image_of(spectrum)
    curve = curve_of(spectrum)
    ticks = ticks_of(spectrum)
    drawn += 1
    _show_waiting()
    _curve_panel.curve = curve
    _curve_panel.ticks = ticks
    _curve_panel.queue_redraw()
    put_on_screen.call_deferred()


## Sends the picture last worked out to the texture the view shows. Public
## for the suite, whose cases have no frame to wait for the flush in.
func put_on_screen() -> void:
    if image == null:
        return
    var texture := _picture.texture as ImageTexture
    if texture != null and Vector2i(texture.get_size()) == image.get_size():
        texture.update(image)
    else:
        _picture.texture = ImageTexture.create_from_image(image)


## The words in place of the image and the curve until the first answer.
func _show_waiting() -> void:
    var waiting := image == null
    _waiting.visible = waiting
    _picture.visible = not waiting
    _curve_panel.visible = not waiting


## The panel the curve is drawn on, its scale written along its foot. It is
## told what to draw, as `SaGraphLabels` is: the view writes the two members
## and asks for the redraw.
class CurvePanel:
    extends Control

    ## How far the curve stays inside the panel's edges, in logical pixels.
    const INSET := 3.0

    ## The view's [member SaGraphSpectrogram.curve] and
    ## [member SaGraphSpectrogram.ticks], written by the view.
    var curve: PackedVector2Array = PackedVector2Array()
    var ticks: Array[Vector2] = []

    func _init() -> void:
        name = "SpectrumCurve"
        size_flags_vertical = Control.SIZE_EXPAND_FILL
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        resized.connect(queue_redraw)

    func _draw() -> void:
        var background := SaGraphPlot.BACKGROUND
        draw_rect(Rect2(Vector2.ZERO, size), Color(background, background, background))
        var font := get_theme_default_font()
        var font_size := maxi(8, int(round(float(SaUI.get_font_size()) * 0.6)))
        var foot := font.get_height(font_size) if font != null else 0.0
        var inset := SaUI.pxf(INSET)
        var area := Rect2(Vector2(inset, inset), size - Vector2(2.0 * inset, 2.0 * inset + foot))
        if area.size.x <= 0.0 or area.size.y <= 0.0:
            return
        var points := PackedVector2Array()
        for point: Vector2 in curve:
            points.append(area.position + point * area.size)
        if points.size() >= 2:
            draw_polyline(points, SaTheme.palette.text_primary, SaUI.pxf(1.5), true)
        if font != null:
            _draw_ticks(font, font_size, area)

    ## The periods along the foot, each under its place, the first carrying
    ## the unit, and a label that would run into the one before it left out.
    func _draw_ticks(font: Font, font_size: int, area: Rect2) -> void:
        var tint := SaTheme.palette.text_muted
        var baseline := size.y - font.get_descent(font_size)
        var clear_from := -INF
        for index in ticks.size():
            var tick := ticks[index]
            var number := "%.0f" % tick.y if tick.y >= 10.0 else "%.1f" % tick.y
            var text := tr("%s px") % number if index == 0 else number
            var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
            var x := area.position.x + tick.x * area.size.x
            draw_line(Vector2(x, area.end.y), Vector2(x, area.end.y - SaUI.pxf(INSET)), tint)
            var left := clampf(x - wide * 0.5, 0.0, size.x - wide)
            if left < clear_from:
                continue
            draw_string(font, Vector2(left, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
            clear_from = left + wide + SaUI.pxf(6.0)
