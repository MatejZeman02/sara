## The Stats docker's saturation by value: how saturated the paint is in the
## shadows, the midtones and the lights, and which of them holds the most.
##
## SPDX-License-Identifier: GPL-3.0-or-later
##
## **Where the saturated pixels are in value**, because a picture whose
## saturation sits in the midtones reads differently from one whose saturation
## sits in the shadows. Oklab chroma is tallied by Oklab L in
## `BINS` steps by `saturation_by_value.gmacs` beside it, over the
## composite's painted chunks through the reduction service, and the tally is
## the one thing read back. Everything after it is arithmetic on forty numbers
## here.
##
## **Three bands**, shadows below L 0.35, midtones to 0.65 and lights above,
## which `BANDS` names and the tooltip says. Three because a painter speaks of
## those three and the question the number answers is which of them holds the
## colour, and
## the edges sit on steps of the tally, so a fourth band moves no kernel. Each
## band shows its mean Oklab chroma, how saturated its paint is, and its share
## of the canvas, so a band of a few dark strokes is not read as a dark picture.
## A row above them names the band whose paint is the most saturated, or none
## when no band reaches `CHROMA_FLOOR`, which is about the least chroma an eye
## tells from grey.
##
## **The canvas nobody painted counts as the background it shows.** A texel
## weighs its alpha, so the kernel counts what paint covers, and the rest of the
## canvas is the remainder of its texel count, added here at the lightness and
## chroma of the checkerboard a transparent document shows, with no dispatch
## over it. A document laid on a colour or a ground holds every chunk, so its
## remainder is nothing and its background is counted where the kernel read it.
extends SaStatsNumber

const SHADER := "saturation_by_value"
const KERNEL := "chroma_by_lightness"

## The tally's steps of Oklab L, two cells each, and the steps of alpha and of
## chroma times alpha a texel adds in. All must match `saturation_by_value.gmacs`.
const BINS := 20
const CELLS := BINS * 2
const WHOLE := 255
const CHROMA_WHOLE := 65535

## The bands, darkest first: the key of the row, its title, the lightness its
## paint is below, the last reaching past white, and the sentence that names it
## the most saturated, whole so that a translation is of a sentence.
const BANDS: Array[Dictionary] = [
    {
        "key": &"saturation_shadows",
        "title": "Shadows",
        "below": 0.35,
        "most": "The most saturated paint is in the shadows.",
    },
    {
        "key": &"saturation_midtones",
        "title": "Midtones",
        "below": 0.65,
        "most": "The most saturated paint is in the midtones.",
    },
    {
        "key": &"saturation_lights",
        "title": "Lights",
        "below": INF,
        "most": "The most saturated paint is in the lights.",
    },
]

## The least mean chroma a band needs for the last row to name it.
const CHROMA_FLOOR := 0.02

## What the canvas shows where nothing covers it.
const CHECKERBOARD := preload("res://shaders/canvas/checkerboard.gdshader")

## What the rows say on hover: what is measured and where the bands are cut.
const HOVER := (
    "How saturated the paint is at each value: the mean Oklab chroma of shadows below lightness 0.35,"
    + " midtones up to 0.65 and lights above, and the share of the canvas each covers."
    + " Canvas nothing covers counts as the background it shows."
)

## What the last row says when no band's paint reaches `CHROMA_FLOOR`.
const NOWHERE := "None"

## The sentence under a band's title before the first run, in place of its share.
const UNSHARED := "Its share of the canvas"


## One band of value: its share of the canvas and how saturated it is.
class Band:
    extends RefCounted

    ## The band's place in `BANDS`.
    var index: int = 0
    ## What of the canvas sits at this value, from 0 to 1.
    var share: float = 0.0
    ## The mean Oklab chroma of what sits at this value, 0 for a band that
    ## holds nothing.
    var chroma: float = 0.0

    func _init(at: int, held_share: float, mean_chroma: float) -> void:
        index = at
        share = held_share
        chroma = mean_chroma


## The bands the last run found, darkest first, empty before the first.
var bands: Array[Band] = []

## The band whose paint is the most saturated, or -1 for none.
var most: int = -1

var _rows: Array[SaPageRow] = []
var _most_row: SaPageRow = null


func _init() -> void:
    reduction = SaReductionService.OverDocument.new(SHADER, KERNEL, CELLS, push_for)


## A section of its own: the row naming the band whose paint is the most
## saturated, the answer first, then a row a band, darkest first, each saying
## how saturated its paint is, with how much of the canvas it covers under its
## title.
func declare(page: SaPage) -> void:
    var hover := tr(HOVER)
    var block := page.section("Saturation by value")
    # No title, so the sentence spans the docker: in the right of a titled row
    # a band's name was cut off at the docker's shipped width.
    var said := readout(hover)
    said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _most_row = block.custom("", said).named(&"saturation_sits")
    _most_row.value = NOWHERE
    _rows.clear()
    for band: Dictionary in BANDS:
        var row := block.custom(band["title"], readout(hover)).named(band["key"])
        # A sentence from the start, because the row builds the label under its
        # title only for one it was declared with.
        row.explain(UNSHARED)
        row.value = 0.0
        _rows.append(row)


## Reads *document*'s bands out of the reduction's total and writes them into
## the rows.
func _fold(document: SaDocument) -> void:
    bands = bands_of(document)
    most = most_saturated(bands)
    _show()


## The bands of *document*'s picture as the reduction's total holds them.
func bands_of(document: SaDocument) -> Array[Band]:
    var numbers := reduction as SaReductionService.OverDocument
    var canvas := document.canvas_size
    return find(numbers.total, canvas.x * canvas.y, background_shown())


## The bands *cells* make on a canvas of *texels* texels, darkest first. A step
## holds the paint at its lightness in `WHOLE`ths of a texel and its chroma
## times alpha in `CHROMA_WHOLE`ths, and what the paint leaves of the canvas
## counts at *background*, a lightness and a chroma.
static func find(cells: PackedInt64Array, texels: int, background: Vector2) -> Array[Band]:
    var weights := PackedFloat64Array()
    var chromas := PackedFloat64Array()
    weights.resize(BANDS.size())
    chromas.resize(BANDS.size())
    var painted := 0.0
    for at in BINS:
        var band := band_of((at + 0.5) / BINS)
        var weight := float(cells[2 * at]) / WHOLE if 2 * at < cells.size() else 0.0
        var chroma := float(cells[2 * at + 1]) / CHROMA_WHOLE if 2 * at + 1 < cells.size() else 0.0
        weights[band] += weight
        chromas[band] += chroma
        painted += weight
    var rest := maxf(float(texels) - painted, 0.0)
    if rest > 0.0:
        var band := band_of(background.x)
        weights[band] += rest
        chromas[band] += rest * background.y
    var whole := painted + rest
    var found: Array[Band] = []
    for band in BANDS.size():
        var share := weights[band] / whole if whole > 0.0 else 0.0
        var mean := chromas[band] / weights[band] if weights[band] > 0.0 else 0.0
        found.append(Band.new(band, share, mean))
    return found


## The band a lightness *lightness* falls in, a lightness below black in the
## first and one past white in the last.
static func band_of(lightness: float) -> int:
    for band in BANDS.size():
        if lightness < float(BANDS[band]["below"]):
            return band
    return BANDS.size() - 1


## The band of *found* whose paint is the most saturated, or -1 when none
## reaches `CHROMA_FLOOR`. The darker of two equal ones.
static func most_saturated(found: Array[Band]) -> int:
    var best := -1
    for band: Band in found:
        if band.chroma >= CHROMA_FLOOR and (best < 0 or band.chroma > found[best].chroma):
            best = band.index
    return best


## What the canvas shows where nothing covers it, the checkerboard of a
## transparent document, as the mean of its two squares in Oklab: x the
## lightness and y the chroma.
static func background_shown() -> Vector2:
    var sum := Vector3.ZERO
    for square: StringName in [&"color_1", &"color_2"]:
        var held: Variant = RenderingServer.shader_get_parameter_default(CHECKERBOARD.get_rid(), square)
        var shown := SaDocument.BACKGROUND_GREY
        if held is Color:
            shown = held
        elif held is Vector4:
            shown = Color(held.x, held.y, held.z)
        var linear := shown.srgb_to_linear()
        sum += SaOklab.from_linear_srgb(Vector3(linear.r, linear.g, linear.b))
    var mean := sum * 0.5
    return Vector2(mean.x, Vector2(mean.y, mean.z).length())


## The push constant `saturation_by_value.gmacs` reads for *rect* of the
## composite, the chunk's share of the canvas, adding into *slot*. Static, so
## the reduction holds no callable that holds the part.
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


## The sentence under a band's title: its share of the canvas.
static func share_words(band: Band) -> String:
    return TranslationServer.translate("%s of the canvas") % ("%d %%" % roundi(band.share * 100.0))


## The band whose paint is the most saturated in the first row, then each
## band's mean chroma as its row's value and words, with its share in the
## sentence under its title. The share goes under the title rather than beside the chroma,
## because the words take the right of a row and a docker of the shipped width
## left them room for four characters and a little.
func _show() -> void:
    for at in _rows.size():
        var row := _rows[at]
        var band := bands[at] if at < bands.size() else Band.new(at, 0.0, 0.0)
        row.value = snappedf(band.chroma, 0.001)
        row.retitle(String(BANDS[at]["title"]), share_words(band))
        _write(row, "%.2f" % band.chroma)
    _most_row.value = NOWHERE if most < 0 else String(BANDS[most]["title"])
    _write(_most_row, sits_words(most))


## The sentence naming the band *band* of `BANDS` as the one whose paint is the
## most saturated, or saying none is for -1.
static func sits_words(band: int) -> String:
    if band < 0:
        return TranslationServer.translate("No value holds saturated paint.")
    return TranslationServer.translate(String(BANDS[band]["most"]))


static func _write(row: SaPageRow, words: String) -> void:
    var shown := row.control as Label
    if shown != null and is_instance_valid(shown):
        shown.text = words
