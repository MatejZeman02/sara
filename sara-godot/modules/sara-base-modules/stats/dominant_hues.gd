## The Stats docker's dominant hues: how many, each one's angle on the wheel and
## share of the canvas, the widest gap between two neighbours and the arc they
## spread over.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **The dominant hues**, how many, how far apart on the wheel, and the share
## of each, because three hues at 120 degrees and two at 30 are different
## paintings. The histogram is of Oklab hue in `BINS` steps round the
## wheel, counted by `dominant_hues.gmacs` beside it over the composite's
## painted chunks through the reduction service, and its bins are the one thing
## read back. Everything after them is arithmetic on a hundred and forty-four
## numbers here.
##
## **A grey adds no hue.** The kernel counts a texel only when its Oklab chroma
## reaches `CHROMA_FLOOR`, and then by its coverage and not its chroma, so a
## share is a share of the canvas and not of the colour in it. 0.03 is about
## where a
## grey mixed with a little colour starts to read as that colour on screen,
## well under the 0.1 and more of an earth or a skin and far over what a neutral
## grey drifts by in a 16 bit float. The row's tooltip says it.
##
## **How hues are told apart**, the same rule the value groups follow but round
## a circle. The histogram is smoothed over five bins, wrapping, every peak of
## it starts a hue, and two neighbours are cut at the lowest bin between their
## peaks, so a peak that straddles 0 and 360 degrees is one peak like any other
## and counts once. Two neighbours stay apart while the histogram between them
## is below `SEPARATION` of the lower peak and are joined otherwise, and past
## `MOST` hues the least separated pair is joined again. A hue holding less
## than `LEAST_SHARE` of the coloured paint is left unnamed rather than joined,
## because averaging a speck of red into a blue across the wheel would move the
## blue's angle towards a colour nobody painted it with.
##
## **An angle to a fiftieth of a degree.** Each bin carries where in it its
## paint's hue falls, so a hue's angle is the circular mean of what was painted
## and does not snap to a bin's middle five degrees wide.
##
## **The canvas nobody painted adds no hue.** What paint leaves uncovered shows
## the checkerboard of two greys, which has no hue, so it counts in the canvas
## the shares are of, by the canvas's size, and in no bin, with no dispatch over
## it. A document laid on a colour holds every chunk, and its ground is read
## where the kernel reads the rest.
extends SaStatsNumber

const SHADER := "dominant_hues"
const KERNEL := "hue_histogram"

## The histogram's steps round the wheel, what a fully covered texel adds to its
## bin, and the steps of a bin its hue's place is counted in. All three must
## match `dominant_hues.gmacs`.
const BINS := 72
const WHOLE := 255
const STEPS := 255

## Two cells a bin: the weight, and the weight times the place in the bin.
const CELLS := BINS * 2

## How wide one bin is, in degrees.
const WIDTH := 360.0 / BINS

## The Oklab chroma under which paint is grey and adds no hue.
const CHROMA_FLOOR := 0.03

## The smoothing every peak is found on, a triangle five bins wide, and how far
## it reaches either side of its middle.
const SMOOTHING: Array[float] = [1.0, 2.0, 3.0, 2.0, 1.0]
const REACH := 2

## Two hues stay apart while the histogram between them is below this share of
## the lower peak.
const SEPARATION := 0.5

## A hue holding less of the coloured paint than this is not named.
const LEAST_SHARE := 0.01

## The most hues the docker names, and so the rows it declares.
const MOST := 6

## What the rows say on hover: how hues are found and the chroma floor.
const HOVER := (
    "Hues are the peaks of a histogram of Oklab hue in 72 steps of five degrees round the wheel, smoothed over five."
    + " Paint under Oklab chroma 0.03 is grey and adds no hue."
    + " Two peaks are two hues while the histogram between them falls below half the lower peak."
    + " A hue under one per cent of the coloured paint is not named, and at most six are."
    + " Shares are of the whole canvas, and the spread is the arc that holds every hue, the wheel less the widest gap."
)


## One hue: its angle and share, the bins it spans round the wheel from
## [member first_bin], and the height of its smoothed peak, which joining reads.
class Hue:
    extends RefCounted

    ## In degrees, from 0 up to 360.
    var angle: float = 0.0
    ## Of the whole canvas, from 0 to 1.
    var share: float = 0.0
    var first_bin: int = 0
    var span: int = 1
    var peak: float = 0.0
    ## The weight of its paint, in texels.
    var weight: float = 0.0

    func _init(first: int, bins: int, height: float) -> void:
        first_bin = first
        span = bins
        peak = height

    ## The last bin it spans, round the wheel.
    func last_bin() -> int:
        return (first_bin + span - 1) % BINS

    ## Its weight, share and angle out of *weights* and *places*, each bin's
    ## mean hue in degrees, over a canvas of *whole* texels. The angle is the
    ## circular mean about its heaviest bin, so a hue across 0 degrees reads as
    ## one angle and not as 180.
    func measure(weights: PackedFloat64Array, places: PackedFloat64Array, whole: float) -> void:
        var heaviest := first_bin
        for step in span:
            var at := (first_bin + step) % BINS
            if weights[at] > weights[heaviest]:
                heaviest = at
        weight = 0.0
        var turned := 0.0
        var origin := places[heaviest]
        for step in span:
            var at := (first_bin + step) % BINS
            weight += weights[at]
            turned += weights[at] * wrapf(places[at] - origin, -180.0, 180.0)
        share = weight / whole if whole > 0.0 else 0.0
        angle = fposmod(origin + (turned / weight if weight > 0.0 else 0.0), 360.0)


## The hues the last run found, the largest share first.
var hues: Array[Hue] = []

## The widest gap between two neighbouring hues in degrees, and the arc that
## holds them all, the wheel less that gap, both 0 with fewer than two. Two hues
## 30 degrees apart leave a gap of 330 and spread over 30, and three 120 apart
## leave 120 and spread over 240.
var widest_gap: float = 0.0
var spread: float = 0.0

## The page the rows are on, whose rules show as many hue rows as there are
## hues.
var _page: SaPage = null
var _count: SaPageRow = null
var _rows: Array[SaPageRow] = []
var _gap: SaPageRow = null
var _spread: SaPageRow = null


func _init() -> void:
    reduction = SaReductionService.OverDocument.new(SHADER, KERNEL, CELLS, push_for)


## A section of its own: how many hues, one row a hue, the largest first, each
## titled by its angle and saying its share, then the widest gap and the
## spread. A hue row is on the page only while there is a hue for it, and the
## last two only while there are two.
func declare(page: SaPage) -> void:
    _page = page
    var hover := tr(HOVER)
    var block := page.section("Dominant hues")
    _count = block.custom("Hues", readout(hover)).named(&"hues").node("HueCount")
    _count.value = 0
    _rows.clear()
    for at in MOST:
        var row := block.custom("Hue", readout(hover)).named(StringName("hue_%d" % (at + 1)))
        row.value = ""
        _count.hides(row, range(at + 1, MOST + 1))
        _rows.append(row)
    _gap = block.custom("Widest gap", readout(hover)).named(&"hue_gap").node("HueGap")
    _gap.value = ""
    _count.hides(_gap, range(2, MOST + 1))
    _spread = block.custom("Spread", readout(hover)).named(&"hue_spread").node("HueSpread")
    _spread.value = ""
    _count.hides(_spread, range(2, MOST + 1))


## Reads *document*'s hues out of the reduction's total and writes them into
## the rows.
func _fold(document: SaDocument) -> void:
    hues = hues_of(document)
    widest_gap = gap_of(hues)
    spread = 360.0 - widest_gap if hues.size() >= 2 else 0.0
    _show()


## The hues of *document*'s picture as the reduction's total holds them.
func hues_of(document: SaDocument) -> Array[Hue]:
    var numbers := reduction as SaReductionService.OverDocument
    var canvas := document.canvas_size
    return find(numbers.total, canvas.x * canvas.y)


## The hues *cells* make on a canvas of *texels* texels, the largest share
## first. A bin's first cell holds the paint of its hue in `WHOLE`ths of a
## texel and its second that times the hue's place in the bin in `STEPS`ths.
static func find(cells: PackedInt64Array, texels: int) -> Array[Hue]:
    var weights := PackedFloat64Array()
    var places := PackedFloat64Array()
    weights.resize(BINS)
    places.resize(BINS)
    var coloured := 0.0
    for at in BINS:
        var weight := float(cells[at * 2]) if at * 2 < cells.size() else 0.0
        var placed := float(cells[at * 2 + 1]) if at * 2 + 1 < cells.size() else 0.0
        weights[at] = weight / WHOLE
        var within := placed / weight / STEPS if weight > 0.0 else 0.5
        places[at] = (at + within) * WIDTH
        coloured += weights[at]
    var found: Array[Hue] = []
    var whole := maxf(float(texels), coloured)
    if coloured <= 0.0 or whole <= 0.0:
        return found
    var smooth := _smoothed(weights)
    found = _peaks(smooth)
    for hue: Hue in found:
        hue.measure(weights, places, whole)
    var least := LEAST_SHARE * coloured
    _join(found, smooth, weights, places, whole, least)
    var named := _named(found, least)
    named.sort_custom(func(one: Hue, other: Hue) -> bool: return one.share > other.share)
    return named


## The hues of *found* holding *least* texels of paint or more.
static func _named(found: Array[Hue], least: float) -> Array[Hue]:
    var named: Array[Hue] = []
    for hue: Hue in found:
        if hue.weight >= least:
            named.append(hue)
    return named


## The widest gap between two neighbouring angles of *found* round the wheel,
## in degrees, 0 with fewer than two.
static func gap_of(found: Array[Hue]) -> float:
    if found.size() < 2:
        return 0.0
    var angles: Array[float] = []
    for hue: Hue in found:
        angles.append(hue.angle)
    angles.sort()
    var widest := angles[0] + 360.0 - angles[angles.size() - 1]
    for at in range(1, angles.size()):
        widest = maxf(widest, angles[at] - angles[at - 1])
    return widest


## The push constant `dominant_hues.gmacs` reads for *rect* of the composite,
## the chunk's share of the canvas, adding into *slot*. Static, so the
## reduction holds no callable that holds the part.
static func push_for(rect: Rect2i, slot: int, document: SaDocument) -> PackedFloat32Array:
    var space := document.color_space
    var params := PackedFloat32Array(
        [
            float(rect.position.x),
            float(rect.position.y),
            float(rect.end.x),
            float(rect.end.y),
            float(slot),
            float(space.coordinates),
            CHROMA_FLOOR,
        ]
    )
    params.append_array(space.transfer.to_params())
    for column: Vector3 in SaColorSpace.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    return params


## *weights* smoothed by `SMOOTHING` round the wheel, the bins past 360 degrees
## being the ones after 0.
static func _smoothed(weights: PackedFloat64Array) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(BINS)
    for at in BINS:
        var sum := 0.0
        for tap in SMOOTHING.size():
            sum += weights[posmod(at + tap - REACH, BINS)] * SMOOTHING[tap]
        out[at] = sum
    return out


## A hue for every peak of *smooth* round the wheel, a run of equal bins higher
## than the bin on either side counting as one, cut from the next at the lowest
## bin between them. The walk starts at a lowest bin of all, so no peak is cut
## in two where the walk begins and ends, and a peak across 0 degrees is one.
static func _peaks(smooth: PackedFloat64Array) -> Array[Hue]:
    var start := 0
    for at in BINS:
        if smooth[at] < smooth[start]:
            start = at
    var tops: Array[int] = []
    var step := 1
    while step < BINS:
        var end := step
        while end + 1 < BINS and _at(smooth, start, end + 1) == _at(smooth, start, step):
            end += 1
        var height := _at(smooth, start, step)
        var rises := _at(smooth, start, step - 1) < height
        var falls := _at(smooth, start, (end + 1) % BINS) < height
        if height > 0.0 and rises and falls:
            tops.append((step + end) >> 1)
        step = end + 1
    var found: Array[Hue] = []
    if tops.is_empty():
        # Even all round, as paint of every hue in equal parts would be: one
        # hue of all of it, whose angle means little and is shown as found.
        if smooth[start] > 0.0:
            found.append(Hue.new(start, BINS, smooth[start]))
        return found
    var first := 0
    for index in tops.size():
        var last := BINS - 1
        if index + 1 < tops.size():
            last = _lowest(smooth, start, tops[index], tops[index + 1])
        found.append(Hue.new((start + first) % BINS, last - first + 1, _at(smooth, start, tops[index])))
        first = last + 1
    return found


## The smoothed bin *step* bins round the wheel from *start*.
static func _at(smooth: PackedFloat64Array, start: int, step: int) -> float:
    return smooth[(start + step) % BINS]


## The first of the lowest bins of *smooth* after *after* and before *before*,
## both counted from *start*.
static func _lowest(smooth: PackedFloat64Array, start: int, after: int, before: int) -> int:
    var lowest := after
    for step in range(after + 1, before):
        if lowest == after or _at(smooth, start, step) < _at(smooth, start, lowest):
            lowest = step
    return lowest


## Joins neighbouring hues of *found* round the wheel until every pair left
## stands apart and `MOST` or fewer hold *least* texels of paint. A pair's
## nearness is the lower of the two bins either side of their cut against the
## lower peak, and of two as near, the pair closer on the wheel is joined first.
## Two hues meet at two cuts, one each way round, and the higher one joins them.
static func _join(
    found: Array[Hue],
    smooth: PackedFloat64Array,
    weights: PackedFloat64Array,
    places: PackedFloat64Array,
    whole: float,
    least: float,
) -> void:
    while found.size() > 1:
        var closest := 0
        var closeness := -1.0
        var apart := 360.0
        for cut in found.size():
            var left := found[cut]
            var right := found[(cut + 1) % found.size()]
            var valley := minf(smooth[left.last_bin()], smooth[right.first_bin])
            var near := valley / minf(left.peak, right.peak)
            var distance := fposmod(right.angle - left.angle, 360.0)
            if near > closeness or (near == closeness and distance < apart):
                closest = cut
                closeness = near
                apart = distance
        if closeness < SEPARATION and _named(found, least).size() <= MOST:
            return
        var kept := found[closest]
        var gone := found[(closest + 1) % found.size()]
        kept.span += gone.span
        kept.peak = maxf(kept.peak, gone.peak)
        kept.measure(weights, places, whole)
        found.erase(gone)


## The count, each hue's angle as its row's title and its share as the row's
## words, the widest gap and the spread.
func _show() -> void:
    _count.value = hues.size()
    _write(_count, str(hues.size()))
    for at in MOST:
        var row := _rows[at]
        if at >= hues.size():
            row.value = ""
            continue
        var hue := hues[at]
        var share := "%d %%" % roundi(hue.share * 100.0)
        row.value = share
        row.retitle(
            TranslationServer.translate_plural("Hue %d°", "Hue %d°", roundi(hue.angle) % 360) % (roundi(hue.angle) % 360), ""
        )
        _write(row, share)
    var two := hues.size() >= 2
    _gap.value = "%d°" % roundi(widest_gap) if two else ""
    _write(_gap, String(_gap.value))
    _spread.value = "%d°" % roundi(spread) if two else ""
    _write(_spread, String(_spread.value))
    if _page != null:
        _page.apply_rules()


static func _write(row: SaPageRow, words: String) -> void:
    var shown := row.control as Label
    if shown != null and is_instance_valid(shown):
        shown.text = words
