## The Stats docker's value groups: how many distinct values the picture is
## built of, and each one's share of the canvas and middle value.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **How many distinct value clusters the picture has**, from the histogram's
## peaks, and their share of the canvas. The histogram is
## of Oklab L in `BINS` steps, counted by `value_groups.gmacs` beside it
## over the composite's painted chunks through the reduction service, and its
## bins are the one thing read back. Everything after them is arithmetic on
## sixty-four numbers here.
##
## **How two peaks are told apart**, which the row's tooltip says in a
## sentence. The histogram is smoothed over five bins, every peak of it starts
## a group, and two neighbouring groups are cut at the lowest bin between their
## peaks. They stay two while the histogram there is below `SEPARATION` of the
## lower peak, and are joined otherwise, the least separated pair first. A
## group holding less than `LEAST_SHARE` of the canvas joins the neighbour it
## is least apart from, and past `MOST` groups the least separated pair is
## joined again, so a busy picture still reads as a handful. Every bin belongs
## to one group, so the shares add up to the canvas.
##
## **The canvas nobody painted counts as the background it shows.** A texel
## weighs its alpha, so the kernel counts what paint covers, and the rest of
## the canvas is the remainder of its texel count, added here at the value of
## the checkerboard a transparent document shows, with no dispatch over it. A
## document laid on a colour or a ground holds every chunk, so its remainder is
## nothing and its background is counted where the kernel read it.
extends SaStatsNumber

const SHADER := "value_groups"
const KERNEL := "value_histogram"

## The histogram's steps of Oklab L, and what a fully covered texel adds to its
## bin. Both must match `value_groups.gmacs`.
const BINS := 64
const WHOLE := 255

## The smoothing every peak is found on, a triangle five bins wide, and how
## far it reaches either side of its middle.
const SMOOTHING: Array[float] = [1.0, 2.0, 3.0, 2.0, 1.0]
const REACH := 2

## Two groups stay apart while the histogram between them is below this share
## of the lower peak.
const SEPARATION := 0.5

## A group holding less of the canvas than this joins a neighbour.
const LEAST_SHARE := 0.01

## The most groups the docker names, and so the rows it declares.
const MOST := 8

## What the canvas shows where nothing covers it.
const CHECKERBOARD := preload("res://shaders/canvas/checkerboard.gdshader")

## What the rows say on hover: how two peaks are told apart.
const HOVER := (
    "Groups are the peaks of a histogram of Oklab lightness in 64 steps, smoothed over five."
    + " Two peaks are two groups while the histogram between them falls below half the lower peak."
    + " A group under one per cent of the canvas joins its neighbour, and at most eight are named."
    + " Canvas nothing covers counts as the background it shows."
)


## One group of values: its share of the canvas, its middle value, and the
## bins it spans with the height of its smoothed peak, which joining reads.
class Group:
    extends RefCounted

    var share: float = 0.0
    var value: float = 0.0
    var first_bin: int = 0
    var last_bin: int = 0
    var peak: float = 0.0

    func _init(first: int, last: int, height: float) -> void:
        first_bin = first
        last_bin = last
        peak = height

    ## Its share and middle value out of *weights* and *sums*, over a canvas
    ## of *whole* texels.
    func measure(weights: PackedFloat64Array, sums: PackedFloat64Array, whole: float) -> void:
        var weight := 0.0
        var sum := 0.0
        for at in range(first_bin, last_bin + 1):
            weight += weights[at]
            sum += sums[at]
        share = weight / whole if whole > 0.0 else 0.0
        value = sum / weight if weight > 0.0 else (first_bin + last_bin + 1) * 0.5 / BINS


## The groups the last run found, darkest first.
var groups: Array[Group] = []

## The page the rows are on, whose rules show as many group rows as there are
## groups.
var _page: SaPage = null
var _count: SaPageRow = null
var _rows: Array[SaPageRow] = []


func _init() -> void:
    reduction = SaReductionService.OverDocument.new(SHADER, KERNEL, BINS, push_for)


## A section of its own: how many groups, then one row a group, darkest first,
## each titled by its middle value and saying its share. A group row is on the
## page only while there is a group for it.
func declare(page: SaPage) -> void:
    _page = page
    var hover := tr(HOVER)
    var block := page.section("Value groups")
    _count = block.custom("Groups", readout(hover)).named(&"value_groups").node("ValueGroupCount")
    _count.value = 0
    _rows.clear()
    for at in MOST:
        var row := block.custom("Value", readout(hover)).named(StringName("value_group_%d" % (at + 1)))
        row.value = ""
        _count.hides(row, range(at + 1, MOST + 1))
        _rows.append(row)


## Reads *document*'s groups out of the reduction's total and writes them into
## the rows.
func _fold(document: SaDocument) -> void:
    groups = groups_of(document)
    _show()


## The groups of *document*'s picture as the reduction's total holds them.
func groups_of(document: SaDocument) -> Array[Group]:
    var numbers := reduction as SaReductionService.OverDocument
    var canvas := document.canvas_size
    return find(numbers.total, canvas.x * canvas.y, background_lightness())


## The groups *bins* make on a canvas of *texels* texels. A bin holds the paint
## at its value in `WHOLE`ths of a texel, and what the paint leaves of the
## canvas counts at the lightness *background*.
static func find(bins: PackedInt64Array, texels: int, background: float) -> Array[Group]:
    var weights := PackedFloat64Array()
    var sums := PackedFloat64Array()
    weights.resize(BINS)
    sums.resize(BINS)
    var painted := 0.0
    for at in BINS:
        var weight := float(bins[at]) / WHOLE if at < bins.size() else 0.0
        weights[at] = weight
        sums[at] = weight * (at + 0.5) / BINS
        painted += weight
    var rest := maxf(float(texels) - painted, 0.0)
    if rest > 0.0:
        var at := clampi(floori(background * BINS), 0, BINS - 1)
        weights[at] += rest
        sums[at] += rest * background
    var whole := painted + rest
    var found: Array[Group] = []
    if whole <= 0.0:
        return found
    var smooth := _smoothed(weights)
    found = _peaks(smooth)
    for group: Group in found:
        group.measure(weights, sums, whole)
    _join(found, smooth, weights, sums, whole)
    return found


## The lightness the canvas shows where nothing covers it: the checkerboard of a
## transparent document, as the mean of its two squares' Oklab L. A checker of
## two greys reads as one ground and not as two groups.
static func background_lightness() -> float:
    var sum := 0.0
    for square: StringName in [&"color_1", &"color_2"]:
        var held: Variant = RenderingServer.shader_get_parameter_default(CHECKERBOARD.get_rid(), square)
        var shown := SaDocument.BACKGROUND_GREY
        if held is Color:
            shown = held
        elif held is Vector4:
            shown = Color(held.x, held.y, held.z)
        var linear := shown.srgb_to_linear()
        sum += SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b)).x
    return sum * 0.5


## The push constant `value_groups.gmacs` reads for *rect* of the composite,
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
        ]
    )
    params.append_array(space.transfer.to_params())
    for column: Vector3 in SaColorSpace.basis_columns(space.to_linear_srgb_matrix()):
        params.append_array(PackedFloat32Array([column.x, column.y, column.z]))
    return params


## *weights* smoothed by `SMOOTHING`, the bins past either end counting nothing.
static func _smoothed(weights: PackedFloat64Array) -> PackedFloat64Array:
    var out := PackedFloat64Array()
    out.resize(BINS)
    for at in BINS:
        var sum := 0.0
        for tap in SMOOTHING.size():
            var from := at + tap - REACH
            if from >= 0 and from < BINS:
                sum += weights[from] * SMOOTHING[tap]
        out[at] = sum
    return out


## A group for every peak of *smooth*, a run of equal bins higher than the bin
## on either side counting as one, cut from the next at the lowest bin between
## them.
static func _peaks(smooth: PackedFloat64Array) -> Array[Group]:
    var tops: Array[int] = []
    var at := 0
    while at < BINS:
        var end := at
        while end + 1 < BINS and smooth[end + 1] == smooth[at]:
            end += 1
        var rises := at == 0 or smooth[at - 1] < smooth[at]
        var falls := end == BINS - 1 or smooth[end + 1] < smooth[at]
        if smooth[at] > 0.0 and rises and falls:
            tops.append((at + end) >> 1)
        at = end + 1
    var found: Array[Group] = []
    var first := 0
    for index in tops.size():
        var last := BINS - 1
        if index + 1 < tops.size():
            last = _lowest(smooth, tops[index], tops[index + 1])
        found.append(Group.new(first, last, smooth[tops[index]]))
        first = last + 1
    return found


## The first of the lowest bins of *smooth* after *after* and before *before*.
static func _lowest(smooth: PackedFloat64Array, after: int, before: int) -> int:
    var lowest := after
    for at in range(after + 1, before):
        if lowest == after or smooth[at] < smooth[lowest]:
            lowest = at
    return lowest


## Joins neighbouring groups of *found* until every pair left stands apart, no
## group is under `LEAST_SHARE` and there are `MOST` or fewer.
static func _join(
    found: Array[Group], smooth: PackedFloat64Array, weights: PackedFloat64Array, sums: PackedFloat64Array, whole: float
) -> void:
    while found.size() > 1:
        var closest := 0
        var closeness := -1.0
        for cut in found.size() - 1:
            var left := found[cut]
            var right := found[cut + 1]
            var near := smooth[left.last_bin] / minf(left.peak, right.peak)
            # A group too small to name joins a neighbour whatever lies between.
            if left.share < LEAST_SHARE or right.share < LEAST_SHARE:
                near += 1.0
            if near > closeness:
                closest = cut
                closeness = near
        if closeness < SEPARATION and found.size() <= MOST:
            return
        var kept := found[closest]
        var gone := found[closest + 1]
        kept.last_bin = gone.last_bin
        kept.peak = maxf(kept.peak, gone.peak)
        kept.measure(weights, sums, whole)
        found.remove_at(closest + 1)


## The count, and each group's middle value as its row's title and its share as
## the row's words.
func _show() -> void:
    _count.value = groups.size()
    _write(_count, str(groups.size()))
    for at in MOST:
        var row := _rows[at]
        if at >= groups.size():
            row.value = ""
            continue
        var group := groups[at]
        var share := "%d %%" % roundi(group.share * 100.0)
        row.value = share
        row.retitle(TranslationServer.translate("Value %s") % ("%.2f" % group.value), "")
        _write(row, share)
    if _page != null:
        _page.apply_rules()


static func _write(row: SaPageRow, words: String) -> void:
    var shown := row.control as Label
    if shown != null and is_instance_valid(shown):
        shown.text = words
